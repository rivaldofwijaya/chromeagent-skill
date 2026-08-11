# chromeagent-skill

A portable skill that lets any coding agent drive **your own running Chrome**, with the profile,
cookies, logins, and tabs you already have open, through the
[`chrome-devtools-mcp`](https://www.npmjs.com/package/chrome-devtools-mcp) server.

## Requirements

- **Node.js LTS** with `npx` (hard requirement of `chrome-devtools-mcp`). `bunx`, `pnpm dlx`, or a
  globally installed `chrome-devtools-mcp` also work.
- **Google Chrome 144 or newer.** `--autoConnect` attaches to your default profile, and that is a
  144+ feature.
- A **one-time opt-in inside Chrome**: open `chrome://inspect/#remote-debugging` and click Allow.
  Nothing here automates that step.
- Native Windows setup uses PowerShell 6+ (`pwsh`). Windows PowerShell 5.1 works for `preflight.ps1`.

## Install

```bash
git clone https://github.com/rivaldofwijaya/chromeagent-skill.git
```

Copy the directory into your agent's skills location, then run setup from your project root:

```bash
sh scripts/setup-mcp.sh --agent auto
```

On native Windows, use the PowerShell setup script:

```powershell
pwsh -File scripts/setup-mcp.ps1 -Agent auto
```

Restart your agent afterwards. MCP config is read at startup.

Both setup scripts resolve paths relative to the current working directory, so run them from the project root; the skill's own directory is never the right place. Invoke the scripts by their absolute path from the project-root shell. If the working directory cannot be the project root, pass `--out-dir "<dir>"` (or `-OutDir "<dir>"`) as the explicit output override. Preflight scans config paths relative to its own current working directory and has no `--out-dir`/`-OutDir` override. If setup writes elsewhere, run preflight from that output directory; otherwise it reports `NOT_CONFIGURED` even though the config exists.

`auto` configures project-scoped agents only (Claude Code and OpenCode); Codex requires an explicit `--agent codex` and writes the user's global `~/.codex/config.toml`.

For `auto`, markers in the resolved output directory select the project target: `.mcp.json` or `.claude/` selects Claude Code, and `opencode.json` selects OpenCode. With no marker, `auto` falls back to Claude Code. It never writes Codex's global config. When Codex is present, POSIX prints `setup-mcp: codex detected but not configured; run --agent codex to update your global Codex config.` and PowerShell prints `setup-mcp: codex detected but not configured; run -Agent codex to update your global Codex config.`

A successful setup prints the absolute path it wrote; check that path against the project root. `--out-dir` and `-OutDir` require an existing directory; neither script creates it.

The help output is:

`usage: setup-mcp.sh --agent auto|claude|codex|opencode [--runner "<argv>"] [--channel beta|dev|canary] [--out-dir <dir>] [--no-redact]`

`usage: setup-mcp.ps1 -Agent auto|claude|codex|opencode [-Runner "<argv>"] [-Channel beta|dev|canary] [-OutDir <dir>] [-NoRedact]`

### Per agent

| Agent | Config written | Scope |
|---|---|---|
| Claude Code | `./.mcp.json` | project |
| OpenCode | `./opencode.json` (`mcp` key, `type: "local"`) | project |
| Codex | `codex mcp add …` → `~/.codex/config.toml` | **global**, since Codex has no project scope |
| Cursor | `./.cursor/mcp.json`, same shape as `.mcp.json`; write it yourself or copy the snippet | project |
| VS Code | `./.vscode/mcp.json`, top-level `servers` shape; write it yourself or copy the VS Code snippet | project |

Preflight detects all five locations, so a hand-written Cursor or VS Code config counts as configured.

### Claude Code / Cursor config (`.mcp.json` / `.cursor/mcp.json`)

```json
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["-y", "chrome-devtools-mcp@latest", "--autoConnect", "--redactNetworkHeaders"]
    }
  }
}
```

### OpenCode config (`opencode.json`)

OpenCode uses a different shape: its `command` is an array containing the runner and all MCP
arguments.

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "chrome-devtools": {
      "type": "local",
      "enabled": true,
      "command": ["npx", "-y", "chrome-devtools-mcp@latest", "--autoConnect", "--redactNetworkHeaders"]
    }
  }
}
```

### Codex config (`~/.codex/config.toml`)

Codex is registered through its CLI rather than a file you write, and it has no project scope, so
this touches your **global** Codex config. Use the explicit `setup-mcp.sh --agent codex` (or
`pwsh -File scripts/setup-mcp.ps1 -Agent codex`) when you want to update it:

```bash
codex mcp add chrome-devtools -- npx -y chrome-devtools-mcp@latest --autoConnect --redactNetworkHeaders
```

That produces:

```toml
[mcp_servers.chrome-devtools]
command = "npx"
args = ["-y", "chrome-devtools-mcp@latest", "--autoConnect", "--redactNetworkHeaders"]
```

### VS Code config (`.vscode/mcp.json`)

VS Code uses a top-level `servers` object, not `mcpServers`. Its other top-level sections are
optional `inputs` and optional `sandbox` (macOS/Linux only); `type: "stdio"` is optional because
stdio is the default.

```json
{
  "servers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["-y", "chrome-devtools-mcp@latest", "--autoConnect", "--redactNetworkHeaders"]
    }
  }
}
```

Flags: `--runner "<argv>"`, `--channel beta|dev|canary`, `--out-dir "<dir>"`, `--no-redact` to use
something other than `npx`, select a non-stable Chrome, choose an explicit output directory, or stop
redacting network headers (only when you are deliberately
debugging auth headers).
PowerShell: `-Runner "<argv>"`, `-Channel beta|dev|canary`, `-OutDir "<dir>"`, and `-NoRedact` with
`setup-mcp.ps1`.

## Check your setup

```bash
sh scripts/preflight.sh      # macOS, Linux, Git Bash / WSL
pwsh -File scripts/preflight.ps1
```

It prints `KEY=value` lines ending in one `STATUS=`. `STATUS=READY` validates local conditions only:
the runner, Chrome, config, and browser/debug state. It does not test whether this agent session has
loaded the MCP tools. If the tools are absent, typically because setup just wrote the config, reload
or restart the MCP connection, wait for the tools to appear, then continue.
Preflight exits 0 when it produces a verdict; use `STATUS`, not the process exit code.
See `references/troubleshooting.md` for anything else.

## Security note

Attaching to your real profile exposes every logged-in session to the agent and to page content.
`--redactNetworkHeaders` is on by default. The skill's policy requires explicit approval before
reading credentials, cookies, tokens, payment details, or private messages, and confirmation before
destructive, irreversible, or outward-facing actions.

## Tests

```bash
sh tests/run-tests.sh
```

Hermetic: every test runs in a sandbox with its own `HOME`, `PATH`, and fake Chrome installs.
PowerShell tests are skipped when `pwsh` is absent.

## License

[MIT](LICENSE).
