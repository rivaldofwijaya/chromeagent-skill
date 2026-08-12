---
name: chromeagent
description: Use when a task needs the user's own running Chrome, with their real profile, cookies, logins, and open tabs, driven through the chrome-devtools MCP server. Verifies or performs one-time setup, then attaches and works.
---

# chromeagent

Drive the user's **real** Chrome through the `chrome-devtools-mcp` server. Most sessions are already
set up; the whole point of this skill is to reach the user's task without ceremony.

## 1. Fast path: try first, do not probe

If `chrome-devtools` MCP tools are present in this session, call `list_pages` immediately.

That call only succeeds when config, Chrome version, and the `chrome://inspect` opt-in are all
already good, so it **is** the check. On success: say nothing about setup, `select_page` on the tab
the user already has open, and get on with the task.

Run preflight only when `list_pages` fails or the tools are absent. Do not use it as idle polling:
reruns and re-probes after remediation or a user action are expected, but do not repeat it when
nothing has changed.

## 2. Preflight

Both setup scripts resolve paths relative to the current working directory, so run them from the project root; the skill's own directory is never the right place. Invoke the scripts by their absolute path from the project-root shell. If the working directory cannot be the project root, use `--out-dir <dir>` (or `-OutDir <dir>`) as the explicit output override. Preflight scans config paths relative to its own current working directory and has no `--out-dir`/`-OutDir` override. If setup writes elsewhere, run preflight from that output directory; otherwise it reports `NOT_CONFIGURED` even though the config exists.

Replace the placeholder paths below with your project root and the installed skill directory.

```bash
cd /path/to/your/project
sh /path/to/chromeagent-skill/scripts/preflight.sh  # macOS, Linux, Git Bash / WSL
```
```powershell
Set-Location /path/to/your/project
pwsh -File /path/to/chromeagent-skill/scripts/preflight.ps1  # native Windows
```

The two paths are different directories, and that is the whole trap: the shell sits in the project,
while the script path points into the installed skill. Worked example for a project at
`~/code/acme-web` and a skill installed at `~/.claude/skills/chromeagent-skill`:

```bash
cd ~/code/acme-web                                              # the CWD preflight scans for config
sh ~/.claude/skills/chromeagent-skill/scripts/preflight.sh      # where the scripts actually live
```

Both print `KEY=value` lines ending in exactly one `STATUS=`. Preflight reports local runner, Chrome,
config, and browser/debug state; it does not test whether this agent session has loaded the MCP tools.
The complete 15-key output contract, in exact order, is:

`PLATFORM`, `RUNNER`, `RUNNER_CMD`, `CHROME_PATH`, `CHROME_CHANNEL`, `CHROME_VERSION`, `CHROME_MAJOR`, `CHROME_OK`, `USER_DATA_DIR`, `CHROME_RUNNING`, `DEBUG_PORT`, `DEBUG_REACHABLE`, `MCP_CONFIG_FILE`, `MCP_CONFIGURED`, `STATUS`.

When a verdict is produced, preflight always exits 0. The `STATUS` value is the signal; never branch
on preflight's exit code.

Read the `STATUS` and branch. Verdict precedence is first failing check wins: `NODE_MISSING` >
`CHROME_MISSING` > `CHROME_TOO_OLD` > `NOT_CONFIGURED` > `CHROME_NOT_RUNNING` > `NEEDS_OPT_IN` >
`READY`.

## 3. Branch on STATUS

| STATUS | Do this |
|---|---|
| `READY` | If the `chrome-devtools` tools are present, say nothing: `list_pages` → `select_page` → the user's task. If the tools are absent, do not call `list_pages` yet: the config may have just been written, so reload/restart the MCP connection, wait for the tools to appear, then continue. |
| `NOT_CONFIGURED` | Run `sh /path/to/chromeagent-skill/scripts/setup-mcp.sh --agent auto` on POSIX or `pwsh -File /path/to/chromeagent-skill/scripts/setup-mcp.ps1 -Agent auto` on native Windows without asking. The command writes into the current working directory, which must be the project root unless an explicit output directory is supplied. On successful setup the config was just written; reload/restart the MCP connection before calling any tool, because MCP config is read at startup. |
| `NEEDS_OPT_IN` | Stop. One instruction: "Open `chrome://inspect/#remote-debugging` in Chrome and click Allow." Then re-run preflight. |
| `CHROME_NOT_RUNNING` | Ask the user to open Chrome normally, then re-run preflight. |
| `CHROME_TOO_OLD` | Report the actual `CHROME_VERSION` found and that `--autoConnect` needs Chrome 144+. Offer the fallbacks below as an explicit choice. |
| `CHROME_MISSING` | Say Chrome was not found, and offer the fallbacks below. |
| `NODE_MISSING` | Ask **once** whether to install Node.js LTS: `winget install OpenJS.NodeJS.LTS` (fallback `choco install nodejs-lts`) / `brew install node` / distro package or `nvm`. Yes → install, then open a **new** terminal (or refresh `PATH`) before re-probing: a shell started before the install still has the pre-install `PATH`, so the re-probe reports `NODE_MISSING` again and looks like a failed install. No → try `bunx`, `pnpm dlx`, or a global `chrome-devtools-mcp` and configure that runner via `--runner`. Neither → hard fail: Node.js LTS is a hard requirement of `chrome-devtools-mcp`. |

`NODE_MISSING` means `RUNNER=none`: preflight found no `npx`, `bunx`, `pnpm`, or global
`chrome-devtools-mcp` runner. If one of those is available, preflight reports that runner instead.

