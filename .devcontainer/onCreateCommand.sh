#!/bin/bash
set -e

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
    echo "${GITHUB_TOKEN}" | gh auth login --with-token
    gh auth status
fi

# Configure Claude with project settings
echo "🤖 Configuring Claude..."
.devcontainer/configure-claude.sh

# Run setup task
echo "🚀 Running setup task..."
mise run setup || echo "Setup will complete when Lucky apps are initialized"

echo "✅ Development environment ready!"

