# LKE Cluster

Create the LKE cluster infrastructure with OpenTofu. The firewall will be added in the next step.

## Check Available Kubernetes Versions

Before creating files, check what versions Linode offers:

```bash
curl -s -H "Authorization: Bearer $LINODE_TOKEN" \
  https://api.linode.com/v4/lke/versions | jq '.data[].id'
```

Use the latest version in your config below.

## LKE Module

**File: `tofu/modules/lke-cluster/variables.tf`**
```hcl
variable "label" {
  description = "Cluster name/label"
  type        = string
}

variable "region" {
  description = "Linode region"
  type        = string
  default     = "us-west"
}

variable "k8s_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.34"
}

variable "pools" {
  description = "Node pool configurations"
  type = list(object({
    type  = string
    count = number
  }))
  default = [{
    type  = "g6-standard-2"
    count = 2
  }]
}

variable "tags" {
  description = "Tags to apply to cluster"
  type        = list(string)
  default     = []
}
```

**File: `tofu/modules/lke-cluster/main.tf`**
```hcl
terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.0"
    }
  }
}

resource "linode_lke_cluster" "this" {
  label       = var.label
  region      = var.region
  k8s_version = var.k8s_version
  tags        = var.tags

  dynamic "pool" {
    for_each = var.pools
    content {
      type  = pool.value.type
      count = pool.value.count
    }
  }
}
```

**File: `tofu/modules/lke-cluster/outputs.tf`**
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
```

## Sandbox Environment

**File: `tofu/environments/sandbox/providers.tf`**
```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

provider "linode" {
  # Token from LINODE_TOKEN environment variable
}
```

**File: `tofu/environments/sandbox/variables.tf`**
```hcl
variable "cluster_label" {
  description = "Name for the LKE cluster"
  type        = string
  default     = "sandbox"
}

variable "region" {
  description = "Linode region"
  type        = string
  default     = "us-west"
}

variable "k8s_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.34"
}

variable "node_type" {
  description = "Linode type for nodes"
  type        = string
  default     = "g6-standard-2"  # 4GB RAM
}

variable "node_count" {
  description = "Number of nodes"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = list(string)
  default     = ["sandbox", "tofu-managed"]
}
```

**File: `tofu/environments/sandbox/main.tf`**
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

# Write kubeconfig to local file
resource "local_sensitive_file" "kubeconfig" {
  content         = base64decode(module.lke_cluster.kubeconfig)
  filename        = "${path.module}/kubeconfig.yaml"
  file_permission = "0600"
}
```

**File: `tofu/environments/sandbox/outputs.tf`**
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
```

## Apply

```bash
cd tofu/environments/sandbox

# Set your token
export LINODE_TOKEN="your-token-here"

# Initialize (downloads providers)
tofu init

# Preview
tofu plan

# Create the cluster
tofu apply
# Type 'yes' when prompted
```

Takes 3-5 minutes. Watch progress in Linode Cloud Manager → Kubernetes.

## Verify

```bash
# Set kubeconfig
export KUBECONFIG=$(tofu output -raw kubeconfig_path)

# Check nodes (may take another minute to be Ready)
kubectl get nodes -w

# Once Ready, check system pods
kubectl get pods -n kube-system
```

## Expected Output

```
NAME                            STATUS   ROLES    AGE   VERSION
lke12345-pool12345-abc123de     Ready    <none>   3m    v1.34.x
lke12345-pool12345-def456gh     Ready    <none>   3m    v1.34.x
```

---

**Once nodes show Ready, proceed to [03-firewall.md](03-firewall.md).**
