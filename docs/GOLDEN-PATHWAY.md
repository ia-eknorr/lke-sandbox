# Golden Pathway: Kubernetes Platform Deployment

This document defines a standardized, repeatable approach for deploying Kubernetes platforms across cloud providers (AWS EKS, Linode LKE, etc.) using a three-layer architecture.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        LAYER 3: WORKLOADS                           │
│  ApplicationSets for business applications and platform services    │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐              │
│  │ App A    │ │ App B    │ │ Monitoring│ │ Logging  │ ...          │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘              │
├─────────────────────────────────────────────────────────────────────┤
│                       LAYER 2: BOOTSTRAP                            │
│  Core services required for GitOps self-management                  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐              │
│  │ ArgoCD   │ │ Ext.Sec. │ │ Traefik  │ │cert-mgr  │              │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘              │
├─────────────────────────────────────────────────────────────────────┤
│                      LAYER 1: INFRASTRUCTURE                        │
│  Cloud resources provisioned via IaC (OpenTofu/Terraform)           │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐              │
│  │ K8s      │ │ VPC/     │ │ IAM/     │ │ Secrets  │              │
│  │ Cluster  │ │ Network  │ │ RBAC     │ │ Manager  │              │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘              │
└─────────────────────────────────────────────────────────────────────┘
```

## Layer Responsibilities

### Layer 1: Infrastructure
**Provisioned by**: OpenTofu/Terraform
**Lifecycle**: Rarely changes after initial setup
**Contains**:
- Kubernetes cluster (EKS, LKE, GKE)
- Networking (VPC, subnets, security groups/firewalls)
- IAM roles and policies
- Cloud secrets manager setup
- DNS zones (optional)
- Container registries (optional)

### Layer 2: Bootstrap
**Provisioned by**: Helm + kubectl (manual or CI script)
**Lifecycle**: Changes infrequently, requires careful coordination
**Contains**:
- ArgoCD (enables GitOps for everything else)
- External Secrets Operator (enables secret management)
- Cert-Manager (enables TLS certificates)
- Ingress Controller (Traefik, NGINX, or ALB Controller)
- External DNS (optional)
- Initial secrets (Git credentials, cloud credentials)

**Why manual?** These services have circular dependencies:
- ArgoCD needs secrets to pull private repos
- External Secrets needs to be deployed before it can provide secrets
- The bootstrap layer breaks this cycle

### Layer 3: Workloads
**Provisioned by**: ArgoCD ApplicationSets
**Lifecycle**: Changes frequently, fully automated
**Contains**:
- Business applications
- Database operators (PGO, PXC)
- Monitoring stack (Prometheus, Grafana)
- Logging stack (Loki, Promtail)
- Additional platform services
- Environment-specific configurations

## Directory Structure

```
repo/
├── tofu/                           # LAYER 1: Infrastructure
│   ├── modules/
│   │   ├── lke-cluster/           # Linode LKE module
│   │   ├── eks-cluster/           # AWS EKS module (if needed)
│   │   ├── firewall/              # Cloud firewall rules
│   │   └── iam/                   # IAM roles/policies
│   └── environments/
│       ├── sandbox/               # Sandbox environment
│       ├── dev/                   # Development environment
│       ├── staging/               # Staging environment
│       └── prod/                  # Production environment
│
├── bootstrap/                      # LAYER 2: Bootstrap
│   ├── README.md                  # Bootstrap instructions
│   ├── install.sh                 # Bootstrap installation script
│   ├── charts/                    # Bootstrap Helm charts
│   │   ├── argocd/
│   │   ├── external-secrets/
│   │   ├── cert-manager/
│   │   └── traefik/
│   └── values/                    # Bootstrap values per environment
│       ├── sandbox/
│       ├── dev/
│       └── prod/
│
├── charts/                         # LAYER 3: Workload Helm charts
│   ├── cluster-config/            # Cluster-wide resources
│   ├── app-template/              # Template for new apps
│   └── {service}/                 # Service-specific charts
│
├── values/                         # LAYER 3: Workload values
│   └── {chart}/
│       ├── common-values.yaml     # Shared across environments
│       ├── dev/
│       │   ├── config.yaml        # Environment metadata
│       │   └── values.yaml        # Dev-specific values
│       ├── staging/
│       └── prod/
│
├── appsets/                        # LAYER 3: ApplicationSet definitions
│   ├── appset-dev.yaml
│   ├── appset-staging.yaml
│   └── appset-prod.yaml
│
└── docs/                           # Documentation
    ├── GOLDEN-PATHWAY.md          # This document
    ├── 01-infrastructure.md
    ├── 02-bootstrap.md
    └── 03-workloads.md
