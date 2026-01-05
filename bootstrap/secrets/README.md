# Bootstrap Secrets

This directory contains secret files that are read by helmfile during bootstrap deployment.

## Required Files

### CLOUDFLARE_API_TOKEN

**Purpose**: DNS-01 challenge for Let's Encrypt certificates

**Create before running helmfile**:
```bash
echo "your-cloudflare-api-token" > CLOUDFLARE_API_TOKEN
```

The token needs Zone DNS Edit permissions for `knorr.casa`.

## What Happens During Bootstrap

When you run `helmfile apply`:

1. Helmfile reads `CLOUDFLARE_API_TOKEN` via `readFile`
2. The value is passed to the Infisical chart as `bootstrapSecrets.cloudflareApiToken`
3. The `provision-eso` job uploads it to Infisical
4. External Secrets syncs it to the `cert-manager` namespace
5. cert-manager uses it for DNS-01 challenges

## Automated Secrets

These secrets are created automatically during bootstrap:

| Secret | Created By | Purpose |
|--------|------------|---------|
| `infisical-machine-identity` | provision-eso job | ClusterSecretStore auth |
| `pgo-pguser-infisical` | PGO | Infisical database credentials |
| `pgo-pguser-keycloak` | PGO | Keycloak database credentials |

## Post-Bootstrap Secrets

### argocd-oidc-client-secret

**When to create**: After Keycloak is deployed and you've created the OIDC client

**Steps**:
1. Log into Keycloak at https://keycloak.sandbox.knorr.casa
2. Create realm `sandbox` and client `argocd`
3. Copy the client secret
4. Store in Infisical project as `argocd-oidc-client-secret`

ArgoCD's ExternalSecret syncs this automatically.

## Security Notes

- All files in this directory are gitignored
- Never commit actual secret values
- The `CLOUDFLARE_API_TOKEN` file is only needed during initial bootstrap
