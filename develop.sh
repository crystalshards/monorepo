#!/bin/bash
# Simple continuous development loop

cd /workspaces/monorepo

# Set up persistent Claude config directory
export CLAUDE_CONFIG_DIR="/workspaces/.claude-config"
export XDG_CONFIG_HOME="/workspaces/.claude-config"
export XDG_DATA_HOME="/workspaces/.claude-data"
export XDG_CACHE_HOME="/workspaces/.claude-cache"

# Ensure directories exist with proper permissions
mkdir -p "$CLAUDE_CONFIG_DIR" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
chmod -R 755 "$CLAUDE_CONFIG_DIR" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

eval "$(mise activate bash)"

# Ensure mise is set up
export PATH="/root/.local/share/mise/shims:/root/.local/bin:${PATH}"
mise trust .mise.toml || true
mise install

# Install Claude CLI if needed
if ! command -v claude &> /dev/null; then
    mise exec -- npm install -g @anthropic-ai/claude-code
fi

# Configure git
git config --global user.name "${GIT_AUTHOR_NAME:-CrystalShards Agent}"
git config --global user.email "${GIT_AUTHOR_EMAIL:-agent@crystalshards.org}"

# Wait for ready signal (authentication)
READY_FILE="/workspaces/.claude-ready"
if [ ! -f "$READY_FILE" ]; then
    echo "⏳ Waiting for authentication..."
    echo "   Run: ./remote-login.sh from your local machine"
    echo ""
    
    while [ ! -f "$READY_FILE" ]; do
        sleep 5
        echo -n "."
    done
    
    echo ""
    echo "✅ Authentication detected! Starting agent loop..."
    echo ""
fi

# Simple loop
while true; do
    echo "🤖 Starting next loop..."
    echo "==========================="
    cat PROMPT.md | claude --verbose -p --dangerously-skip-permissions
    sleep 5
done