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

echo "=== 3. Logging into Azure Container Registry (ACR) ==="
az acr login --name "$ACR_NAME"

echo "=== 4. Building & Pushing Docker Image ==="
# Build using the ACR login server tag
docker build -t "$ACR_LOGIN_SERVER/aks-learning-app:latest" ./app
docker push "$ACR_LOGIN_SERVER/aks-learning-app:latest"

echo "=== 5. Fetching AKS Credentials ==="
az aks get-credentials --resource-group "$RG_NAME" --name "$CLUSTER_NAME" --overwrite-existing

echo "=== 6. Substituting Manifest Placeholders & Deploying ==="
# Replace placeholders and create a temporary deployment manifest
sed -e "s|<APP_IDENTITY_CLIENT_ID>|${APP_IDENTITY_CLIENT_ID}|g" \
    -e "s|<KEY_VAULT_URI>|${KEY_VAULT_URI}|g" \
    -e "s|akslearning.azurecr.io|${ACR_LOGIN_SERVER}|g" \
    k8s/deployment.yaml > k8s/deployment_templated.yaml

# Apply the templated deployment and service manifests
kubectl apply -f k8s/deployment_templated.yaml -f k8s/service.yaml

# Clean up the templated manifest
rm k8s/deployment_templated.yaml

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
