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
| `app/index.js` | Keyless Azure OpenAI inference via Workload Identity |
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
│  │  │ Azure OpenAI │  Workload   │  │  AzureLinux      │  │   │  │
│  │  │  Account     │◄────────────│  │                  │  │   │  │
│  │  │              │  Identity   │  │  ┌────────────┐  │  │   │  │
│  │  │  chat model  │  OIDC fed.  │  │  │ Pod        │  │  │   │  │
│  │  │  deployment  │             │  │  │ (non-root) │  │  │   │  │
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
│  │  │  User-Assigned        │  │  → OpenAI User              │ │  │
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
| Azure OpenAI `S0` account | Usage-based | No key management; model cost depends on tokens and quota |
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
- An Azure subscription with permission to create resource groups, assign roles, register the `Microsoft.ContainerService` and `Microsoft.CognitiveServices` providers, and use Azure OpenAI quota in your selected region

---

## Quick Start (15 minutes)

```bash
# 1. Clone and configure
git clone https://github.com/<you>/aks.git && cd aks

# 2. Optionally override defaults in variables.tf, then provision everything
./deploy.sh

# 3. Test the deployed service
kubectl port-forward service/aks-learning-app 8080:80

curl -X POST http://localhost:8080/api/generate \
  -H 'Content-Type: application/json' \
  -d '{"prompt": "explain workload identity in one sentence"}'
```

To prove the pod can assume an Azure identity before it calls inference, inspect the safe token summary endpoint:

```bash
curl -s http://localhost:8080/api/azure-identity | jq
```

For a guided walkthrough, see [`labs/01-azure-role-from-pod.md`](labs/01-azure-role-from-pod.md).

> **What `deploy.sh` does**: runs `terraform apply`, reads all outputs, builds and pushes the Docker image with Azure Container Registry Tasks, fetches kubeconfig, and deploys the Helm chart with the Terraform-produced identity and Azure OpenAI values. One script, zero manual steps.

---

## GitHub Actions App CI/CD

This repo includes an app delivery pipeline in `.github/workflows/app-ci-cd.yml`.

On pull requests it:

- Installs Node dependencies.
- Runs the Jest tests.
- Lints the Helm chart.

On pushes to `main` it:

- Logs into Azure using GitHub OIDC.
- Builds the app container.
- Pushes two image tags to ACR: `latest` and the Git commit SHA.
- Commits `image.tag=<commit-sha>` into `k8s/chart/values.yaml`.
- Lets ArgoCD reconcile the Git-tracked Helm chart into AKS.

### One-time GitHub setup

Terraform creates a dedicated user-assigned managed identity for GitHub Actions and trusts only this repository's `main` branch:

```hcl
subject = "repo:<owner>/<repo>:ref:refs/heads/main"
```

If your repository is not `didiberman/practical-aks`, override this before applying:

```bash
terraform apply \
  -var='github_repository=<owner>/<repo>' \
  -var='github_actions_branch=main'
```

Then configure these GitHub repository variables from the Terraform outputs:

```bash
gh variable set AZURE_CLIENT_ID --body "$(terraform output -raw github_actions_client_id)"
gh variable set AZURE_TENANT_ID --body "$(terraform output -raw github_actions_tenant_id)"
gh variable set AZURE_SUBSCRIPTION_ID --body "$(terraform output -raw github_actions_subscription_id)"
gh variable set RESOURCE_PREFIX --body "$(terraform output -raw resource_group_name | sed 's/-rg$//')"
```

In GitHub, also allow workflow write access under **Settings -> Actions -> General -> Workflow permissions -> Read and write permissions**. If `main` is protected, allow GitHub Actions to push deployment commits or switch the workflow to open a deployment PR instead.

No Azure client secret is required. The workflow uses a short-lived OIDC token from GitHub and exchanges it for the managed identity Terraform created.

---

## Local Development & Testing (Zero Cost via Kind)

To test the application locally without incurring any Azure cloud costs, you can deploy the stack on a local Kubernetes cluster using **Kind (Kubernetes in Docker)**. 

