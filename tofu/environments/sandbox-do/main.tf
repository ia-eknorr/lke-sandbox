module "doks_cluster" {
  source = "../../modules/doks-cluster"

  label       = var.cluster_label
  region      = var.region
  k8s_version = var.k8s_version
  tags        = var.tags

  pools = [{
    type  = var.node_type
    count = var.node_count
  }]
}

# Extract node Droplet IDs from DOKS cluster output
# Pattern matches LKE for consistency (useful for firewall attachment)
locals {
  node_ids = module.doks_cluster.node_droplet_ids
}

# Note: DOKS managed clusters have built-in control plane firewall
# Node firewalls can be added via digitalocean_firewall if needed
# For sandbox, we rely on DOKS defaults (similar to LKE with permissive rules)

# Write kubeconfig to local file
resource "local_sensitive_file" "kubeconfig" {
  content         = base64decode(module.doks_cluster.kubeconfig)
  filename        = "${path.module}/kubeconfig.yaml"
  file_permission = "0600"
}
