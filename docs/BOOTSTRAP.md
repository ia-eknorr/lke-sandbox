# Bootstrap Guide

Deploy the LKE Sandbox platform from scratch using the **Secrets-First GitOps** approach.

## Overview

The bootstrap process deploys the "secrets pipeline" (PGO → Infisical → External-Secrets → ArgoCD), which then enables ArgoCD to manage all other services via GitOps.

```
Bootstrap (helmfile apply):
  pgo → infisical → external-secrets → argocd

ArgoCD Manages (via apps/):
  cert-manager → traefik → trust-manager → keycloak
```

Most steps are automated. You only need to:
1. Create the Cloudflare API token file
2. Run helmfile
3. (Optional) Configure Keycloak for OIDC

## Prerequisites

- LKE cluster provisioned (`tofu apply` completed)
- `kubectl` configured with cluster access
- `helm` and `helmfile` installed
- Cloudflare API token with Zone DNS Edit permissions for `knorr.casa`

## Step 1: Prepare Secrets

Create the Cloudflare API token file before running helmfile:

```bash
cd bootstrap/secrets
echo "your-cloudflare-api-token" > CLOUDFLARE_API_TOKEN
```

This file is gitignored and will be read by helmfile during deployment.

## Step 2: Deploy Bootstrap Services

```bash
cd bootstrap
helmfile -e lke apply
```

This deploys (in order):
1. **Gateway API CRDs** (presync hook)
2. **PGO** - PostgreSQL Operator with `mgmt` database cluster
3. **Infisical** - Secrets platform with auto-bootstrap
4. **External Secrets** - Operator with ClusterSecretStore
5. **ArgoCD** - GitOps controller with platform-apps Application

### What Happens Automatically

The `provision-eso` job runs after Infisical is ready and:
- Creates the "sandbox" project in Infisical
- Creates a Machine Identity with Universal Auth
- Adds the identity to the project
- Uploads the Cloudflare API token to Infisical
- Creates the `infisical-machine-identity` K8s secret

No manual Infisical configuration is required.

### Expected Timeline

| Phase | Duration | Notes |
|-------|----------|-------|
| PGO + PostgresCluster | 3-5 min | Waits for database to be ready |
| Infisical + Bootstrap | 2-3 min | Auto-creates admin user and project |
| External Secrets | 1 min | ClusterSecretStore becomes healthy |
| ArgoCD | 1-2 min | Starts syncing platform-apps |

Total: ~10 minutes

## Step 3: Verify Deployment

```bash
# Check ClusterSecretStore is healthy
kubectl get clustersecretstore infisical
# STATUS=Valid, READY=True

# Check ArgoCD applications
kubectl get applications -n argocd

# Check all pods are running
kubectl get pods -A | grep -v Running
```

## Step 4: GitOps Takes Over

Once External Secrets is healthy, ArgoCD's `platform-apps` Application syncs and deploys:
- **cert-manager** - Issues wildcard certificate for `*.sandbox.knorr.casa`
- **traefik** - Gateway API ingress controller
- **trust-manager** - CA certificate distribution
- **keycloak** - Identity provider (if enabled)

Public URLs become available after Traefik and cert-manager are healthy:
- https://argocd.sandbox.knorr.casa
- https://infisical.sandbox.knorr.casa
- https://keycloak.sandbox.knorr.casa

## Step 5: Configure Keycloak (Optional)

If you want OIDC authentication for ArgoCD:

### Get Keycloak Admin Credentials

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

ArgoCD's ExternalSecret syncs the OIDC secret automatically.

## Accessing Services Before Traefik

Before Traefik is deployed, use port-forward:

```bash
# Infisical
kubectl port-forward svc/infisical-frontend -n infisical 8080:80
# Access: http://localhost:8080

# ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Access: https://localhost:8080
```

### Infisical Credentials

Auto-bootstrap creates the admin user:
- Email: `admin@knorr.casa`
- Password: `ChangeMe123!` (change after first login)

### ArgoCD Credentials

```bash
# Get admin password
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
```

## Verification Checklist

- [ ] Cloudflare API token file created in `bootstrap/secrets/`
- [ ] `helmfile apply` completed successfully
- [ ] PostgresCluster ready: `kubectl get postgrescluster -n pgo`
- [ ] Infisical pods running: `kubectl get pods -n infisical`
- [ ] ClusterSecretStore healthy: `kubectl get clustersecretstore infisical`
- [ ] ArgoCD applications synced: `kubectl get applications -n argocd`
- [ ] Certificate issued: `kubectl get certificate -n traefik`
- [ ] Public URLs accessible

## Troubleshooting

### provision-eso Job Failed

Check the job logs:
```bash
kubectl logs -n infisical job/provision-eso
```

Common issues:
- Infisical not ready (wait and retry)
- Bootstrap output secret missing (check `infisical-bootstrap-output`)

### ClusterSecretStore Not Ready

```bash
kubectl describe clustersecretstore infisical
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

Verify the Machine Identity secret exists:
```bash
kubectl get secret infisical-machine-identity -n external-secrets
```

### Certificate Not Issuing

```bash
kubectl describe certificate sandbox-wildcard -n traefik
kubectl describe certificaterequest -n traefik
```

Check if cloudflare-api-token secret was synced:
```bash
kubectl get externalsecret cloudflare-api-token -n cert-manager
kubectl get secret cloudflare-api-token -n cert-manager
```

### Infisical Database Errors

If you see "read-only transaction" errors:
```bash
kubectl logs -n infisical -l app.kubernetes.io/name=infisical --tail=50
```

Infisical should connect to `pgo-primary.pgo.svc`, not PgBouncer. This is configured in the chart.

## Multi-Environment Support

For DigitalOcean:
```bash
helmfile -e do apply
```

This uses `bootstrap/environments/do.yaml` which sets:
- `suffix: -do` (hostnames become `argocd-do.sandbox.knorr.casa`)
- `storageClass: do-block-storage`

## Disaster Recovery

### Full Cluster Recovery

1. Provision infrastructure:
   ```bash
   cd tofu/environments/sandbox
   tofu apply
   export KUBECONFIG=$(tofu output -raw kubeconfig_path)
   ```

2. Ensure Cloudflare token file exists:
   ```bash
   ls bootstrap/secrets/CLOUDFLARE_API_TOKEN
   ```

3. Run bootstrap:
   ```bash
   cd bootstrap
   helmfile -e lke apply
   ```

4. ArgoCD syncs all applications automatically

### Database Recovery

PGO manages backups via pgBackRest:
```bash
kubectl exec -it $(kubectl get pods -n pgo -l postgres-operator.crunchydata.com/role=master -o name | head -1) -n pgo -- pgbackrest info
```

## Known Limitations

### LKE Webhook Timeout

LKE's control plane cannot reach ClusterIP services. External Secrets webhook is disabled.

### PgBouncer Replica Routing

Infisical connects directly to PostgreSQL primary to avoid read-replica routing issues.
