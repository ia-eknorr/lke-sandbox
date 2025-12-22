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