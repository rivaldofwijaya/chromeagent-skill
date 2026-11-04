# shellcheck shell=sh
# Documentation tests. They guard what the docs promise, not how a sentence
# reads: the decision table covers every verdict, the documented contract
# matches what the scripts actually print and write, and every command an agent
# is told to run resolves. Wording is free to change.

skill_assert_fixed() {
  if printf '%s\n' "$2" | grep -F -q -- "$1"; then _ok "contains '$1'"
  else _fail "missing '$1' in output"; fi
}

SKILL_FILE="$REPO_ROOT/skills/chromeagent/SKILL.md"
SETUP_FILE="$REPO_ROOT/skills/chromeagent/references/setup.md"
TROUBLE_FILE="$REPO_ROOT/skills/chromeagent/references/troubleshooting.md"
README_FILE="$REPO_ROOT/README.md"

# table_row VERDICT — the SKILL.md decision-table row for VERDICT.
table_row() {
  sed -n '/^| STATUS | Do this |$/,/^$/p' "$SKILL_FILE" | grep "^| \`$1\` |"
}

test_case "SKILL.md: has frontmatter with name and description"
head=$(head -5 "$SKILL_FILE")
assert_contains 'name: chromeagent' "$head"
assert_contains 'description:' "$head"
if [ "$(sed -n '1p' "$SKILL_FILE")" = '---' ]; then _ok "frontmatter opens on line 1"
else _fail "frontmatter does not open on line 1"; fi
closing=$(sed -n '2,20p' "$SKILL_FILE" | grep -n '^---$' | head -1)
if [ -n "$closing" ]; then _ok "frontmatter has a closing delimiter"; else _fail "missing closing frontmatter delimiter"; fi

test_case "SKILL.md: documents every verdict as exactly one decision-table branch"
for v in READY NOT_CONFIGURED NEEDS_OPT_IN CHROME_NOT_RUNNING CHROME_TOO_OLD CHROME_MISSING NODE_MISSING; do
  rows=$(sed -n '/^| STATUS | Do this |$/,/^$/p' "$SKILL_FILE" | grep -c "^| \`$v\` |")
  if [ "$rows" -eq 1 ]; then _ok "decision table branches $v"; else _fail "decision table has $rows branches for $v"; fi
done

test_case "SKILL.md: the decision table routes each verdict to its remedy"
skill_assert_fixed 'reload' "$(table_row READY)"
skill_assert_fixed '--agent auto' "$(table_row NOT_CONFIGURED)"
skill_assert_fixed '--agent codex' "$(table_row NOT_CONFIGURED)"
skill_assert_fixed 'references/setup.md' "$(table_row NOT_CONFIGURED)"
skill_assert_fixed 'reload' "$(table_row NOT_CONFIGURED)"
skill_assert_fixed 'chrome://inspect/#remote-debugging' "$(table_row NEEDS_OPT_IN)"
skill_assert_fixed 'CHROME_VERSION' "$(table_row CHROME_TOO_OLD)"
skill_assert_fixed 'PATH' "$(table_row NODE_MISSING)"

test_case "SKILL.md: the fast path comes before preflight"
fast_heading=$(grep -n '^## 1\. Fast path' "$SKILL_FILE" | head -1 | cut -d: -f1)
pre_heading=$(grep -n '^## 2\. Preflight$' "$SKILL_FILE" | head -1 | cut -d: -f1)
if [ -n "$fast_heading" ] && [ -n "$pre_heading" ] && [ "$fast_heading" -lt "$pre_heading" ]; then
  _ok "fast path section precedes preflight"
  skill_assert_fixed 'list_pages' "$(sed -n "${fast_heading},$((pre_heading - 1))p" "$SKILL_FILE")"
else
  _fail "fast path section is not before preflight"
fi

