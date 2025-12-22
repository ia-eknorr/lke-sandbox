terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.0"
    }
  }
}

resource "linode_firewall" "this" {
  label = var.label
  tags  = var.tags

  # Default: drop all inbound
  inbound_policy = "DROP"

  # Allow HTTPS
  inbound {
    label    = "allow-https"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "443"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # Allow HTTP (for cert-manager or redirects)
  inbound {
    label    = "allow-http"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "80"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # Allow Kubernetes API
  inbound {
    label    = "allow-kube-api"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "6443"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # Allow NodePort range
  inbound {
    label    = "allow-nodeports"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "30000-32767"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # Allow kubelet health checks (internal)
  inbound {
    label    = "allow-kubelet"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "10250"
    ipv4     = ["192.168.128.0/17"]
  }

# Allow webhook callbacks from LKE control plane
  inbound {
    label    = "allow-webhooks"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "8443,9443,10250,10260"
    ipv4     = ["0.0.0.0/0"]
}

  # Allow all outbound
  outbound_policy = "ACCEPT"

  # Attach to specified Linodes
  linodes = var.linodes
}
