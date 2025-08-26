#!/bin/bash
set -e

# Check required environment variables
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "❌ Missing ANTHROPIC_API_KEY"
    exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Missing GITHUB_TOKEN"
    exit 1
fi

# Set defaults
POD_NAME="${POD_NAME:-crystalshards-agent}"
NAMESPACE="claude"
GIT_URL="${GIT_URL:-https://github.com/crystalshards/crystalshards-claude.git}"
GIT_BRANCH="${GIT_BRANCH:-main}"

echo "🚀 Launching CrystalShards Agent"
echo "================================"
echo "Namespace: $NAMESPACE"
echo "Pod: $POD_NAME"
echo "Git URL: $GIT_URL"
echo "Git Branch: $GIT_BRANCH"
echo ""

# Read the kubernetes-dev-pod.yaml and substitute environment variables
cat kubernetes-dev-pod.yaml | \
    sed "s|YOUR_CLAUDE_API_KEY_HERE|$ANTHROPIC_API_KEY|g" | \
    sed "s|YOUR_GITHUB_TOKEN_HERE|$GITHUB_TOKEN|g" | \
    sed "s|crystalshards-agent|$POD_NAME|g" | \
    sed "s|ENVBUILDER_GIT_URL: https://github.com/crystalshards/crystalshards-claude.git|ENVBUILDER_GIT_URL: $GIT_URL|g" | \
    sed "s|value: main|value: $GIT_BRANCH|g" > kubectl apply -f -

# Delete existing resources
echo "🧹 Cleaning up existing resources..."
kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --ignore-not-found=true --wait=false
kubectl delete pvc crystalshards-workspace -n "$NAMESPACE" --ignore-not-found=true --wait=false

# Apply the manifest
echo "📦 Creating resources..."
kubectl apply -f $TEMP_MANIFEST

# Wait for pod to be ready
echo "⏳ Waiting for pod to be ready..."
kubectl wait --for=condition=Ready pod/$POD_NAME -n $NAMESPACE --timeout=300s || true

echo ""
echo "✅ Agent launched!"
echo ""
echo "Useful commands:"
echo "📜 kubectl logs -f $POD_NAME -n $NAMESPACE"
echo "🔍 kubectl describe pod $POD_NAME -n $NAMESPACE"
echo "💻 kubectl exec -it $POD_NAME -n $NAMESPACE -- bash"
echo "🗑️  kubectl delete -f kubernetes-dev-pod.yaml"
echo "📜 Following logs (Ctrl+C to exit)..."
kubectl logs -f "$POD_NAME" -n "$NAMESPACE"