# Platform (Ingress & TLS)

This sets up Traefik with Gateway API, cert-manager, and TLS for `*.knorr.casa`.

## Install Gateway API CRDs

Gateway API requires CRDs to be installed first:

```bash
# Ensure kubeconfig is set
export KUBECONFIG=/path/to/tofu/environments/sandbox/kubeconfig.yaml

# Install Gateway API CRDs (standard channel)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

# Verify
kubectl get crds | grep gateway
# Should see: gatewayclasses, gateways, httproutes, etc.
```

## Install cert-manager

```bash
# Add Helm repo
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager with CRDs
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.2 \
  --set crds.enabled=true \
  --wait

# Verify pods are running
kubectl get pods -n cert-manager
```

## Create Cloudflare API Secret

Create the secret for DNS-01 challenges:

```bash
# Create namespace for secrets if needed
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

# Create the secret (replace with your actual token)
kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token=YOUR_CLOUDFLARE_TOKEN_HERE
```

## Create ClusterIssuer

**File: `bootstrap/cert-manager/clusterissuer.yaml`**
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    # Production Let's Encrypt
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com  # Change to your email
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
        selector:
          dnsZones:
            - "knorr.casa"
```

Apply it:
```bash
kubectl apply -f bootstrap/cert-manager/clusterissuer.yaml

# Verify issuers are ready
kubectl get clusterissuer
# STATUS should show Ready: True
```

## Install Traefik with Gateway API

**File: `bootstrap/traefik/values.yaml`**
```yaml
# Traefik Helm values for Gateway API mode

# Enable Gateway API provider
providers:
  kubernetesGateway:
    enabled: true

# Disable default IngressRoute provider (using Gateway API instead)
ingressRoute:
  dashboard:
    enabled: false

# Enable Traefik dashboard (accessible via HTTPRoute)
api:
  dashboard: true
  insecure: true

# Service configuration - creates NodeBalancer on Linode
service:
  type: LoadBalancer
  annotations:
    # Linode-specific annotations (optional)
    service.beta.kubernetes.io/linode-loadbalancer-throttle: "4"

# Gateway configuration - Traefik will create the Gateway resource
gateway:
  enabled: true
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  listeners:
    web:
      port: 8000
      protocol: HTTP
      hostname: "*.sandbox.knorr.casa"
      namespacePolicy:
        from: All
    websecure:
      port: 8443
      protocol: HTTPS
      hostname: "*.sandbox.knorr.casa"
      namespacePolicy:
        from: All
      certificateRefs:
        - name: sandbox-wildcard-tls
          kind: Secret
      mode: Terminate
    # Apex domain listener
    websecure-apex:
      port: 8443
      protocol: HTTPS
      hostname: "sandbox.knorr.casa"
      namespacePolicy:
        from: All
      certificateRefs:
        - name: sandbox-wildcard-tls
          kind: Secret
      mode: Terminate

# Entry points
ports:
  traefik:
    port: 9000
    expose:
      default: true
    exposedPort: 9000
    protocol: TCP
  web:
    port: 8000
    exposedPort: 80
    protocol: TCP
    redirections:
      entryPoint:
        to: websecure
        scheme: https
        permanent: true
  websecure:
    port: 8443
    exposedPort: 443
    protocol: TCP

# Enable access logs (optional, helpful for debugging)
logs:
  access:
    enabled: true

# Resource limits
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"

# Create HTTPRoute for Traefik dashboard
extraObjects:
- |
  apiVersion: gateway.networking.k8s.io/v1
  kind: HTTPRoute
  metadata:
    name: traefik-dashboard
    namespace: traefik
  spec:
    parentRefs:
      - name: traefik-gateway
        namespace: traefik
    hostnames:
      - "traefik.sandbox.knorr.casa"
    rules:
      - matches:
          - path:
              type: PathPrefix
              value: /
        backendRefs:
          - name: traefik
            port: 9000

additionalArguments:
- "--api.insecure=true"
```

Install Traefik:
```bash
# Add Helm repo
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Install
helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --values bootstrap/traefik/values.yaml \
  --wait

# Check the service - note the EXTERNAL-IP
kubectl get svc -n traefik traefik
# May take 1-2 minutes for IP assignment
```

## Get NodeBalancer IP & Update DNS

```bash
# Get the external IP
kubectl get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Go to Cloudflare and create DNS records:

