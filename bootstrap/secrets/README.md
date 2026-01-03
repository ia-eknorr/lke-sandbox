# Bootstrap Secrets

This document lists the secrets that must be created in Infisical during the manual bootstrap phase.

## Prerequisites

Before creating these secrets, you must:

1. Complete the Infisical setup wizard at `https://infisical.sandbox.knorr.casa`
2. Create an organization and project
3. Create a Machine Identity for external-secrets with appropriate permissions

## Required Secrets

### cloudflare-api-token

**Purpose**: DNS-01 challenge for Let's Encrypt certificates

**When to create**: During initial bootstrap

**Format in Infisical**:
- Secret name: `cloudflare-api-token`
- Value: Your Cloudflare API token with DNS Edit permissions

**Used by**: cert-manager ClusterIssuer (via ExternalSecret)

---

### argocd-oidc-client-secret

**Purpose**: OIDC client secret for ArgoCD to authenticate with Keycloak

**When to create**: After Keycloak is deployed and you've created the `argocd` OIDC client

**Format in Infisical**:
- Secret name: `argocd-oidc-client-secret`
- Value: The client secret from Keycloak's `argocd` client configuration

**Used by**: ArgoCD OIDC configuration (via ExternalSecret)

---

## Automated Secrets

The following secrets are **automatically synced** and do not require manual creation:

### keycloak-db (Automated)

**How it works**: The Keycloak chart uses External-Secrets with the Kubernetes provider to read the PGO-generated `pgo-pguser-keycloak` secret directly from the `pgo` namespace. No manual step required!

**Flow**:
```
PGO creates secret → Kubernetes SecretStore reads it → ExternalSecret syncs to keycloak namespace
     (pgo ns)              (reads from pgo ns)              (keycloak ns)
```

---

## Creating the Machine Identity Secret

After creating the Machine Identity in Infisical, create the Kubernetes secret:

```bash
kubectl create secret generic infisical-machine-identity \
  -n external-secrets \
  --from-literal=clientId=<YOUR_CLIENT_ID> \
  --from-literal=clientSecret=<YOUR_CLIENT_SECRET>
```

This enables the ClusterSecretStore to authenticate with Infisical.

## Local Secret Files

The secret files in this directory (gitignored) contain actual secret values for reference:

- `CLOUDFLARE_API_TOKEN` - Cloudflare API token (store in Infisical)

**Do not commit these files!** They are gitignored for a reason.
