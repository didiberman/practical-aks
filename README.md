# AKS Learning Lab: Production-Grade Kubernetes on Azure, for Cheap

> A hands-on educational project that walks you through building **highly available**, **secure** infrastructure with **automated CI/CD** on Azure Kubernetes Service — using real production patterns, not toy examples.

[![Terraform CI/CD](https://img.shields.io/badge/Terraform-CI%2FCD-7B42BC?logo=terraform)](https://github.com/features/actions)
[![App CI/CD](https://img.shields.io/badge/App-CI%2FCD%20%2B%20SecOps-2088FF?logo=github-actions)](https://github.com/features/actions)
[![AKS](https://img.shields.io/badge/Azure-AKS-0078D4?logo=microsoft-azure)](https://learn.microsoft.com/azure/aks/)
[![Trivy](https://img.shields.io/badge/Security-Trivy%20Scanned-1904DA?logo=aqua)](https://trivy.dev/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## What You Will Learn

By the time you've worked through this repo, you'll understand how real teams build and ship to Kubernetes. Each file in this project teaches something specific:

| File / Directory | What it teaches |
|---|---|
| `main.tf` | AKS networking, identities, RBAC, ACR — the full infra graph |
| `variables.tf` / `outputs.tf` | How to parameterise and surface Terraform state |
| `versions.tf` | Provider pinning and why it matters |
| `.github/workflows/tf-ci-cd.yml` | Gating infra changes with automated validation |
| `.github/workflows/app-ci-cd.yml` | MLOps + SecOps in a single pipeline |
| `app/Dockerfile` | Multi-stage hardened container builds |
| `app/index.js` | Secure secret retrieval via Workload Identity |
| `k8s/deployment.yaml` | Security contexts, health probes, resource bounds |
| `k8s/service.yaml` | ClusterIP + future ingress patterns |
| `deploy.sh` | Wiring Terraform outputs into K8s manifests |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        GitHub Actions                               │
│                                                                     │
│   ┌──────────────────┐          ┌───────────────────────────────┐  │
│   │  Terraform CI/CD │          │  App CI/CD + MLOps + SecOps   │  │
│   │                  │          │                               │  │
│   │ fmt → validate → │          │  prompt tests → trivy(k8s)   │  │
│   │ plan → apply     │          │  → build → trivy(image)      │  │
│   └────────┬─────────┘          └──────────────┬────────────────┘  │
└────────────│──────────────────────────────────│───────────────────┘
             │ OIDC (no long-lived keys)         │ push image
             ▼                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        Azure Subscription                           │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Resource Group: aks-learn-rg                                │  │
│  │                                                              │  │
│  │  ┌──────────────┐   AcrPull   ┌────────────────────────┐   │  │
│  │  │    ACR       │◄────────────│   AKS Cluster          │   │  │
│  │  │ (Standard)   │             │                        │   │  │
│  │  └──────────────┘             │  ┌──────────────────┐  │   │  │
│  │                               │  │  systempool      │  │   │  │
│  │  ┌──────────────┐             │  │  2x D2s_v5       │  │   │  │
│  │  │  Key Vault   │  Workload   │  │  AzureLinux      │  │   │  │
│  │  │  (Standard)  │◄────────────│  │                  │  │   │  │
│  │  │              │  Identity   │  │  ┌────────────┐  │  │   │  │
│  │  │  gemini-api  │  OIDC fed.  │  │  │ Pod        │  │  │   │  │
│  │  │  -key secret │             │  │  │ (non-root) │  │  │   │  │
│  │  └──────────────┘             │  │  └────────────┘  │  │   │  │
│  │                               │  └──────────────────┘  │   │  │
│  │  ┌──────────────┐             │                        │   │  │
│  │  │    VNet      │             │  Azure CNI Overlay     │   │  │
│  │  │ 10.240.0.0/16│◄────────────│  Pod CIDR: 192.168/16  │   │  │
│  │  │  aks-subnet  │  Network    │  Svc CIDR: 172.16/16   │   │  │
│  │  │ 10.240.0.0/22│  Contributor│  Policy:   Azure       │   │  │
│  │  └──────────────┘             └────────────────────────┘   │  │
│  │                                                              │  │
│  │  ┌───────────────────────┐  ┌─────────────────────────────┐ │  │
│  │  │  AKS Control Plane    │  │  App Managed Identity       │ │  │
│  │  │  User-Assigned        │  │  → KV Secrets User          │ │  │
│  │  │  Managed Identity     │  │  → Federated Credential     │ │  │
│  │  └───────────────────────┘  └─────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Why This Stack Is Cheap

Cloud Kubernetes gets expensive fast. This project makes deliberate choices to keep costs low without sacrificing the patterns that matter in production.

| Decision | Cost Impact | Why It's Still Production-Grade |
|---|---|---|
| `Standard_D2s_v5` (2 vCPU, 8 GiB) | ~$140/mo for 2 nodes | Burstable enough for LLM proxy workloads |
| `AzureLinux` OS SKU | Smaller image, faster boot | Fewer CVEs, smaller attack surface |
| `ACR Standard` SKU | ~$20/mo vs $50+ for Premium | Geo-replication not needed for a single region |
| `Key Vault Standard` SKU | ~$0.03/10k ops | HSM not required for learning |
| `node_count = 2` | Minimum for HA | Two nodes means pod disruption budget works |
| Azure CNI Overlay | No IP exhaustion tax | Pods get virtual IPs, not VNet IPs — scales cheaply |
| No public load balancer (ClusterIP) | $0 for the LB | Internal only; use port-forward or add ingress later |

**Estimated total**: ~$165–$180/month. Destroy with `terraform destroy` when not learning.

---

## Prerequisites

```bash
# Tools you need installed
az --version        # Azure CLI 2.50+
terraform --version # 1.5.0+
kubectl version     # 1.28+
docker --version    # any recent version
node --version      # 22 (for local app dev)

# Azure login
az login
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
```

You'll also need:
- A [Gemini API key](https://aistudio.google.com/apikey) (free tier is sufficient for learning)
- An Azure subscription with permission to create resource groups, assign roles, and register the `Microsoft.ContainerService` provider

---

## Quick Start (15 minutes)

```bash
# 1. Clone and configure
git clone https://github.com/<you>/aks.git && cd aks

# 2. Optionally override defaults in variables.tf, then provision everything
./deploy.sh

# 3. Upload your Gemini API key to Key Vault (emitted by deploy.sh)
az keyvault secret set \
  --vault-name "<KV_NAME>" \
  --name "gemini-api-key" \
  --value "<YOUR_GEMINI_KEY>"

# 4. Test the deployed service
kubectl port-forward service/aks-learning-app 8080:80

curl -X POST http://localhost:8080/api/generate \
  -H 'Content-Type: application/json' \
  -d '{"prompt": "explain workload identity in one sentence"}'
```

> **What `deploy.sh` does**: runs `terraform apply`, reads all outputs, logs into ACR, builds and pushes the Docker image, fetches kubeconfig, substitutes template placeholders in the K8s manifests, and runs `kubectl apply`. One script, zero manual steps.

---

## Deep Dive: Infrastructure (`main.tf`)

The Terraform file provisions resources in a deliberate order. Understanding the dependency graph is the first lesson.

### Module 1 — Networking

```hcl
resource "azurerm_virtual_network" "vnet" {
  address_space = ["10.240.0.0/16"]   # Room for 65,536 addresses
}

resource "azurerm_subnet" "aks_subnet" {
  address_prefixes = ["10.240.0.0/22"]  # 1,024 node IPs
}
```

**Why a dedicated subnet?** AKS needs to attach node NICs to a subnet it controls. Sharing subnets with other resources causes RBAC and IP-allocation conflicts.

**Azure CNI Overlay** (set in `network_profile`) means pods get IPs from a separate overlay range (`192.168.0.0/16`) — not from the VNet. This is the key to scaling cheaply: you don't burn VNet IP space per pod.

```
Node gets:   10.240.0.x  (real VNet IP)
Pod gets:    192.168.x.x (virtual, overlaid by the CNI)
Service gets: 172.16.0.x  (cluster-internal only)
```

### Module 2 — Identity (the most important part)

This project uses **three different identities**, each with the minimum permissions required:

```
┌─────────────────────────────────────────────────────────┐
│  Identity             Role              Scope            │
│─────────────────────────────────────────────────────────│
│  AKS Control Plane    Network Contrib.  aks-subnet only  │
│  Kubelet (AKS)        AcrPull           ACR only         │
│  App Pod              KV Secrets User   Key Vault only   │
└─────────────────────────────────────────────────────────┘
```

**Why User-Assigned for the control plane?** System-assigned identities are deleted when the resource is deleted. User-assigned identities survive cluster recreation — critical for disaster recovery scenarios.

### Module 3 — Workload Identity (Zero-Secret Secret Management)

This is the most architecturally interesting part of the project.

```
┌──────────────┐     OIDC token      ┌──────────────────────────┐
│  K8s Pod     │────────────────────►│  Azure AD / Entra ID     │
│  (SA token)  │                     │                          │
└──────────────┘                     │  Federated Credential:   │
       ▲                             │  issuer  = AKS OIDC URL  │
       │                             │  subject = k8s SA name   │
  ServiceAccount                     │                          │
  llm-service-sa                     │  → issues Azure token    │
                                     └──────────┬───────────────┘
                                                │
                                                ▼
                                     ┌──────────────────────┐
                                     │  Key Vault           │
                                     │  (KV Secrets User)   │
                                     └──────────────────────┘
```

The Terraform resources that make this work:

```hcl
# Step 1: Enable OIDC on the cluster
oidc_issuer_enabled       = true
workload_identity_enabled = true

# Step 2: Create the trust bridge
resource "azurerm_federated_identity_credential" "app_federated_credential" {
  issuer  = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject = "system:serviceaccount:default:llm-service-sa"
}
```

**The result**: the pod never receives a password, API key, or certificate. It gets a short-lived Kubernetes token, exchanges it for an Azure token, and calls Key Vault. Nothing to rotate. Nothing to leak.

---

## Deep Dive: The Application (`app/`)

The Node.js service demonstrates the **correct pattern** for reading secrets in a cloud-native app.

### Secret Resolution Order

```javascript
async function getApiKey() {
  // 1. Local dev: read from env var (fast iteration)
  if (process.env.GEMINI_API_KEY) return process.env.GEMINI_API_KEY;

  // 2. Production: DefaultAzureCredential picks up the Workload Identity
  //    token volume injected by the AKS webhook automatically
  const credential = new DefaultAzureCredential();
  const client = new SecretClient(keyVaultUri, credential);
  return (await client.getSecret(secretName)).value;
}
```

`DefaultAzureCredential` tries a chain of credential sources. Inside AKS with Workload Identity enabled, it automatically finds the projected token volume — no configuration required. Locally it falls through to `az login` credentials or env vars.

### Multi-Stage Docker Build

```dockerfile
# Stage 1: install only production deps
FROM node:22-alpine AS builder
RUN npm ci --only=production

# Stage 2: lean final image (no build tools)
FROM node:22-alpine
COPY --from=builder /usr/src/app/node_modules ./node_modules

# Never run as root
USER node
```

**Why two stages?** The builder stage can have `devDependencies`, build tools, and package caches. None of that goes into the final image. Smaller images mean faster pulls and a smaller CVE surface.

---

## Deep Dive: Kubernetes Manifests (`k8s/`)

### Security Context — Every Field Explained

```yaml
securityContext:
  allowPrivilegeEscalation: false  # Cannot gain more privs than parent process
  readOnlyRootFilesystem: true     # Filesystem is immutable at runtime
  runAsNonRoot: true               # Admission controller rejects root containers
  runAsUser: 1000                  # Matches the 'node' user in the Dockerfile
  capabilities:
    drop:
    - ALL                          # No Linux capabilities; not even NET_BIND_SERVICE
```

Drop all capabilities and add back only what you need. Most web services need exactly zero.

### Resource Bounds — Why Both Requests and Limits

```yaml
resources:
  requests:
    cpu: "100m"     # Scheduler uses this to place the pod
    memory: "128Mi"
  limits:
    cpu: "200m"     # Hard cap — pod is throttled, not killed
    memory: "256Mi" # Hard cap — pod is OOM-killed if exceeded
```

Without `requests`, the scheduler places pods blindly. Without `limits`, a single runaway process can starve every other pod on the node.

### Health Probes — The Difference Between Liveness and Readiness

```yaml
livenessProbe:   # "Is the process alive?" — restart if NO
  httpGet:
    path: /healthz
  periodSeconds: 10

readinessProbe:  # "Can this pod serve traffic?" — remove from Service if NO
  httpGet:
    path: /healthz
  periodSeconds: 5
```

A pod can be alive but not ready (e.g., still loading model weights). Kubernetes routes traffic only to ready pods. Use both.

---

## Deep Dive: CI/CD Pipelines (`.github/workflows/`)

### Pipeline 1 — Terraform CI/CD

```
PR opened                          PR merged to main
     │                                    │
     ▼                                    ▼
┌─────────────┐                  ┌──────────────────┐
│  validate   │                  │  plan & apply    │
│             │                  │  (commented out  │
│ fmt -check  │                  │   — activate     │
│ init        │                  │   when ready)    │
│ validate    │                  └──────────────────┘
└─────────────┘
```

`terraform fmt -check` fails the pipeline if files aren't formatted. This enforces a consistent style across contributors without argument.

The `plan_and_apply` job is intentionally commented out in the workflow. This is a learning decision: uncomment it, add your Azure secrets (see below), and you have a full GitOps infrastructure pipeline.

**OIDC Auth to Azure** (no stored credentials):

```yaml
permissions:
  id-token: write   # Required: lets GitHub request an OIDC token

steps:
  - uses: azure/login@v2
    with:
      client-id: ${{ secrets.AZURE_CLIENT_ID }}
      tenant-id: ${{ secrets.AZURE_TENANT_ID }}
      subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

GitHub exchanges its OIDC token for an Azure token. No `AZURE_CLIENT_SECRET` ever stored in GitHub Secrets.

### Pipeline 2 — App CI/CD + MLOps + SecOps

Three jobs run in parallel on every `app/` or `k8s/` change:

```
push to main (app/** or k8s/**)
         │
         ├──► prompt-validation-tests
         │    └─ npm test (Jest)
         │       Validates prompt formatting logic before any image is built.
         │       Catches regressions in the MLOps layer cheaply.
         │
         ├──► secops-manifest-scan
         │    └─ trivy config scan on k8s/
         │       Fails on HIGH/CRITICAL misconfigs (missing securityContext,
         │       privileged containers, etc.) before anything hits the cluster.
         │
         └──► build-and-scan-image
              ├─ docker buildx (multi-platform capable)
              └─ trivy image scan
                 Fails on HIGH/CRITICAL CVEs in OS packages or Node deps.
                 exit-code: '1' means a vulnerable image never gets pushed.
```

**Key insight**: Trivy runs on both the Kubernetes YAML (`scan-type: 'config'`) and the built Docker image (`image-ref`). These are different scanners catching different classes of problems — misconfigurations vs. CVEs.

---

## Activating the Full GitOps Pipeline

The `plan_and_apply` job in `tf-ci-cd.yml` is ready to uncomment. To enable it:

**1. Create a Service Principal for GitHub**

```bash
az ad sp create-for-rbac \
  --name "github-aks-deploy" \
  --role Contributor \
  --scopes /subscriptions/<SUBSCRIPTION_ID> \
  --sdk-auth
```

**2. Add GitHub Secrets**

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | `appId` from the SP output |
| `AZURE_TENANT_ID` | `tenant` from the SP output |
| `AZURE_SUBSCRIPTION_ID` | your subscription ID |

**3. Configure a Remote Backend** (required for team use)

```hcl
# Add to versions.tf before uncommenting plan_and_apply
terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstate<unique>"
    container_name       = "tfstate"
    key                  = "aks-learn.tfstate"
  }
}
```

**4. Uncomment the job** in `.github/workflows/tf-ci-cd.yml`

---

## Adding Ingress (Next Step After This Repo)

This project uses `ClusterIP` — the service is internal only. The natural next step is HTTPS ingress. Two options:

**Option A: NGINX Ingress Controller** (OSS, very common)

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --set controller.service.type=LoadBalancer
```

**Option B: Azure Application Gateway for Containers** (managed, no extra VM)

```hcl
# Add to main.tf
resource "azurerm_kubernetes_cluster" "aks" {
  # ...existing config...
  ingress_application_gateway {
    gateway_name = "${var.resource_prefix}-agw"
    subnet_cidr  = "10.240.4.0/28"
  }
}
```

Both terminate TLS and route external traffic to the `aks-learning-app` Service. NGINX is cheaper; AGfC is fully managed.

---

## Extending the System

Ideas for taking this further, ordered by difficulty:

| Extension | Concepts Covered |
|---|---|
| Add Horizontal Pod Autoscaler | `kubectl autoscale`, metrics-server |
| Add Pod Disruption Budget | `minAvailable: 1`, safe rolling updates |
| Add Network Policy | deny-all default, explicit allow rules |
| Add user node pool | taint/toleration, system vs user pools |
| Add KEDA for event-driven scale | Scale-to-zero, Azure Service Bus triggers |
| Add Azure Monitor + Prometheus | `--enable-azure-monitor-metrics`, Grafana |
| Swap Gemini for Azure OpenAI | Same Workload Identity pattern, different SDK |
| Add multi-environment (dev/prod) | Terraform workspaces or separate state files |

---

## Tearing Down

```bash
# Remove the K8s resources first (so Azure doesn't fight over managed resources)
kubectl delete -f k8s/

# Destroy all Azure infrastructure
terraform destroy
```

**Note**: The Key Vault has `purge_protection_enabled = false` intentionally. This means it can be fully deleted (including soft-deleted state) without waiting the default 90-day purge window — useful for a learning environment where you provision and destroy frequently.

---

## Project Structure

```
aks/
├── .github/
│   └── workflows/
│       ├── tf-ci-cd.yml        # Terraform format + validate + (plan/apply)
│       └── app-ci-cd.yml       # MLOps tests + K8s manifest scan + image build + CVE scan
├── app/
│   ├── Dockerfile              # Multi-stage, non-root, Alpine
│   ├── index.js                # Express LLM proxy, Workload Identity secret fetch
│   ├── package.json
│   ├── prompts/
│   │   └── system_prompt.txt   # Versioned system prompt (MLOps pattern)
│   └── test/
│       └── prompt.test.js      # Jest unit tests for prompt formatting
├── k8s/
│   ├── deployment.yaml         # ServiceAccount + Deployment with security context
│   └── service.yaml            # ClusterIP service
├── main.tf                     # All Azure resources (VNet, AKS, KV, ACR, Identities)
├── variables.tf                # Parameterised inputs
├── outputs.tf                  # Cluster name, KV URI, ACR server, etc.
├── versions.tf                 # Provider pinning
└── deploy.sh                   # End-to-end provisioning + deploy script
```

---

## Security Checklist

Every item on this list is implemented in the project — trace each one back to a specific file:

- [x] **No long-lived credentials** — Workload Identity + OIDC everywhere (`main.tf` lines 116–123)
- [x] **Secrets in Key Vault, not env vars** — `app/index.js` `getApiKey()`
- [x] **RBAC on Key Vault** — `enable_rbac_authorization = true` (`main.tf` line 91)
- [x] **ACR admin disabled** — `admin_enabled = false` (`main.tf` line 132)
- [x] **Non-root containers** — `USER node` in Dockerfile, `runAsNonRoot: true` in deployment
- [x] **Read-only filesystem** — `readOnlyRootFilesystem: true` in deployment
- [x] **All capabilities dropped** — `capabilities.drop: [ALL]` in deployment
- [x] **Resource limits set** — prevents noisy-neighbour CPU/memory issues
- [x] **K8s manifests scanned** — Trivy config scan in CI (`app-ci-cd.yml`)
- [x] **Container image scanned** — Trivy image scan in CI on every build
- [x] **Azure Network Policies** — `network_policy = "azure"` in AKS network profile
- [x] **Minimum RBAC scope** — each identity has exactly one role on exactly one resource

---

## Contributing

This is a learning resource. If you find a security issue, a better practice, or a concept that isn't well explained — open an issue or a PR.
