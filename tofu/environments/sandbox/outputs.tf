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
