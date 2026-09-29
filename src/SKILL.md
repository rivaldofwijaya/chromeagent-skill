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
already good, so it **is** the check. On success: say nothing about setup, pick the tab the user already
has open (§5), and get on with the task.

Run preflight only when `list_pages` fails or the tools are absent. Do not use it as idle polling:
reruns and re-probes after remediation or a user action are expected, but do not repeat it when
nothing has changed.

## 2. Preflight

For project-scoped targets, the following working-directory rule applies. Both setup scripts resolve paths relative to the current working directory, so run them from the project root; the skill's own directory is never the right place. Invoke the scripts by their absolute path from the project-root shell. If the working directory cannot be the project root, use `--out-dir <dir>` (or `-OutDir <dir>`) as the explicit output override. Preflight scans config paths relative to its own current working directory and has no `--out-dir`/`-OutDir` override. If setup writes elsewhere, run preflight from that output directory; otherwise it reports `NOT_CONFIGURED` even though the config exists.

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
| `READY` | If the `chrome-devtools` tools are present, say nothing: `list_pages` → pick the tab (§5) → the user's task. If the tools are absent, do not call `list_pages` yet: the config may have just been written, so reload/restart the MCP connection, wait for the tools to appear, then continue. |
| `NOT_CONFIGURED` | Pick the setup target for the host you are actually running in, then run setup without asking. Under Claude Code or OpenCode use `--agent auto` (`-Agent auto`), which reads markers in the output directory to choose between them. Under Codex use `--agent codex` (`-Agent codex`), which writes the user's global `~/.codex/config.toml`: say so before running it; `auto` never writes it, so following the `auto` branch under Codex configures a consumer that is not running. POSIX: `sh /path/to/chromeagent-skill/scripts/setup-mcp.sh --agent <target>`; native Windows: `pwsh -File /path/to/chromeagent-skill/scripts/setup-mcp.ps1 -Agent <target>`. Under `auto` the command writes into the current working directory, which must be the project root unless an explicit output directory is supplied. If `CHROME_CHANNEL` is not `stable`, or setup exits non-zero, read `references/setup.md` first: it has the channel flag, the exit codes, and the merge rules. On successful setup the config was just written; reload/restart the MCP connection before calling any tool, because MCP config is read at startup. |
| `NEEDS_OPT_IN` | Stop. One instruction: "Open `chrome://inspect/#remote-debugging` in Chrome and click Allow." Then re-run preflight. |
| `CHROME_NOT_RUNNING` | Ask the user to open Chrome normally, then re-run preflight. |
| `CHROME_TOO_OLD` | Report the actual `CHROME_VERSION` found and that `--autoConnect` needs Chrome 144+. Offer the fallbacks below as an explicit choice. |
| `CHROME_MISSING` | Say Chrome was not found, and offer the fallbacks below. |
| `NODE_MISSING` | Ask **once** whether to install Node.js LTS: `winget install OpenJS.NodeJS.LTS` (fallback `choco install nodejs-lts`) / `brew install node` / distro package or `nvm`. Yes → install, then open a **new** terminal (or refresh `PATH`) before re-probing: a shell started before the install still has the pre-install `PATH`, so the re-probe reports `NODE_MISSING` again and looks like a failed install. No → try `bunx`, `pnpm dlx`, or a global `chrome-devtools-mcp` and configure that runner via `--runner`. Neither → hard fail: Node.js LTS is a hard requirement of `chrome-devtools-mcp`. |

`NODE_MISSING` means `RUNNER=none`: preflight found no `npx`, `bunx`, `pnpm`, or global
`chrome-devtools-mcp` runner. If one of those is available, preflight reports that runner instead.

## 4. Fallbacks: offered, never chosen silently

Both cost the user something. State the cost, let them pick.

- `--browserUrl=http://127.0.0.1:9222` against a Chrome the user launches themselves with a separate
  `--user-data-dir`. Keeps a debuggable instance without the 144+ opt-in, but it is **not** their
  normal profile unless they point it at one.
- `--isolated`, an MCP-launched throwaway profile. **Loses all cookies and logins.**

Silent degradation is prohibited. Never quietly fall back to an isolated profile.

## 5. Working style once attached

You are driving the user's live browser, not a scratch one.

- Attach to what exists: call `list_pages`. Pick the tab by what it shows — its title and URL — not
  by its position in the list. When more than one tab could be the right one, name the candidates and
  ask instead of guessing. Page tools take that tab's `pageId` (the server default); pass it rather
  than relying on `select_page`, which only sets the target for calls without one. Don't spray new tabs.
- Close only tabs you opened. A tab the user already had open is theirs: close it only when the user asks for that tab, and name the tab you are closing so they can stop you if it is the wrong one. §6's confirm-first entry is how you obtain that request when the user has not already made it; this bullet says which tab the rule is about, not a second gate.
- Leave the browser as you found it: no clearing storage, no signing out, no changing settings as a
  side effect.
- After any navigation, reload, or action that re-renders the page, take a fresh `take_snapshot` before reusing any element reference. A reference from an earlier snapshot can now point at a
  different element, or at nothing. When the next step needs that fresh state anyway, pass
  `includeSnapshot: true` to the input action instead of making a second call.
- Read with `take_snapshot`; screenshot only when layout or visual state actually matters. Send a
  large snapshot, screenshot, or trace to `filePath` instead of into the conversation, unless the
  page holds the sensitive data in §7.
- Verify the requested outcome from what the page now shows — the URL, the confirmation, the
  changed row — not from the fact that a tool call returned without error.

## 6. Action policy: default allow

This is a browser-automation skill. Get work done.

**Authorisation follows the effect, not the mechanism.** Clicking, typing, submitting a form and
calling `evaluate_script` are all just ways of causing something to happen; what decides the rule
is what happens to the user's account or to the outside world. A click that publishes is a publication, and a script that posts a request is that request. The two lists below cover the
ordinary cases — when a control's label, the page state, or the script's own body shows a
confirm-first effect, it is confirm-first whatever the mechanism.

**Allowed without asking:** navigate, click, hover, drag, type, fill forms, scroll, read
DOM/console/network, screenshot, `evaluate_script`, performance traces, open new tabs.

**Confirm first**, with one clear question naming the concrete effect, before:
- deleting or destroying anything (delete records, close an account, clear data or history);
- irreversible or outward-facing actions (submit a payment, place an order, send an email or
  message, post publicly, invite or remove a user);
- anything that invalidates the session (logout, revoke tokens, change password);
- closing a tab the user already had open;
- bulk actions repeated across many items.

A request that names the effect carries its own authorisation: when they asked you to send *that*
message, sending it is the task, not a fresh risk to re-ask about. A request that names only a goal
— "clean up my inbox", "get my order through" — does not name the deletions, the payment, or the
bulk repetition that reaching it would take, so each of those stays confirm-first. Authorisation
reaches the named action and its obvious repeats within the task; it is not a blanket pass for the
session and does not transfer to a different class of risky action. If page state makes an allowed action risky in context, such as a "Save" that also
publishes, treat it as confirm-first.

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
- The default config also carries `--no-performance-crux`, so a performance trace does not send the
  traced URLs to Google's CrUX API. Drop it only when the user asks for field data, and say that the
  traced URLs will leave the machine.
- Say once, at first setup, that attaching to the real profile exposes logged-in sessions to you and
  to page content. Don't repeat it every run.

## Reference

- `references/setup.md`: the setup CLI's flags, channels, exit codes, and merge rules.
- `references/troubleshooting.md`: failure modes and their fixes.
