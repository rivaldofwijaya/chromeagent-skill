if ! host_tool_path pwsh >/dev/null 2>&1; then
  printf 'skip test_ps1_contract.sh — pwsh not installed\n'
else

run_ps1() {
  (cd "$SANDBOX/project" && HOME="$HOME" pwsh -NoProfile -File "$REPO_ROOT/scripts/preflight.ps1" 2>/dev/null)
}

test_case "ps1: emits the same key set in the same order as the sh probe"
link_host_tool pwsh
out=$(run_ps1)
keys=$(printf '%s\n' "$out" | sed -n 's/^\([A-Z_]*\)=.*/\1/p' | tr '\n' ' ')
expected="PLATFORM RUNNER RUNNER_CMD CHROME_PATH CHROME_CHANNEL CHROME_VERSION CHROME_MAJOR CHROME_OK USER_DATA_DIR CHROME_RUNNING DEBUG_PORT DEBUG_REACHABLE MCP_CONFIG_FILE MCP_CONFIGURED STATUS "
if [ "$keys" = "$expected" ]; then _ok "key order matches"; else _fail "key order was: $keys"; fi

test_case "ps1: stable wins across roots over beta in a preferred root"
link_host_tool pwsh
stub_cmd npx 'exit 0'
export ProgramFiles=pf
export LOCALAPPDATA=lad
mkdir -p "$CHROMEAGENT_ROOT/pf/Google/Chrome Beta/Application" \
  "$CHROMEAGENT_ROOT/lad/Google/Chrome/Application"
printf '%s\n' beta > "$CHROMEAGENT_ROOT/pf/Google/Chrome Beta/Application/chrome.exe"
printf '%s\n' stable > "$CHROMEAGENT_ROOT/lad/Google/Chrome/Application/chrome.exe"
out=$(run_ps1)
unset ProgramFiles LOCALAPPDATA
assert_kv CHROME_CHANNEL stable "$out"

test_case "ps1: no runner keeps Chrome fields at sh defaults"
link_host_tool pwsh
export CHROMEAGENT_FAKE_CHROME="stable|C:/fake/chrome.exe|145.0.7300.20|C:/fake/UserData"
out=$(run_ps1)
unset CHROMEAGENT_FAKE_CHROME
assert_kv RUNNER none "$out"
assert_kv CHROME_PATH none "$out"
assert_kv CHROME_CHANNEL none "$out"
assert_kv CHROME_VERSION unknown "$out"
assert_kv CHROME_MAJOR 0 "$out"
assert_kv CHROME_OK no "$out"
assert_kv USER_DATA_DIR "" "$out"
assert_kv DEBUG_PORT 9222 "$out"
assert_status NODE_MISSING "$out"

test_case "ps1: a fake chrome 143 yields CHROME_TOO_OLD"
link_host_tool pwsh
stub_cmd npx 'exit 0'
export CHROMEAGENT_FAKE_CHROME="stable|C:/fake/chrome.exe|143.0.7000.1|C:/fake/UserData"
out=$(run_ps1)
unset CHROMEAGENT_FAKE_CHROME
assert_kv CHROME_MAJOR 143 "$out"
assert_status CHROME_TOO_OLD "$out"

test_case "ps1: a fake chrome 145 with no config yields NOT_CONFIGURED"
link_host_tool pwsh
stub_cmd npx 'exit 0'
export CHROMEAGENT_FAKE_CHROME="stable|C:/fake/chrome.exe|145.0.7300.20|C:/fake/UserData"
out=$(run_ps1)
unset CHROMEAGENT_FAKE_CHROME
assert_kv CHROME_OK yes "$out"
assert_status NOT_CONFIGURED "$out"

