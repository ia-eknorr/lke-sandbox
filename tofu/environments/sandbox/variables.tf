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