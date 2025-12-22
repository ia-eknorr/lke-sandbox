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