```

## Deployment Sequence

### Step 1: Infrastructure (Layer 1)

```bash
# Navigate to environment
cd tofu/environments/sandbox

# Set required environment variables
export LINODE_TOKEN="..."        # For LKE
# OR
export AWS_PROFILE="..."         # For EKS

# Initialize and apply
tofu init
tofu plan
tofu apply

# Export kubeconfig
export KUBECONFIG=$(tofu output -raw kubeconfig_path)

# Verify cluster access
kubectl cluster-info
kubectl get nodes
```

### Step 2: Bootstrap (Layer 2)

```bash
# Run bootstrap script (or manually apply each step)
./bootstrap/install.sh sandbox

# OR manually:

# 1. Install Gateway API CRDs (if using Gateway API)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

# 2. Install cert-manager
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true --wait

# 3. Create initial secrets (cloud credentials)
kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token=$CLOUDFLARE_API_TOKEN

# 4. Apply cert-manager resources (ClusterIssuer, Certificates)
helm upgrade --install cert-manager-config bootstrap/charts/cert-manager \
  -f bootstrap/values/sandbox/cert-manager.yaml \
  --namespace cert-manager --wait

# 5. Install ingress controller (Traefik)
helm upgrade --install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  -f bootstrap/values/sandbox/traefik.yaml --wait

# 6. Install External Secrets Operator
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace \
  --wait

# 7. Create secret store credentials
kubectl create secret generic aws-secret-manager-credentials \
  --namespace external-secrets \
  --from-literal=access-key=$AWS_ACCESS_KEY_ID \
  --from-literal=secret-key=$AWS_SECRET_ACCESS_KEY

# 8. Install ArgoCD
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  -f bootstrap/values/sandbox/argocd.yaml --wait

# 9. Create ArgoCD Git credentials
kubectl create secret generic repo-creds \
  --namespace argocd \
  --from-literal=url=https://github.com/YOUR_ORG \
  --from-literal=username=git \
  --from-literal=password=$GITHUB_TOKEN

# 10. Apply bootstrap ApplicationSet (manages bootstrap services via GitOps)
kubectl apply -f bootstrap/appset-bootstrap.yaml
```

### Step 3: Workloads (Layer 3)

```bash
# Apply workload ApplicationSets
# (ArgoCD will automatically sync all charts/values combinations)

kubectl apply -f appsets/appset-sandbox.yaml

# Verify applications are syncing
kubectl get applications -n argocd
```

## Values Hierarchy

Values are merged in this order (later overrides earlier):

```
1. charts/{service}/values.yaml           # Chart defaults
2. values/{service}/common-values.yaml    # Cross-environment defaults
3. values/{service}/{env}/values.yaml     # Environment-specific
```

### Example: cert-manager values

**`charts/cert-manager/values.yaml`** (chart defaults):
```yaml
clusterIssuer:
  enabled: true

certificate:
  enabled: true
```

**`values/cert-manager/common-values.yaml`** (shared config):
```yaml
clusterIssuer:
  name: letsencrypt-prod
  server: https://acme-v02.api.letsencrypt.org/directory

certificate:
  namespace: traefik
```

**`values/cert-manager/sandbox/values.yaml`** (environment-specific):
```yaml
clusterIssuer:
  email: admin@example.com

certificate:
  name: sandbox-wildcard
  secretName: sandbox-wildcard-tls
  dnsNames:
    - sandbox.example.com
    - "*.sandbox.example.com"

cloudflare:
  secretName: cloudflare-api-token
