# Bootstrap Guide

This guide walks through deploying the LKE Sandbox platform from scratch using the **Secrets-First GitOps** approach.

## Philosophy

Deploy the "secrets pipeline" first (PGO → Infisical → External-Secrets → ArgoCD), then let ArgoCD manage everything else via GitOps. Manual configuration is limited to Infisical setup, which is unavoidable for any secrets management system.

## Architecture Overview

```
Manual Bootstrap (helmfile apply):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
pgo → infisical → external-secrets → argocd

ArgoCD Manages (via sync-waves):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Wave 0: cert-manager
Wave 1: traefik, trust-manager
Wave 2: keycloak
```

## Prerequisites

- `kubectl` configured for the target LKE cluster
- `helm` and `helmfile` installed
- Cloudflare API token with DNS Edit permissions (store in Infisical later)

## Step 1: Deploy Secrets Pipeline

```bash
cd bootstrap
helmfile apply
```

This deploys:
- **Gateway API CRDs** (presync hook)
- **pgo** - Crunchy Postgres Operator (database for Infisical)
- **infisical** - Self-hosted secrets management
- **external-secrets** - Syncs Infisical → Kubernetes Secrets
- **argocd** - GitOps controller with App of Apps

> **Note**: At this point, the ClusterSecretStore will be unhealthy (no Machine Identity yet), and ArgoCD OIDC will fail (Keycloak not deployed yet). This is expected.

## Step 2: Configure Infisical

### Initial Setup

1. Navigate to https://infisical.sandbox.knorr.casa
2. Complete the setup wizard:
   - Create admin account
   - Create organization
   - Create project (e.g., `platform-secrets`)

### Create Machine Identity

1. Go to **Access Control → Machine Identities**
2. Create new identity: `external-secrets-operator`
3. Add to your project with **Member** or **Admin** role
4. Create authentication method: **Universal Auth**
5. Note the **Client ID** and **Client Secret**

### Create Bootstrap Secrets

Create this secret in Infisical (see `bootstrap/secrets/README.md` for details):

| Secret Name              | Purpose                             | When to Create       |
|--------------------------|-------------------------------------|----------------------|
| `cloudflare-api-token`   | DNS-01 challenge for Let's Encrypt  | During initial setup |

> **Note**: The `keycloak-db` credentials are **automatically synced** from PGO using the External-Secrets Kubernetes provider. No manual step required!

## Step 3: Activate External-Secrets

Create the Kubernetes secret with Machine Identity credentials:

```bash
kubectl create secret generic infisical-machine-identity \
  -n external-secrets \
  --from-literal=clientId=<YOUR_CLIENT_ID> \
  --from-literal=clientSecret=<YOUR_CLIENT_SECRET>
```

Verify the ClusterSecretStore becomes healthy:

```bash
kubectl get clustersecretstore infisical
```

## Step 4: GitOps Takes Over

Once the ClusterSecretStore is healthy, ArgoCD's `platform-apps` Application will sync and deploy:

1. **cert-manager** (Wave 0) - Issues wildcard certificate
2. **traefik** (Wave 1) - Gateway API ingress controller
3. **trust-manager** (Wave 1) - CA certificate distribution
4. **keycloak** (Wave 2) - Identity provider

Watch the deployments:

```bash
# Check ArgoCD applications
kubectl get applications -n argocd

# Watch platform apps sync
argocd app list
```

## Step 5: Configure Keycloak (Post-Deploy)

Once Keycloak is deployed by ArgoCD:

### Get Initial Admin Credentials

```bash
echo "Username: $(kubectl get secret keycloak-initial-admin -n keycloak -o jsonpath='{.data.username}' | base64 -d)"
echo "Password: $(kubectl get secret keycloak-initial-admin -n keycloak -o jsonpath='{.data.password}' | base64 -d)"
```

### Create ArgoCD OIDC Client

1. Log in at https://keycloak.sandbox.knorr.casa
2. Create realm: `sandbox`
3. Create client:
   - Client ID: `argocd`
   - Client authentication: ON
   - Valid redirect URIs: `https://argocd.sandbox.knorr.casa/auth/callback`
4. Copy the client secret from Credentials tab
5. Store in Infisical as `argocd-oidc-client-secret`

ArgoCD's ExternalSecret will automatically sync the OIDC secret, and OIDC login will start working.

## Verification Checklist

- [ ] `helmfile apply` completed successfully
- [ ] Infisical is accessible and configured
- [ ] ClusterSecretStore is healthy: `kubectl get clustersecretstore`
- [ ] All ArgoCD applications are synced: `argocd app list`
- [ ] Wildcard certificate is issued: `kubectl get certificate -n traefik`
- [ ] Keycloak is accessible
- [ ] ArgoCD OIDC login works (after Step 5)

## Disaster Recovery

### Database Recovery

All stateful data is stored in PostgreSQL (PGO) with automatic pgBackRest backups.

```bash
# List available backups
kubectl exec -it pgo-instance1-xxxx -n pgo -- pgbackrest info
```

### Full Cluster Recovery

1. Re-provision infrastructure: `cd tofu/environments/sandbox && tofu apply`
2. Run helmfile: `cd bootstrap && helmfile apply`
3. Configure Infisical (Step 2) - or restore PGO database from backup
4. Create Machine Identity secret (Step 3)
5. ArgoCD will sync all applications automatically

## Troubleshooting

### ClusterSecretStore Not Ready

Check the external-secrets operator logs:

```bash
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

Verify the Machine Identity secret exists:

```bash
kubectl get secret infisical-machine-identity -n external-secrets
```

### ArgoCD Apps Not Syncing

Check the platform-apps Application:

```bash
kubectl describe application platform-apps -n argocd
```

Verify ArgoCD can access the git repository.

### Cert-Manager Certificate Pending

Check the Certificate and ClusterIssuer status:

```bash
kubectl describe certificate sandbox-wildcard -n traefik
kubectl describe clusterissuer letsencrypt-prod
```

Ensure `cloudflare-api-token` secret exists in Infisical and is synced to cert-manager namespace.
