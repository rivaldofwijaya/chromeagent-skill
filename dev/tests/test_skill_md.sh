skill_assert_fixed() {
  if printf '%s\n' "$2" | grep -F -q -- "$1"; then _ok "contains '$1'"
  else _fail "missing '$1' in output"; fi
}

test_case "SKILL.md: has frontmatter with name and description"
skill="$REPO_ROOT/src/SKILL.md"
head=$(head -5 "$skill")
assert_contains '^---' "$head"
assert_contains 'name: chromeagent' "$head"
assert_contains 'description:' "$head"
if [ "$(sed -n '1p' "$skill")" = '---' ]; then
  _ok "frontmatter opens on line 1"
else
  _fail "frontmatter does not open on line 1"
fi
closing=$(sed -n '2,20p' "$skill" | grep -n '^---$' | head -1 | cut -d: -f1)
if [ -n "$closing" ]; then _ok "frontmatter has a closing delimiter"; else _fail "missing closing frontmatter delimiter"; fi

test_case "SKILL.md: documents every verdict as a decision-table branch"
skill="$REPO_ROOT/src/SKILL.md"
table=$(sed -n '/^| STATUS | Do this |$/,/^$/p' "$skill")
for v in READY NOT_CONFIGURED NEEDS_OPT_IN CHROME_NOT_RUNNING CHROME_TOO_OLD CHROME_MISSING NODE_MISSING; do
  rows=$(printf '%s\n' "$table" | grep -c "^| \`$v\` |")
  if [ "$rows" -eq 1 ]; then _ok "decision table branches $v"; else _fail "decision table has $rows branches for $v"; fi
done

test_case "SKILL.md: puts the fast path section before the preflight script"
skill="$REPO_ROOT/src/SKILL.md"
fast_heading=$(grep -n '^## 1\. Fast path' "$skill" | head -1 | cut -d: -f1)
pre_heading=$(grep -n '^## 2\. Preflight$' "$skill" | head -1 | cut -d: -f1)
preflight_command=$(grep -n '^sh /path/to/chromeagent-skill/scripts/preflight\.sh' "$skill" | head -1 | cut -d: -f1)
if [ -n "$fast_heading" ] && [ -n "$pre_heading" ] && [ -n "$preflight_command" ] &&
   [ "$fast_heading" -lt "$pre_heading" ] && [ "$pre_heading" -lt "$preflight_command" ]; then
  _ok "fast path section and list_pages path precede preflight command"
  fast_section=$(sed -n "${fast_heading},$((pre_heading - 1))p" "$skill")
  skill_assert_fixed 'list_pages' "$fast_section"
else
  _fail "fast path section is not before the preflight command"
fi

test_case "SKILL.md: reloads absent MCP tools and permits remediation reruns"
skill="$REPO_ROOT/src/SKILL.md"
body=$(cat "$skill")
table=$(sed -n '/^| STATUS | Do this |$/,/^$/p' "$skill")
ready_row=$(printf '%s\n' "$table" | grep '^| `READY` |')
not_configured_row=$(printf '%s\n' "$table" | grep '^| `NOT_CONFIGURED` |')
skill_assert_fixed 'tools are absent' "$ready_row"
skill_assert_fixed 'config may have just been written' "$ready_row"
skill_assert_fixed 'reload/restart the MCP connection' "$ready_row"
skill_assert_fixed 'config was just written' "$not_configured_row"
skill_assert_fixed 'reload/restart the MCP connection' "$not_configured_row"
skill_assert_fixed 'does not test whether this agent session has loaded the MCP tools' "$body"
skill_assert_fixed 'Do not use it as idle polling' "$body"
skill_assert_fixed 'reruns and re-probes after remediation or a user action are expected' "$body"

