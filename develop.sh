#!/bin/bash
# Simple continuous development loop

cd /workspaces/monorepo

# Determine actual home directory (envbuilder may set HOME=/root even for non-root users)
if [ "$USER" = "claude" ] || [ "$(whoami)" = "claude" ]; then
    ACTUAL_HOME="/home/claude"
else
    ACTUAL_HOME="$HOME"
fi

# Set up cache directories in user home (writable by claude user)
export CLAUDE_CONFIG_DIR="$ACTUAL_HOME/.config/claude"
export XDG_CONFIG_HOME="$ACTUAL_HOME/.config"
export XDG_DATA_HOME="$ACTUAL_HOME/.local/share"
export XDG_CACHE_HOME="$ACTUAL_HOME/.cache"

# Ensure directories exist
mkdir -p "$CLAUDE_CONFIG_DIR" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

eval "$(mise activate bash)"

# Ensure mise is set up (use ACTUAL_HOME instead of hardcoded /root)
export PATH="$ACTUAL_HOME/.local/share/mise/shims:$ACTUAL_HOME/.local/bin:${PATH}"
mise trust .mise.toml || true
mise install

# Run setup task to install additional tools
mise run setup

# Configure git
git config --global user.name "${GIT_AUTHOR_NAME:-CrystalShards Agent}"
git config --global user.email "${GIT_AUTHOR_EMAIL:-agent@crystalshards.org}"

# Wait for ready signal (authentication)
until claude -p "say hello" > /dev/null 2>&1; do
    echo "⏳ Waiting for authentication..."
    echo "   Run: ./remote-login.sh from your local machine"
    echo ""    
done

echo ""
echo "✅ Authentication detected! Starting agent loop..."
echo ""

# Simple loop
while true; do
    echo "🤖 Starting next loop..."
    git pull origin main
    cat PROMPT.md | claude --dangerously-skip-permissions --print --include-partial-messages --output-format=stream-json --verbose | tools/claude-render
    sleep 5
done