test_case "ps1: wrongly-cased autoConnect is not detected"
link_host_tool pwsh
stub_cmd npx 'exit 0'
export CHROMEAGENT_FAKE_CHROME="stable|C:/fake/chrome.exe|145.0.7300.20|C:/fake/UserData"
printf '%s\n' '{"mcpServers":{"chrome-devtools":{"command":"npx","args":["--autoconnect"]}}}' > "$SANDBOX/project/.mcp.json"
out=$(run_ps1)
unset CHROMEAGENT_FAKE_CHROME
assert_kv MCP_CONFIGURED no "$out"
assert_status NOT_CONFIGURED "$out"

run_setup_ps1() {
  (cd "$SANDBOX/project" && HOME="$HOME" pwsh -NoProfile -File "$REPO_ROOT/scripts/setup-mcp.ps1" "$@" 2>&1)
}

run_setup_ps1_timeout() {
  # run_setup_ps1_timeout SECONDS ARGS... -> prints command output and
  # "rc=<code>" or "rc=TIMEOUT". The output file keeps the bounded command
  # single-shot, so a failed timeout assertion cannot be followed by a hang.
  secs="$1"; shift
  timeout_output="$SANDBOX/ps1-timeout.out"
  ( cd "$SANDBOX/project" && HOME="$HOME" pwsh -NoProfile -File "$REPO_ROOT/scripts/setup-mcp.ps1" "$@" >"$timeout_output" 2>&1 ) &
  rp=$!
  ( sleep "$secs"; kill -9 "$rp" 2>/dev/null ) &
  wp=$!
  wait "$rp" 2>/dev/null; rc=$?
  kill "$wp" 2>/dev/null
  if [ "$rc" -eq 137 ]; then printf 'rc=TIMEOUT\n'; else printf 'rc=%s\n' "$rc"; fi
  cat "$timeout_output"
  rm -f "$timeout_output"
}