test_case "SKILL.md: documents the preflight contract and decision signal"
skill="$REPO_ROOT/src/SKILL.md"
body=$(cat "$skill")
expected_keys='`PLATFORM`, `RUNNER`, `RUNNER_CMD`, `CHROME_PATH`, `CHROME_CHANNEL`, `CHROME_VERSION`, `CHROME_MAJOR`, `CHROME_OK`, `USER_DATA_DIR`, `CHROME_RUNNING`, `DEBUG_PORT`, `DEBUG_REACHABLE`, `MCP_CONFIG_FILE`, `MCP_CONFIGURED`, `STATUS`.'
keys_line=$(grep '^`PLATFORM`' "$skill" | head -1)
if [ "$keys_line" = "$expected_keys" ]; then _ok "15 preflight keys are in order"; else _fail "15-key preflight order changed: $keys_line"; fi
precedence=$(sed -n '/^Read the `STATUS` and branch/,/^$/p' "$skill" | tr '\n' ' ')
signal=$(sed -n '/^When a verdict is produced/,/^$/p' "$skill" | tr '\n' ' ')
skill_assert_fixed '`NODE_MISSING` > `CHROME_MISSING` > `CHROME_TOO_OLD` > `NOT_CONFIGURED` > `CHROME_NOT_RUNNING` > `NEEDS_OPT_IN` > `READY`.' "$precedence"
skill_assert_fixed 'preflight always exits 0' "$signal"
skill_assert_fixed '`STATUS` value is the signal; never branch on preflight' "$signal"
skill_assert_fixed '`--autoConnect` needs Chrome 144+' "$body"

test_case "SKILL.md: documents platform setup flags, channels, and exit failures"
skill="$REPO_ROOT/src/SKILL.md"
body=$(cat "$skill")
skill_assert_fixed 'sh /path/to/chromeagent-skill/scripts/setup-mcp.sh --agent auto --channel "$CHROME_CHANNEL"' "$body"
skill_assert_fixed 'pwsh -File /path/to/chromeagent-skill/scripts/setup-mcp.ps1 -Agent auto -Channel $CHROME_CHANNEL' "$body"
skill_assert_fixed '`--runner "<argv>"`' "$body"
skill_assert_fixed '`--channel beta|dev|canary`' "$body"
skill_assert_fixed '`-Agent`, `-Runner`, `-Channel`, and `-NoRedact`' "$body"
skill_assert_fixed 'do not pass `--channel chromium` or `-Channel chromium`' "$body"
setup_contract=$(sed -n '/^The POSIX setup CLI accepts/,/^$/p' "$skill" | tr '\n' ' ')
skill_assert_fixed 'Exit 3 is a setup failure on either platform' "$setup_contract"
skill_assert_fixed 'Invalid JSON during a Node merge and Codex' "$body"
skill_assert_fixed 'invalid existing JSON and Codex registration failures can also exit 3' "$body"
skill_assert_fixed 'does not use the sh manual-merge branch' "$body"

test_case "docs: documents the cwd contract, output directory, and auto scope"
skill=$(cat "$REPO_ROOT/src/SKILL.md")
readme=$(cat "$REPO_ROOT/README.md")
cwd_sentence="Both setup scripts resolve paths relative to the current working directory, so run them from the project root; the skill's own directory is never the right place."
auto_sentence='`auto` configures project-scoped agents only (Claude Code and OpenCode); Codex requires an explicit `--agent codex` and writes the user'\''s global `~/.codex/config.toml`.'
skill_assert_fixed "$cwd_sentence" "$skill"
skill_assert_fixed 'Invoke the scripts by their absolute path from the project-root shell.' "$skill"
skill_assert_fixed 'use `--out-dir <dir>` (or `-OutDir <dir>`) as the explicit output override' "$skill"
skill_assert_fixed "$auto_sentence" "$skill"
skill_assert_fixed 'A successful setup prints the absolute path it wrote; check that path against the project root.' "$skill"
skill_assert_fixed 'usage: setup-mcp.sh --agent auto|claude|codex|opencode [--runner "<argv>"] [--channel beta|dev|canary] [--out-dir <dir>] [--no-redact]' "$skill"
skill_assert_fixed 'usage: setup-mcp.ps1 -Agent auto|claude|codex|opencode [-Runner "<argv>"] [-Channel beta|dev|canary] [-OutDir <dir>] [-NoRedact]' "$skill"
skill_assert_fixed "$cwd_sentence" "$readme"
skill_assert_fixed 'Invoke the scripts by their absolute path from the project-root shell.' "$readme"
skill_assert_fixed 'Flags: `--runner "<argv>"`, `--channel beta|dev|canary`, `--out-dir "<dir>"`, `--no-redact`' "$readme"
skill_assert_fixed 'PowerShell: `-Runner "<argv>"`, `-Channel beta|dev|canary`, `-OutDir "<dir>"`, and `-NoRedact`' "$readme"
skill_assert_fixed "$auto_sentence" "$readme"
skill_assert_fixed 'usage: setup-mcp.sh --agent auto|claude|codex|opencode [--runner "<argv>"] [--channel beta|dev|canary] [--out-dir <dir>] [--no-redact]' "$readme"
skill_assert_fixed 'usage: setup-mcp.ps1 -Agent auto|claude|codex|opencode [-Runner "<argv>"] [-Channel beta|dev|canary] [-OutDir <dir>] [-NoRedact]' "$readme"
skill_assert_fixed 'setup-mcp: codex detected but not configured; run --agent codex to update your global Codex config.' "$skill"
skill_assert_fixed 'setup-mcp: codex detected but not configured; run -Agent codex to update your global Codex config.' "$skill"
skill_assert_fixed 'setup-mcp: codex detected but not configured; run --agent codex to update your global Codex config.' "$readme"
skill_assert_fixed 'setup-mcp: codex detected but not configured; run -Agent codex to update your global Codex config.' "$readme"