If preflight reports `CHROME_CHANNEL` as `beta`, `dev`, or `canary`, pass that exact reported value through.
On POSIX use `sh /path/to/chromeagent-skill/scripts/setup-mcp.sh --agent auto --channel "$CHROME_CHANNEL"`;
on native Windows use `pwsh -File /path/to/chromeagent-skill/scripts/setup-mcp.ps1 -Agent auto -Channel $CHROME_CHANNEL`.
A non-stable Chrome keeps its
profile in a different directory and `--autoConnect` must be told which one. Omit the channel flag for
`stable`.

The POSIX setup CLI accepts agents `auto|claude|codex|opencode`, plus `--runner "<argv>"`,
`--channel beta|dev|canary`, `--out-dir <dir>`, and `--no-redact`. The native PowerShell spelling is `-Agent`, `-Runner`, `-Channel`, and `-NoRedact`; add `-OutDir <dir>` for the output-directory override. It accepts the same three channel values. On native Windows, use
`pwsh -File /path/to/chromeagent-skill/scripts/setup-mcp.ps1 -Agent auto` for the setup branch above. Both setup CLIs use exit 0
for success and exit 2 for bad usage or invalid agent/channel values. Exit 3 is a setup failure on
either platform, not a preflight verdict and not synonymous with manual merge.

The help output is:

`usage: setup-mcp.sh --agent auto|claude|codex|opencode [--runner "<argv>"] [--channel beta|dev|canary] [--out-dir <dir>] [--no-redact]`

`usage: setup-mcp.ps1 -Agent auto|claude|codex|opencode [-Runner "<argv>"] [-Channel beta|dev|canary] [-OutDir <dir>] [-NoRedact]`

`auto` configures project-scoped agents only (Claude Code and OpenCode); Codex requires an explicit `--agent codex` and writes the user's global `~/.codex/config.toml`.

For `auto`, markers in the resolved output directory select the project target: `.mcp.json` or `.claude/` selects Claude Code, and `opencode.json` selects OpenCode. With no marker, `auto` falls back to Claude Code. It never writes Codex's global config. When Codex is present, POSIX prints `setup-mcp: codex detected but not configured; run --agent codex to update your global Codex config.` and PowerShell prints `setup-mcp: codex detected but not configured; run -Agent codex to update your global Codex config.`

A successful setup prints the absolute path it wrote; check that path against the project root. `--out-dir` and `-OutDir` require an existing directory; neither script creates it.

The setup defaults are exactly `--autoConnect`, `--redactNetworkHeaders`, in that order;
`--no-redact` (or `-NoRedact`) drops the redaction flag, and a channel flag follows those defaults.

If preflight reports `CHROME_CHANNEL=chromium`, do not pass `--channel chromium` or `-Channel chromium`:
neither setup CLI accepts that value. Offer the `--browserUrl` fallback below, using a Chromium instance
the user launches with remote debugging, or ask the user to use a supported Chrome channel.

For `setup-mcp.sh`, an existing config with no Node available for JSON merging is left untouched, a
manual-merge snippet is printed, and the command exits 3. Invalid JSON during a Node merge and Codex
registration failures also exit 3. `setup-mcp.ps1` always merges an existing config natively with its
PowerShell JSON parser; invalid existing JSON and Codex registration failures can also exit 3, but it
does not use the sh manual-merge branch. This cross-platform difference is deliberate.

## 4. Fallbacks: offered, never chosen silently

Both cost the user something. State the cost, let them pick.

- `--browserUrl=http://127.0.0.1:9222` against a Chrome the user launches themselves with a separate
  `--user-data-dir`. Keeps a debuggable instance without the 144+ opt-in, but it is **not** their
  normal profile unless they point it at one.
- `--isolated`, an MCP-launched throwaway profile. **Loses all cookies and logins.**

Silent degradation is prohibited. Never quietly fall back to an isolated profile.

## 5. Working style once attached

You are driving the user's live browser, not a scratch one.

- Attach to what exists: `list_pages` → `select_page`. Don't spray new tabs.
- Prefer `take_snapshot` for reading page structure; screenshot when layout or visual state actually
  matters.
- Never close a tab the user already had open. Close only tabs you opened.
- Leave the browser as you found it: no clearing storage, no signing out, no changing settings as a
  side effect.

## 6. Action policy: default allow

This is a browser-automation skill. Get work done.

**Allowed without asking:** navigate, click, hover, drag, type, fill forms, scroll, read
DOM/console/network, screenshot, `evaluate_script`, performance traces, open new tabs.

**Confirm first**, with one clear question naming the concrete effect, before:
- deleting or destroying anything (delete records, close an account, clear data or history);
- irreversible or outward-facing actions (submit a payment, place an order, send an email or
  message, post publicly, invite or remove a user);
- anything that invalidates the session (logout, revoke tokens, change password);
- closing tabs the user had open;
- bulk actions repeated across many items.

Authorisation covers that action and its obvious repeats within the task. It is not a blanket pass
for the session, and it does not transfer to a different class of risky action. If page state makes
an allowed action risky in context, such as a "Save" that also publishes, treat it as confirm-first.

## 7. Sensitive data

The real profile means every logged-in session is reachable.

- Read credentials, cookies, auth tokens, payment details, private messages, and health or financial
  page content **only** when the task genuinely requires it **and** the user has explicitly approved
  that specific access.
- When approved, use the minimum: confirm a property ("the session cookie is present") rather than
  echoing the value.
- Never transmit such data to an external service, paste it into a commit, or write it to a file
  outside what the user asked for.
- Redact when quoting: truncate tokens and keys; never reproduce a full card or account number.
- The default config carries `--redactNetworkHeaders`. Drop it only when the user is deliberately
  debugging auth headers and says so, and note the change when you do.
- Say once, at first setup, that attaching to the real profile exposes logged-in sessions to you and
  to page content. Don't repeat it every run.

## Reference

`references/troubleshooting.md`: failure modes and their fixes.
