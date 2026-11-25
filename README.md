# Claude Code as an ACP agent in PhpStorm

Runs Claude Code **inside a dev container** from the JetBrains AI / Air chat panel, using
the container's Claude Code login, settings and toolchain. The built-in "Claude" entry in
the agent picker runs Claude Code on the host instead.

## How it works

The adapter (`@agentclientprotocol/claude-agent-acp`) is installed **on the host** and
executed **inside the container** over the project's bind mount, so the container needs
no npm registry access.

PhpStorm spawns `claude-acp.sh` on the host. The script `docker exec`s into the
container and speaks ACP (JSON-RPC) over stdio.

## Requirements

- Docker on the host, and a running dev container with the project bind-mounted
- Node.js in the container, and Claude Code installed and logged in there
- Node.js and npm on the host, for `setup.sh`
- macOS or Linux host (the scripts are bash)

## Files

| File | Runs on | Purpose |
|---|---|---|
| `claude-acp.sh` | host | Spawned by PhpStorm; execs the adapter in the container |
| `setup.sh` | host | Installs the adapter, registers the agent |
| `package.json` | — | Pins the adapter |
| `node_modules/` | container | The adapter. ~70 MB; safe to delete, `setup.sh` restores it |

## Install

On the host, not in the container. Clone into the project's `.claude/acp`, so the
container can run the adapter from `<container project dir>/.claude/acp` over the bind mount:

```bash
cd <project>
git clone https://github.com/ptmcnally/claude-code-docker-acp.git .claude/acp
bash .claude/acp/setup.sh <claude-container-name>
```

`<claude-container-name>` is your dev container as shown by `docker ps --format '{{.Names}}'`.
`setup.sh` writes `~/.jetbrains/acp.json` if absent, otherwise prints the entry to add. Then
pick **Claude Docker** in the AI Chat agent list. The config hot-reloads; no IDE restart.

Add `.claude/acp/` to the project's `.gitignore`.

## Config format

`~/.jetbrains/acp.json`: the top-level key is `agent_servers`, and each key is the
display name shown in AI Chat:

```json
{
  "default_mcp_settings": {},
  "agent_servers": {
    "Claude Docker": {
      "command": "/Users/<you>/<repo>/.claude/acp/claude-acp.sh",
      "args": [],
      "env": {
        "CLAUDE_ACP_CONTAINER": "<claude-container-name>"
      }
    }
  }
}
```

Any other shape (`agents`, the registry's `distribution` form) reloads silently and
registers nothing; no validation error is logged. Keep each string on one line: a line
break inside a key or value breaks the entry. Docs:
`jetbrains.com/help/ai-assistant/2026.2/acp.html#add-custom-agent`

## Configuration

Set these in the agent's `env` in `acp.json`. Defaults match the standard Claude Code
dev container.

| Variable | Default | Purpose |
|---|---|---|
| `CLAUDE_ACP_CONTAINER` | required | Container name |
| `CLAUDE_ACP_HOST_DIR` | two levels above `claude-acp.sh` | Project path on the host |
| `CLAUDE_ACP_CONTAINER_DIR` | `/workspace` | Project path in the container |
| `CLAUDE_ACP_CONTAINER_USER` | `node` | User the agent runs as |
| `CLAUDE_ACP_CONTAINER_HOME` | `/home/<user>` | That user's home, where Claude Code keeps its login |
| `CLAUDE_ACP_CLAUDE_BIN` | `<home>/.local/bin/claude` | Claude Code binary in the container |

## Gotchas

- **`HOME`**: `docker exec -u <user>` inherits the *host's* `HOME`, not the container
  user's. The script sets it explicitly; otherwise Claude Code cannot find its login.
- **`ANTHROPIC_API_KEY`**: an empty value is dropped so it does not shadow the login.
- **Paths**: ACP has no path translation. The IDE sends host paths; the container sees
  its own project path. Fixed with a symlink (host path → container path) recreated on each
  launch. Do **not** bind-mount the repo a second time, as that bypasses any mounts
  layered over it.
- **stdout**: ACP is JSON-RPC over stdio. Anything on stdout corrupts the stream; all
  diagnostics must go to stderr.
- **Claude Code binary**: `setup.sh` installs with `--omit=optional`, which drops the
  SDK's bundled per-platform Claude Code binaries (~550 MB). `CLAUDE_CODE_EXECUTABLE`
  points the adapter at the container's own Claude Code instead; without it the adapter
  fails to start.
- **`PATH`**: GUI-spawned processes on macOS get a minimal PATH, so the script adds
  `/usr/local/bin` and `/opt/homebrew/bin` for `docker`.

## Troubleshooting

```bash
CLAUDE_ACP_CONTAINER=<claude-container-name> ./claude-acp.sh --check     # host only; prints container, user, entry point, symlink
CLAUDE_ACP_CONTAINER=<claude-container-name> ./claude-acp.sh < /dev/null # should exit silently; any stdout output is a bug
```

Errors surface in the chat panel. IDE-side logging:

```bash
grep -iE 'acp.json|Local ACP agents' ~/Library/Logs/JetBrains/PhpStorm*/idea.log | tail
```

Agent count should rise by one when the config loads. If an old chat fails to reopen,
start a new one.

## Security

The agent is an ordinary process inside the container: the container's auth, settings,
hooks, network rules and mounts all apply to it. The adapter's npm packages are installed
on the host and enter the container over the bind mount, so review them as you would any
other dependency you place there.

## License

MIT, see [LICENSE](LICENSE).
