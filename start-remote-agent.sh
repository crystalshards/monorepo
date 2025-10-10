#!/bin/bash
set -e

# Check required environment variables
if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Missing GITHUB_TOKEN"
    exit 1
fi

# Set defaults
POD_NAME="${POD_NAME:-crystalshards-agent}"
NAMESPACE="claude"
KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-gke_crystalshards-org_us-central1_crystalshards-cluster}"
GIT_URL="${GIT_URL:-https://github.com/crystalshards/crystalshards-claude.git}"
GIT_BRANCH="${GIT_BRANCH:-main}"

echo "🚀 Launching CrystalShards Agent"
echo "================================"
echo "Cluster Context: $KUBECTL_CONTEXT"
echo "Namespace: $NAMESPACE"
echo "Pod: $POD_NAME"
echo "Git URL: $GIT_URL"
echo "Git Branch: $GIT_BRANCH"
echo ""

# Delete existing resources
echo "🧹 Cleaning up existing resources..."
kubectl --context "$KUBECTL_CONTEXT" delete pod "$POD_NAME" -n "$NAMESPACE" --ignore-not-found=true --wait
kubectl --context "$KUBECTL_CONTEXT" delete pvc crystalshards-workspaces -n "$NAMESPACE" --ignore-not-found=true --wait
kubectl --context "$KUBECTL_CONTEXT" delete pvc crystalshards-docker-storage -n "$NAMESPACE" --ignore-not-found=true --wait

# Apply the manifest
echo "📦 Creating resources..."
cat kubernetes-dev-pod.yaml | \
    sed "s|YOUR_GITHUB_TOKEN_HERE|$GITHUB_TOKEN|g" | \
    sed "s|crystalshards-agent|$POD_NAME|g" | \
    sed "s|ENVBUILDER_GIT_URL: https://github.com/crystalshards/crystalshards-claude.git|ENVBUILDER_GIT_URL: $GIT_URL|g" | \
    sed "s|value: main|value: $GIT_BRANCH|g" | kubectl --context "$KUBECTL_CONTEXT" apply -f -

# Wait for pod to be ready
echo "⏳ Waiting for pod to be ready..."
kubectl --context "$KUBECTL_CONTEXT" wait --for=condition=Ready pod/$POD_NAME -n $NAMESPACE --timeout=300s || true

echo ""
echo "✅ Pod is ready!"
echo ""
echo "Next steps:"

./remote-claude.sh --dangerously-skip-permissions "Say: You are now logged in, you may quit this claude session."

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Authentication complete!"
    echo ""
    echo "The agent will now start processing tasks automatically."
    echo ""
    echo "📜 To view logs: kubectl --context $KUBECTL_CONTEXT logs -f $POD_NAME -n $NAMESPACE -c agent"
else
    echo ""
    echo "❌ Authentication failed. Please try again."
    exit 1
fi

echo "📜 Following logs"
kubectl --context "$KUBECTL_CONTEXT" logs -f $POD_NAME -n $NAMESPACE -c agent

echo "Useful commands:"
echo "📜 kubectl --context $KUBECTL_CONTEXT logs -f $POD_NAME -n $NAMESPACE -c agent"
echo "🔍 kubectl --context $KUBECTL_CONTEXT describe pod $POD_NAME -n $NAMESPACE"
echo "💻 kubectl --context $KUBECTL_CONTEXT exec -it $POD_NAME -n $NAMESPACE -c agent -- bash"
echo "🗑️ kubectl --context $KUBECTL_CONTEXT delete pod $POD_NAME -n $NAMESPACE"
echo ""