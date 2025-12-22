output "id" {
  description = "Firewall ID"
  value       = linode_firewall.this.id
}

output "status" {
  description = "Firewall status"
  value       = linode_firewall.this.status
}