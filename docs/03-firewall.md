# Firewall

Add firewall rules to your cluster. This protects the nodes from unwanted traffic.

## Firewall Module

**File: `tofu/modules/firewall/variables.tf`**
```hcl
variable "label" {
  description = "Firewall name"
  type        = string
}

variable "tags" {
  description = "Tags for the firewall"
  type        = list(string)
  default     = []
}

variable "linodes" {
  description = "List of Linode IDs to attach firewall to"
  type        = list(number)
  default     = []
}
```

**File: `tofu/modules/firewall/main.tf`**
```hcl
terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.0"
    }
  }
}

resource "linode_firewall" "this" {
  label = var.label
  tags  = var.tags

  # Default: drop all inbound
  inbound_policy = "DROP"

  # Allow HTTPS
  inbound {
    label    = "allow-https"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "443"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # Allow HTTP (for cert-manager or redirects)
  inbound {
    label    = "allow-http"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "80"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # Allow Kubernetes API
  inbound {
    label    = "allow-kube-api"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "6443"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # Allow NodePort range
  inbound {
    label    = "allow-nodeports"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "30000-32767"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # Allow kubelet health checks (internal)
  inbound {
    label    = "allow-kubelet"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "10250"
    ipv4     = ["192.168.128.0/17"]
  }

  # Allow webhook callbacks from LKE control plane
  inbound {
    label    = "allow-webhooks"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "8443,9443,10250,10260"
    ipv4     = ["0.0.0.0/0"]
  }

  # Allow all outbound
  outbound_policy = "ACCEPT"

  # Attach to specified Linodes
  linodes = var.linodes
}
```

**File: `tofu/modules/firewall/outputs.tf`**
```hcl
output "id" {
  description = "Firewall ID"
  value       = linode_firewall.this.id
}

output "status" {
  description = "Firewall status"
  value       = linode_firewall.this.status
}
```

## Update LKE Module Outputs

We need to expose node instance IDs from the LKE module.

**Update: `tofu/modules/lke-cluster/outputs.tf`**
```hcl
output "id" {
  description = "Cluster ID"
  value       = linode_lke_cluster.this.id
}

output "label" {
  description = "Cluster label"
  value       = linode_lke_cluster.this.label
}

output "kubeconfig" {
  description = "Kubeconfig for cluster access (base64 encoded)"
  value       = linode_lke_cluster.this.kubeconfig
  sensitive   = true
}

output "api_endpoints" {
  description = "Kubernetes API endpoints"
  value       = linode_lke_cluster.this.api_endpoints
}

output "pool" {
  description = "Node pool information"
  value       = linode_lke_cluster.this.pool
}
```

## Update Sandbox Environment

**Update: `tofu/environments/sandbox/main.tf`**
```hcl
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
```

**Update: `tofu/environments/sandbox/outputs.tf`**
```hcl
output "cluster_id" {
  description = "LKE Cluster ID"
  value       = module.lke_cluster.id
}

output "cluster_label" {
  description = "Cluster label"
  value       = module.lke_cluster.label
}

output "api_endpoints" {
  description = "Kubernetes API endpoints"
  value       = module.lke_cluster.api_endpoints
}

output "kubeconfig_path" {
  description = "Path to generated kubeconfig"
  value       = abspath(local_sensitive_file.kubeconfig.filename)
}

output "firewall_id" {
  description = "Firewall ID"
  value       = module.firewall.id
}

output "node_ids" {
  description = "Linode IDs of cluster nodes"
  value       = local.node_ids
}
```

## Apply

```bash
cd tofu/environments/sandbox

# Preview changes
tofu plan

# Apply (adds firewall, attaches to nodes)
tofu apply
```

## Verify

```bash
# Check firewall in Linode
linode-cli firewalls list

# Check it's attached to your nodes
linode-cli firewalls devices-list <firewall-id>

# Verify cluster still works
kubectl get nodes
```

You can also see the firewall in Cloud Manager → Firewalls.

## Notes

- Node IDs come directly from the LKE cluster resource - no separate data source needed
- This works from scratch in a single `tofu apply`
- If you scale the cluster later, re-run `tofu apply` to attach new nodes to the firewall

---

**Infrastructure complete. Proceed to [04-platform.md](04-platform.md) for platform setup (Traefik, cert-manager, TLS).**
