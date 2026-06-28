# AKS Learning Lab: Production-Grade Kubernetes on Azure, for Cheap

> A hands-on educational project that walks you through building **highly available**, **secure** infrastructure with **automated CI/CD** on Azure Kubernetes Service — using real production patterns, not toy examples.

[![Terraform CI/CD](https://img.shields.io/badge/Terraform-CI%2FCD-7B42BC?logo=terraform)](https://github.com/features/actions)
[![App CI/CD](https://img.shields.io/badge/App-CI%2FCD%20%2B%20SecOps-2088FF?logo=github-actions)](https://github.com/features/actions)
[![AKS](https://img.shields.io/badge/Azure-AKS-0078D4?logo=microsoft-azure)](https://learn.microsoft.com/azure/aks/)
[![Trivy](https://img.shields.io/badge/Security-Trivy%20Scanned-1904DA?logo=aqua)](https://trivy.dev/)
[![StepSecurity](https://img.shields.io/badge/Supply%20Chain-Harden--Runner-orange?logo=github)](https://github.com/step-security/harden-runner)
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

## Supply Chain Security: The Trivy Attack and Why It Matters Here

> **This project was directly affected.** Our original workflow used `aquasecurity/trivy-action@master` — the exact reference that was weaponised in the March 2026 attack. This section explains what happened and what we changed.

### What Happened (March 19, 2026)

Attackers compromised Aqua Security's GitHub credentials and force-pushed **76 of 77 version tags** in `aquasecurity/trivy-action` — including `@master` — to point at malicious commits. The payload injected a credential stealer into `entrypoint.sh` that ran *before* the legitimate Trivy scan. Pipelines looked completely normal. Logs showed a clean scan. Meanwhile, CI/CD secrets (cloud tokens, GitHub tokens, SSH keys) were being encrypted and exfiltrated to `scan.aquasecurtiy.org` — a typosquatted domain designed to blend into network logs.

Over 1,000 enterprise environments were hit. The stolen credentials were later used in ransomware extortion.

```
Before the fix — our workflow:             What that line actually ran on March 19:

uses: aquasecurity/trivy-action@master     → malicious commit
                                             ├── entrypoint.sh (patched)
                                             │   └── steal secrets, encrypt, exfil
                                             └── run real trivy (looks normal)
```

**The root cause was a floating reference.** Tags and branch names are mutable pointers — anyone with write access to the repo can silently redirect them. `@master`, `@v3`, `@latest` are all the same class of risk.

### What We Changed

**Fix 1: Pin to a commit SHA, not a tag.**

```yaml
# Before (vulnerable):
uses: aquasecurity/trivy-action@master

# After (safe — SHA is immutable, cannot be redirected):
uses: aquasecurity/trivy-action@57a97c7e7821a5776cebc9bb87c984fa69cba8f1 # v0.35.0
```

A commit SHA cannot be force-pushed. Once a commit exists, its SHA is cryptographically bound to its content. This is the first line of defence.

**Fix 2: Add `step-security/harden-runner` as the external security layer.**

SHA pinning stops *known-bad* references. But it doesn't help if you're running a SHA you think is good and it isn't (orphaned commits, submodule tricks). `harden-runner` is the second layer: it installs a network agent on the runner *before any other step runs* and enforces an egress allowlist.

```yaml
- name: Harden Runner
  uses: step-security/harden-runner@9af89fc71515a100421586dfdb3dc9c984fbf411 # v2.19.4
  with:
    egress-policy: audit   # → 'block' with allowed-endpoints once you've baselined
```

In `audit` mode it logs all outbound connections. Switch to `block` mode with an explicit allowlist and a compromised action physically cannot reach an attacker's server — the syscall is intercepted at the kernel level before the packet leaves the runner.

Had `harden-runner` with `block` mode been in place on March 19, the connection to `scan.aquasecurtiy.org` would have been blocked and logged. The exfiltration would have failed even though the malicious code ran.

**Fix 3: Minimum `permissions` at the workflow level.**

```yaml
permissions:
  contents: read  # workflow-level default
```

If a compromised action tries to push code back to your repository using the `GITHUB_TOKEN`, this stops it. The token simply doesn't have write permission.

### The Layered Defence Model

```
Attack surface          Our control               What it stops
─────────────────────────────────────────────────────────────────────
Mutable tag reference   SHA pinning               Tag/branch hijacking
Unknown-bad SHA         harden-runner (block)     C2 callbacks, exfil
Token abuse             permissions: read          Repo write-back
Privileged runner       No extra capabilities      Lateral movement
```

No single control is complete. SHA pinning didn't stop orphaned-commit tricks. `harden-runner` had its own DoH bypass in the community tier. Minimum permissions don't stop data exfiltration. That's why all three are in the workflow together.

### Practical Next Steps

To move from `audit` to `block` mode:

1. Run the pipeline once in `audit` mode
2. Check the StepSecurity dashboard for observed egress endpoints
3. Add them to `allowed-endpoints` in the workflow
4. Switch `egress-policy` to `block`

```yaml
- name: Harden Runner
  uses: step-security/harden-runner@9af89fc71515a100421586dfdb3dc9c984fbf411 # v2.19.4
  with:
    egress-policy: block
    allowed-endpoints: >
      registry.npmjs.org:443
      ghcr.io:443
      github.com:443
      api.github.com:443
      ghcr.io:443
      objects.githubusercontent.com:443
```

---

## The GitOps Pipeline (ArgoCD)

This project uses a GitOps workflow to manage application deployments. **ArgoCD** is automatically provisioned and configured on first deploy:

1. **ArgoCD Server:** Installed via the `argo-cd` Helm chart into the `argocd` namespace.
2. **ArgoCD Application Configuration:** Deployed via the `argocd-apps` Helm chart. It configures ArgoCD to sync the application state with the `k8s/chart` directory in this GitHub repository (`https://github.com/didiberman/practical-aks.git`).
3. **Dynamic Value Injection:** Since we cannot hardcode cluster-specific outputs (like Key Vault URI or Managed Identity Client ID) in Git, Terraform automatically injects them as Helm parameters in the ArgoCD Application definition.

### Accessing ArgoCD
To open the ArgoCD dashboard:
1. Port-forward the ArgoCD service:
   ```bash
   kubectl port-forward service/argocd-server -n argocd 8080:443
   ```
2. Open `https://localhost:8080` in your browser.
3. Login using:
   * **Username:** `admin`
   * **Password:** Retrieve the auto-generated password (the server pod name) by running:
     ```bash
     kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
     ```

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
# Destroy all Azure infrastructure and Helm releases (ArgoCD and applications)
terraform destroy
```

**Note**: The Key Vault has `purge_protection_enabled = false` intentionally. This means it can be fully deleted (including soft-deleted state) without waiting the default 90-day purge window — useful for a learning environment where you provision and destroy frequently.

---

## Project Structure

```
aks/
├── .github/
│   └── workflows/
│       ├── tf-ci-cd.yml        # Terraform format + validate (local plan/apply only)
│       └── app-ci-cd.yml       # MLOps tests + K8s config scan + image build + CVE scan
├── app/
│   ├── Dockerfile              # Multi-stage, non-root, Alpine
│   ├── index.js                # Express LLM proxy, Workload Identity secret fetch
│   ├── package.json
│   ├── prompts/
│   │   └── system_prompt.txt   # Versioned system prompt (MLOps pattern)
│   └── test/
│       └── prompt.test.js      # Jest unit tests for prompt formatting
├── k8s/
│   ├── chart/                  # Helm chart used by ArgoCD and deploy.sh
│   │   ├── Chart.yaml          # Chart metadata
│   │   ├── values.yaml         # Default parameters
│   │   └── templates/          # Templates (deployment, service)
│   ├── deployment.yaml         # (Deprecated) Static deployment manifest
│   └── service.yaml            # (Deprecated) Static service manifest
├── main.tf                     # Azure resources, Helm providers, ArgoCD setup
├── variables.tf                # Parameterised inputs
├── outputs.tf                  # Cluster name, KV URI, ACR server, etc.
├── versions.tf                 # Provider pinning
└── deploy.sh                   # End-to-end provisioning + Helm deploy script
```

---

## DevSecOps Checklist

Every control here is implemented and traceable to a specific file. Each is mapped to the class of attack it addresses.

### Infrastructure & Identity

- [x] **No long-lived credentials** — Workload Identity + OIDC federation (`main.tf:116–123`). Addresses: credential theft attacks like the CircleCI breach (2023), where stored tokens were exfiltrated from CI memory.
- [x] **Secrets in Key Vault, not env vars** — `app/index.js` `getApiKey()`. Addresses: env var leakage via debug logs, crash dumps, and `kubectl describe pod` output.
- [x] **RBAC on Key Vault** — `enable_rbac_authorization = true` (`main.tf:91`). Addresses: legacy access-policy misconfiguration that granted overly broad secret access.
- [x] **ACR admin disabled** — `admin_enabled = false` (`main.tf:132`). Addresses: shared static credentials for container registries — a common lateral movement path.
- [x] **Minimum RBAC scope** — each identity has exactly one role on exactly one resource. Addresses: blast radius of any single compromised identity.
- [x] **Azure Network Policies** — `network_policy = "azure"` in AKS network profile. Addresses: unrestricted pod-to-pod traffic enabling lateral movement once a pod is compromised.

### Container & Runtime

- [x] **Non-root containers** — `USER node` in Dockerfile, `runAsNonRoot: true` in deployment. Addresses: container breakout attacks that require root to exploit kernel vulnerabilities.
- [x] **Read-only filesystem** — `readOnlyRootFilesystem: true` in deployment. Addresses: malware that writes persistence mechanisms or modifies binaries at runtime.
- [x] **All Linux capabilities dropped** — `capabilities.drop: [ALL]` in deployment. Addresses: privilege escalation via capabilities like `NET_RAW`, `SYS_ADMIN` — a common container escape vector.
- [x] **Resource limits set** — CPU and memory bounds in deployment. Addresses: resource exhaustion attacks and noisy-neighbour interference.
- [x] **Multi-stage Docker build** — production image contains no build tools or dev dependencies. Reduces CVE surface area in the final image.

### CI/CD & Supply Chain

- [x] **GitHub Actions pinned to commit SHAs** — `trivy-action@57a97c7e...` and `harden-runner@9af89fc7...`. Addresses: the March 2026 Trivy supply chain attack, where 76 mutable tags were force-pushed to malicious commits (CVE-2026-33634 / GHSA-69fq-xp46-6x23).
- [x] **`step-security/harden-runner` on every job** — network egress agent installed before any other step. Addresses: C2 callbacks from compromised actions — would have blocked exfiltration to `scan.aquasecurtiy.org` in the Trivy attack even if the malicious code ran.
- [x] **Minimum `permissions: contents: read`** — workflow-level GITHUB_TOKEN restriction. Addresses: compromised actions using the token to push malicious code back to the repository (the `tj-actions/changed-files` attack pattern, 2025).
- [x] **K8s manifests scanned by Trivy config** — catches misconfigurations before they reach the cluster. Addresses: privilege escalation via missing `securityContext`, privileged containers, host path mounts.
- [x] **Container image scanned on every build** — Trivy image scan with `exit-code: 1` on HIGH/CRITICAL. Addresses: shipping known-vulnerable OS packages or Node dependencies to production.
- [x] **MLOps prompt validation tests** — prompt format is tested in CI before any image is built. Addresses: prompt injection regressions reaching production silently.

---

## Contributing

This is a learning resource. If you find a security issue, a better practice, or a concept that isn't well explained — open an issue or a PR.