run_setup_ps1_with_move_failure() {
  agent="$1"
  (cd "$SANDBOX/project" && HOME="$HOME" SETUP_AGENT="$agent" SETUP_PS1_PATH="$REPO_ROOT/scripts/setup-mcp.ps1" pwsh -NoProfile -Command '
    function Move-Item {
      param([string]$LiteralPath, [string]$Destination, [switch]$Force)
      throw "injected move failure"
    }
    & $env:SETUP_PS1_PATH -Agent $env:SETUP_AGENT
    exit $LASTEXITCODE
  ' 2>&1)
}

test_case "ps1 setup: writes .mcp.json for claude"
link_host_tool pwsh
stub_cmd npx 'exit 0'
out=$(run_setup_ps1 -Agent claude)
rc=$?
if [ "$rc" -eq 0 ]; then _ok "exit 0"; else _fail "expected exit 0, got $rc"; fi
body=$(cat "$SANDBOX/project/.mcp.json" 2>/dev/null || true)
assert_contains 'chrome-devtools' "$body"
assert_contains 'autoConnect' "$body"
assert_contains 'redactNetworkHeaders' "$body"

test_case "ps1 setup: -NoRedact omits the redaction flag"
link_host_tool pwsh
stub_cmd npx 'exit 0'
run_setup_ps1 -Agent claude -NoRedact >/dev/null
body=$(cat "$SANDBOX/project/.mcp.json" 2>/dev/null || true)
assert_not_contains 'redactNetworkHeaders' "$body"

test_case "ps1 setup: merges into an existing .mcp.json"
link_host_tool pwsh
stub_cmd npx 'exit 0'
printf '%s\n' '{"mcpServers":{"other-server":{"command":"other","args":["original",{"nested":[1,null,false]},null]}},"unrelated":{"keep":true,"nested":[null,{"value":"nested-value"},7],"primitive":"keep-me","number":42},"topNull":null,"topPrimitive":"plain"}' > "$SANDBOX/project/.mcp.json"
run_setup_ps1 -Agent claude >/dev/null
body=$(cat "$SANDBOX/project/.mcp.json" 2>/dev/null || true)
assert_contains 'other-server' "$body"
assert_contains 'chrome-devtools' "$body"
assert_contains 'unrelated' "$body"
assert_contains 'nested-value' "$body"
assert_contains '"topNull": null' "$body"
assert_contains '"topPrimitive": "plain"' "$body"
assert_contains '"number": 42' "$body"

test_case "ps1 setup: writes opencode.json with a command array"
link_host_tool pwsh
stub_cmd npx 'exit 0'
run_setup_ps1 -Agent opencode >/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then _ok "exit 0"; else _fail "expected exit 0, got $rc"; fi
body=$(cat "$SANDBOX/project/opencode.json" 2>/dev/null || true)
assert_contains '"local"' "$body"
assert_contains '"command": \[' "$body"
assert_contains '"npx"' "$body"
assert_contains 'autoConnect' "$body"

test_case "ps1 setup: -Channel follows the default flags in order"
link_host_tool pwsh
stub_cmd npx 'exit 0'
run_setup_ps1 -Agent claude -Channel beta >/dev/null
body=$(cat "$SANDBOX/project/.mcp.json" 2>/dev/null || true)
assert_contains 'autoConnect' "$body"
assert_contains 'redactNetworkHeaders' "$body"
assert_contains 'beta' "$body"
auto_line=$(printf '%s\n' "$body" | grep -n -- '"--autoConnect"' | sed -n '1p' | sed 's/:.*//')
redact_line=$(printf '%s\n' "$body" | grep -n -- '"--redactNetworkHeaders"' | sed -n '1p' | sed 's/:.*//')
channel_line=$(printf '%s\n' "$body" | grep -n -- '"--channel"' | sed -n '1p' | sed 's/:.*//')
if [ -n "$auto_line" ] && [ -n "$redact_line" ] && [ -n "$channel_line" ] && [ "$auto_line" -lt "$redact_line" ] && [ "$redact_line" -lt "$channel_line" ]; then
  _ok "default flags precede channel"
else
  _fail "default flag order was auto=$auto_line redact=$redact_line channel=$channel_line"
fi

test_case "ps1 setup: a bad -Agent value exits 2"
link_host_tool pwsh
out=$(run_setup_ps1 -Agent nope)
rc=$?
if [ "$rc" -eq 2 ]; then _ok "exit 2"; else _fail "expected exit 2, got $rc"; fi
assert_contains 'unknown agent' "$out"

test_case "ps1 setup: a bad -Channel value exits 2"
link_host_tool pwsh
out=$(run_setup_ps1 -Agent claude -Channel nightly)
rc=$?
if [ "$rc" -eq 2 ]; then _ok "exit 2"; else _fail "expected exit 2, got $rc"; fi
assert_contains 'invalid channel' "$out"

test_case "ps1 setup: a trailing -Agent is a usage error, not an infinite loop"
link_host_tool pwsh
out=$(run_setup_ps1_timeout 5 -Agent)
assert_contains 'rc=2' "$out"
assert_contains 'setup-mcp: -Agent requires a value' "$out"

test_case "ps1 setup: a trailing -Runner is a usage error, not an infinite loop"
link_host_tool pwsh
out=$(run_setup_ps1_timeout 5 -Runner)
assert_contains 'rc=2' "$out"
assert_contains 'setup-mcp: -Runner requires a value' "$out"

test_case "ps1 setup: a trailing -Channel is a usage error, not an infinite loop"
link_host_tool pwsh
out=$(run_setup_ps1_timeout 5 -Channel)
assert_contains 'rc=2' "$out"
assert_contains 'setup-mcp: -Channel requires a value' "$out"

test_case "ps1 setup: an unknown option exits 2"
link_host_tool pwsh
out=$(run_setup_ps1 -Bogus)
rc=$?
if [ "$rc" -eq 2 ]; then _ok "exit 2"; else _fail "expected exit 2, got $rc"; fi
assert_contains 'setup-mcp: unknown option -Bogus' "$out"

test_case "ps1 setup: a repeated option exits 2"
link_host_tool pwsh
out=$(run_setup_ps1 -Agent claude -Agent codex)
rc=$?
if [ "$rc" -eq 2 ]; then _ok "exit 2"; else _fail "expected exit 2, got $rc"; fi
assert_contains 'setup-mcp: repeated option -Agent' "$out"

test_case "ps1 setup: every repeated option exits 2 and terminates"
link_host_tool pwsh
out=$(run_setup_ps1_timeout 5 -Runner bunx -Runner pnpm)
assert_contains 'rc=2' "$out"
out=$(run_setup_ps1_timeout 5 -Channel beta -Channel dev)
assert_contains 'rc=2' "$out"
out=$(run_setup_ps1_timeout 5 -NoRedact -NoRedact)
assert_contains 'rc=2' "$out"

test_case "ps1 setup: empty and option-looking values terminate"
link_host_tool pwsh
stub_cmd npx 'exit 0'
out=$(run_setup_ps1_timeout 5 -Runner "")
assert_contains 'rc=0' "$out"
out=$(run_setup_ps1_timeout 5 -Agent "")
assert_contains 'rc=2' "$out"
out=$(run_setup_ps1_timeout 5 -Channel "")
assert_contains 'rc=2' "$out"
out=$(run_setup_ps1_timeout 5 -Runner -Agent)
assert_contains 'rc=0' "$out"

test_case "ps1 setup: -- is an unknown option"
link_host_tool pwsh
out=$(run_setup_ps1 --)
rc=$?
if [ "$rc" -eq 2 ]; then _ok "exit 2"; else _fail "expected exit 2, got $rc"; fi
assert_contains 'setup-mcp: unknown option --' "$out"

test_case "ps1 setup: -h and --help print usage and exit 0"
link_host_tool pwsh
out=$(run_setup_ps1 -h)
rc=$?
if [ "$rc" -eq 0 ]; then _ok "-h exits 0"; else _fail "expected -h exit 0, got $rc"; fi
assert_contains 'usage: setup-mcp.ps1 -Agent' "$out"
assert_not_contains 'setup-mcp.sh' "$out"
out=$(run_setup_ps1 --help)
rc=$?
if [ "$rc" -eq 0 ]; then _ok "--help exits 0"; else _fail "expected --help exit 0, got $rc"; fi
assert_contains 'usage: setup-mcp.ps1 -Agent' "$out"
assert_not_contains 'setup-mcp.sh' "$out"

test_case "ps1 setup: invalid JSON is left untouched"
link_host_tool pwsh
stub_cmd npx 'exit 0'
printf '%s\n' '{not valid json' > "$SANDBOX/project/.mcp.json"
before=$(cat "$SANDBOX/project/.mcp.json")
out=$(run_setup_ps1 -Agent claude)
rc=$?
after=$(cat "$SANDBOX/project/.mcp.json")
if [ "$rc" -eq 3 ]; then _ok "exit 3"; else _fail "expected exit 3, got $rc"; fi
assert_contains 'not valid JSON' "$out"
if [ "$before" = "$after" ]; then _ok "invalid JSON survived"; else _fail "invalid JSON was modified"; fi

test_case "ps1 setup: a failed atomic rename leaves no temp or partial file"
link_host_tool pwsh
stub_cmd npx 'exit 0'
printf '%s\n' '{"mcpServers":{"other-server":{"command":"other"}}}' > "$SANDBOX/project/.mcp.json"
before=$(cat "$SANDBOX/project/.mcp.json")
out=$(run_setup_ps1_with_move_failure claude)
rc=$?
after=$(cat "$SANDBOX/project/.mcp.json")
if [ "$rc" -eq 3 ]; then _ok "rename failure exits 3"; else _fail "expected rename failure exit 3, got $rc"; fi
if [ "$before" = "$after" ]; then _ok "original file survived rename failure"; else _fail "original file was modified"; fi
temp_left=no
for temp in "$SANDBOX/project"/..mcp.json.tmp-*; do
  if [ -e "$temp" ]; then temp_left=yes; fi
done
if [ "$temp_left" = no ]; then _ok "temporary file was cleaned up"; else _fail "temporary file was left behind"; fi

test_case "ps1 setup: failed creates exit 3 for claude and opencode"
link_host_tool pwsh
stub_cmd npx 'exit 0'
out=$(run_setup_ps1_with_move_failure claude)
rc=$?
if [ "$rc" -eq 3 ]; then _ok "claude create failure exits 3"; else _fail "expected claude create failure exit 3, got $rc"; fi
if [ ! -e "$SANDBOX/project/.mcp.json" ]; then _ok "claude target was not created"; else _fail "claude target was created"; fi
out=$(run_setup_ps1_with_move_failure opencode)
rc=$?
if [ "$rc" -eq 3 ]; then _ok "opencode create failure exits 3"; else _fail "expected opencode create failure exit 3, got $rc"; fi
if [ ! -e "$SANDBOX/project/opencode.json" ]; then _ok "opencode target was not created"; else _fail "opencode target was created"; fi

test_case "ps1 setup: malformed JSON root shapes fail without clobbering"
link_host_tool pwsh
stub_cmd npx 'exit 0'
printf '%s\n' '[]' > "$SANDBOX/project/.mcp.json"
before=$(cat "$SANDBOX/project/.mcp.json")
out=$(run_setup_ps1 -Agent claude)
rc=$?
after=$(cat "$SANDBOX/project/.mcp.json")
if [ "$rc" -eq 3 ]; then _ok "array root exits 3"; else _fail "expected array root exit 3, got $rc"; fi
assert_contains 'not valid JSON' "$out"
if [ "$before" = "$after" ]; then _ok "array root survived"; else _fail "array root was modified"; fi

printf '%s\n' '42' > "$SANDBOX/project/.mcp.json"
before=$(cat "$SANDBOX/project/.mcp.json")
out=$(run_setup_ps1 -Agent claude)
rc=$?
after=$(cat "$SANDBOX/project/.mcp.json")
if [ "$rc" -eq 3 ]; then _ok "primitive root exits 3"; else _fail "expected primitive root exit 3, got $rc"; fi
assert_contains 'not valid JSON' "$out"
if [ "$before" = "$after" ]; then _ok "primitive root survived"; else _fail "primitive root was modified"; fi

test_case "ps1 setup: malformed mcpServers array is replaced"
link_host_tool pwsh
stub_cmd npx 'exit 0'
printf '%s\n' '{"mcpServers":[]}' > "$SANDBOX/project/.mcp.json"
run_setup_ps1 -Agent claude >/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then _ok "exit 0"; else _fail "expected exit 0, got $rc"; fi
assert_contains 'chrome-devtools' "$(cat "$SANDBOX/project/.mcp.json")"

test_case "ps1 setup: malformed mcp string is replaced"
link_host_tool pwsh
stub_cmd npx 'exit 0'
printf '%s\n' '{"mcp":"not-an-object"}' > "$SANDBOX/project/opencode.json"
run_setup_ps1 -Agent opencode >/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then _ok "exit 0"; else _fail "expected exit 0, got $rc"; fi
assert_contains 'chrome-devtools' "$(cat "$SANDBOX/project/opencode.json")"

test_case "ps1 setup: absent Codex CLI requires manual merge"
link_host_tool pwsh
stub_cmd npx 'exit 0'
out=$(run_setup_ps1 -Agent codex)
rc=$?
if [ "$rc" -eq 3 ]; then _ok "exit 3"; else _fail "expected exit 3, got $rc"; fi
assert_contains 'global' "$out"
assert_contains 'codex mcp add' "$out"

fi