We have provided an automated local deployment script [deploy-local.sh](file:///Users/yadid/documents/github/aks/deploy-local.sh) that:
1. Verifies your Docker daemon is active.
2. Accepts Azure OpenAI endpoint/deployment settings from environment variables.
3. Provisions a local `kind` cluster named `aks-local` (if it does not already exist).
4. Builds the container image locally.
5. Loads the image directly into the `kind` cluster (eliminating the need for a container registry).
6. Installs or upgrades the application using **Helm** with local image settings. Kind does not provide AKS Workload Identity, so local inference needs a separate Azure credential source or a real AKS deployment.

### Run Local Deployment

```bash
# Optional: point the local pod at an existing Azure OpenAI account
export AZURE_OPENAI_ENDPOINT="https://<account>.openai.azure.com"
export AZURE_OPENAI_DEPLOYMENT="gpt-4o-mini"

# Execute the local deployment script
./deploy-local.sh
```

### Test the Local App

1. Forward the local Kubernetes service port to your host machine:
   ```bash
   kubectl port-forward service/aks-learning-app 8080:80
   ```
2. Send a query to the API:
   ```bash
   curl -X POST http://localhost:8080/api/generate \
     -H 'Content-Type: application/json' \
     -d '{"prompt": "explain workload identity in one sentence"}'
   ```

### Tear Down Local Cluster

To clean up and delete the local Kind cluster when you are done:
```bash
kind delete cluster --name aks-local
```

---

## Exercise: Prove Workload Identity From Inside The Pod

After `./deploy.sh` succeeds against real AKS, run this from your terminal:

```bash
kubectl get pods -l app=aks-learning-app
kubectl exec deploy/aks-learning-app -- printenv | grep -E 'AZURE_|APPLICATION'
```

Now call Azure OpenAI directly from inside the container. This uses the same projected service-account token and managed identity that the app uses:

```bash
kubectl exec deploy/aks-learning-app -- node -e '
const { DefaultAzureCredential } = require("@azure/identity");

(async () => {
  const endpoint = process.env.AZURE_OPENAI_ENDPOINT.replace(/\/+$/, "");
  const deployment = process.env.AZURE_OPENAI_DEPLOYMENT;
  const apiVersion = process.env.AZURE_OPENAI_API_VERSION;
  const credential = new DefaultAzureCredential();
  const token = await credential.getToken("https://cognitiveservices.azure.com/.default");

  const response = await fetch(`${endpoint}/openai/deployments/${encodeURIComponent(deployment)}/chat/completions?api-version=${apiVersion}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token.token}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      messages: [
        { role: "user", content: "In one sentence, explain AKS Workload Identity." }
      ]
    })
  });

  const body = await response.json();
  if (!response.ok) throw new Error(JSON.stringify(body));
  console.log(body.choices[0].message.content);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
'
```

If that works, the pod is not using an API key. It is exchanging its Kubernetes service-account token for a Microsoft Entra ID token and using Azure RBAC to call Azure OpenAI.

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
│  App Pod              OpenAI User       Azure OpenAI only│
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
                                     │  Azure OpenAI        │
                                     │  (OpenAI User)       │
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

**The result**: the pod never receives a password, API key, or certificate. It gets a short-lived Kubernetes token, exchanges it for an Azure token, and calls Azure OpenAI. Nothing to rotate. Nothing to leak.

---

## Deep Dive: The Application (`app/`)

The Node.js service demonstrates the **correct pattern** for keyless Azure service calls from a cloud-native app.

### Token Resolution

```javascript
const credential = new DefaultAzureCredential();
const token = await credential.getToken("https://cognitiveservices.azure.com/.default");
```

`DefaultAzureCredential` tries a chain of credential sources. Inside AKS with Workload Identity enabled, it automatically finds the projected service-account token volume injected by the AKS webhook. Locally, a container does not inherit your host `az login`; use the real AKS deployment for the cleanest keyless path.

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
3. **Dynamic Value Injection:** Since we cannot hardcode cluster-specific outputs (like the Azure OpenAI endpoint or Managed Identity Client ID) in Git, Terraform automatically injects them as Helm parameters in the ArgoCD Application definition.

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
| Add Azure AI Foundry model routing | Same Workload Identity pattern, broader model catalog |
| Add multi-environment (dev/prod) | Terraform workspaces or separate state files |

---

## Tearing Down

```bash
# Destroy all Azure infrastructure and Helm releases (ArgoCD and applications)
terraform destroy
```

**Note**: Azure OpenAI model deployment can fail if the selected region does not have quota for the configured model/version. Override `azure_region`, `azure_openai_model_name`, and `azure_openai_model_version` in Terraform if your subscription requires a different combination.

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
│   ├── index.js                # Express LLM proxy, keyless Azure OpenAI calls
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
├── outputs.tf                  # Cluster name, Azure OpenAI endpoint, ACR server, etc.
├── versions.tf                 # Provider pinning
└── deploy.sh                   # End-to-end provisioning + Helm deploy script
```

---

## DevSecOps Checklist

Every control here is implemented and traceable to a specific file. Each is mapped to the class of attack it addresses.

### Infrastructure & Identity

- [x] **No long-lived credentials** — Workload Identity + OIDC federation (`main.tf`). Addresses: credential theft attacks like the CircleCI breach (2023), where stored tokens were exfiltrated from CI memory.
- [x] **No model API keys in pods** — `app/index.js` gets an Entra ID token through `DefaultAzureCredential`. Addresses: env var leakage via debug logs, crash dumps, and `kubectl describe pod` output.
- [x] **RBAC on Azure OpenAI** — `Cognitive Services OpenAI User` is scoped to the OpenAI account (`main.tf`). Addresses: overly broad inference access.
- [x] **ACR admin disabled** — `admin_enabled = false` (`main.tf`). Addresses: shared static credentials for container registries — a common lateral movement path.
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
