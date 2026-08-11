assert_setup_rc() {
  expected="$1"
  actual="$2"
  if [ "$actual" -eq "$expected" ]; then
    _ok "exit $expected"
  else
    _fail "expected exit $expected, got $actual"
  fi
}

test_case "setup claude: writes .mcp.json when absent"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
out=$(run_setup --agent claude)
rc=$?
assert_setup_rc 0 "$rc"
f="$SANDBOX/project/.mcp.json"
if [ -f "$f" ]; then _ok ".mcp.json created"; else _fail ".mcp.json not created"; fi
body=$(cat "$f")
assert_contains '"chrome-devtools"' "$body"
assert_contains 'chrome-devtools-mcp@latest' "$body"
assert_contains '\-\-autoConnect' "$body"
assert_contains '\-\-redactNetworkHeaders' "$body"
if printf '%s\n' "$body" | grep -q -- '"--autoConnect".*"--redactNetworkHeaders"'; then
  _ok "default flags are ordered"
else
  _fail "default flags are out of order"
fi

test_case "setup claude: --no-redact omits the redaction flag"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
run_setup --agent claude --no-redact >/dev/null
rc=$?
assert_setup_rc 0 "$rc"
body=$(cat "$SANDBOX/project/.mcp.json")
assert_contains '\-\-autoConnect' "$body"
assert_not_contains 'redactNetworkHeaders' "$body"

test_case "setup claude: --channel adds the channel flag"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
run_setup --agent claude --channel beta >/dev/null
rc=$?
assert_setup_rc 0 "$rc"
body=$(cat "$SANDBOX/project/.mcp.json")
assert_contains '\-\-channel' "$body"
assert_contains 'beta' "$body"

test_case "setup claude: --runner overrides the launch command"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
run_setup --agent claude --runner "bunx" >/dev/null
rc=$?
assert_setup_rc 0 "$rc"
body=$(cat "$SANDBOX/project/.mcp.json")
assert_contains '"command": "bunx"' "$body"

test_case "setup claude: --runner preserves space-separated argv"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
run_setup --agent claude --runner "bunx --scope project" >/dev/null
rc=$?
assert_setup_rc 0 "$rc"
body=$(cat "$SANDBOX/project/.mcp.json")
assert_contains '"command": "bunx"' "$body"
assert_contains '"--scope"' "$body"
assert_contains '"project"' "$body"

test_case "setup claude: --runner escapes a double quote"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
run_setup --agent claude --runner 'bun"x' >/dev/null
rc=$?
assert_setup_rc 0 "$rc"
body=$(cat "$SANDBOX/project/.mcp.json")
if printf '%s\n' "$body" | grep -Fq '"command": "bun\"x"'; then
  _ok "runner quote is JSON-escaped"
else
  _fail "runner quote was not JSON-escaped"
fi

test_case "setup claude: invalid --channel is a usage error"
stub_cmd uname 'echo Darwin'
out=$(run_setup --agent claude --channel nightly)
rc=$?
assert_setup_rc 2 "$rc"
assert_contains 'invalid channel' "$out"

test_case "setup claude: failed merge leaves the existing file intact"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
if link_host_tool node; then
  printf '%s\n' '{"mcpServers":{"other-server":{"command":"other","args":["original"]}}}' > "$SANDBOX/project/.mcp.json"
  before=$(cat "$SANDBOX/project/.mcp.json")
  chmod 500 "$SANDBOX/project"
  out=$(run_setup --agent claude)
  rc=$?
  chmod 700 "$SANDBOX/project"
  after=$(cat "$SANDBOX/project/.mcp.json")
  assert_setup_rc 3 "$rc"
  if [ "$before" = "$after" ]; then _ok "file survived failed merge"; else _fail "file was modified by failed merge"; fi
else
  _fail "host node unavailable"
fi

test_case "setup claude: failed create is reported as failure"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
chmod 500 "$SANDBOX/project"
out=$(run_setup --agent claude)
rc=$?
chmod 700 "$SANDBOX/project"
assert_setup_rc 3 "$rc"
assert_not_contains 'wrote ./.mcp.json' "$out"

test_case "setup claude: an existing file is merged, not clobbered"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
if link_host_tool node; then
  cat > "$SANDBOX/project/.mcp.json" <<'JSON'
{"mcpServers":{"other-server":{"command":"other","args":["x"]}}}
JSON
  run_setup --agent claude >/dev/null
  rc=$?
  assert_setup_rc 0 "$rc"
  body=$(cat "$SANDBOX/project/.mcp.json")
  assert_contains 'other-server' "$body"
  assert_contains 'chrome-devtools' "$body"
else
  _fail "host node unavailable"
fi

