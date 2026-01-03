# Implementation Guide: Restructuring to Golden Pathway

This guide walks you through restructuring your lke-sandbox repository to follow the three-layer golden pathway architecture with Vault for secrets management.

## Prerequisites

Before starting, ensure you have:
- [ ] `kubectl` configured with your LKE cluster
- [ ] `helm` v3 installed
- [ ] `tofu` (OpenTofu) installed
- [ ] Git repository cloned locally

## Overview

You'll be restructuring from:
```
lke-sandbox/
├── bootstrap/
│   ├── cert-manager/     ← Raw YAML manifests
│   ├── traefik/          ← Helm values only
│   └── charts/           ← Empty
└── tofu/
```

To:
```
lke-sandbox/
├── bootstrap/            ← Layer 2: Bootstrap services
│   ├── charts/           ← Helm charts for bootstrap
│   ├── values/           ← Values per environment
│   └── install.sh        ← Bootstrap script
├── charts/               ← Layer 3: Workload charts + Platform Library
│   └── platform-library/ ← Shared templates (used by all layers)
├── values/               ← Layer 3: Workload values
├── appsets/              ← ArgoCD ApplicationSets
└── tofu/                 ← Layer 1: Infrastructure (unchanged)
```

---

## Phase 1: Create New Directory Structure

### Step 1.1: Create Bootstrap Directories

```bash
# Navigate to your repo root
cd /Users/eknorr/IA/code/personal/lke-sandbox

# Create bootstrap chart directories
mkdir -p bootstrap/charts/argocd/templates
mkdir -p bootstrap/charts/vault/templates
mkdir -p bootstrap/charts/external-secrets/templates
mkdir -p bootstrap/charts/cert-manager/templates
mkdir -p bootstrap/charts/traefik/templates

# Create bootstrap values directory
mkdir -p bootstrap/values/sandbox
```

**Why this structure?** Each bootstrap service gets its own Helm chart directory. Even if you're wrapping an upstream chart (like HashiCorp's Vault), having your own chart gives you:
- Custom templates (ClusterSecretStore, Issuers, etc.)
- Controlled dependency versions
- Environment-specific templating

### Step 1.2: Create Workload Directories

```bash
# Create platform library (shared templates for all layers)
mkdir -p charts/platform-library/templates

# Create workload chart directories
mkdir -p charts/cert-manager/templates
mkdir -p charts/cluster-config/templates
mkdir -p charts/app-template/templates  # Template for new apps

# Create workload values directories
mkdir -p values/cert-manager/sandbox
mkdir -p values/traefik/sandbox
mkdir -p values/cluster-config/sandbox

# Create ApplicationSet directory
mkdir -p appsets
```

### Step 1.3: Verify Structure

```bash
# Display the new structure
tree -L 3 -d --prune
```

Expected output:
```
.
├── appsets
├── bootstrap
│   ├── charts
│   │   ├── argocd
│   │   ├── cert-manager
│   │   ├── external-secrets
│   │   ├── traefik
│   │   └── vault
│   └── values
│       └── sandbox
├── charts
│   ├── app-template
│   ├── cert-manager
│   ├── cluster-config
│   └── platform-library  ← Shared templates for all layers
├── docs
├── tofu
│   ├── environments
│   └── modules
└── values
    ├── cert-manager
    ├── cluster-config
    └── traefik
```

---

## Phase 2: Create Bootstrap Charts

The bootstrap layer includes services needed before GitOps can self-manage. These are deployed manually (or via CI) at cluster creation time.

### Step 2.0: Create the Platform Library Chart

Before creating individual service charts, we'll create a **library chart** that contains shared templates. This eliminates duplication and ensures consistency across all services.

**Why a library chart?**
- Single source of truth for common templates (HTTPRoute, labels, etc.)
- One place to update when patterns change
- Consistent behavior across all bootstrap and workload charts
- Reduces maintenance as you add more services

**Why in `charts/` instead of `bootstrap/charts/`?**
- Bootstrap is "set and forget" - deployed once at cluster creation
- The library evolves as you add new services and patterns
- Workload charts in `charts/` will frequently reference it
- Keeps the shared library alongside the services that use it most

Create the library chart directory (already done in Step 1.2, verify it exists):
```bash
mkdir -p charts/platform-library/templates
```

Create `charts/platform-library/Chart.yaml`:
```yaml
apiVersion: v2
name: platform-library
description: Shared Helm templates for the platform
type: library  # This makes it a library chart - cannot be installed directly
version: 0.1.0
```

