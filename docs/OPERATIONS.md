# Operations Guide

Day-2 operations, maintenance, and troubleshooting for LKE Sandbox.

## Quick Reference

### Access Commands

```bash
# Set kubeconfig
export KUBECONFIG=$(cd tofu/environments/sandbox && tofu output -raw kubeconfig_path)

# Access Infisical (before Traefik is up)
kubectl port-forward svc/infisical-frontend -n infisical 8080:80

# Access ArgoCD (before Traefik is up)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get ArgoCD admin password
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d

# Get Keycloak admin credentials
kubectl get secret keycloak-initial-admin -n keycloak -o jsonpath='{.data.username}' | base64 -d
kubectl get secret keycloak-initial-admin -n keycloak -o jsonpath='{.data.password}' | base64 -d
```

### Health Checks

```bash
# Cluster health
kubectl get nodes
kubectl top nodes

# All pods status
kubectl get pods -A | grep -v Running

# ClusterSecretStore health
kubectl get clustersecretstore infisical

# ArgoCD application status
kubectl get applications -n argocd

# Certificate status
kubectl get certificates -A
kubectl get certificaterequests -A
```

---

## Common Operations

### Adding a New Application

1. Create HTTPRoute in your application namespace:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
  namespace: my-app
spec:
  parentRefs:
    - name: traefik-gateway
      namespace: traefik
  hostnames:
    - myapp.sandbox.knorr.casa
  rules:
    - backendRefs:
        - name: my-app-service
          port: 80
```

2. Verify the route is attached:
```bash
kubectl get httproute my-app -n my-app
```

### Adding a Secret to an Application

1. Create secret in Infisical:
   - Go to your project → Secrets
   - Add key-value pair
   - Select environment (dev/staging/prod)

2. Create ExternalSecret:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-secret
  namespace: my-app
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: infisical
  target:
    name: my-secret
  data:
    - secretKey: MY_KEY
      remoteRef:
        key: MY_KEY
```

3. Verify sync:
```bash
kubectl get externalsecret my-secret -n my-app
kubectl get secret my-secret -n my-app
```

### Scaling the Cluster

```bash
# Update node count in variables.tf
cd tofu/environments/sandbox
# Edit variables.tf: node_count = 4

# Apply changes
tofu plan
tofu apply
```

### Upgrading Kubernetes Version

1. Check available versions:
```bash
linode-cli lke versions-list
```

2. Update `k8s_version` in `tofu/environments/sandbox/variables.tf`

3. Apply (note: this triggers a rolling update):
```bash
cd tofu/environments/sandbox
tofu plan
tofu apply
```

---

## Maintenance

### Certificate Renewal

Certificates renew automatically via cert-manager. To check status:

```bash
# Check certificate expiry
kubectl get certificate sandbox-wildcard -n traefik -o jsonpath='{.status.notAfter}'

# Check renewal status
kubectl describe certificate sandbox-wildcard -n traefik

# Force renewal (if needed)
kubectl delete certificaterequest -n traefik -l cert-manager.io/certificate-name=sandbox-wildcard
```

### Database Backup and Restore

PGO automatically manages backups via pgBackRest.

```bash
# List backups
kubectl exec -it $(kubectl get pods -n pgo -l postgres-operator.crunchydata.com/role=master -o name | head -1) -n pgo -- pgbackrest info

# Manual backup
kubectl exec -it $(kubectl get pods -n pgo -l postgres-operator.crunchydata.com/role=master -o name | head -1) -n pgo -- pgbackrest backup --type=full

# Restore (creates new cluster from backup)
# Edit PostgresCluster CR with restore specification
```

### Rotating Secrets

1. Update secret in Infisical
2. External Secrets syncs automatically (default: 1h refresh)
3. Force immediate sync:
```bash
kubectl annotate externalsecret <name> -n <namespace> force-sync=$(date +%s) --overwrite
```

4. Restart consuming pods:
```bash
kubectl rollout restart deployment/<name> -n <namespace>
```

---

## Troubleshooting

### ClusterSecretStore Not Ready

**Symptoms**: ExternalSecrets stuck in `SecretSyncedError`

