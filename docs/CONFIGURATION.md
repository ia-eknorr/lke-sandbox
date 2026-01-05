# Configuration Reference

Complete reference for all configurable values in LKE Sandbox.

## Environment Variables

### Required

| Variable | Description | Example |
|----------|-------------|---------|
| `LINODE_TOKEN` | Linode API token with Read/Write permissions for Linodes, LKE, NodeBalancers, Firewalls, IPs | `abc123...` |
| `CLOUDFLARE_API_TOKEN` | Cloudflare API token with Zone DNS Edit for `knorr.casa` | `xyz789...` |

### Generated

| Variable | Description | Source |
|----------|-------------|--------|
| `KUBECONFIG` | Path to kubeconfig file | `tofu output -raw kubeconfig_path` |

---

## Layer 1: Infrastructure (OpenTofu)

### LKE Cluster Variables

Location: `tofu/environments/sandbox/variables.tf`

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `cluster_label` | string | `"sandbox"` | Name for the LKE cluster |
| `region` | string | `"us-west"` | Linode region |
| `k8s_version` | string | `"1.34"` | Kubernetes version |
| `node_type` | string | `"g6-standard-2"` | Linode instance type (4GB RAM) |
| `node_count` | number | `3` | Number of worker nodes |
| `tags` | list(string) | `["sandbox", "tofu-managed"]` | Tags for resources |

### LKE Cluster Module

Location: `tofu/modules/lke-cluster/variables.tf`

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `label` | string | required | Cluster name/label |
| `region` | string | `"us-west"` | Linode region |
| `k8s_version` | string | `"1.34"` | Kubernetes version |
| `pools` | list(object) | `[{type="g6-standard-2", count=2}]` | Node pool configurations |
| `tags` | list(string) | `[]` | Tags to apply |

### Firewall Module

Location: `tofu/modules/firewall/variables.tf`

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `label` | string | required | Firewall name |
| `tags` | list(string) | `[]` | Tags for the firewall |
| `linodes` | list(number) | `[]` | Linode IDs to attach firewall to |

### Outputs

| Output | Description |
|--------|-------------|
| `cluster_id` | LKE cluster ID |
| `api_endpoints` | Kubernetes API endpoints |
| `kubeconfig_path` | Path to generated kubeconfig file |

---

## Layer 2: Bootstrap (Helmfile)

### Environment Values

Location: `bootstrap/environments/lke.yaml`

| Key | Value | Description |
|-----|-------|-------------|
| `cloud` | `lke` | Cloud provider identifier |
| `domain` | `sandbox.knorr.casa` | Base domain for services |
| `suffix` | `""` | Hostname suffix (empty for LKE, `-do` for DigitalOcean) |
| `storageClass` | `linode-block-storage-retain` | Default storage class |

### PGO (PostgreSQL Operator)

Location: `bootstrap/values/pgo/pgo/values.yaml`

| Key | Default | Description |
|-----|---------|-------------|
| `pgo.replicas` | `2` | Number of PGO operator replicas |
| `storage.className` | (from env) | Storage class for PostgreSQL PVCs |

The chart also creates a `PostgresCluster` named `mgmt` with:
- PostgreSQL 16
- Users: `keycloak`, `infisical`
- PgBouncer connection pooling
- pgBackRest backups

### Infisical

Location: `bootstrap/values/infisical/infisical/values.yaml`

| Key | Default | Description |
|-----|---------|-------------|
| `httpRoute.hostname` | `infisical.sandbox.knorr.casa` | Public hostname |
| `bootstrap.adminEmail` | `admin@knorr.casa` | Initial admin email |
| `bootstrap.adminPassword` | `ChangeMe123!` | Initial admin password (change after login!) |

Templated in helmfile:
| Key | Template | Description |
|-----|----------|-------------|
| `httpRoute.hostname` | `infisical{{ .Values.suffix }}.{{ .Values.domain }}` | Generates `infisical.sandbox.knorr.casa` |
| `bootstrapSecrets.cloudflareApiToken` | `readFile "secrets/CLOUDFLARE_API_TOKEN"` | Uploaded to Infisical |

### External Secrets Operator

Location: `bootstrap/values/external-secrets/external-secrets/values.yaml`

| Key | Default | Description |
|-----|---------|-------------|
| `clusterSecretStore.infisicalUrl` | `http://infisical-upstream.infisical.svc:8080` | Internal Infisical API URL |
| `clusterSecretStore.secretsScope.projectSlug` | `sandbox` | Infisical project slug |
| `clusterSecretStore.secretsScope.environmentSlug` | `dev` | Infisical environment |

