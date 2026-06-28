#!/bin/bash
set -e

echo "=== 1. Running Terraform Apply ==="
terraform apply -auto-approve

echo "=== 2. Fetching Terraform Outputs ==="
RG_NAME=$(terraform output -raw resource_group_name)
CLUSTER_NAME=$(terraform output -raw kubernetes_cluster_name)
ACR_NAME=$(terraform output -raw acr_name)
ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server)
APP_IDENTITY_CLIENT_ID=$(terraform output -raw app_identity_client_id)
KEY_VAULT_URI=$(terraform output -raw key_vault_uri)

echo "Active Resource Group: $RG_NAME"
echo "Active Cluster: $CLUSTER_NAME"
echo "Active ACR: $ACR_NAME ($ACR_LOGIN_SERVER)"
echo "App Client ID: $APP_IDENTITY_CLIENT_ID"
echo "Key Vault URI: $KEY_VAULT_URI"

echo "=== 3. Building & Pushing Image Keylessly in the Cloud (Azure Container Registry Tasks) ==="
# Uses Azure's managed cloud builders - no local Docker daemon required!
az acr build --registry "$ACR_NAME" --image aks-learning-app:latest ./app

echo "=== 5. Fetching AKS Credentials ==="
az aks get-credentials --resource-group "$RG_NAME" --name "$CLUSTER_NAME" --overwrite-existing

echo "=== 6. Deploying via Helm ==="
helm upgrade --install aks-learning-app ./k8s/chart \
    --namespace default \
    --set appIdentityClientId="${APP_IDENTITY_CLIENT_ID}" \
    --set keyVaultUri="${KEY_VAULT_URI}" \
    --set acrLoginServer="${ACR_LOGIN_SERVER}"

echo "=== 7. Provisioning and Deployment Complete! ==="
echo ""
echo "Next Steps:"
echo "1. Upload your Gemini API key to Key Vault:"
KV_NAME=$(echo "$KEY_VAULT_URI" | awk -F'//' '{print $2}' | awk -F'.' '{print $1}')
echo "   az keyvault secret set --vault-name \"$KV_NAME\" --name \"gemini-api-key\" --value \"YOUR_API_KEY\""
echo "2. Port-forward the deployment to test locally:"
echo "   kubectl port-forward service/aks-learning-app 8080:80"
echo "3. Query the endpoint:"
echo "   curl -X POST http://localhost:8080/api/generate -H 'Content-Type: application/json' -d '{\"prompt\":\"explain workload identity in 1 sentence\"}'"
