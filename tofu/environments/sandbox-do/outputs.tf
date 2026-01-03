output "cluster_id" {
  description = "DOKS Cluster ID"
  value       = module.doks_cluster.id
}

output "cluster_label" {
  description = "Cluster label"
  value       = module.doks_cluster.label
}

output "api_endpoints" {
  description = "Kubernetes API endpoints"
  value       = module.doks_cluster.api_endpoints
}

output "kubeconfig_path" {
  description = "Path to generated kubeconfig"
  value       = abspath(local_sensitive_file.kubeconfig.filename)
}

output "node_ids" {
  description = "Droplet IDs of cluster nodes"
  value       = local.node_ids
}
