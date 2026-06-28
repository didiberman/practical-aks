# Lab 01: Assume an Azure Identity From AKS and Call Azure OpenAI

## Goal

Prove that a workload running inside Kubernetes can assume an Azure managed identity and consume an Azure service without an API key, client secret, or mounted credential file.

This lab uses:

- AKS Workload Identity as the trust bridge between Kubernetes and Microsoft Entra ID.
- A user-assigned managed identity as the Azure identity assumed by the pod.
- Azure RBAC to grant that identity `Cognitive Services OpenAI User`.
- Azure OpenAI as the target Azure service.
- The app's `/api/azure-identity` and `/api/generate` endpoints as proof.

## What Is Being Proved

The pod starts with a Kubernetes service account token. AKS Workload Identity lets the Azure Identity SDK exchange that token for an Azure AD access token scoped to Cognitive Services.

```text
Kubernetes Pod
  serviceAccountName: llm-service-sa
        |
        | projected service account token
        v
AKS OIDC issuer
        |
        | federated credential trusts this subject:
        | system:serviceaccount:default:llm-service-sa
        v
User-assigned managed identity
        |
        | Azure RBAC role:
        | Cognitive Services OpenAI User
        v
Azure OpenAI inference endpoint
```

## Relevant Files

| File | What to inspect |
|---|---|
| `main.tf` | `azurerm_user_assigned_identity.app_identity`, `azurerm_federated_identity_credential.app_federated_credential`, and `azurerm_role_assignment.app_openai_user` |
| `k8s/chart/templates/deployment.yaml` | ServiceAccount annotation and pod label that activate Workload Identity |
| `app/index.js` | `DefaultAzureCredential`, `/api/azure-identity`, and `/api/generate` |

## Deploy

From the repository root:

```bash
./deploy.sh
```

Fetch the cluster credentials if needed:

```bash
az aks get-credentials \
  --resource-group "$(terraform output -raw resource_group_name)" \
  --name "$(terraform output -raw kubernetes_cluster_name)" \
  --overwrite-existing
```

## Verify The Kubernetes Side

Check that the service account has the managed identity client ID annotation:

```bash
kubectl get serviceaccount llm-service-sa \
  -o jsonpath='{.metadata.annotations.azure\.workload\.identity/client-id}{"\n"}'
```

Compare it with the Terraform output:

```bash
terraform output -raw app_identity_client_id
```

They should match.

Check that the pod has the Workload Identity opt-in label:

```bash
kubectl get pods -l app=aks-learning-app \
  -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.metadata.labels.azure\.workload\.identity/use}{"\n"}{end}'
```

Expected value:

```text
true
```

## Verify The Azure Token

Port-forward the service:

```bash
kubectl port-forward service/aks-learning-app 8080:80
```

In another terminal, ask the app to acquire and summarize an Azure token:

```bash
curl -s http://localhost:8080/api/azure-identity | jq
```

Expected shape:

```json
{
  "identity": {
    "audience": "https://cognitiveservices.azure.com",
    "tenantId": "...",
    "clientId": "...",
    "objectId": "...",
    "expiresAt": "...",
    "tokenType": "Bearer"
  },
  "service": {
    "scope": "https://cognitiveservices.azure.com/.default",
    "endpointConfigured": true,
    "deployment": "gpt-4o-mini",
    "apiVersion": "2024-10-21"
  },
  "proof": "This pod acquired an Azure AD access token for Azure Cognitive Services without an API key."
}
```

The raw access token is intentionally not returned.

## Verify Azure OpenAI Inference

Call the app endpoint that uses the same identity to consume Azure OpenAI:

```bash
curl -s -X POST http://localhost:8080/api/generate \
  -H 'Content-Type: application/json' \
  -d '{"prompt": "Explain AKS Workload Identity in one sentence."}' | jq
```

Expected result:

```json
{
  "text": "...",
  "metadata": {
    "deployment": "gpt-4o-mini",
    "latencyMs": 1234,
    "promptLength": 47,
    "timestamp": "..."
  }
}
```

## Break It On Purpose

Change the service account annotation to a bad client ID:

```bash
helm upgrade --install aks-learning-app ./k8s/chart \
  --namespace default \
  --set appIdentityClientId="00000000-0000-0000-0000-000000000000" \
  --set azureOpenAI.endpoint="$(terraform output -raw azure_openai_endpoint)" \
  --set azureOpenAI.deployment="$(terraform output -raw azure_openai_deployment_name)" \
  --set azureOpenAI.apiVersion="$(terraform output -raw azure_openai_api_version)" \
  --set acrLoginServer="$(terraform output -raw acr_login_server)"
```

Restart the deployment:

```bash
kubectl rollout restart deployment/aks-learning-app
kubectl rollout status deployment/aks-learning-app
```

Call the identity proof endpoint again:

```bash
curl -s http://localhost:8080/api/azure-identity | jq
```

This should fail because the Kubernetes service account no longer maps to the managed identity that has Azure OpenAI access.

Restore the correct value:

```bash
./deploy.sh
```

## Key Takeaway

The application does not know an Azure API key. It proves cloud access by acquiring a Microsoft Entra ID token from inside the cluster and using Azure RBAC to call Azure OpenAI.