test_case "SKILL.md: the documented preflight contract matches what preflight prints"
stub_cmd npx 'exit 0'
actual_keys=$(run_preflight | sed 's/=.*//' | sed 's/.*/`&`/' | tr '\n' ',' | sed 's/,$/./; s/,/, /g')
documented_keys=$(grep '^`PLATFORM`' "$SKILL_FILE" | head -1)
if [ "$documented_keys" = "$actual_keys" ]; then _ok "documented keys match preflight's output order"
else _fail "documented '$documented_keys' but preflight prints '$actual_keys'"; fi
precedence=$(sed -n '/^Read the `STATUS` and branch/,/^$/p' "$SKILL_FILE" | tr '\n' ' ')
skill_assert_fixed '`NODE_MISSING` > `CHROME_MISSING` > `CHROME_TOO_OLD` > `NOT_CONFIGURED` > `CHROME_NOT_RUNNING` > `NEEDS_OPT_IN` > `READY`.' "$precedence"
skill_assert_fixed 'always exits 0' "$(cat "$SKILL_FILE")"

test_case "SKILL.md: the confirm-first list covers every class of risky effect"
action=$(sed -n '/^## 6\. Action policy/,/^## 7\. Sensitive data/p' "$SKILL_FILE")
for expected in 'Confirm first' 'deleting or destroying' 'irreversible or outward-facing' \
  'invalidates the session' 'closing a tab the user already had open' 'bulk actions repeated across many items'; do
  skill_assert_fixed "$expected" "$action"
done
if grep -qF 'Never close a tab the user already had open' "$SKILL_FILE"; then
  _fail "an absolute tab prohibition contradicts the confirm-first entry"
else
  _ok "no absolute tab prohibition"
fi

test_case "SKILL.md: setup detail lives in references/setup.md"
for moved in 'The POSIX setup CLI accepts' 'usage: setup-mcp.sh' 'manual-merge snippet is printed'; do
  if grep -qF -- "$moved" "$SKILL_FILE"; then _fail "SKILL.md still carries setup detail: $moved"
  else _ok "SKILL.md leaves '$moved' to setup.md"; fi
done

test_case "docs: every default server flag is documented where it applies"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
run_setup --agent claude >/dev/null
flags=$(sed -n 's/^ *"args": //p' "$SANDBOX/project/.mcp.json" | tr -d '[]",' | tr ' ' '\n' | grep '^--')
[ -n "$flags" ] || _fail "setup wrote no flags"
for flag in $flags; do
  skill_assert_fixed "\`$flag\`" "$(cat "$SKILL_FILE")"
  skill_assert_fixed "\`$flag\`" "$(cat "$SETUP_FILE")"
  skill_assert_fixed "\`$flag\`" "$(cat "$README_FILE")"
done
for heading in '## Network headers look redacted' '## Performance traces show no field data' '## A `file:` URL is rejected'; do
  skill_assert_fixed "$heading" "$(cat "$TROUBLE_FILE")"
done

test_case "docs: README's config examples are what setup writes"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
run_setup --agent claude >/dev/null
run_setup --agent opencode >/dev/null
readme=$(cat "$README_FILE")
claude_args=$(sed -n 's/^ *"args": //p' "$SANDBOX/project/.mcp.json")
opencode_command=$(sed -n 's/^ *"command": //p' "$SANDBOX/project/opencode.json")
codex_line="codex mcp add chrome-devtools -- npx $(printf '%s' "$claude_args" | tr -d '[]",')"
skill_assert_fixed "\"args\": $claude_args" "$readme"
skill_assert_fixed "args = $claude_args" "$readme"
skill_assert_fixed "\"command\": $opencode_command" "$readme"
skill_assert_fixed "$codex_line" "$readme"
# Every config line, not just one copy: README repeats the args in several
# snippets, and a stale copy must not hide behind a correct one.
stale=$(printf '%s\n' "$readme" | sed 's/^ *//' | grep -E '^("args": |args = |"command": \[|codex mcp add )' |
  grep -v -x -F -e "\"args\": $claude_args" -e "args = $claude_args" \
    -e "\"command\": $opencode_command" -e "$codex_line")
if [ -n "$stale" ]; then _fail "README has a config line setup does not write: $stale"
else _ok "every README config line matches setup's output"; fi