test_case "SKILL.md: setup picks the target for the host it is running in"
skill=$(cat "$REPO_ROOT/src/SKILL.md")
table=$(sed -n '/^| STATUS | Do this |$/,/^$/p' "$REPO_ROOT/src/SKILL.md")
not_configured_row=$(printf '%s\n' "$table" | grep '^| `NOT_CONFIGURED` |')
skill_assert_fixed 'Pick the setup target for the host you are actually running in' "$not_configured_row"
skill_assert_fixed '--agent codex' "$not_configured_row"
skill_assert_fixed 'writes the user'\''s global' "$not_configured_row"
skill_assert_fixed 'config was just written' "$not_configured_row"
skill_assert_fixed 'reload/restart the MCP connection' "$not_configured_row"
skill_assert_fixed 'Codex configuration is global: it applies to every project on the machine, so say that you are writing it before you do.' "$skill"
skill_assert_fixed 'Setup merges into an existing config rather than replacing it.' "$skill"

test_case "SKILL.md: the host-aware target reaches the channel, path-check, and PowerShell lines"
skill=$(cat "$REPO_ROOT/src/SKILL.md")
skill_assert_fixed 'For Claude Code or OpenCode, on POSIX use' "$skill"
skill_assert_fixed '--agent codex --channel "$CHROME_CHANNEL"' "$skill"
skill_assert_fixed '-Agent codex -Channel $CHROME_CHANNEL' "$skill"
skill_assert_fixed '-Agent <target>` for the host-aware setup branch above' "$skill"
skill_assert_fixed 'For Codex there is no printed path to check: success is the line `setup-mcp: registered chrome-devtools with the Codex CLI` and exit 0' "$skill"

test_case "docs: troubleshooting covers a wrong-directory setup"
body=$(cat "$REPO_ROOT/src/references/troubleshooting.md")
skill_assert_fixed '## Config was written to the wrong directory' "$body"

test_case "SKILL.md: names both script flavours and the confirm-first policy"
skill="$REPO_ROOT/src/SKILL.md"
body=$(cat "$skill")
action=$(sed -n '/^## 6\. Action policy/,/^## 7\. Sensitive data/p' "$skill")
assert_contains 'preflight.sh' "$body"
assert_contains 'preflight.ps1' "$body"
assert_contains 'chrome://inspect/#remote-debugging' "$body"
assert_contains 'redactNetworkHeaders' "$body"
assert_contains 'Confirm first' "$action"
assert_contains 'deleting or destroying' "$action"
assert_contains 'irreversible or outward-facing' "$action"
assert_contains 'invalidates the session' "$action"
assert_contains 'closing a tab the user already had open' "$action"
assert_contains 'bulk actions repeated across many items' "$action"

