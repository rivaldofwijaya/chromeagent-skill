# Troubleshooting

Run `sh scripts/preflight.sh` (or `pwsh -File scripts/preflight.ps1`) and match the `STATUS=` line.
Preflight emits a verdict and exits 0; use `STATUS`, not the process exit code.

## `NODE_MISSING`

No `npx`, `bunx`, `pnpm`, or global `chrome-devtools-mcp`.

- macOS: `brew install node`
- Windows: `winget install OpenJS.NodeJS.LTS` (or `choco install nodejs-lts`)
- Linux: your distro package, or `nvm install --lts`

Then re-run preflight. If you cannot install Node, `bunx` or `pnpm dlx` work:
`sh scripts/setup-mcp.sh --agent auto --runner "bunx"`.

## `CHROME_MISSING`

No Chrome or Chromium was found in the standard locations for your platform. Install Google Chrome,
or if it lives somewhere unusual, use the `--browserUrl` fallback below.

## `CHROME_TOO_OLD`

`--autoConnect` needs Chrome 144+. Preflight reports the version it found in `CHROME_VERSION`.
Update Chrome (Menu → Help → About Google Chrome), or use a fallback:

- **`--browserUrl`**: launch Chrome yourself with `--remote-debugging-port=9222` **and a separate
  `--user-data-dir`**, then configure `--browserUrl=http://127.0.0.1:9222`. No 144 opt-in needed, but
  it is not your normal profile unless you point it at one. Chrome refuses `--remote-debugging-port`
  against the default profile, which is why the separate dir is mandatory.
- **`--isolated`**: the MCP server launches a throwaway profile. **You lose all cookies and logins.**

## `NOT_CONFIGURED`

No `chrome-devtools` entry with `--autoConnect` in any scanned config. Run
`sh scripts/setup-mcp.sh --agent auto`, then **restart your agent**. MCP config is read at startup.
On native Windows, use `pwsh -File scripts/setup-mcp.ps1 -Agent auto` instead.

Scanned, in order: `./.mcp.json`, `./.vscode/mcp.json`, `./.cursor/mcp.json`, `./opencode.json`,
`./.codex/config.toml`, `~/.codex/config.toml`, `~/.config/opencode/opencode.json`.

## Existing config could not be merged

Symptom: setup reports that an existing file is invalid, cannot be written, or is already present
without Node, and exits 3. The existing config is left untouched.

Cause: POSIX `setup-mcp.sh` uses Node to parse and merge an existing JSON config. It reports
`already exists and Node is unavailable, so it was left untouched` and prints a snippet for manual
merge when Node is unavailable. Invalid JSON and other existing-file setup failures also exit 3.
`setup-mcp.ps1` always merges an existing config natively because PowerShell has a JSON parser; the `sh` manual-merge branch is unreachable on Windows. This asymmetry is deliberate. Invalid JSON and
other existing-file setup failures on Windows also exit 3.

Fix: preserve a copy of the existing file, repair its JSON or permissions, then rerun setup. On
POSIX without Node, merge the printed `chrome-devtools` entry by hand, or install Node and rerun.
On Windows, rerun `pwsh -File scripts/setup-mcp.ps1 -Agent auto` after repairing the file. Exit 3 is a setup failure on either platform; it is not only the manual-merge case. Restart the agent after
a successful setup.

## `CHROME_NOT_RUNNING`

Open Chrome normally (no special flags) and re-run preflight.

## `NEEDS_OPT_IN`

Chrome is running but is not exposing a debugging endpoint. Open
`chrome://inspect/#remote-debugging` and click **Allow**. It is a one-time per-profile choice, and
you can revoke it from the same page. Nothing automates this; it is a deliberate human gate.

If you already allowed it: fully quit Chrome (not just the window) and reopen it, then re-run
preflight.

## `READY` but the MCP tools are absent from the session

**Symptom:** Preflight reports `STATUS=READY`, but this agent session has no `chrome-devtools` tools.

**Cause:** `READY` validates local conditions only: runner, Chrome, config, and browser/debug state.
Preflight cannot see whether the agent's MCP client has loaded its tools. This is common immediately
after setup writes the config.

**Fix:** Reload or restart the MCP connection, wait for the tools to appear, then continue. The MCP
server loads at agent startup.

### Other `READY` checks

- Preflight reports `DEBUG_REACHABLE=unknown` on machines with no `curl`, `wget`, or `node` to probe
  with. If a port file existed it still reports `READY` and lets the real connection be the test,
  so a failure here means the endpoint genuinely is not answering. Re-do the opt-in.
- Non-stable Chrome keeps its profile elsewhere. Check `CHROME_CHANNEL`; if it is not `stable`,
  re-run setup with `--channel beta|dev|canary`.
- If `CHROME_CHANNEL=chromium`, do not pass `--channel chromium` to `setup-mcp.sh` or `-Channel
  chromium` to `setup-mcp.ps1`; neither setup CLI accepts it. Use the `--browserUrl` fallback or a
  supported Chrome channel instead.
- Multiple Chrome channels running at once: `--autoConnect` picks the channel's default profile, so
  quit the ones you are not targeting.

## Network headers look redacted

That is `--redactNetworkHeaders`, on by default. Re-run setup with `--no-redact` only when you are
deliberately debugging auth headers, and be aware the agent will then see them.
