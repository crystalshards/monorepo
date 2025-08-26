#!/bin/bash
set -e

# Check required environment variables
if [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
    echo "❌ Missing CLAUDE_CODE_OAUTH_TOKEN"
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

# Delete existing resources
echo "🧹 Cleaning up existing resources..."
kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --ignore-not-found=true --wait
kubectl delete pvc crystalshards-workspaces -n "$NAMESPACE" --ignore-not-found=true --wait
kubectl delete pvc crystalshards-docker-storage -n "$NAMESPACE" --ignore-not-found=true --wait

# Apply the manifest
echo "📦 Creating resources..."
cat kubernetes-dev-pod.yaml | \
    sed "s|YOUR_GITHUB_TOKEN_HERE|$GITHUB_TOKEN|g" | \
    sed "s|crystalshards-agent|$POD_NAME|g" | \
    sed "s|ENVBUILDER_GIT_URL: https://github.com/crystalshards/crystalshards-claude.git|ENVBUILDER_GIT_URL: $GIT_URL|g" | \
    sed "s|value: main|value: $GIT_BRANCH|g" | kubectl apply -f -

# Wait for pod to be ready
echo "⏳ Waiting for pod to be ready..."
kubectl wait --for=condition=Ready pod/$POD_NAME -n $NAMESPACE --timeout=300s || true

echo ""
echo "✅ Pod is ready!"
echo ""
echo "Next steps:"
echo "1. Run ./remote-login.sh to authenticate with Claude Code"
echo "2. The agent will start automatically after successful login"
echo ""
echo "Useful commands:"
echo "📜 kubectl logs -f $POD_NAME -n $NAMESPACE -c agent"
echo "🔍 kubectl describe pod $POD_NAME -n $NAMESPACE"
echo "💻 kubectl exec -it $POD_NAME -n $NAMESPACE -c agent -- bash"
echo "🗑️  kubectl delete pod $POD_NAME -n $NAMESPACE"
echo ""