test_case "docs: README states the supported agents and requirements"
body=$(cat "$REPO_ROOT/README.md")
for expected in \
  '| Claude Code | `./.mcp.json` | project |' \
  '| OpenCode | `./opencode.json` (`mcp` key, `type: "local"`) | project |' \
  '| Codex | `codex mcp add …` → `~/.codex/config.toml` | **global**, since Codex has no project scope |' \
  '| Cursor | `./.cursor/mcp.json`, same shape as `.mcp.json`; write it yourself or copy the snippet | project |' \
  '| VS Code | `./.vscode/mcp.json`, top-level `servers` shape; write it yourself or copy the VS Code snippet | project |' \
  '- **Node.js LTS** with `npx`' \
  '- **Google Chrome 144 or newer.**' \
  '- A **one-time opt-in inside Chrome**: open `chrome://inspect/#remote-debugging` and click Allow.' \
  '- Native Windows setup uses PowerShell 6+ (`pwsh`).'; do
  skill_assert_fixed "$expected" "$body"
done

test_case "docs: troubleshooting names every verdict and gives the READY tools fix"
body=$(cat "$REPO_ROOT/src/references/troubleshooting.md")
for expected in \
  '## `READY` but the MCP tools are absent from the session' \
  '## `NOT_CONFIGURED`' \
  '## `NEEDS_OPT_IN`' \
  '## `CHROME_NOT_RUNNING`' \
  '## `CHROME_TOO_OLD`' \
  '## `CHROME_MISSING`' \
  '## `NODE_MISSING`' \
  '**Symptom:** Preflight reports `STATUS=READY`, but this agent session has no `chrome-devtools` tools.' \
  '**Cause:** `READY` validates local conditions only: runner, Chrome, config, and browser/debug state.' \
  '**Fix:** Reload or restart the MCP connection, wait for the tools to appear, then continue.'; do
  skill_assert_fixed "$expected" "$body"
done

test_case "docs: SKILL.md's reference link resolves"
if [ -f "$REPO_ROOT/src/references/troubleshooting.md" ]; then _ok "troubleshooting.md exists"; else _fail "dangling reference"; fi

test_case "docs: README mirrors shipped agent config targets and platform flags"
body=$(cat "$REPO_ROOT/README.md")
for expected in \
  '| Claude Code | `./.mcp.json` | project |' \
  '| OpenCode | `./opencode.json` (`mcp` key, `type: "local"`) | project |' \
  '| Codex | `codex mcp add …` → `~/.codex/config.toml` | **global**, since Codex has no project scope |' \
  '| Cursor | `./.cursor/mcp.json`, same shape as `.mcp.json`; write it yourself or copy the snippet | project |' \
  '| VS Code | `./.vscode/mcp.json`, top-level `servers` shape; write it yourself or copy the VS Code snippet | project |' \
  '### Claude Code / Cursor config (`.mcp.json` / `.cursor/mcp.json`)' \
  '"mcpServers": {' \
  '### OpenCode config (`opencode.json`)' \
  '"$schema": "https://opencode.ai/config.json"' \
  '"mcp": {' \
  '"type": "local",' \
  '"enabled": true,' \
  '"command": ["npx", "-y", "chrome-devtools-mcp@latest", "--autoConnect", "--redactNetworkHeaders"]' \
  '### Codex config (`~/.codex/config.toml`)' \
  'codex mcp add chrome-devtools -- npx -y chrome-devtools-mcp@latest --autoConnect --redactNetworkHeaders' \
  '[mcp_servers.chrome-devtools]' \
  '### VS Code config (`.vscode/mcp.json`)' \
  'VS Code uses a top-level `servers` object, not `mcpServers`.' \
  '"servers": {' \
  '`type: "stdio"` is optional because' \
  '"args": ["-y", "chrome-devtools-mcp@latest", "--autoConnect", "--redactNetworkHeaders"]' \
  'sh /path/to/chromeagent-skill/scripts/setup-mcp.sh --agent auto' \
  'pwsh -File /path/to/chromeagent-skill/scripts/setup-mcp.ps1 -Agent auto' \
  'Flags: `--runner "<argv>"`' \
  '`--channel beta|dev|canary`' \
  '`--no-redact`' \
  '`STATUS=READY` validates local conditions only' \
  'It does not test whether this agent session has' \
  'restart the MCP connection, wait for the tools to appear, then continue.' \
  'typically because setup just wrote the config'; do
  skill_assert_fixed "$expected" "$body"