**Note**: The `infisical-machine-identity` secret must be created manually:
```bash
kubectl create secret generic infisical-machine-identity \
  -n external-secrets \
  --from-literal=clientId=<YOUR_CLIENT_ID> \
  --from-literal=clientSecret=<YOUR_CLIENT_SECRET>
```

### ArgoCD

Location: `bootstrap/values/argocd/argocd/values.yaml`

| Key | Default | Description |
|-----|---------|-------------|
| `httpRoute.hostname` | `argocd.sandbox.knorr.casa` | Public hostname |

Templated in helmfile:
| Key | Template | Description |
|-----|----------|-------------|
| `httpRoute.hostname` | `argocd{{ .Values.suffix }}.{{ .Values.domain }}` | Public hostname |
| `argo-cd.global.domain` | Same as hostname | ArgoCD domain |
| `argo-cd.configs.cm.url` | `https://{{ hostname }}` | Public URL |
| `argo-cd.configs.cm.oidc.config` | See helmfile | Keycloak OIDC configuration |

OIDC Configuration (from helmfile):
```yaml
oidc.config: |
  name: Keycloak
  issuer: https://keycloak{{ .Values.suffix }}.{{ .Values.domain }}/realms/sandbox
  clientID: argocd
  clientSecret: $oidc.keycloak.clientSecret
  requestedScopes:
    - openid
    - profile
    - email
    - groups
```

---

## Layer 3: Workloads (ArgoCD)

### cert-manager

Location: `values/cert-manager/values.yaml` (if exists) or chart defaults

Key resources created:
- **ClusterIssuer** `letsencrypt-prod`: DNS-01 solver with Cloudflare
- **Certificate** `sandbox-wildcard`: Wildcard cert for `*.sandbox.knorr.casa`

### Traefik

Location: `values/traefik/values.yaml` (if exists) or chart defaults

Key resources:
- **Gateway** `traefik-gateway`: Gateway API entry point
- **GatewayClass** `traefik`: Traefik as Gateway controller

### Keycloak

Location: `values/keycloak/values.yaml` (if exists) or chart defaults

Managed by Keycloak Operator:
- **Keycloak** CR: Defines instance configuration
- **KeycloakRealmImport** CR: Optional realm configuration

---

## HTTPRoute Template

All services use the `platform-library` chart for consistent HTTPRoute configuration:

| Key | Type | Description |
|-----|------|-------------|
| `httpRoute.enabled` | bool | Enable HTTPRoute creation |
| `httpRoute.hostname` | string | Hostname for the route |
| `httpRoute.gateway.name` | string | Gateway name (default: `traefik-gateway`) |
| `httpRoute.gateway.namespace` | string | Gateway namespace (default: `traefik`) |
| `httpRoute.service.name` | string | Backend service name |
| `httpRoute.service.port` | number | Backend service port |

Example:
```yaml
httpRoute:
  enabled: true
  hostname: myapp.sandbox.knorr.casa
  gateway:
    name: traefik-gateway
    namespace: traefik
  service:
    name: my-app
    port: 8080
```

---

## Secret References

### Required Secrets

| Secret Name | Namespace | Keys | Source |
|-------------|-----------|------|--------|
| `cloudflare-api-token` | cert-manager | `api-token` | Synced from Infisical |
| `infisical-machine-identity` | external-secrets | `clientId`, `clientSecret` | Created manually |

### Generated Secrets

| Secret Name | Namespace | Source | Consumer |
|-------------|-----------|--------|----------|
| `pgo-pguser-infisical` | pgo | PGO | Infisical |
| `pgo-pguser-keycloak` | pgo | PGO | Keycloak |
| `sandbox-wildcard-tls` | traefik | cert-manager | Traefik Gateway |
| `keycloak-initial-admin` | keycloak | Keycloak Operator | Admin login |

---

## Linode Instance Types

Common node types for LKE:

| Type | vCPUs | RAM | Storage | $/month |
|------|-------|-----|---------|---------|
| `g6-nanode-1` | 1 | 1GB | 25GB | $5 |
| `g6-standard-1` | 1 | 2GB | 50GB | $12 |
| `g6-standard-2` | 2 | 4GB | 80GB | $24 |
| `g6-standard-4` | 4 | 8GB | 160GB | $48 |
| `g6-standard-6` | 6 | 16GB | 320GB | $96 |

---

## Storage Classes

### Linode

| Class | Description | Reclaim |
|-------|-------------|---------|
| `linode-block-storage` | Block storage, delete on PVC delete | Delete |
| `linode-block-storage-retain` | Block storage, retain on PVC delete | Retain |

### DigitalOcean

| Class | Description | Reclaim |
|-------|-------------|---------|
| `do-block-storage` | DigitalOcean Volumes | Delete |
| `do-block-storage-retain` | DigitalOcean Volumes (custom) | Retain |
