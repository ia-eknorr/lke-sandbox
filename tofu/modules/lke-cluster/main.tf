terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.0"
    }
  }
}

resource "linode_lke_cluster" "this" {
  label       = var.label
  region      = var.region
  k8s_version = var.k8s_version
  tags        = var.tags

  dynamic "pool" {
    for_each = var.pools
    content {
      type  = pool.value.type
      count = pool.value.count
    }
  }

  # Enable control plane HA
  # control_plane {
  #   high_availability = true
  # }
}