#!/bin/bash
set -e

# Set defaults
POD_NAME="${POD_NAME:-crystalshards-agent}"
NAMESPACE="claude"

echo "🔐 CrystalShards Agent Login"
echo "============================"
echo ""

# Check if pod exists and is ready
if ! kubectl --context gke_waldrip-net_us-central1-a_cluster-1 get pod "$POD_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "❌ Pod $POD_NAME not found in namespace $NAMESPACE"
    echo "   Run ./remote.sh first to create the pod"
    exit 1
fi

# Check pod status
POD_STATUS=$(kubectl --context gke_waldrip-net_us-central1-a_cluster-1 get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
if [ "$POD_STATUS" != "Running" ]; then
    echo "❌ Pod is not running (status: $POD_STATUS)"
    echo "   Wait for pod to be ready or run ./remote.sh"
    exit 1
fi

echo "📝 Starting login process..."
echo ""
echo "⚠️  IMPORTANT: Use your Claude Max account if available!"
echo ""

# Execute login in the container
kubectl --context gke_waldrip-net_us-central1-a_cluster-1 exec -it "$POD_NAME" -n "$NAMESPACE" -c agent -- bash -c "
    cd /workspaces/monorepo

    # Set up cache directories in user home
    export CLAUDE_CONFIG_DIR=\"\$HOME/.config/claude\"
    export XDG_CONFIG_HOME=\"\$HOME/.config\"
    export XDG_DATA_HOME=\"\$HOME/.local/share\"
    export XDG_CACHE_HOME=\"\$HOME/.cache\"

    # Ensure directories exist
    mkdir -p \"\$CLAUDE_CONFIG_DIR\" \"\$XDG_DATA_HOME\" \"\$XDG_CACHE_HOME\"

    # Activate mise environment
    eval \"\$(mise activate bash)\"
    export PATH=\"/root/.local/share/mise/shims:/root/.local/bin:\${PATH}\"

    # Ensure Claude CLI is installed
    if ! command -v claude &> /dev/null; then
        echo 'Installing Claude CLI...'
        npm install -g @anthropic-ai/claude-code
    fi

    # Perform login
    claude login
    touch /workspaces/.claude-ready

    # Verify login and create ready file
    if [ -f /workspaces/.claude-ready ]; then
        echo ''
        echo '✅ Login successful! Ready file created.'
        echo '   Config stored in: \$CLAUDE_CONFIG_DIR'
    else
        echo ''
        echo '❌ Login failed. Please try again.'
        exit 1
    fi
"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Authentication complete!"
    echo ""
    echo "The agent will now start processing tasks automatically."
    echo ""
    echo "📜 To view logs: kubectl --context gke_waldrip-net_us-central1-a_cluster-1 logs -f $POD_NAME -n $NAMESPACE -c agent"
else
    echo ""
    echo "❌ Authentication failed. Please try again."
    exit 1
fi