Create `charts/platform-library/templates/_helpers.tpl`:
```yaml
{{/*
Common name helper - uses release name
*/}}
{{- define "platform.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "platform.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "platform.selectorLabels" -}}
app.kubernetes.io/name: {{ include "platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

Create `charts/platform-library/templates/_httproute.tpl`:
```yaml
{{/*
HTTPRoute template for Gateway API
Usage: {{ include "platform.httproute" . }}
*/}}
{{- define "platform.httproute" -}}
{{- if .Values.httpRoute.enabled }}
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ include "platform.name" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "platform.labels" . | nindent 4 }}
  {{- with .Values.httpRoute.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  parentRefs:
    - name: {{ .Values.httpRoute.gateway.name | default "traefik-gateway" }}
      namespace: {{ .Values.httpRoute.gateway.namespace | default "traefik" }}
  hostnames:
    {{- if .Values.httpRoute.hostnames }}
    {{- toYaml .Values.httpRoute.hostnames | nindent 4 }}
    {{- else if .Values.httpRoute.hostname }}
    - {{ .Values.httpRoute.hostname | quote }}
    {{- end }}
  rules:
    {{- if .Values.httpRoute.rules }}
    {{- range .Values.httpRoute.rules }}
    - matches:
        {{- toYaml .matches | nindent 8 }}
      {{- with .filters }}
      filters:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      backendRefs:
        - name: {{ $.Values.httpRoute.service.name | default (include "platform.name" $) }}
          port: {{ $.Values.httpRoute.service.port }}
    {{- end }}
    {{- else }}
    - matches:
        - path:
            type: PathPrefix
            value: {{ .Values.httpRoute.path | default "/" }}
      backendRefs:
        - name: {{ .Values.httpRoute.service.name | default (include "platform.name" .) }}
          port: {{ .Values.httpRoute.service.port }}
    {{- end }}
{{- end }}
{{- end }}
```

Create `charts/platform-library/templates/_ingress.tpl` (for AWS ALB compatibility):
```yaml
{{/*
Ingress template for AWS ALB or other ingress controllers
Usage: {{ include "platform.ingress" . }}
*/}}
{{- define "platform.ingress" -}}
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "platform.name" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "platform.labels" . | nindent 4 }}
  {{- with .Values.ingress.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- with .Values.ingress.className }}
  ingressClassName: {{ . }}
  {{- end }}
  {{- if .Values.ingress.tls }}
  tls:
    {{- range .Values.ingress.tls }}
    - hosts:
        {{- range .hosts }}
        - {{ . | quote }}
        {{- end }}
      secretName: {{ .secretName }}
    {{- end }}
  {{- end }}
  rules:
    {{- range .Values.ingress.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            pathType: {{ .pathType | default "Prefix" }}
            backend:
              service:
                name: {{ .serviceName | default (include "platform.name" $) }}
                port:
                  number: {{ .servicePort | default $.Values.ingress.service.port }}
          {{- end }}
    {{- end }}
{{- end }}
{{- end }}
```

Create `charts/platform-library/values.yaml` (default values for documentation):
```yaml
# Default values for platform-library
# These serve as documentation for expected values structure

httpRoute:
  enabled: false
  hostname: ""           # Single hostname (string)
  hostnames: []          # Multiple hostnames (array) - takes precedence
  annotations: {}
  gateway:
    name: traefik-gateway
    namespace: traefik
  service:
    name: ""             # Defaults to release name
    port: 80
  path: "/"
  rules: []              # Custom rules (optional)

ingress:
  enabled: false
  className: ""
  annotations: {}
  hosts: []
  tls: []
  service:
    port: 80
```

**Verify the library chart:**
```bash
helm lint charts/platform-library
```

You should see: `1 chart(s) linted, 0 chart(s) failed`

---

### Step 2.1: PGO (PostgreSQL Operator) Chart

**Why PGO first?** CrunchyData PostgreSQL Operator provides databases for Keycloak and Infisical. It must be running before dependent services.

The chart is already created at `bootstrap/charts/pgo/`. Here's the structure:

```
bootstrap/charts/pgo/
├── Chart.yaml                    # Wrapper for upstream PGO
├── values.yaml                   # Default values
└── templates/
    └── postgrescluster.yaml      # PostgresCluster CR for mgmt database
```

**Chart.yaml** (already exists):
```yaml
apiVersion: v2
name: pgo
description: Deploy the PGO Postgres Operator
version: 1.0.0
appVersion: 5.8.2
type: application
dependencies:
- name: pgo
  version: 5.8.2
  repository: oci://registry.developers.crunchydata.com/crunchydata
```

**Key PostgresCluster configuration:**
- Creates a `mgmt` cluster with PostgreSQL 16
- PgBouncer proxy for connection pooling
- Users: `keycloak`, `infisical` (each with their own database)
- Backups via pgBackRest

**Note:** Update storage classes for your environment:
- AWS: `gp3` (data), `efs` (backups)
- Linode: `linode-block-storage` or `null` (default)

---

### Step 2.2: Keycloak Operator Chart

**Why Keycloak?** Provides OIDC authentication for ArgoCD, Infisical, and other services. Uses the Keycloak Operator pattern for CRD-based management.

The chart is already created at `bootstrap/charts/keycloak-operator/`. Here's the structure:

```
bootstrap/charts/keycloak-operator/
├── Chart.yaml
├── values.yaml
├── crds/                          # Keycloak CRDs
│   ├── keycloaks.k8s.keycloak.org-v1.yml
│   └── keycloakrealmimports.k8s.keycloak.org-v1.yml
└── templates/
    ├── _helpers.tpl
    ├── deployment.yaml            # Keycloak Operator deployment
    ├── rbac.yaml
    ├── service.yaml
    ├── serviceaccount.yaml
    ├── certificate.yaml           # TLS certificate
    ├── ingressroutetcp.yaml       # Traefik IngressRouteTCP for TLS passthrough
    └── keycloak.yaml              # Keycloak CR instance
```

**Key features:**
- Uses Keycloak Operator (CRD-based)
- TLS passthrough via Traefik IngressRouteTCP
- Connects to PGO PostgreSQL via PgBouncer
- 2 replicas with pod anti-affinity

**values.yaml key settings:**
```yaml
ingress:
  enabled: true
  useTraefik: true  # Uses IngressRouteTCP for TLS passthrough
  # hostname: keycloak.sandbox.knorr.casa  # Set per environment

db:
  host: mgmt-pgbouncer.pgo.svc  # PGO PgBouncer service
```

---

### Step 2.3: Infisical Chart

**Why Infisical?** Modern secrets management with a developer-friendly UI. Provides secrets to applications via External Secrets Operator.

Create `bootstrap/charts/infisical/Chart.yaml`:
```yaml
apiVersion: v2
name: infisical
description: Self-hosted Infisical secrets management platform
type: application
version: 0.1.0
appVersion: "0.93.1"

dependencies:
  # Platform library for shared templates
  - name: platform-library
    version: "0.1.0"
    repository: "file://../../charts/platform-library"
  # Upstream Infisical chart
  - name: infisical-standalone
    version: "1.7.2"
    repository: "https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/"
    alias: infisical
```

Create `bootstrap/charts/infisical/values.yaml`:
```yaml
infisical:
  # Use external PostgreSQL from PGO
  postgresql:
    enabled: false

  # Use bundled Redis for sandbox (or external for production)
  redis:
    enabled: true

  backend:
    replicaCount: 1
    image:
      tag: "v0.93.1-postgres"

  frontend:
    replicaCount: 1

  # Disable upstream ingress - we use HTTPRoute
  ingress:
    enabled: false

# HTTPRoute configuration (Gateway API)
httpRoute:
  enabled: true
  hostname: ""  # Set in environment values
  gateway:
    name: traefik-gateway
    namespace: traefik
  service:
    name: infisical-backend
    port: 8080
```

**Pre-requisites:** Before deploying, create the `infisical-secrets` Kubernetes secret:
```bash
# Generate secrets
ENCRYPTION_KEY=$(openssl rand -hex 16)
AUTH_SECRET=$(openssl rand -hex 16)

# Create secret (replace password with actual PGO-generated password)
kubectl create secret generic infisical-secrets \
  --namespace infisical \
  --from-literal=ENCRYPTION_KEY=$ENCRYPTION_KEY \
  --from-literal=AUTH_SECRET=$AUTH_SECRET \
  --from-literal=DB_CONNECTION_URI="postgres://infisical:PASSWORD@mgmt-pgbouncer.pgo.svc:5432/infisical" \
  --from-literal=SITE_URL="https://infisical.sandbox.knorr.casa" \
  --from-literal=REDIS_URL="redis://infisical-redis-master:6379"
```

Create `bootstrap/charts/infisical/templates/httproute.yaml`:
```yaml
{{/* Use the shared HTTPRoute template from platform-library */}}
{{ include "platform.httproute" . }}
```

---

### Step 2.4: Create External Secrets Bootstrap Chart

Create `bootstrap/charts/external-secrets/Chart.yaml`:
```yaml
apiVersion: v2
name: external-secrets
description: External Secrets Operator for Kubernetes
type: application
version: 0.1.0
appVersion: "0.9.0"

dependencies:
  - name: external-secrets
    version: "1.2.0"
    repository: "https://charts.external-secrets.io"
```

Create `bootstrap/charts/external-secrets/values.yaml`:
```yaml
external-secrets:
  installCRDs: true

  webhook:
    port: 9443

  certController:
    requeueInterval: "5m"

  serviceAccount:
    create: true
    name: external-secrets

# ClusterSecretStore configuration for Infisical
clusterSecretStore:
  enabled: true
  name: infisical

  # Infisical instance URL
  infisicalUrl: ""  # Set in environment values

  # Reference to secret containing Infisical Machine Identity credentials
  secretRef:
    name: infisical-machine-identity
    namespace: external-secrets
    clientIdKey: clientId
    clientSecretKey: clientSecret
```

Create `bootstrap/charts/external-secrets/templates/clustersecretstore.yaml`:
```yaml
{{- if .Values.clusterSecretStore.enabled }}
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: {{ .Values.clusterSecretStore.name }}
  labels:
    app.kubernetes.io/managed-by: Helm
spec:
  provider:
    infisical:
      siteUrl: {{ .Values.clusterSecretStore.infisicalUrl | quote }}
      auth:
        universalAuthCredentials:
          clientId:
            secretRef:
              name: {{ .Values.clusterSecretStore.secretRef.name }}
              namespace: {{ .Values.clusterSecretStore.secretRef.namespace }}
              key: {{ .Values.clusterSecretStore.secretRef.clientIdKey }}
          clientSecret:
            secretRef:
              name: {{ .Values.clusterSecretStore.secretRef.name }}
              namespace: {{ .Values.clusterSecretStore.secretRef.namespace }}
              key: {{ .Values.clusterSecretStore.secretRef.clientSecretKey }}
{{- end }}
```

**Pre-requisites:** Create a Machine Identity in Infisical, then create the credentials secret:
```bash
kubectl create secret generic infisical-machine-identity \
  --namespace external-secrets \
  --from-literal=clientId=YOUR_CLIENT_ID \
  --from-literal=clientSecret=YOUR_CLIENT_SECRET
```

### Step 2.3: Create Cert-Manager Bootstrap Chart

Create `bootstrap/charts/cert-manager/Chart.yaml`:
```yaml
apiVersion: v2
name: cert-manager
description: TLS certificate management with Let's Encrypt
type: application
version: 0.1.0
appVersion: "1.14.0"

dependencies:
  - name: cert-manager
    version: "v1.19.2"
    repository: "https://charts.jetstack.io"
```

Create `bootstrap/charts/cert-manager/values.yaml`:
```yaml
cert-manager:
  installCRDs: true

  # For Gateway API integration
  featureGates: "ExperimentalGatewayAPISupport=true"

  prometheus:
    enabled: false

# ClusterIssuer configuration
clusterIssuer:
  enabled: true
  name: letsencrypt-prod
  email: ""  # Set in environment values
  server: https://acme-v02.api.letsencrypt.org/directory
  privateKeySecretRef: letsencrypt-prod-account-key

  # DNS-01 solver configuration
  dns01:
    provider: cloudflare
    cloudflare:
      email: ""  # Set in environment values
      apiTokenSecretRef:
        name: cloudflare-api-token
        key: api-token

# Certificate configuration
certificate:
  enabled: true
  name: ""  # Set in environment values
  namespace: traefik
  secretName: ""  # Set in environment values
  dnsNames: []  # Set in environment values
```

Create `bootstrap/charts/cert-manager/templates/clusterissuer.yaml`:
```yaml
{{- if .Values.clusterIssuer.enabled }}
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: {{ .Values.clusterIssuer.name }}
spec:
  acme:
    email: {{ .Values.clusterIssuer.email }}
    server: {{ .Values.clusterIssuer.server }}
    privateKeySecretRef:
      name: {{ .Values.clusterIssuer.privateKeySecretRef }}
    solvers:
      - dns01:
          cloudflare:
            email: {{ .Values.clusterIssuer.dns01.cloudflare.email }}
            apiTokenSecretRef:
              name: {{ .Values.clusterIssuer.dns01.cloudflare.apiTokenSecretRef.name }}
              key: {{ .Values.clusterIssuer.dns01.cloudflare.apiTokenSecretRef.key }}
{{- end }}
```

Create `bootstrap/charts/cert-manager/templates/certificate.yaml`:
```yaml
{{- if .Values.certificate.enabled }}
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: {{ .Values.certificate.name }}
  namespace: {{ .Values.certificate.namespace }}
spec:
  secretName: {{ .Values.certificate.secretName }}
  issuerRef:
    name: {{ .Values.clusterIssuer.name }}
    kind: ClusterIssuer
  dnsNames:
    {{- range .Values.certificate.dnsNames }}
    - {{ . | quote }}
    {{- end }}
{{- end }}
```

### Step 2.4: Create Traefik Bootstrap Chart

Create `bootstrap/charts/traefik/Chart.yaml`:
```yaml
apiVersion: v2
name: traefik
description: Traefik ingress controller with Gateway API support
type: application
version: 0.1.0
appVersion: "3.0.0"

dependencies:
  - name: traefik
    version: "38.0.1"
    repository: "https://traefik.github.io/charts"
```

Move your existing Traefik values to `bootstrap/charts/traefik/values.yaml`:
```bash
# Copy your existing values as the base
cp bootstrap/traefik/values.yaml bootstrap/charts/traefik/values.yaml
```

Then wrap it under the `traefik:` key (since it's a dependency):
```yaml
# bootstrap/charts/traefik/values.yaml
traefik:
  # Paste your existing values here, indented under traefik:
  providers:
    kubernetesGateway:
      enabled: true
  # ... rest of your values
```

### Step 2.5: Create ArgoCD Bootstrap Chart

Create `bootstrap/charts/argocd/Chart.yaml`:
```yaml
apiVersion: v2
name: argocd
description: ArgoCD for GitOps continuous delivery
type: application
version: 0.1.0
appVersion: "2.10.0"

dependencies:
  # Platform library for shared templates (in charts/ directory)
  - name: platform-library
    version: "0.1.0"
    repository: "file://../../charts/platform-library"
  # Upstream ArgoCD chart
  - name: argo-cd
    version: "8.3.5"
    repository: "https://argoproj.github.io/argo-helm"
```

Create `bootstrap/charts/argocd/values.yaml`:
```yaml
argo-cd:
  global:
    domain: argocd.sandbox.knorr.casa

  configs:
    params:
      server.insecure: true  # TLS terminated at gateway

    cm:
      url: https://argocd.sandbox.knorr.casa

      # Enable Helm value files from outside chart directory
      helm.valuesFileSchemes: >-
        secrets+gpg-import, secrets+gpg-import-kubernetes,
        secrets+age-import, secrets+age-import-kubernetes,
        secrets, secrets+literal,
        https, file

  server:
    # Disable upstream Ingress - we use HTTPRoute instead
    ingress:
      enabled: false

    # Disable built-in certificate (using wildcard via Gateway)
    certificate:
      enabled: false

  # Disable dex (use built-in auth for now)
  dex:
    enabled: false

# HTTPRoute configuration (Gateway API)
httpRoute:
  enabled: true
  hostname: ""  # Set in environment values
  gateway:
    name: traefik-gateway
    namespace: traefik
  service:
    name: argocd-server
    port: 80

# Repository credentials (will be created via External Secrets)
repoCredentials:
  enabled: false  # Enable after Vault/ESO are running
```

Create `bootstrap/charts/argocd/templates/httproute.yaml`:
```yaml
{{/* Use the shared HTTPRoute template from platform-library */}}
{{ include "platform.httproute" . }}
```

---

## Phase 2.5: Understanding the HTTPRoute Pattern

All bootstrap services use **Gateway API (HTTPRoute)** instead of traditional Ingress for consistency. This section explains the pattern and how the platform library simplifies it.

### Why HTTPRoute for Everything?

| Aspect | Our Approach |
|--------|--------------|
| **Consistency** | Same routing pattern for bootstrap and workload layers |
| **Modern API** | Gateway API is the future of Kubernetes ingress |
| **Traefik native** | Traefik handles both, but Gateway API is its preferred mode |
| **Library chart** | `platform-library` provides reusable templates |

### How the Platform Library Works

The `platform-library` chart (created in Step 2.0 at `charts/platform-library/`) provides shared templates that all other charts use. Here's the pattern:

**1. Add library as dependency in Chart.yaml:**

For bootstrap charts (in `bootstrap/charts/`):
```yaml
dependencies:
  - name: platform-library
    version: "0.1.0"
    repository: "file://../../charts/platform-library"
```

For workload charts (in `charts/`):
```yaml
dependencies:
  - name: platform-library
    version: "0.1.0"
    repository: "file://../platform-library"
```

**2. Disable upstream Ingress in values:**
```yaml
upstream-chart:
  server:
    ingress:
      enabled: false
```

**3. Add HTTPRoute configuration to values:**
```yaml
httpRoute:
  enabled: true
  hostname: ""  # Set per environment
  gateway:
    name: traefik-gateway
    namespace: traefik
  service:
    name: <service-name>
    port: <service-port>
```

**4. Create a one-line template file:**
```yaml
# templates/httproute.yaml
{{ include "platform.httproute" . }}
```

That's it! The library handles all the complexity.

### Available Library Templates

The `platform-library` provides these templates:

| Template | Include Statement | Purpose |
|----------|-------------------|---------|
| HTTPRoute | `{{ include "platform.httproute" . }}` | Gateway API routing |
| Ingress | `{{ include "platform.ingress" . }}` | AWS ALB / traditional ingress |
| Labels | `{{ include "platform.labels" . }}` | Consistent Kubernetes labels |
| Name | `{{ include "platform.name" . }}` | Resource naming |

### Values Structure Reference

The library expects this values structure for HTTPRoute:

```yaml
httpRoute:
  enabled: true                    # Enable/disable the route
  hostname: "app.example.com"      # Single hostname (string)
  # OR
  hostnames:                       # Multiple hostnames (array)
    - "app.example.com"
    - "app2.example.com"
  annotations: {}                  # Optional annotations
  gateway:
    name: traefik-gateway          # Gateway name (default: traefik-gateway)
    namespace: traefik             # Gateway namespace (default: traefik)
  service:
    name: ""                       # Service name (default: release name)
    port: 80                       # Service port
  path: "/"                        # Path prefix (default: /)
  rules: []                        # Custom rules (optional, advanced)
```

### Switching Between HTTPRoute and Ingress

The library supports both patterns. To use Ingress instead (e.g., for AWS ALB):

```yaml
# Disable HTTPRoute
httpRoute:
  enabled: false

# Enable Ingress
ingress:
  enabled: true
  className: alb
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
  hosts:
    - host: app.example.com
      paths:
        - path: /
          pathType: Prefix
  service:
    port: 80
```

Then create `templates/ingress.yaml`:
```yaml
{{ include "platform.ingress" . }}
```

### Bootstrap Services Using HTTPRoute

| Service | Hostname Pattern | Service:Port |
|---------|-----------------|--------------|
| Keycloak | `keycloak.<env>.knorr.casa` | TLS passthrough via IngressRouteTCP |
| Infisical | `infisical.<env>.knorr.casa` | `infisical-backend:8080` |
| ArgoCD | `argocd.<env>.knorr.casa` | `argocd-server:80` |
| Traefik Dashboard | `traefik.<env>.knorr.casa` | `traefik:9000` |
| Grafana (future) | `grafana.<env>.knorr.casa` | `grafana:3000` |

---

## Phase 3: Create Bootstrap Values

### Step 3.1: Create Sandbox Environment Values

Create `bootstrap/values/sandbox/infisical.yaml`:
```yaml
# Sandbox-specific Infisical configuration

# HTTPRoute for Infisical UI access
httpRoute:
  hostname: infisical.sandbox.knorr.casa
```

Create `bootstrap/values/sandbox/keycloak.yaml`:
```yaml
# Sandbox-specific Keycloak configuration

ingress:
  hostname: keycloak.sandbox.knorr.casa

certificate:
  issuerName: letsencrypt-prod
```

Create `bootstrap/values/sandbox/external-secrets.yaml`:
```yaml
# Sandbox-specific External Secrets configuration

clusterSecretStore:
  enabled: true
  name: infisical
  infisicalUrl: "https://infisical.sandbox.knorr.casa"
```

Create `bootstrap/values/sandbox/cert-manager.yaml`:
```yaml
# Sandbox-specific cert-manager configuration

clusterIssuer:
  email: etknorr@gmail.com
  dns01:
    cloudflare:
      email: etknorr@gmail.com

certificate:
  name: sandbox-wildcard
  secretName: sandbox-wildcard-tls
  dnsNames:
    - sandbox.knorr.casa
    - "*.sandbox.knorr.casa"
```

Create `bootstrap/values/sandbox/traefik.yaml`:
```yaml
# Sandbox-specific Traefik configuration

traefik:
  gateway:
    listeners:
      websecure:
        hostname: "*.sandbox.knorr.casa"
      websecure-apex:
        hostname: sandbox.knorr.casa
```

Create `bootstrap/values/sandbox/argocd.yaml`:
```yaml
# Sandbox-specific ArgoCD configuration

argo-cd:
  global:
    domain: argocd.sandbox.knorr.casa

  configs:
    cm:
      url: https://argocd.sandbox.knorr.casa

# HTTPRoute for ArgoCD UI access
httpRoute:
  hostname: argocd.sandbox.knorr.casa
```

---

## Phase 4: Create Bootstrap Installation Script

Create `bootstrap/install.sh`:
```bash
#!/bin/bash
set -euo pipefail

# Bootstrap installation script
# Usage: ./bootstrap/install.sh <environment>
# Example: ./bootstrap/install.sh sandbox

ENVIRONMENT="${1:-sandbox}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=========================================="
echo "Bootstrapping environment: ${ENVIRONMENT}"
echo "=========================================="

# Check prerequisites
command -v kubectl >/dev/null 2>&1 || { echo "kubectl required but not found"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "helm required but not found"; exit 1; }

# Verify cluster connection
echo "Verifying cluster connection..."
kubectl cluster-info || { echo "Cannot connect to cluster"; exit 1; }

# Function to install a bootstrap chart
install_chart() {
    local chart=$1
    local namespace=$2
    local extra_args="${3:-}"

    echo ""
    echo "----------------------------------------"
    echo "Installing ${chart} in namespace ${namespace}"
    echo "----------------------------------------"

    # Update dependencies
    helm dependency update "${SCRIPT_DIR}/charts/${chart}" 2>/dev/null || true

    # Build values file arguments
    local values_args="-f ${SCRIPT_DIR}/charts/${chart}/values.yaml"
    if [[ -f "${SCRIPT_DIR}/values/${ENVIRONMENT}/${chart}.yaml" ]]; then
        values_args="${values_args} -f ${SCRIPT_DIR}/values/${ENVIRONMENT}/${chart}.yaml"
    fi

    # Install/upgrade
    helm upgrade --install "${chart}" "${SCRIPT_DIR}/charts/${chart}" \
        --namespace "${namespace}" \
        --create-namespace \
        ${values_args} \
        ${extra_args} \
        --wait --timeout 5m
}

# Step 1: Install Gateway API CRDs
echo ""
echo "=========================================="
echo "Step 1: Installing Gateway API CRDs"
echo "=========================================="
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

# Step 2: Install cert-manager
echo ""
echo "=========================================="
echo "Step 2: Installing cert-manager"
echo "=========================================="
install_chart "cert-manager" "cert-manager"

# Step 3: Create Cloudflare secret (if not exists)
echo ""
echo "=========================================="
echo "Step 3: Creating Cloudflare API token secret"
echo "=========================================="
if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
    echo "WARNING: CLOUDFLARE_API_TOKEN not set"
    echo "Set it with: export CLOUDFLARE_API_TOKEN='your-token'"
else
    kubectl create secret generic cloudflare-api-token \
        --namespace cert-manager \
        --from-literal=api-token="${CLOUDFLARE_API_TOKEN}" \
        --dry-run=client -o yaml | kubectl apply -f -
fi

# Step 4: Install Traefik
echo ""
echo "=========================================="
echo "Step 4: Installing Traefik"
echo "=========================================="
install_chart "traefik" "traefik"

# Step 5: Install PGO (PostgreSQL Operator)
echo ""
echo "=========================================="
echo "Step 5: Installing PGO (PostgreSQL Operator)"
echo "=========================================="
install_chart "pgo" "pgo"

# Wait for PGO operator to be ready
echo "Waiting for PGO operator..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=pgo -n pgo --timeout=120s || true

# Wait for PostgresCluster to be ready
echo "Waiting for PostgresCluster to be ready (this may take a few minutes)..."
kubectl wait --for=condition=ready pod -l postgres-operator.crunchydata.com/cluster=mgmt -n pgo --timeout=300s || true

# Step 6: Install Keycloak
echo ""
echo "=========================================="
echo "Step 6: Installing Keycloak"
echo "=========================================="
install_chart "keycloak-operator" "keycloak"

# Wait for Keycloak to be ready
echo "Waiting for Keycloak..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n keycloak --timeout=180s || true

# Step 7: Install Infisical
echo ""
echo "=========================================="
echo "Step 7: Installing Infisical"
echo "=========================================="
install_chart "infisical" "infisical"

# Wait for Infisical to be ready
echo "Waiting for Infisical..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=infisical -n infisical --timeout=120s || true

# Step 8: Install External Secrets
echo ""
echo "=========================================="
echo "Step 8: Installing External Secrets"
echo "=========================================="
install_chart "external-secrets" "external-secrets"

# Step 9: Install ArgoCD
echo ""
echo "=========================================="
echo "Step 9: Installing ArgoCD"
echo "=========================================="
install_chart "argocd" "argocd"

# Get ArgoCD initial password
echo ""
echo "=========================================="
echo "Bootstrap Complete!"
echo "=========================================="
echo ""
echo "ArgoCD initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo ""
echo "Access ArgoCD at: https://argocd.${ENVIRONMENT}.knorr.casa"
echo "Access Keycloak at: https://keycloak.${ENVIRONMENT}.knorr.casa"
echo "Access Infisical at: https://infisical.${ENVIRONMENT}.knorr.casa"
echo ""
echo "Next steps:"
echo "1. Configure Keycloak realm and create OIDC clients"
echo "2. Configure Infisical and create Machine Identity for External Secrets"
echo "3. Create ArgoCD repository credentials"
echo "4. Apply workload ApplicationSets"
```

Make it executable:
```bash
chmod +x bootstrap/install.sh
```

---

## Phase 5: Create Workload Charts

### Step 5.1: Create Cluster Config Chart

This chart contains cluster-wide resources that don't fit elsewhere.

Create `charts/cluster-config/Chart.yaml`:
```yaml
apiVersion: v2
name: cluster-config
description: Cluster-wide configuration resources
type: application
version: 0.1.0
appVersion: "1.0.0"
```

Create `charts/cluster-config/values.yaml`:
```yaml
# Default values for cluster-config

storageClasses:
  enabled: false
  classes: []

namespaces:
  enabled: true
  names:
    - ignition
    - monitoring
    - logging
```

Create `charts/cluster-config/templates/namespaces.yaml`:
```yaml
{{- if .Values.namespaces.enabled }}
{{- range .Values.namespaces.names }}
---
apiVersion: v1
kind: Namespace
metadata:
  name: {{ . }}
{{- end }}
{{- end }}
```

### Step 5.2: Create App Template Chart

This is a starting point for new applications.

Create `charts/app-template/Chart.yaml`:
```yaml
apiVersion: v2
name: app-template
description: Template chart for new applications
type: application
version: 0.1.0
appVersion: "1.0.0"
```

Create `charts/app-template/values.yaml`:
```yaml
# Application configuration
app:
  name: my-app
  replicas: 1

  image:
    repository: nginx
    tag: latest
    pullPolicy: IfNotPresent

  service:
    type: ClusterIP
    port: 80

  ingress:
    enabled: false
    className: traefik
    host: ""
    tls:
      enabled: true
      secretName: sandbox-wildcard-tls

  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 256Mi

# HTTPRoute for Gateway API (alternative to Ingress)
httpRoute:
  enabled: true
  parentRef:
    name: traefik-gateway
    namespace: traefik
```

Create `charts/app-template/templates/deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.app.name }}
  labels:
    app: {{ .Values.app.name }}