1. **Log into Cloudflare Dashboard** → select `knorr.casa`
2. **DNS** → **Records** → **Add record**
3. Create these records:

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| A | sandbox | YOUR_NODEBALANCER_IP | DNS only (gray cloud) |
| A | *.sandbox | YOUR_NODEBALANCER_IP | DNS only (gray cloud) |

**Note:** Use "DNS only" (gray cloud), not "Proxied" (orange cloud). Proxied mode interferes with TLS certificate validation.

## Verify Gateway Created by Traefik

With `gateway.enabled: true` in the Traefik Helm values, the Gateway and GatewayClass are created automatically. Verify they exist:

```bash
# Check GatewayClass
kubectl get gatewayclass

# Check Gateway (created by Traefik Helm chart)
kubectl get gateway -n traefik
kubectl describe gateway traefik-gateway -n traefik
```

The Gateway is named `traefik-gateway` and already has the listeners configured for HTTP, HTTPS wildcard, and HTTPS apex domain.

## Request Wildcard Certificate

**File: `bootstrap/cert-manager/certificate.yaml`**
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: sandbox-wildcard
  namespace: traefik
spec:
  secretName: sandbox-wildcard-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - "sandbox.knorr.casa"
    - "*.sandbox.knorr.casa"
```

Apply and watch:
```bash
kubectl apply -f bootstrap/cert-manager/certificate.yaml

# Watch certificate progress (takes 1-2 minutes for DNS-01)
kubectl get certificate -n traefik -w

# Check for issues
kubectl describe certificate sandbox-wildcard -n traefik
kubectl get certificaterequest -n traefik
kubectl describe certificaterequest -n traefik

# Check cert-manager logs if stuck
kubectl logs -n cert-manager -l app=cert-manager -f
```

## Test with a Sample App

Create a test app to verify the setup works end-to-end:

```yaml
# Simple nginx deployment for testing
# Save this as test-app.yaml or apply inline
apiVersion: v1
kind: Namespace
metadata:
  name: test-app
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: test-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: test-app
spec:
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
---
# HTTPRoute - routes traffic to the app
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: nginx-route
  namespace: test-app
spec:
  parentRefs:
    - name: traefik-gateway
      namespace: traefik
  hostnames:
    - "test.sandbox.knorr.casa"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: nginx
          port: 80
```

Deploy and test:
```bash
kubectl apply -f test-app.yaml

# Wait for pod to be ready
kubectl get pods -n test-app -w

# Test in browser or curl
curl https://test.sandbox.knorr.casa

# Should see nginx welcome page!
```

## Verify Everything

```bash
# Check all components
echo "=== Nodes ==="
kubectl get nodes

echo "=== cert-manager ==="
kubectl get pods -n cert-manager

echo "=== Traefik ==="
kubectl get pods -n traefik
kubectl get svc -n traefik

echo "=== Gateway ==="
kubectl get gateway -n traefik
kubectl get gatewayclass

echo "=== Certificate ==="
kubectl get certificate -n traefik

echo "=== HTTPRoutes ==="
kubectl get httproute -A

echo "=== Test App ==="
kubectl get pods -n test-app
```

## Troubleshooting

**Certificate stuck in "Pending":**
```bash
kubectl describe certificate sandbox-wildcard -n traefik
kubectl get challenges -A
kubectl describe challenge -n traefik <challenge-name>
```

**Gateway not accepting routes:**
```bash
kubectl describe gateway traefik-gateway -n traefik
# Check "Status" section for listener conditions
```

**No external IP on service:**
```bash
kubectl describe svc traefik -n traefik
# Check events for NodeBalancer creation errors
```

**DNS not resolving:**
```bash
dig test.sandbox.knorr.casa
# Should return your NodeBalancer IP
```

---

## Summary

You now have:
- ✅ LKE cluster (2x 4GB nodes)
- ✅ Firewall rules (including webhook callbacks)
- ✅ Gateway API with Traefik (gateway auto-created by Helm)
- ✅ Traefik dashboard at `https://traefik.sandbox.knorr.casa`
- ✅ Wildcard TLS certificate for `*.sandbox.knorr.casa`
- ✅ Automatic HTTP→HTTPS redirect
- ✅ Working HTTPRoute example

**Estimated monthly cost:** ~$58
- LKE nodes: $48 (2x $24)
- NodeBalancer: $10

**Next steps for your sandbox:**
- Deploy applications with HTTPRoutes
- Add more namespaces for different projects
- Consider adding monitoring (optional)
- When ready for the full platform, you have the patterns down!
