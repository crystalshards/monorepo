#!/bin/bash
set -e
set -x

echo "🔮 Setting up CrystalShards development environment..."

# Ensure workspace directory exists
mkdir -p /workspaces/monorepo
cd /workspaces/monorepo

# Trust mise config
echo "🔧 Setting up mise..."
mise trust .mise.toml || true
mise install

# Run mise check task
mise run check

# Create directory structure for monorepo
echo "📁 Creating monorepo structure..."
mkdir -p apps/shards-registry
mkdir -p apps/shards-docs  
mkdir -p apps/gigs
mkdir -p apps/worker
mkdir -p terraform
mkdir -p libraries
mkdir -p .github/workflows

echo "🔐 Configuring Git credentials..."
git config --global user.name "${GIT_AUTHOR_NAME:-CrystalShards Agent}"
git config --global user.email "${GIT_AUTHOR_EMAIL:-agent@crystalshards.org}"
git config --global init.defaultBranch main
git config --global push.autoSetupRemote true

# Configure GitHub CLI if token is available
if [ -n "${GITHUB_TOKEN}" ]; then
    echo "🔐 Configuring GitHub CLI..."
    gh auth status
fi

# Configure Claude with project settings
echo "🤖 Configuring Claude..."
# Claude config directory and file (using environment variable from devcontainer.json)
CLAUDE_CONFIG_FILE="${CLAUDE_CONFIG_DIR}/config.json"

# Ensure config directory exists
mkdir -p "$CLAUDE_CONFIG_DIR"

# Initialize config file if it doesn't exist
if [ ! -f "$CLAUDE_CONFIG_FILE" ]; then
    echo '{}' > "$CLAUDE_CONFIG_FILE"
fi

# Create the configuration using jq
# This follows the same pattern as the Go code but using jq for JSON manipulation
jq  '. + {
     "hasCompletedOnboarding": true,
     "bypassPermissionsModeAccepted": true,
     "autoUpdaterStatus": "disabled",
     "hasAcknowledgedCostThreshold": true
   }' "$CLAUDE_CONFIG_FILE" > "${CLAUDE_CONFIG_FILE}.tmp" && mv "${CLAUDE_CONFIG_FILE}.tmp" "$CLAUDE_CONFIG_FILE"

# Set restrictive permissions on the config file
chmod 0600 "$CLAUDE_CONFIG_FILE"

echo "Claude configuration updated successfully"

# Run setup task
echo "🚀 Running setup task..."
mise run setup || echo "Setup will complete when Lucky apps are initialized"

echo "✅ Development environment ready!"

