#!/bin/bash
# Configure Claude with necessary settings for autonomous operation

set -euo pipefail
set -x

# Claude config directory and file
CLAUDE_CONFIG_FILE="${CLAUDE_CONFIG_DIR}/claude-config.json"

# Ensure config directory exists
mkdir -p "$CLAUDE_CONFIG_DIR"
sudo chown -R $USER:$USER "$CLAUDE_CONFIG_DIR"

# Initialize config file if it doesn't exist
if [ ! -f "$CLAUDE_CONFIG_FILE" ]; then
    echo '{}' > "$CLAUDE_CONFIG_FILE"
fi

# Create the configuration using jq
# This follows the same pattern as the Go code but using jq for JSON manipulation
jq --arg api_key "${ANTHROPIC_API_KEY:-}" \
   '. + {
     "hasCompletedOnboarding": true,
     "bypassPermissionsModeAccepted": true,
     "autoUpdaterStatus": "disabled",
     "hasAcknowledgedCostThreshold": true
   }' "$CLAUDE_CONFIG_FILE" > "${CLAUDE_CONFIG_FILE}.tmp" && mv -f "${CLAUDE_CONFIG_FILE}.tmp" "$CLAUDE_CONFIG_FILE"

# Set restrictive permissions on the config file
chmod 0600 "$CLAUDE_CONFIG_FILE"

echo "Claude configuration updated successfully"