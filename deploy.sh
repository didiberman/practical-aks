#!/bin/bash
set -e

echo "=== Pre-check: Ensure chart changes are pushed to GitHub ==="
# ArgoCD syncs the Helm chart directly from GitHub. Any local chart changes
# must be committed and pushed before Terraform applies, otherwise ArgoCD
# will deploy the stale version from the remote.
if ! git diff --quiet HEAD -- k8s/chart || ! git diff --cached --quiet -- k8s/chart; then
  echo "ERROR: Uncommitted changes detected in k8s/chart."
  echo "Commit and push all chart changes before running this script."
  exit 1
fi
UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
if [[ -n "$UPSTREAM" ]] && [[ -n "$(git log "${UPSTREAM}..HEAD" 2>/dev/null)" ]]; then
  echo "ERROR: Unpushed commits detected. Run: git push"
  exit 1
fi

echo "=== 1. Planning and Applying Terraform ==="
terraform plan -out=tfplan
terraform apply tfplan

echo "=== 2. Fetching Terraform Outputs ==="
RG_NAME=$(terraform output -raw resource_group_name)
CLUSTER_NAME=$(terraform output -raw kubernetes_cluster_name)
ACR_NAME=$(terraform output -raw acr_name)
ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server)

echo "Active Resource Group: $RG_NAME"
echo "Active Cluster: $CLUSTER_NAME"
echo "Active ACR: $ACR_NAME ($ACR_LOGIN_SERVER)"

echo "=== 3. Building & Pushing Image via ACR Tasks (no local Docker required) ==="
az acr build --registry "$ACR_NAME" --image aks-learning-app:latest ./app

echo "=== 4. Fetching AKS Credentials ==="
az aks get-credentials --resource-group "$RG_NAME" --name "$CLUSTER_NAME" --overwrite-existing

echo "=== 5. Waiting for ArgoCD to be ready ==="
kubectl wait --for=condition=available deployment/argocd-server \
  --namespace argocd --timeout=300s

echo "=== 6. Provisioning and Deployment Complete! ==="
echo ""
echo "Terraform deployed ArgoCD, which manages the application via GitOps."
echo "ArgoCD is configured to auto-sync from GitHub. The app will be live shortly."
echo ""
echo "Next Steps:"
echo "1. Check ArgoCD sync status:"
echo "   kubectl -n argocd get applications"
echo "2. Port-forward the ArgoCD dashboard (admin password below):"
echo "   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:80"
echo "3. Once the app is synced, test the API:"
echo "   kubectl port-forward service/aks-learning-app 8080:80"
echo "   curl -X POST http://localhost:8080/api/generate -H 'Content-Type: application/json' -d '{\"prompt\":\"explain workload identity in 1 sentence\"}'"