done

test_case "docs: troubleshooting covers shipped failure causes and fixes"
body=$(cat "$REPO_ROOT/src/references/troubleshooting.md")
for expected in \
  '## `NODE_MISSING`' \
  '## `CHROME_MISSING`' \
  '## `CHROME_TOO_OLD`' \
  '## `NOT_CONFIGURED`' \
  '## `CHROME_NOT_RUNNING`' \
  '## `NEEDS_OPT_IN`' \
  '## `READY` but the MCP tools are absent from the session' \
  '## Existing config could not be merged' \
  'No `npx`, `bunx`, `pnpm`, or global `chrome-devtools-mcp`.' \
  '`--autoConnect` needs Chrome 144+.' \
  'No `chrome-devtools` entry with `--autoConnect` in any scanned config.' \
  'Open Chrome normally (no special flags) and re-run preflight.' \
  'Chrome is running but is not exposing a debugging endpoint.' \
  '**Symptom:** Preflight reports `STATUS=READY`, but this agent session has no `chrome-devtools` tools.' \
  '**Cause:** `READY` validates local conditions only: runner, Chrome, config, and browser/debug state.' \
  '**Fix:** Reload or restart the MCP connection, wait for the tools to appear, then continue.' \
  'server loads at agent startup.' \
  'already exists and Node is unavailable, so it was left untouched' \
  '`setup-mcp.ps1` always merges an existing config natively' \
  'the `sh` manual-merge branch is unreachable on Windows' \
  'Exit 3 is a setup failure on either platform; it is not only the manual-merge case.' \
  'If `CHROME_CHANNEL=chromium`, do not pass `--channel chromium`'; do
  skill_assert_fixed "$expected" "$body"
done

test_case "docs: every script invocation resolves from the project root"
skill=$(cat "$REPO_ROOT/src/SKILL.md")
readme=$(cat "$REPO_ROOT/README.md")
# A bare relative path fails from the project root, because scripts/ lives under
# the installed skill directory and preflight must run in the project.
for bare in \
  'sh scripts/setup-mcp.sh' \
  'pwsh -File scripts/setup-mcp.ps1' \
  'sh scripts/preflight.sh' \
  'pwsh -File scripts/preflight.ps1'; do
  if printf '%s\n' "$skill" | grep -F -q -- "$bare"; then
    _fail "SKILL.md has a bare relative invocation: $bare"
  else
    _ok "SKILL.md has no bare '$bare'"
  fi
  if printf '%s\n' "$readme" | grep -F -q -- "$bare"; then
    _fail "README.md has a bare relative invocation: $bare"
  else
    _ok "README.md has no bare '$bare'"
  fi
done
skill_assert_fixed 'sh /path/to/chromeagent-skill/scripts/setup-mcp.sh --agent auto' "$skill"
skill_assert_fixed 'pwsh -File /path/to/chromeagent-skill/scripts/setup-mcp.ps1 -Agent auto' "$skill"

test_case "docs: the NODE_MISSING row warns that a pre-install shell has a stale PATH"
skill="$REPO_ROOT/src/SKILL.md"
table=$(sed -n '/^| STATUS | Do this |$/,/^$/p' "$skill")
node_row=$(printf '%s\n' "$table" | grep '^| `NODE_MISSING` |')
skill_assert_fixed 'open a **new** terminal (or refresh `PATH`) before re-probing' "$node_row"
skill_assert_fixed 'still has the pre-install `PATH`' "$node_row"

test_case "SKILL.md: one consistent rule for pre-existing tabs"
skill=$(cat "$REPO_ROOT/src/SKILL.md")
skill_assert_fixed 'Close only tabs you opened.' "$skill"
skill_assert_fixed 'A tab the user already had open is theirs: close it only when the user asks for that tab, and confirm the specific tab first.' "$skill"
skill_assert_fixed 'closing a tab the user already had open' "$skill"
if grep -qF 'Never close a tab the user already had open' "$REPO_ROOT/src/SKILL.md"; then
  _fail "the absolute prohibition still contradicts the confirm-first entry"
else
  _ok "no absolute tab prohibition remains"
fi
