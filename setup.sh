#!/usr/bin/env bash
# Run this ON THE HOST, not inside the container.
# Installs the ACP adapter and registers the agent
# with the JetBrains AI / Air plugin.
set -euo pipefail

ACP_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_NAME='Claude Docker'
CFG="$HOME/.jetbrains/acp.json"
CONTAINER="${1:-}"

if [ -f /.dockerenv ]; then
    echo 'This script must run on the host, not inside the container.' >&2

    exit 1
fi

# Docker's own name rule; also keeps the value safe to write into JSON.
if ! [[ "$CONTAINER" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
    echo 'Usage: setup.sh <claude-container-name>   (see: docker ps --format "{{.Names}}")' >&2

    exit 1
fi

export CLAUDE_ACP_CONTAINER="$CONTAINER"

echo "adapter dir : $ACP_DIR"
echo "container   : $CONTAINER"

cd "$ACP_DIR"
[ -f package-lock.json ] || { echo 'package-lock.json missing - refusing to resolve versions.' >&2; exit 1; }

# Install exactly what the lockfile pins. The only optional deps are the SDK's
# bundled Claude Code binaries; claude-acp.sh uses the image's claude instead.
npm ci --omit=optional

chmod +x "$ACP_DIR/claude-acp.sh"

echo
echo 'Verifying the wrapper...'
"$ACP_DIR/claude-acp.sh" --check

# The plugin expects "agent_servers", keyed by the display name shown in AI Chat.
# It watches this file and hot-reloads, so no IDE restart is needed.
echo
if [ -f "$CFG" ]; then
    echo "$CFG already exists - leaving it alone. Add this under \"agent_servers\":"
    echo
    printf '  "%s": { "command": "%s/claude-acp.sh", "args": [], "env": { "CLAUDE_ACP_CONTAINER": "%s" } }\n' \
        "$AGENT_NAME" "$ACP_DIR" "$CONTAINER"
else
    mkdir -p "$(dirname "$CFG")"
    cat > "$CFG" <<JSON
{
  "default_mcp_settings": {},
  "agent_servers": {
    "$AGENT_NAME": {
      "command": "$ACP_DIR/claude-acp.sh",
      "args": [],
      "env": {
        "CLAUDE_ACP_CONTAINER": "$CONTAINER"
      }
    }
  }
}
JSON
    echo "wrote $CFG"
fi

echo
echo "Pick \"$AGENT_NAME\" in the AI Chat agent list."
