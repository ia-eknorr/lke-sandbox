module "lke_cluster" {
  source = "../../modules/lke-cluster"

  label       = var.cluster_label
  region      = var.region
  k8s_version = var.k8s_version
  tags        = var.tags

  pools = [{
    type  = var.node_type
    count = var.node_count
  }]
}

# Extract node instance IDs from LKE cluster output
locals {
  node_ids = flatten([
    for pool in module.lke_cluster.pool : [
      for node in pool.nodes : node.instance_id
    ]
  ])
}

module "firewall" {
  source = "../../modules/firewall"

  label   = "${var.cluster_label}-fw"
  tags    = var.tags
  linodes = local.node_ids
}

# Write kubeconfig to local file
resource "local_sensitive_file" "kubeconfig" {
  content         = base64decode(module.lke_cluster.kubeconfig)
  filename        = "${path.module}/kubeconfig.yaml"
  file_permission = "0600"
}
