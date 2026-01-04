variable "label" {
  description = "Cluster name/label"
  type        = string
}

variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "sfo3"
}

variable "k8s_version" {
  description = "Kubernetes version (use 'doctl kubernetes options versions' to list)"
  type        = string
  default     = "1.34.1-do.2"
}

variable "pools" {
  description = "Node pool configurations"
  type = list(object({
    type  = string  # DigitalOcean droplet size (e.g., s-2vcpu-4gb)
    count = number
  }))
  default = [{
    type  = "s-2vcpu-4gb"
    count = 3
  }]
}

variable "tags" {
  description = "Tags to apply to cluster"
  type        = list(string)
  default     = []
}
