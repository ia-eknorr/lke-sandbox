# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LKE Sandbox is a Kubernetes infrastructure project for Linode Kubernetes Engine (LKE) using OpenTofu for infrastructure-as-code and Gateway API for ingress routing. The domain is `*.sandbox.knorr.casa`.

## Architecture

**Infrastructure Layer (OpenTofu)**
- `tofu/modules/lke-cluster/` - Reusable LKE cluster module
- `tofu/modules/firewall/` - Linode firewall module with LKE-specific rules
- `tofu/environments/sandbox/` - Sandbox environment configuration

**Platform Layer (Kubernetes/Helm)**
- `bootstrap/cert-manager/` - ClusterIssuer and Certificate manifests for Let's Encrypt with Cloudflare DNS-01
- `bootstrap/traefik/` - Helm values for Traefik with Gateway API mode

## Commands

### Infrastructure (OpenTofu)

```bash
cd tofu/environments/sandbox

# Required: Set Linode API token
export LINODE_TOKEN="..."

tofu init          # Initialize providers
tofu plan          # Preview changes
tofu apply         # Apply changes
tofu destroy       # Tear down infrastructure

# Get kubeconfig path
export KUBECONFIG=$(tofu output -raw kubeconfig_path)
```

### Platform (Kubernetes)

```bash
# Install Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

# Install cert-manager
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true --wait

# Create Cloudflare secret for DNS-01
kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token=$CLOUDFLARE_API_TOKEN

# Apply cert-manager resources
kubectl apply -f bootstrap/cert-manager/

# Install Traefik
helm upgrade --install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  --values bootstrap/traefik/values.yaml --wait
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `LINODE_TOKEN` | Linode API token (Read/Write for Linodes, LKE, NodeBalancers, Firewalls, IPs) |
| `CLOUDFLARE_API_TOKEN` | Cloudflare API token with DNS Edit permissions for `knorr.casa` |
| `KUBECONFIG` | Path to kubeconfig (generated at `tofu/environments/sandbox/kubeconfig.yaml`) |

## Key Configuration

- **Kubernetes version**: 1.34
- **Region**: us-west
- **Node pool**: 2x g6-standard-2 (4GB RAM each)
- **Gateway**: Traefik-managed (`traefik-gateway` in traefik namespace)
- **TLS**: Wildcard certificate for `*.sandbox.knorr.casa`
