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
  This is the launch mode that yields `DEBUG_REACHABLE=yes` and serves `/json/list`; the
  `chrome://inspect` opt-in yields `DEBUG_REACHABLE=optin` and serves neither.
- **`--isolated`**: the MCP server launches a throwaway profile. **You lose all cookies and logins.**

## `NOT_CONFIGURED`

No `chrome-devtools` entry with `--autoConnect` in any scanned config. Run
`sh scripts/setup-mcp.sh --agent auto`, then **restart your agent**. MCP config is read at startup.
On native Windows, use `pwsh -File scripts/setup-mcp.ps1 -Agent auto` instead.

Scanned, in order: `./.mcp.json`, `./.vscode/mcp.json`, `./.cursor/mcp.json`, `./opencode.json`,
`./.codex/config.toml`, `~/.codex/config.toml`, `~/.config/opencode/opencode.json`.

## Config was written to the wrong directory

**Symptom:** Setup reports success but preflight still says `NOT_CONFIGURED`, or the agent never gains the tools.

**Cause:** Both setup scripts resolve paths against the working directory, and a shell that was `cd`'d elsewhere — for example into the skill's own directory — silently retargets the write. Preflight also scans config paths relative to its own working directory, so it will not find a config written by `--out-dir`/`-OutDir` when run from a different directory.

**Fix:** Check the absolute path in setup's output, move or delete the stray file, then re-run setup from the project root or pass `--out-dir` (or `-OutDir`). If you use an output-directory override, run preflight from that same directory. `auto` does not configure Codex; use the explicit `--agent codex` (or `-Agent codex`) for the user's global Codex config.

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

The opt-in endpoint is **WebSocket-only**. It exposes exactly the browser endpoint named on line 2
of `DevToolsActivePort` and answers `404` to every HTTP path, including `/json/version` and the rest
of the `/json/*` family. A manual `curl http://127.0.0.1:<DEBUG_PORT>/json/version` returning `404` is
therefore **not** evidence of a broken setup — it is what a healthy opt-in looks like.

Use the values preflight already printed — `DEBUG_PORT` and `USER_DATA_DIR` — rather than the
defaults. A beta, dev, or canary profile has its own directory, and Chrome can pick a port other
than 9222. The checks that do work:

- `lsof -nP -iTCP:<DEBUG_PORT> -sTCP:LISTEN` — something is listening on the port.
- `cat "<USER_DATA_DIR>/DevToolsActivePort"` — line 1 is the port, line 2 is the
  `/devtools/browser/<uuid>` path.

Preflight reports this state as `DEBUG_REACHABLE=optin`.

## `READY` but the MCP tools are absent from the session

**Symptom:** Preflight reports `STATUS=READY`, but this agent session has no `chrome-devtools` tools.

**Cause:** `READY` validates local conditions only: runner, Chrome, config, and browser/debug state.
Preflight cannot see whether the agent's MCP client has loaded its tools. This is common immediately
after setup writes the config.

**Fix:** Reload or restart the MCP connection, wait for the tools to appear, then continue. The MCP
server loads at agent startup.

### Other `READY` checks

- `DEBUG_REACHABLE=optin` means something answered on the debug port with a non-200 status. That is
  the normal value for a `chrome://inspect` opt-in, whose endpoint is WebSocket-only. It reports
  `READY` only when Chrome's `DevToolsActivePort` file is also present, so the two together are the
  evidence; the real connection remains the final test. `DEBUG_REACHABLE=yes` means the classic
  `--remote-debugging-port` launch, which does serve `/json/version` over plain HTTP.
- An uncommon false `READY` can occur if `DevToolsActivePort` is stale. Chrome does not delete the
  file when opt-in is revoked, and preflight trusts line 1 both as the port to probe and as the port-file
  corroboration. If an unrelated listener occupies that port and returns any non-200 response, preflight
  sees `DEBUG_REACHABLE=optin` plus the port file and reports `STATUS=READY`, even though Chrome is not
  serving DevTools there. `READY` validates local conditions only; the real connection remains the final
  test. To tell, run `lsof -nP -iTCP:<DEBUG_PORT> -sTCP:LISTEN` and confirm the listener is a Google
  Chrome process, then check that line 1 of `<USER_DATA_DIR>/DevToolsActivePort` is the port you
  expect — taking both values from preflight's own output rather than assuming port 9222 and the
  stable-channel profile. Delete the stale file and/or free the port, re-do the opt-in, and re-run
  preflight; Chrome rewrites the file when opt-in is granted.
  A stale file with nothing listening yields `DEBUG_REACHABLE=no` and correctly leads to
  `NEEDS_OPT_IN`, so this is a rare squatter edge case, not a routine failure.
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