spec:
  replicas: {{ .Values.app.replicas }}
  selector:
    matchLabels:
      app: {{ .Values.app.name }}
  template:
    metadata:
      labels:
        app: {{ .Values.app.name }}
    spec:
      containers:
        - name: {{ .Values.app.name }}
          image: "{{ .Values.app.image.repository }}:{{ .Values.app.image.tag }}"
          imagePullPolicy: {{ .Values.app.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.app.service.port }}
          resources:
            {{- toYaml .Values.app.resources | nindent 12 }}
```

Create `charts/app-template/templates/service.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.app.name }}
spec:
  type: {{ .Values.app.service.type }}
  ports:
    - port: {{ .Values.app.service.port }}
      targetPort: {{ .Values.app.service.port }}
  selector:
    app: {{ .Values.app.name }}
```

Create `charts/app-template/templates/httproute.yaml`:
```yaml
{{- if .Values.httpRoute.enabled }}
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ .Values.app.name }}
spec:
  parentRefs:
    - name: {{ .Values.httpRoute.parentRef.name }}
      namespace: {{ .Values.httpRoute.parentRef.namespace }}
  hostnames:
    - {{ .Values.app.ingress.host | quote }}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: {{ .Values.app.name }}
          port: {{ .Values.app.service.port }}
{{- end }}
```

---

## Phase 6: Create Workload Values

### Step 6.1: Create Common Values

Create `values/cluster-config/common-values.yaml`:
```yaml
# Common values for cluster-config across all environments

