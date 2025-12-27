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

### keycloak-db

**Purpose**: Database credentials for Keycloak to connect to PGO PostgreSQL

**When to create**: After PGO creates the keycloak user (during helmfile apply)

**Format in Infisical** (JSON secret with properties):
```json
{
  "user": "keycloak",
  "password": "<password from pgo-pguser-keycloak secret>"
}
```

**How to get the values**:
```bash
kubectl get secret pgo-pguser-keycloak -n pgo -o jsonpath='{.data.user}' | base64 -d
kubectl get secret pgo-pguser-keycloak -n pgo -o jsonpath='{.data.password}' | base64 -d
```

**Used by**: Keycloak operator (via ExternalSecret → keycloak-db-secret)

---

### argocd-oidc-client-secret

**Purpose**: OIDC client secret for ArgoCD to authenticate with Keycloak

**When to create**: After Keycloak is deployed and you've created the `argocd` OIDC client

**Format in Infisical**:
- Secret name: `argocd-oidc-client-secret`
- Value: The client secret from Keycloak's `argocd` client configuration

**Used by**: ArgoCD OIDC configuration (via ExternalSecret)

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

The secret files in this directory (gitignored) contain the actual secret values extracted from the current cluster. Use these to populate Infisical:

- `CLOUDFLARE_API_TOKEN` - Cloudflare API token
- `KEYCLOAK_DB` - Keycloak database credentials (JSON with user/password)

**Do not commit these files!** They are gitignored for a reason.
