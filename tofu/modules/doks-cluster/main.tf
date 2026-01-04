terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

resource "digitalocean_kubernetes_cluster" "this" {
  name    = var.label
  region  = var.region
  version = var.k8s_version
  tags    = var.tags

  # Auto-upgrade minor patch versions
  auto_upgrade = true

  # Maintenance window: Sundays at 3am UTC
  maintenance_policy {
    day        = "sunday"
    start_time = "03:00"
  }

  # Node pools - dynamic like LKE
  # DOKS requires at least one inline node_pool block
  dynamic "node_pool" {
    for_each = var.pools
    content {
      name       = "${var.label}-pool-${node_pool.key}"
      size       = node_pool.value.type
      node_count = node_pool.value.count
      tags       = var.tags
    }
  }

  # Destroy LoadBalancers and Volumes when cluster is deleted
  # Set to false in production to prevent data loss
  destroy_all_associated_resources = true
}