namespaces:
  enabled: true
```

Create `values/cluster-config/sandbox/config.yaml`:
```yaml
# ApplicationSet metadata for cluster-config in sandbox
namespace: kube-system
syncWave: "-2"
```

Create `values/cluster-config/sandbox/values.yaml`:
```yaml
# Sandbox-specific cluster-config values

namespaces:
  names:
    - ignition
    - monitoring
    - logging
```

---

## Phase 7: Create ApplicationSet

Create `appsets/appset-sandbox.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: workloads-sandbox
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - matrix:
        generators:
          # Generator 1: Find all workload charts
          - git:
              repoURL: https://github.com/YOUR_USERNAME/lke-sandbox.git
              revision: HEAD
              directories:
                - path: charts/*
          # Generator 2: Find matching config files
          - git:
              repoURL: https://github.com/YOUR_USERNAME/lke-sandbox.git
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
        repoURL: https://github.com/YOUR_USERNAME/lke-sandbox.git
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

---

## Phase 8: Update CLAUDE.md

Update your project's `CLAUDE.md` to reflect the new structure:

```markdown
# CLAUDE.md

## Project Overview

LKE Sandbox is a Kubernetes platform following the three-layer golden pathway architecture.

## Architecture

### Layer 1: Infrastructure (OpenTofu)
- `tofu/modules/` - Reusable infrastructure modules
- `tofu/environments/` - Environment-specific configurations

### Layer 2: Bootstrap (Helm + Manual)
- `bootstrap/charts/` - Core platform services (ArgoCD, Vault, cert-manager, etc.)
- `bootstrap/values/` - Environment-specific bootstrap values
- `bootstrap/install.sh` - Bootstrap installation script

### Layer 3: Workloads (ArgoCD ApplicationSets)
- `charts/` - Application Helm charts
- `values/` - Environment-specific application values
- `appsets/` - ArgoCD ApplicationSet definitions

## Commands

### Infrastructure
```bash
cd tofu/environments/sandbox
export LINODE_TOKEN="..."
tofu init && tofu apply
export KUBECONFIG=$(tofu output -raw kubeconfig_path)
```

### Bootstrap
```bash
export CLOUDFLARE_API_TOKEN="..."
./bootstrap/install.sh sandbox
```

### Workloads
```bash
kubectl apply -f appsets/appset-sandbox.yaml
```
```

---

## Phase 9: Clean Up Old Structure

After verifying the new structure works:

```bash
# Move old bootstrap files to backup (optional)
mkdir -p _backup
mv bootstrap/cert-manager _backup/
mv bootstrap/traefik _backup/

# Or delete them
rm -rf bootstrap/cert-manager
rm -rf bootstrap/traefik
rm -rf bootstrap/charts  # The old empty directory
```

---

## Verification Checklist

After completing all phases, verify:

- [ ] Directory structure matches the golden pathway
- [ ] All Chart.yaml files are valid (`helm lint charts/*`)
- [ ] All values files are valid YAML
- [ ] Bootstrap script runs without errors
- [ ] ArgoCD is accessible and healthy
- [ ] Vault is accessible and initialized
- [ ] Wildcard certificate is issued
- [ ] ApplicationSet generates expected Applications

## Next Steps

1. **Add more workload charts** - Copy `app-template` and customize
2. **Configure Vault secrets** - Add actual secrets for applications
3. **Set up Kargo** - For automated environment promotions
4. **Add monitoring** - Prometheus/Grafana stack
5. **Add logging** - Loki/Promtail stack
