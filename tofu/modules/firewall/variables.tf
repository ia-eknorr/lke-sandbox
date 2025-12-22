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