test_case "setup claude: is idempotent"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
if link_host_tool node; then
  run_setup --agent claude >/dev/null
  rc=$?
  assert_setup_rc 0 "$rc"
  run_setup --agent claude >/dev/null
  rc=$?
  assert_setup_rc 0 "$rc"
  body=$(cat "$SANDBOX/project/.mcp.json")
  n=$(printf '%s\n' "$body" | grep -c 'chrome-devtools"')
  if [ "$n" -eq 1 ]; then _ok "single chrome-devtools entry"; else _fail "entry count $n"; fi
else
  _fail "host node unavailable"
fi

test_case "setup claude: without node an existing file is left alone and a snippet is printed"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
if command -v node >/dev/null 2>&1; then
  _fail "node unexpectedly reachable in sandbox"
else
  _ok "node unavailable in sandbox"
fi
printf '%s\n' '{"mcpServers":{"other-server":{"command":"other"}}}' > "$SANDBOX/project/.mcp.json"
before=$(cat "$SANDBOX/project/.mcp.json")
out=$(run_setup --agent claude)
rc=$?
after=$(cat "$SANDBOX/project/.mcp.json")
assert_setup_rc 3 "$rc"
if [ "$before" = "$after" ]; then _ok "file untouched"; else _fail "file was modified without node"; fi
assert_contains 'chrome-devtools' "$out"
assert_contains 'merge' "$out"

test_case "setup: an unknown --agent is a usage error"
stub_cmd uname 'echo Darwin'
out=$(run_setup --agent nope)
rc=$?
assert_setup_rc 2 "$rc"

test_case "setup opencode: writes opencode.json with a command array"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
run_setup --agent opencode >/dev/null
rc=$?
assert_setup_rc 0 "$rc"
body=$(cat "$SANDBOX/project/opencode.json")
assert_contains '"type": "local"' "$body"
assert_contains '"command": \[' "$body"
assert_contains 'autoConnect' "$body"

test_case "setup opencode: failed create exits 3"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
chmod 500 "$SANDBOX/project"
out=$(run_setup --agent opencode)
rc=$?
chmod 700 "$SANDBOX/project"
assert_setup_rc 3 "$rc"
assert_not_contains 'wrote ./opencode.json' "$out"

test_case "setup opencode: merges into an existing opencode.json under the mcp key"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
node_bin=$(host_tool_path node) && ln -sf "$node_bin" "$SANDBOX/bin/node"
printf '%s\n' '{"mcp":{"other":{"type":"local","command":["x"]}}}' > "$SANDBOX/project/opencode.json"
run_setup --agent opencode >/dev/null
body=$(cat "$SANDBOX/project/opencode.json")
assert_contains '"other"' "$body"
assert_contains 'chrome-devtools' "$body"

test_case "setup codex: runs codex mcp add when the CLI is present"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
stub_cmd codex "printf '%s\n' \"CODEX_CALLED \$*\" >> \"\$HOME/codex.log\""
out=$(run_setup --agent codex)
log=$(cat "$HOME/codex.log")
assert_contains 'CODEX_CALLED mcp add' "$log"
assert_contains 'autoConnect' "$log"
assert_contains 'global' "$out"

test_case "setup codex: prints the command when the CLI is absent"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
out=$(run_setup --agent codex)
assert_contains 'codex mcp add' "$out"
assert_contains 'global' "$out"

test_case "setup auto: configures every detected agent"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
node_bin=$(host_tool_path node) && ln -sf "$node_bin" "$SANDBOX/bin/node"
printf '%s\n' '{"mcp":{}}' > "$SANDBOX/project/opencode.json"
printf '%s\n' '{"mcpServers":{}}' > "$SANDBOX/project/.mcp.json"
run_setup --agent auto >/dev/null
assert_contains 'chrome-devtools' "$(cat "$SANDBOX/project/opencode.json")"
assert_contains 'chrome-devtools' "$(cat "$SANDBOX/project/.mcp.json")"

test_case "setup auto: falls back to claude when nothing is detected"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
run_setup --agent auto >/dev/null
if [ -f "$SANDBOX/project/.mcp.json" ]; then _ok "defaulted to claude"; else _fail "no .mcp.json written"; fi

test_case "setup claude: malformed JSON root shapes fail without clobbering"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
if link_host_tool node; then
  printf '%s\n' '[]' > "$SANDBOX/project/.mcp.json"
  before=$(cat "$SANDBOX/project/.mcp.json")
  out=$(run_setup --agent claude)
  rc=$?
  after=$(cat "$SANDBOX/project/.mcp.json")
  assert_setup_rc 3 "$rc"
  assert_contains 'must contain a JSON object at the root' "$out"
  if [ "$before" = "$after" ]; then _ok "array root survived"; else _fail "array root was modified"; fi

  printf '%s\n' '42' > "$SANDBOX/project/.mcp.json"
  before=$(cat "$SANDBOX/project/.mcp.json")
  out=$(run_setup --agent claude)
  rc=$?
  after=$(cat "$SANDBOX/project/.mcp.json")
  assert_setup_rc 3 "$rc"
  assert_contains 'must contain a JSON object at the root' "$out"
  if [ "$before" = "$after" ]; then _ok "primitive root survived"; else _fail "primitive root was modified"; fi