test_case "docs: the documented usage lines are the scripts' own"
sh_usage=$(sh "$REPO_ROOT/skills/chromeagent/scripts/setup-mcp.sh" --help)
ps_usage=$(sed -n "s/^  Write-Info '\\(usage: setup-mcp.ps1 .*\\)'\$/\\1/p" "$REPO_ROOT/skills/chromeagent/scripts/setup-mcp.ps1")
[ -n "$ps_usage" ] || _fail "could not read setup-mcp.ps1's usage line"
for doc in "$SETUP_FILE" "$README_FILE"; do
  skill_assert_fixed "$sh_usage" "$(cat "$doc")"
  skill_assert_fixed "$ps_usage" "$(cat "$doc")"
done

test_case "docs: README lists every supported agent and the requirements"
readme=$(cat "$README_FILE")
for expected in '| Claude Code |' '| OpenCode |' '| Codex |' '| Cursor |' '| VS Code |' \
  'Chrome 144' 'chrome://inspect/#remote-debugging' 'Node 20.19+'; do
  skill_assert_fixed "$expected" "$readme"
done

test_case "docs: troubleshooting has a section for every verdict"
body=$(cat "$TROUBLE_FILE")
for v in NODE_MISSING CHROME_MISSING CHROME_TOO_OLD NOT_CONFIGURED CHROME_NOT_RUNNING NEEDS_OPT_IN; do
  skill_assert_fixed "## \`$v\`" "$body"
done
skill_assert_fixed '## `READY` but the MCP tools are absent from the session' "$body"
skill_assert_fixed '## Config was written to the wrong directory' "$body"
skill_assert_fixed '## Existing config could not be merged' "$body"
skill_assert_fixed 'Node 20.19+, 22.12+, or 23+' "$body"
skill_assert_fixed '`startup_timeout_sec = 20`' "$body"

test_case "docs: no remediation hands a Codex user an unconditional auto"
# Every line that prescribes an `auto` invocation must name the codex
# alternative on the same line; `auto` never configures Codex.
# setup.md is exempt: it lists the auto and codex commands on separate lines
# under their host names.
unconditional=$(grep -F -e 'setup-mcp.sh --agent auto' -e 'setup-mcp.ps1 -Agent auto' "$TROUBLE_FILE" | grep -F -v -- 'codex')
if [ -n "$unconditional" ]; then _fail "troubleshooting.md prescribes an unconditional target: $unconditional"
else _ok "every troubleshooting.md auto invocation names the codex alternative"; fi

test_case "docs: reference links resolve"
for ref in $(grep -o 'references/[a-z-]*\.md' "$SKILL_FILE" "$TROUBLE_FILE" | sed 's/^[^:]*://' | sort -u); do
  if [ -f "$REPO_ROOT/skills/chromeagent/$ref" ]; then _ok "$ref exists"; else _fail "dangling reference $ref"; fi
done

test_case "docs: every script invocation resolves from the project root"
# A bare relative path fails from the project root, because scripts/ lives under
# the installed skill directory and preflight must run in the project.
for doc in "$SKILL_FILE" "$README_FILE" "$TROUBLE_FILE" "$SETUP_FILE"; do
  bare=$(grep -E -e '(sh|pwsh -File) scripts/(setup-mcp|preflight)\.(sh|ps1)' "$doc")
  if [ -n "$bare" ]; then _fail "$(basename "$doc") has a bare relative invocation: $bare"
  else _ok "$(basename "$doc") has no bare relative invocation"; fi
done
for doc in "$SKILL_FILE" "$SETUP_FILE"; do
  skill_assert_fixed 'sh /path/to/chromeagent-skill/scripts/setup-mcp.sh --agent' "$(cat "$doc")"
  skill_assert_fixed 'pwsh -File /path/to/chromeagent-skill/scripts/setup-mcp.ps1 -Agent' "$(cat "$doc")"
done
skill_assert_fixed 'sh /path/to/chromeagent-skill/scripts/preflight.sh' "$(cat "$SKILL_FILE")"
skill_assert_fixed 'pwsh -File /path/to/chromeagent-skill/scripts/preflight.ps1' "$(cat "$SKILL_FILE")"