```

## ApplicationSet Pattern

### Matrix Generator (Recommended)

The matrix generator combines chart directories with environment configs:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: workloads-sandbox
  namespace: argocd
spec:
  goTemplate: true
  generators:
    - matrix:
        generators:
          # Generator 1: Find all charts
          - git:
              repoURL: https://github.com/YOUR_ORG/YOUR_REPO.git
              revision: HEAD
              directories:
                - path: charts/*
                - path: charts/cluster-config
                  exclude: true  # Handled separately if needed
          # Generator 2: Find matching config files
          - git:
              repoURL: https://github.com/YOUR_ORG/YOUR_REPO.git
              revision: HEAD
              files:
                - path: "values/{{ index .path.segments 1 }}/sandbox/config.yaml"
  template:
    metadata:
      name: "{{ index .path.segments 1 }}-sandbox"
      annotations:
        argocd.argoproj.io/sync-wave: "{{ .syncWave | default \"0\" }}"
    spec:
      project: default
      source:
        repoURL: https://github.com/YOUR_ORG/YOUR_REPO.git
        targetRevision: HEAD
        path: "charts/{{ index .path.segments 1 }}"
        helm:
          ignoreMissingValueFiles: true
          valueFiles:
            - "../../values/{{ index .path.segments 1 }}/common-values.yaml"
            - "../../values/{{ index .path.segments 1 }}/sandbox/values.yaml"
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{ .namespace | default (index .path.segments 1) }}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
```

### Config.yaml Structure

Each environment needs a `config.yaml` for the ApplicationSet generator:

```yaml
# values/{chart}/sandbox/config.yaml
namespace: cert-manager
syncWave: "-1"  # Optional: controls deployment order
```

## Cloud Provider Differences

### Linode (LKE)

```yaml
# Infrastructure
- Uses NodeBalancer for LoadBalancer services
- Firewall via Linode Cloud Firewall
- No native secrets manager (use External Secrets with AWS/Vault)

# Ingress
- Traefik or NGINX Ingress Controller
- Gateway API supported

# DNS
- External-DNS with Cloudflare/Route53
- Or manual DNS management
```

### AWS (EKS)

```yaml
# Infrastructure
- Uses AWS Load Balancer Controller for ALB/NLB
- Security Groups for pod networking
- AWS Secrets Manager for secrets

# Ingress
- AWS Load Balancer Controller (ALB Ingress)
- Or Traefik/NGINX

# DNS
- External-DNS with Route53
- ACM for managed certificates
```

## Adding a New Service

1. **Create the chart** (or use existing upstream):
   ```bash
   mkdir -p charts/my-service/templates
   # Create Chart.yaml, values.yaml, templates/
   ```

2. **Create values hierarchy**:
   ```bash
   mkdir -p values/my-service/{dev,staging,prod}
   touch values/my-service/common-values.yaml
   touch values/my-service/dev/config.yaml
   touch values/my-service/dev/values.yaml
   ```

3. **Commit and push**:
   ```bash
   git add charts/my-service values/my-service
   git commit -m "Add my-service chart and values"
   git push
   ```

4. **ArgoCD auto-discovers** the new service via ApplicationSet

## Best Practices

### Do
- Keep charts generic, put specifics in values
- Use `common-values.yaml` for settings shared across environments
- Use sync waves to control deployment order
- Use External Secrets for all sensitive data
- Version your charts with `Chart.yaml` version field
- Use `ignoreMissingValueFiles: true` for optional value files

### Don't
- Hardcode environment-specific values in charts
- Store secrets in Git (use External Secrets)
- Mix bootstrap and workload services in the same layer
- Skip the bootstrap layer for "simple" deployments

## Troubleshooting

### ArgoCD not syncing
```bash
# Check application status
argocd app list
argocd app get <app-name>

# Check for sync errors
argocd app sync <app-name> --dry-run
```

### ApplicationSet not generating apps
```bash
# Check generator output
kubectl get applicationset <name> -n argocd -o yaml

# Check logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller
```

### Values not merging correctly
```bash
# Test helm template locally
helm template charts/my-service \
  -f values/my-service/common-values.yaml \
  -f values/my-service/dev/values.yaml
```