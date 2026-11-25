#!/usr/bin/env bash
# ACP wrapper: runs claude-agent-acp inside the dev container named by CLAUDE_ACP_CONTAINER,
# so Claude Code uses the container's subscription auth and toolchain rather than
# the host's. Registered in ~/.jetbrains/acp.json under "agent_servers".
#
# Air spawns this on the host and talks JSON-RPC over stdio, so nothing but the
# protocol may ever reach stdout. All diagnostics go to stderr.
set -euo pipefail

# GUI apps inherit a minimal PATH, so docker is usually not on it.
PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# This repo is cloned into <project>/.claude/acp, so the project root is two levels up.
HOST_DIR="${CLAUDE_ACP_HOST_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
CONTAINER_DIR="${CLAUDE_ACP_CONTAINER_DIR:-/workspace}"
CONTAINER_USER="${CLAUDE_ACP_CONTAINER_USER:-node}"
CONTAINER_HOME="${CLAUDE_ACP_CONTAINER_HOME:-/home/$CONTAINER_USER}"
CLAUDE_BIN="${CLAUDE_ACP_CLAUDE_BIN:-$CONTAINER_HOME/.local/bin/claude}"
ADAPTER_DIR="$CONTAINER_DIR/.claude/acp"
PKG=@agentclientprotocol/claude-agent-acp

CONTAINER="${CLAUDE_ACP_CONTAINER:-}"
CONTAINER="${CONTAINER//\\n/}"
CONTAINER="${CONTAINER//\\r/}"
CONTAINER="${CONTAINER//[[:space:]]/}"

log() { printf '%s\n' "$*" >&2; }
die() { log "claude-acp: $*"; exit 1; }

# Read the adapter's declared bin from its own package.json rather than
# hardcoding a dist path that may change between releases.
resolve_entry() {
    docker exec -u "$CONTAINER_USER" "$1" node -e '
        const path = require("path");
        const pkgDir = path.join(process.argv[1], "node_modules", process.argv[2]);
        const pkg = require(path.join(pkgDir, "package.json"));
        const bin = typeof pkg.bin === "string" ? pkg.bin : Object.values(pkg.bin)[0];
        process.stdout.write(path.join(pkgDir, bin));
    ' "$ADAPTER_DIR" "$PKG" 2>/dev/null
}

command -v docker >/dev/null 2>&1 || die 'docker not found on PATH'

[ -n "$CONTAINER" ] || die 'CLAUDE_ACP_CONTAINER is not set - add it to the agent "env" in ~/.jetbrains/acp.json'
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" != 'true' ]; then
    log "claude-acp: container $(printf '%q' "$CONTAINER") is not running - start your dev environment"
    log "running containers: $(docker ps --format '{{.Names}}' 2>&1 | tr '\n' ' ')"

    exit 1
fi

ENTRY="$(resolve_entry "$CONTAINER")"
[ -n "$ENTRY" ] || die "adapter not installed in $ADAPTER_DIR - run setup.sh on the host first"

# Make the host's project path resolve inside the container. A symlink rather than
# a second bind mount, so any mounts layered over the project still apply.
# Recreated each launch to survive container recreates.
docker exec -u root "$CONTAINER" sh -c \
    'mkdir -p "$(dirname "$1")" && ln -sfn "$2" "$1"' _ "$HOST_DIR" "$CONTAINER_DIR" >/dev/null 2>&1 \
    || die 'could not create the path symlink inside the container'

if [ "${1:-}" = '--check' ]; then
    log "container : $CONTAINER"
    log "user      : $CONTAINER_USER (HOME=$CONTAINER_HOME)"
    log "claude    : $CLAUDE_BIN"
    log "entry     : $ENTRY"
    log "symlink   : $HOST_DIR -> $CONTAINER_DIR"
    log 'OK - Air can spawn this script.'

    exit 0
fi

# docker exec passes the host's HOME through, so Claude Code would miss its login
# under the container user's home without this.
# An empty ANTHROPIC_API_KEY would shadow that login, so it is dropped when empty.
# CLAUDE_CODE_EXECUTABLE runs the image's Claude Code, not the npm-bundled one.
exec docker exec -i -u "$CONTAINER_USER" -e HOME="$CONTAINER_HOME" \
    -e CLAUDE_CODE_EXECUTABLE="$CLAUDE_BIN" \
    -w "$HOST_DIR" "$CONTAINER" \
    sh -c '[ -n "${ANTHROPIC_API_KEY:-}" ] || unset ANTHROPIC_API_KEY; exec node "$1"' _ "$ENTRY"
