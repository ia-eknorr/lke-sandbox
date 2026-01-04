output "id" {
  description = "Cluster ID"
  value       = digitalocean_kubernetes_cluster.this.id
}

output "label" {
  description = "Cluster label"
  value       = digitalocean_kubernetes_cluster.this.name
}

output "kubeconfig" {
  description = "Kubeconfig for cluster access (base64 encoded for LKE compatibility)"
  # DOKS returns raw config, encode it to match LKE interface
  value       = base64encode(digitalocean_kubernetes_cluster.this.kube_config[0].raw_config)
  sensitive   = true
}

output "api_endpoints" {
  description = "Kubernetes API endpoints"
  # DOKS returns single endpoint, wrap in list for LKE compatibility
  value       = [digitalocean_kubernetes_cluster.this.endpoint]
}

output "pool" {
  description = "Node pool information"
  value       = digitalocean_kubernetes_cluster.this.node_pool
}

# Additional outputs useful for firewall attachment
output "node_droplet_ids" {
  description = "Droplet IDs for all nodes (useful for firewall attachment)"
  value = flatten([
    for pool in digitalocean_kubernetes_cluster.this.node_pool : [
      for node in pool.nodes : node.droplet_id
    ]
  ])
}