else
  _fail "host node unavailable"
fi

test_case "setup opencode: malformed JSON root shapes fail without clobbering"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
if link_host_tool node; then
  printf '%s\n' '[]' > "$SANDBOX/project/opencode.json"
  before=$(cat "$SANDBOX/project/opencode.json")
  out=$(run_setup --agent opencode)
  rc=$?
  after=$(cat "$SANDBOX/project/opencode.json")
  assert_setup_rc 3 "$rc"
  assert_contains 'must contain a JSON object at the root' "$out"
  if [ "$before" = "$after" ]; then _ok "array root survived"; else _fail "array root was modified"; fi

  printf '%s\n' '42' > "$SANDBOX/project/opencode.json"
  before=$(cat "$SANDBOX/project/opencode.json")
  out=$(run_setup --agent opencode)
  rc=$?
  after=$(cat "$SANDBOX/project/opencode.json")
  assert_setup_rc 3 "$rc"
  assert_contains 'must contain a JSON object at the root' "$out"
  if [ "$before" = "$after" ]; then _ok "primitive root survived"; else _fail "primitive root was modified"; fi
else
  _fail "host node unavailable"
fi

test_case "setup claude: malformed mcpServers array is replaced"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
if link_host_tool node; then
  printf '%s\n' '{"mcpServers":[]}' > "$SANDBOX/project/.mcp.json"
  run_setup --agent claude >/dev/null
  rc=$?
  assert_setup_rc 0 "$rc"
  assert_contains 'chrome-devtools' "$(cat "$SANDBOX/project/.mcp.json")"
else
  _fail "host node unavailable"
fi

test_case "setup opencode: malformed mcp string is replaced"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
if link_host_tool node; then
  printf '%s\n' '{"mcp":"not-an-object"}' > "$SANDBOX/project/opencode.json"
  run_setup --agent opencode >/dev/null
  rc=$?
  assert_setup_rc 0 "$rc"
  assert_contains 'chrome-devtools' "$(cat "$SANDBOX/project/opencode.json")"
else
  _fail "host node unavailable"
fi

# A value-taking option given as the LAST argument must be a usage error, not an
# infinite loop. POSIX `shift 2` with one argument left shifts nothing and
# returns 1, so an unguarded `shift 2` spins the parser forever and burns a core.
# Each case runs under a hard timeout: a regression must FAIL the suite, never hang it.
run_setup_timeout() {
  # run_setup_timeout SECONDS ARGS... -> prints "rc=<code>" or "rc=TIMEOUT"
  secs="$1"; shift
  ( cd "$SANDBOX/project" && sh "$REPO_ROOT/scripts/setup-mcp.sh" "$@" >/dev/null 2>&1 ) &
  rp=$!
  ( sleep "$secs"; kill -9 "$rp" 2>/dev/null ) &
  wp=$!
  wait "$rp" 2>/dev/null; rc=$?
  kill "$wp" 2>/dev/null
  if [ "$rc" -eq 137 ]; then printf 'rc=TIMEOUT\n'; else printf 'rc=%s\n' "$rc"; fi
}

test_case "setup: a trailing --runner is a usage error, not an infinite loop"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
out=$(run_setup_timeout 5 --agent claude --runner)
assert_contains 'rc=2' "$out"

test_case "setup: a trailing --agent is a usage error, not an infinite loop"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
out=$(run_setup_timeout 5 --agent)
assert_contains 'rc=2' "$out"

test_case "setup: a trailing --channel is a usage error, not an infinite loop"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
out=$(run_setup_timeout 5 --agent claude --channel)
assert_contains 'rc=2' "$out"

test_case "setup: repeated options are usage errors and terminate"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
out=$(run_setup_timeout 5 --agent claude --agent codex)
assert_contains 'rc=2' "$out"
out=$(run_setup_timeout 5 --runner bunx --runner pnpm)
assert_contains 'rc=2' "$out"
out=$(run_setup_timeout 5 --channel beta --channel dev)
assert_contains 'rc=2' "$out"
out=$(run_setup_timeout 5 --no-redact --no-redact)
assert_contains 'rc=2' "$out"

test_case "setup: empty and option-looking values terminate"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
out=$(run_setup_timeout 5 --agent "")
assert_contains 'rc=2' "$out"
out=$(run_setup_timeout 5 --channel "")
assert_contains 'rc=2' "$out"
out=$(run_setup_timeout 5 --runner --agent)
assert_contains 'rc=0' "$out"
out=$(run_setup_timeout 5 --)
assert_contains 'rc=2' "$out"

test_case "setup: an empty --runner value terminates"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
out=$(run_setup_timeout 5 --runner "")
assert_contains 'rc=0' "$out"
