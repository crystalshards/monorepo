#!/bin/bash
# Simple continuous development loop

cd /workspaces/monorepo

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

# Simple loop
while true; do
    cat PROMPT.md | claude --verbose -p --dangerously-skip-permissions
    sleep 5
done