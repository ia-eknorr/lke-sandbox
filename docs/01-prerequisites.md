# Prerequisites & Project Setup

## Create Linode API Token

1. Log into Linode Cloud Manager: https://cloud.linode.com
2. Click your profile icon (top right) → **API Tokens**
3. Click **Create a Personal Access Token**
4. Configure:
   - **Label:** `sandbox-tofu`
   - **Expiry:** 6 months (or your preference)
   - **Permissions:** Read/Write for:
     - Linodes
     - Kubernetes (LKE)
     - NodeBalancers
     - Firewalls
     - IPs
5. Click **Create Token**
6. **Copy immediately** - won't be shown again
7. Store securely (password manager)

## Create Cloudflare API Token

You'll need this for cert-manager DNS-01 challenges later.

1. Log into Cloudflare: https://dash.cloudflare.com
2. Profile icon → **My Profile** → **API Tokens**
3. Click **Create Token**
4. Use **Edit zone DNS** template, or create custom:
   - **Permissions:** Zone → DNS → Edit
   - **Zone Resources:** Include → Specific zone → `knorr.casa`
5. **Create Token** and copy immediately
6. Store securely

## Install Required Tools

```bash
# OpenTofu
brew install opentofu

# Kubernetes CLI
brew install kubectl

# Helm (for platform layer)
brew install helm

# Optional but useful
brew install k9s
brew install jq
```

Verify installations:
```bash
tofu version
kubectl version --client
helm version
```

## Repository Structure

Navigate to your existing repo and create this structure:

```bash
cd /path/to/your/repo

# Create directory structure
mkdir -p tofu/modules/lke-cluster
mkdir -p tofu/modules/firewall
mkdir -p tofu/environments/sandbox
mkdir -p bootstrap/cert-manager
mkdir -p bootstrap/traefik
mkdir -p bootstrap/charts
mkdir -p docs
```

Your repo should look like:
```
lke-sandbox/
├── tofu/
│   ├── modules/
│   │   ├── lke-cluster/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   └── firewall/
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   └── environments/
│       └── sandbox/
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           ├── providers.tf
│           └── kubeconfig.yaml  (gitignored, generated)
├── bootstrap/
│   ├── cert-manager/
│   │   ├── clusterissuer.yaml
│   │   └── certificate.yaml
│   ├── traefik/
│   │   └── values.yaml
│   └── charts/
└── docs/
```

## Environment Variables

Set up your Linode token for OpenTofu. Choose one method:

**Option A: Export in shell (temporary)**
```bash
export LINODE_TOKEN="your-token-here"
```

**Option B: Use a .envrc file (with direnv)**
```bash
# In repo root, create .envrc
echo 'export LINODE_TOKEN="your-token-here"' > .envrc
direnv allow
```

**Option C: terraform.tfvars (we'll use this)**

We'll put non-sensitive config in `terraform.tfvars` and pass the token via environment variable.

## Git Ignore Setup

Add to your `.gitignore`:
```gitignore
# OpenTofu
*.tfstate
*.tfstate.*
.terraform/
.terraform.lock.hcl
terraform.tfvars
*.tfvars

# Credentials
.envrc
kubeconfig*
*.kubeconfig

# OS
.DS_Store
```

## Quick Verification

Before proceeding, verify you can authenticate with Linode:

```bash
export LINODE_TOKEN="your-token-here"

# Test with curl
curl -H "Authorization: Bearer $LINODE_TOKEN" \
  https://api.linode.com/v4/profile

# Should return your profile info
```

---

## Next Steps

Once you have:

- [ ] Linode API token created and stored
- [ ] Cloudflare API token created and stored
- [ ] Tools installed (tofu, kubectl, helm)
- [ ] Repository structure created
- [ ] LINODE_TOKEN environment variable working

Proceed to [02-lke-cluster.md](02-lke-cluster.md) to create the LKE cluster.
