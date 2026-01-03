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

> **Important**: The public URL (`https://infisical.sandbox.knorr.casa`) is NOT accessible yet—Traefik and cert-manager are deployed by ArgoCD after ExternalSecrets is working. Use port-forward to access Infisical.

### Access Infisical

Auto-bootstrap has already created the admin user and organization. Just log in:

1. Port-forward to access Infisical:
   ```bash
   kubectl port-forward svc/infisical-frontend -n infisical 8080:80
   ```

2. Navigate to http://localhost:8080

3. Log in with bootstrap credentials:
   - Email: `admin@knorr.casa`
   - Password: `ChangeMe123!` (change this after login!)

4. Create a project (e.g., name it "sandbox")
   - Infisical auto-generates a slug like `sandbox-abc12`

5. **Copy the project slug** and update the values file:
   - Go to **Project Settings** → click **"Copy Project Slug"**
   - Update `bootstrap/values/external-secrets/external-secrets/values.yaml`:
     ```yaml
     clusterSecretStore:
       secretsScope:
         projectSlug: "your-actual-slug"  # Paste the copied slug here
         environmentSlug: "dev"           # Must match an environment in your project
     ```
   - Infisical creates `dev`, `staging`, `prod` environments by default

### Create Machine Identity

1. Go to **Organization Settings → Access Control → Machine Identities**
2. Create new identity: `external-secrets-operator`
3. Add authentication method: **Universal Auth**
4. Create a **Client Secret**
5. Note the **Client ID** and **Client Secret**

### Grant Machine Identity Access to Project

> **Important**: The Machine Identity must be added to the project separately!

1. Go to your **sandbox** project → **Project Settings** → **Access Control**
2. Click **Add Member** → select **Machine Identity**
3. Add `external-secrets-operator` with **Member** or **Admin** role

### Create Bootstrap Secrets

Create this secret in Infisical (see `bootstrap/secrets/README.md` for details):

| Secret Name              | Purpose                             | When to Create       |
|--------------------------|-------------------------------------|----------------------|
| `cloudflare-api-token`   | DNS-01 challenge for Let's Encrypt  | During initial setup |

> **Note**: The `keycloak-db` credentials are **automatically synced** from PGO using the External-Secrets Kubernetes provider. No manual step required!

## Step 3: Activate External-Secrets

1. Create the Kubernetes secret with Machine Identity credentials:

   ```bash
   kubectl create secret generic infisical-machine-identity \
     -n external-secrets \
     --from-literal=clientId=<YOUR_CLIENT_ID> \
     --from-literal=clientSecret=<YOUR_CLIENT_SECRET>
   ```

2. Apply the updated values (with your project slug from Step 2.5):

   ```bash
   cd bootstrap && helmfile -l name=external-secrets sync
   ```

3. Verify the ClusterSecretStore becomes healthy:

   ```bash
   kubectl get clustersecretstore infisical
   # Should show: STATUS=Valid, READY=True
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

> **Note**: After traefik and cert-manager are healthy, public URLs become available:
> - https://infisical.sandbox.knorr.casa
> - https://argocd.sandbox.knorr.casa
> - https://keycloak.sandbox.knorr.casa (after Wave 2)

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
- [ ] Infisical auto-bootstrap completed (check: `kubectl get secret infisical-bootstrap-secret -n infisical`)
- [ ] Logged into Infisical, created project and Machine Identity
- [ ] Machine Identity secret created: `kubectl get secret infisical-machine-identity -n external-secrets`
- [ ] ClusterSecretStore is healthy: `kubectl get clustersecretstore infisical`
- [ ] All ArgoCD applications are synced: `argocd app list`
- [ ] Wildcard certificate is issued: `kubectl get certificate -n traefik`
- [ ] Public URLs accessible (infisical, argocd, keycloak)
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

## Known LKE Limitations

### External-Secrets Webhook Disabled

**Issue**: LKE's managed Kubernetes control plane cannot reach ClusterIP services, which prevents admission webhooks from functioning. The External Secrets validating webhook times out when the API server tries to call it.

**Resolution**: External-Secrets webhook is disabled in `bootstrap/charts/external-secrets/values.yaml`:

```yaml
external-secrets:
  webhook:
    create: false
```

This means ClusterSecretStore and ExternalSecret resources are not validated on creation. The trade-off is acceptable for a sandbox environment.

### PgBouncer Routes to Replicas

**Issue**: PGO's PgBouncer service may route connections to read replicas by default, causing "cannot execute UPDATE in a read-only transaction" errors.

**Resolution**: Infisical connects directly to the PostgreSQL primary (`pgo-primary.pgo.svc`) instead of PgBouncer (`pgo-pgbouncer.pgo.svc`). This is configured in `bootstrap/charts/infisical/templates/secrets.yaml`.

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

### Infisical Pods CrashLoopBackOff

If Infisical pods show "read-only transaction" errors:

```bash
kubectl logs -n infisical -l component=infisical --tail=20 | grep -i "read-only"
```

This indicates connection to a PostgreSQL replica instead of the primary. Verify the connection string:

```bash
kubectl get secret infisical-secrets -n infisical -o jsonpath='{.data.DB_CONNECTION_URI}' | base64 -d
```

The URI should contain `pgo-primary.pgo.svc`, not `pgo-pgbouncer.pgo.svc`. If incorrect, patch the secret:

```bash
# Get the correct primary URI
kubectl get secret pgo-pguser-infisical -n pgo -o jsonpath='{.data.uri}' | base64 -d

# Patch with primary connection (manually construct the base64-encoded value)
# Then restart the deployment
kubectl rollout restart deployment/infisical -n infisical
```

### Cert-Manager Certificate Pending

Check the Certificate and ClusterIssuer status:

```bash
kubectl describe certificate sandbox-wildcard -n traefik
kubectl describe clusterissuer letsencrypt-prod
```

Ensure `cloudflare-api-token` secret exists in Infisical and is synced to cert-manager namespace.