**Check**:
```bash
kubectl get clustersecretstore infisical -o yaml
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

**Common causes**:
1. Machine Identity secret missing:
   ```bash
   kubectl get secret infisical-machine-identity -n external-secrets
   ```

2. Infisical not accessible:
   ```bash
   kubectl run curl --rm -it --image=curlimages/curl -- \
     curl -v http://infisical-upstream.infisical.svc:8080/api/status
   ```

3. Wrong project slug - verify in Infisical UI → Project Settings

### Certificate Not Issuing

**Check**:
```bash
kubectl describe certificate sandbox-wildcard -n traefik
kubectl describe certificaterequest -n traefik
kubectl describe order -n traefik
kubectl describe challenge -n traefik
```

**Common causes**:
1. Cloudflare token invalid or missing permissions
2. DNS propagation delay (wait 5-10 minutes)
3. Rate limiting (check Let's Encrypt status)

**Verify Cloudflare secret**:
```bash
kubectl get externalsecret cloudflare-api-token -n cert-manager
kubectl get secret cloudflare-api-token -n cert-manager
```

### Infisical CrashLoopBackOff

**Check**:
```bash
kubectl logs -n infisical -l app.kubernetes.io/name=infisical --tail=50
```

**"read-only transaction" error**:

Infisical is connecting to a PostgreSQL replica instead of primary.

**Fix**:
```bash
# Verify connection string points to pgo-primary, not pgo-pgbouncer
kubectl get secret infisical-secrets -n infisical -o jsonpath='{.data.DB_CONNECTION_URI}' | base64 -d

# Should contain: pgo-primary.pgo.svc
# Should NOT contain: pgo-pgbouncer.pgo.svc
```

### ArgoCD Application Out of Sync

**Check**:
```bash
kubectl describe application <app-name> -n argocd
argocd app diff <app-name>
```

**Force sync**:
```bash
argocd app sync <app-name> --force
```

**Common causes**:
1. Git repository not accessible
2. Helm values merge conflict
3. Resource already exists (owned by different app)

### Traefik Not Routing Traffic

**Check**:
```bash
# Gateway status
kubectl get gateway traefik-gateway -n traefik -o yaml

# HTTPRoute status
kubectl get httproute -A

# Traefik logs
kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=100
```

**Verify TLS**:
```bash
kubectl get secret sandbox-wildcard-tls -n traefik
```

### Pods Pending (Insufficient Resources)

**Check**:
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl top nodes
```

**Solutions**:
1. Scale up node count (see Scaling section)
2. Use larger node type
3. Check resource requests/limits

---

## Disaster Recovery

### Full Cluster Recovery

1. **Provision infrastructure**:
   ```bash
   cd tofu/environments/sandbox
   export LINODE_TOKEN="..."
   tofu init && tofu apply
   export KUBECONFIG=$(tofu output -raw kubeconfig_path)
   ```

2. **Deploy bootstrap**:
   ```bash
   cd bootstrap
   helmfile -e lke apply
   ```

3. **Restore Infisical database** (if backup exists):
   ```bash
   # Restore PGO backup - see PGO documentation
   ```

4. **Recreate Machine Identity**:
   - Log into Infisical
   - Create new Machine Identity
   - Create Kubernetes secret

5. **Verify ArgoCD syncs all apps**:
   ```bash
   kubectl get applications -n argocd
   ```

### Partial Recovery (Single Service)

For individual service issues, ArgoCD self-heals automatically. To force:

```bash
# Delete and let ArgoCD recreate
argocd app sync <app-name> --prune

# Or delete resources directly
kubectl delete deployment <name> -n <namespace>
# ArgoCD will recreate from Git
```

---

## Monitoring Commands

### Resource Usage

```bash
# Node resources
kubectl top nodes

# Pod resources
kubectl top pods -A --sort-by=memory

# Storage usage
kubectl get pvc -A
```

### Logs

```bash
# ArgoCD
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=100

# External Secrets
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=100

# cert-manager
kubectl logs -n cert-manager -l app=cert-manager --tail=100

# Traefik
kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=100

# Infisical
kubectl logs -n infisical -l app.kubernetes.io/name=infisical --tail=100

# PostgreSQL (PGO)
kubectl logs -n pgo -l postgres-operator.crunchydata.com/role=master --tail=100
```

### Events

```bash
# Cluster-wide events
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Namespace events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

---

## Known Limitations

### LKE Webhook Timeout

LKE's managed control plane cannot reach ClusterIP services, causing admission webhook timeouts.

**Affected**: External Secrets webhook
**Workaround**: Webhook disabled in chart values

### PgBouncer Replica Routing

PGO's PgBouncer may route to read replicas by default.

**Affected**: Infisical write operations
**Workaround**: Infisical connects directly to `pgo-primary.pgo.svc`

### NodeBalancer IP Changes

LKE NodeBalancer IPs can change on cluster recreation.

**Affected**: DNS records
**Workaround**: Update DNS after infrastructure changes or use External-DNS