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

  # Allow all TCP on private network (pod-to-pod cross-node traffic)
  inbound {
    label    = "allow-private-tcp"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "1-65535"
    ipv4     = ["192.168.128.0/17"]
  }

  # Allow Calico IPENCAP (IP-in-IP) for pod networking across nodes
  inbound {
    label    = "allow-calico-ipip"
    action   = "ACCEPT"
    protocol = "IPENCAP"
    ipv4     = ["192.168.128.0/17"]
  }

# Allow webhook callbacks from LKE control plane
  # LKE control plane IPs are not disclosed, so we allow all TCP for webhook ports
  # See: https://www.linode.com/community/questions/24953/cert-manager-problem-with-webhook-io-timeout
  inbound {
    label    = "allow-webhooks"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "1-65535"
    ipv4     = ["0.0.0.0/0"]
  }

  # Allow all outbound
  outbound_policy = "ACCEPT"

  # Attach to specified Linodes
  linodes = var.linodes
}
