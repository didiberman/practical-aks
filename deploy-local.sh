#!/bin/bash
set -e

# Configuration
CLUSTER_NAME="aks-local"
IMAGE_NAME="aks-learning-app"
IMAGE_TAG="local"
NAMESPACE="default"

echo "=== 1. Checking Environment ==="
# Check if Docker daemon is running
if ! docker info >/dev/null 2>&1; then
  echo "Error: Docker daemon is not running. Please start Docker first."
  exit 1
fi

# Retrieve or prompt for GEMINI_API_KEY
if [ -z "$GEMINI_API_KEY" ]; then
  echo "Warning: GEMINI_API_KEY environment variable is not set."
  echo "You can set it via: export GEMINI_API_KEY=\"your_key\""
  echo "Or enter it now (press Enter to skip and configure later):"
  read -r -s -p "Gemini API Key: " INPUT_KEY
  echo ""
  if [ -n "$INPUT_KEY" ]; then
    GEMINI_API_KEY="$INPUT_KEY"
  fi
fi

echo "=== 2. Creating/Verifying Kind Cluster ==="
# Create kind cluster if not exists
if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "Creating kind cluster '${CLUSTER_NAME}'..."
  kind create cluster --name "$CLUSTER_NAME"
else
  echo "Kind cluster '${CLUSTER_NAME}' already exists."
fi

# Set kubectl context to the local cluster
kubectl config use-context "kind-${CLUSTER_NAME}"

echo "=== 3. Building Local Image ==="
# Build local Docker image
echo "Building local Docker image ${IMAGE_NAME}:${IMAGE_TAG}..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" ./app

echo "=== 4. Loading Image into Kind ==="
# Load image into kind cluster (avoids having to push to a registry)
echo "Loading image ${IMAGE_NAME}:${IMAGE_TAG} into kind cluster..."
kind load docker-image "${IMAGE_NAME}:${IMAGE_TAG}" --name "$CLUSTER_NAME"

echo "=== 5. Deploying via Helm ==="
# Install or upgrade Helm release
if [ -n "$GEMINI_API_KEY" ]; then
  echo "Deploying with local Gemini API Key..."
  helm upgrade --install "$IMAGE_NAME" ./k8s/chart \
    --namespace "$NAMESPACE" \
    --set image.tag="${IMAGE_TAG}" \
    --set acrLoginServer="" \
    --set geminiApiKey="${GEMINI_API_KEY}"
else
  echo "Deploying without API key. Note: LLM features will fail until you provide a key."
  helm upgrade --install "$IMAGE_NAME" ./k8s/chart \
    --namespace "$NAMESPACE" \
    --set image.tag="${IMAGE_TAG}" \
    --set acrLoginServer=""
fi

echo "=== 6. Local Deployment Complete! ==="
echo ""
echo "Next Steps to Test:"
echo "1. Port-forward the deployment to test locally:"
echo "   kubectl port-forward service/aks-learning-app 8080:80"
echo ""
echo "2. In another terminal, query the local API endpoint:"
echo "   curl -X POST http://localhost:8080/api/generate \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '\"prompt\":\"explain workload identity in 1 sentence\"}'"
echo ""
echo "To tear down the cluster later, run:"
echo "   kind delete cluster --name ${CLUSTER_NAME}"
