variable "cluster_label" {
  description = "Name for the DOKS cluster"
  type        = string
  default     = "sandbox-do"
}

variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "sfo3"
}

variable "k8s_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.34.1-do.2"
}

variable "node_type" {
  description = "DigitalOcean droplet size for nodes"
  type        = string
  default     = "s-2vcpu-4gb"  # 4GB RAM, equivalent to LKE g6-standard-2
}

variable "node_count" {
  description = "Number of nodes"
  type        = number
  default     = 3
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = list(string)
  default     = ["sandbox-do", "tofu-managed"]
}
