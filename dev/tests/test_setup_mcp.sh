# shellcheck shell=sh
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
assert_contains 'chrome-devtools-mcp@1.12.0' "$body"
assert_contains '\-\-autoConnect' "$body"
assert_contains '\-\-redactNetworkHeaders' "$body"
if printf '%s\n' "$body" | grep -q -- '"--autoConnect".*"--redactNetworkHeaders".*"--no-performance-crux".*"--no-file-navigations".*"--no-usage-statistics"'; then
  _ok "default flags are ordered"
else
  _fail "default flags are out of order"
fi

test_case "setup claude: --out-dir writes into the named directory, not cwd"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
out_dir="$SANDBOX/target"
mkdir "$out_dir"
out=$(run_setup --agent claude --out-dir "$out_dir")
rc=$?
assert_setup_rc 0 "$rc"
if [ -f "$out_dir/.mcp.json" ]; then _ok "named directory received .mcp.json"; else _fail "named directory did not receive .mcp.json"; fi
if [ ! -e "$SANDBOX/project/.mcp.json" ]; then _ok "cwd did not receive .mcp.json"; else _fail "cwd received .mcp.json"; fi

test_case "setup claude: --out-dir rejects a nonexistent directory"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
out_dir="$SANDBOX/missing"
out=$(run_setup --agent claude --out-dir "$out_dir")
rc=$?
assert_setup_rc 2 "$rc"
assert_contains "setup-mcp: --out-dir $out_dir is not a directory" "$out"
if [ ! -e "$out_dir" ]; then _ok "nonexistent directory was not created"; else _fail "nonexistent directory was created"; fi
if [ ! -e "$SANDBOX/project/.mcp.json" ]; then _ok "cwd was not written"; else _fail "cwd was written"; fi

test_case "setup claude: --out-dir rejects a file"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
out_dir="$SANDBOX/not-a-directory"
printf '%s\n' original > "$out_dir"
out=$(run_setup --agent claude --out-dir "$out_dir")
rc=$?
assert_setup_rc 2 "$rc"
assert_contains "setup-mcp: --out-dir $out_dir is not a directory" "$out"
if [ -f "$out_dir" ] && [ "$(cat "$out_dir")" = original ]; then
  _ok "file target was left untouched"
else
  _fail "file target was changed"
fi

test_case "setup: refuses dangling symlink targets without creating pointed-at files"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
mkdir -p "$HOME/elsewhere"
for agent in claude opencode; do
  if [ "$agent" = claude ]; then target_name=.mcp.json; else target_name=opencode.json; fi
  target="$SANDBOX/project/$target_name"
  pointed_to="$HOME/elsewhere/config.json"
  if ! make_symlink "$pointed_to" "$target"; then
    _skip "this platform will not create a symlink (Windows: needs admin or Developer Mode)"
    break
  fi
  out=$(run_setup --agent "$agent")
  rc=$?
  assert_setup_rc 3 "$rc"
  assert_contains "setup-mcp: refusing to write through symlink $target" "$out"
  if [ -L "$target" ]; then _ok "$target remained a symlink"; else _fail "$target was replaced"; fi
  if [ ! -e "$pointed_to" ]; then _ok "pointed-at file was not created"; else _fail "pointed-at file was created"; fi
done

test_case "setup: directory-shaped targets fail without writing inside them"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
for agent in claude opencode; do
  if [ "$agent" = claude ]; then target_name=.mcp.json; else target_name=opencode.json; fi
  target="$SANDBOX/project/$target_name"
  mkdir "$target"
  out=$(run_setup --agent "$agent")
  rc=$?
  assert_setup_rc 3 "$rc"
  assert_contains "setup-mcp: failed to write $target" "$out"
  if [ -d "$target" ] && [ -z "$(ls -A "$target")" ]; then
    _ok "$target remained an empty directory"
  else
    _fail "$target was changed or received a temp file"
  fi
done

test_case "setup claude: default output directory remains cwd"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
run_setup --agent claude >/dev/null
rc=$?
assert_setup_rc 0 "$rc"
if [ -f "$SANDBOX/project/.mcp.json" ]; then _ok "cwd received .mcp.json"; else _fail "cwd did not receive .mcp.json"; fi

test_case "setup claude: success message names the absolute target"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
out=$(run_setup --agent claude)
rc=$?
assert_setup_rc 0 "$rc"
assert_contains "$SANDBOX/project/.mcp.json" "$out"
assert_not_contains 'wrote ./' "$out"

test_case "setup claude: merge message names the absolute target"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
if link_host_tool node; then
  printf '%s\n' '{"mcpServers":{"other-server":{"command":"other"}}}' > "$SANDBOX/project/.mcp.json"
  out=$(run_setup --agent claude)
  rc=$?
  assert_setup_rc 0 "$rc"
  assert_contains "$SANDBOX/project/.mcp.json" "$out"
else
  _fail "host node unavailable"
fi

test_case "setup: help documents --out-dir"
out=$(run_setup --help)
rc=$?
assert_setup_rc 0 "$rc"
usage='usage: setup-mcp.sh --agent auto|claude|opencode [--runner "<argv>"] [--channel beta|dev|canary] [--out-dir <dir>] [--no-redact] [--force]'
case "$out" in
  *"$usage"*) _ok "usage includes --out-dir" ;;
  *) _fail "usage does not include --out-dir" ;;
esac

test_case "setup claude: --no-redact omits the redaction flag"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
run_setup --agent claude --no-redact >/dev/null
rc=$?
assert_setup_rc 0 "$rc"
body=$(cat "$SANDBOX/project/.mcp.json")
assert_contains '\-\-autoConnect' "$body"
assert_not_contains 'redactNetworkHeaders' "$body"
assert_contains 'no-performance-crux' "$body"
assert_contains 'no-file-navigations' "$body"
assert_contains 'no-usage-statistics' "$body"

test_case "setup claude: --channel adds the channel flag"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
run_setup --agent claude --channel beta >/dev/null
rc=$?
assert_setup_rc 0 "$rc"
body=$(cat "$SANDBOX/project/.mcp.json")
assert_contains '\-\-channel' "$body"
if printf '%s\n' "$body" | grep -q -- '"--no-usage-statistics", "--channel", "beta"'; then
  _ok "channel follows the default flags"
else
  _fail "channel does not follow the default flags"
fi
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

test_case "setup: a global chrome-devtools-mcp is the last-resort runner, without a package spec"
stub_cmd uname 'echo Darwin'
stub_cmd chrome-devtools-mcp 'exit 0'
run_setup --agent claude >/dev/null
rc=$?
assert_setup_rc 0 "$rc"
body=$(cat "$SANDBOX/project/.mcp.json")
assert_contains '"command": "chrome-devtools-mcp"' "$body"
assert_contains '"args": \["--autoConnect"' "$body"
assert_not_contains 'chrome-devtools-mcp@' "$body"
run_setup --agent opencode >/dev/null
body=$(cat "$SANDBOX/project/opencode.json")
assert_contains '"command": \["chrome-devtools-mcp", "--autoConnect"' "$body"
assert_not_contains 'chrome-devtools-mcp@' "$body"

test_case "setup: a package runner still beats a global chrome-devtools-mcp"
stub_cmd uname 'echo Darwin'
stub_cmd chrome-devtools-mcp 'exit 0'
stub_cmd pnpm 'exit 0'
run_setup --agent claude >/dev/null
body=$(cat "$SANDBOX/project/.mcp.json")
assert_contains '"command": "pnpm"' "$body"
assert_contains 'chrome-devtools-mcp@1.12.0' "$body"

test_case "setup claude: --runner naming the global binary omits the package spec"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
for runner in chrome-devtools-mcp /opt/node/bin/chrome-devtools-mcp 'C:\nodejs\chrome-devtools-mcp.cmd'; do
  rm -f "$SANDBOX/project/.mcp.json"
  run_setup --agent claude --runner "$runner" >/dev/null
  body=$(cat "$SANDBOX/project/.mcp.json")
  assert_contains '"args": \["--autoConnect"' "$body"
  assert_not_contains 'chrome-devtools-mcp@' "$body"
done

test_case "setup: an existing fallback entry is not replaced without --force"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
if link_host_tool node; then
  for agent in claude opencode; do
    if [ "$agent" = claude ]; then f="$SANDBOX/project/.mcp.json"; key=mcpServers
    else f="$SANDBOX/project/opencode.json"; key=mcp; fi
    printf '{"%s":{"chrome-devtools":{"command":"npx","args":["-y","chrome-devtools-mcp@1.12.0","--browserUrl=http://127.0.0.1:9222"]}}}\n' "$key" > "$f"
    before=$(cat "$f")
    out=$(run_setup --agent "$agent")
    rc=$?
    assert_setup_rc 3 "$rc"
    assert_contains 'already has a chrome-devtools entry without --autoConnect' "$out"
    assert_contains 'pass --force' "$out"
    if [ "$(cat "$f")" = "$before" ]; then _ok "$agent fallback entry left untouched"
    else _fail "$agent fallback entry was changed"; fi
    out=$(run_setup --agent "$agent" --force)
    rc=$?
    assert_setup_rc 0 "$rc"
    body=$(cat "$f")
    assert_contains 'autoConnect' "$body"
    assert_not_contains 'browserUrl' "$body"
  done
else
  _fail "host node unavailable"
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
if ! link_host_tool node; then
  _fail "host node unavailable"
elif printf '%s\n' '{"mcpServers":{"other-server":{"command":"other","args":["original"]}}}' > "$SANDBOX/project/.mcp.json" &&
     ! deny_writes "$SANDBOX/project"; then
  _skip "a read-only directory cannot be enforced here (root, or an elevated Windows shell)"
else
  before=$(cat "$SANDBOX/project/.mcp.json")
  out=$(run_setup --agent claude)
  rc=$?
  allow_writes "$SANDBOX/project"
  after=$(cat "$SANDBOX/project/.mcp.json")
  assert_setup_rc 3 "$rc"
  if [ "$before" = "$after" ]; then _ok "file survived failed merge"; else _fail "file was modified by failed merge"; fi
fi

test_case "setup claude: failed create is reported as failure"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
if deny_writes "$SANDBOX/project"; then
  out=$(run_setup --agent claude)
  rc=$?
  allow_writes "$SANDBOX/project"
  assert_setup_rc 3 "$rc"
  assert_contains "setup-mcp: failed to write $SANDBOX/project/.mcp.json" "$out"
  assert_not_contains "wrote $SANDBOX/project/.mcp.json" "$out"
else
  _skip "a read-only directory cannot be enforced here (root, or an elevated Windows shell)"
fi

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
if deny_writes "$SANDBOX/project"; then
  out=$(run_setup --agent opencode)
  rc=$?
  allow_writes "$SANDBOX/project"
  assert_setup_rc 3 "$rc"
  assert_contains "setup-mcp: failed to write $SANDBOX/project/opencode.json" "$out"
  assert_not_contains "wrote $SANDBOX/project/opencode.json" "$out"
else
  _skip "a read-only directory cannot be enforced here (root, or an elevated Windows shell)"
fi

test_case "setup opencode: merges into an existing opencode.json under the mcp key"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
node_bin=$(host_tool_path node) && ln -sf "$node_bin" "$SANDBOX/bin/node"
printf '%s\n' '{"mcp":{"other":{"type":"local","command":["x"]}}}' > "$SANDBOX/project/opencode.json"
run_setup --agent opencode >/dev/null
body=$(cat "$SANDBOX/project/opencode.json")
assert_contains '"other"' "$body"
assert_contains 'chrome-devtools' "$body"

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


test_case "setup auto: probes and configures markers in the explicit --out-dir"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
out_dir="$SANDBOX/target"
mkdir "$out_dir"
if link_host_tool node; then
  printf '%s\n' '{"mcpServers":{}}' > "$out_dir/.mcp.json"
  printf '%s\n' '{"mcp":{}}' > "$out_dir/opencode.json"
  # With the probe reverted from "$OUT_DIR" to ".", the empty cwd would
  # trigger the Claude fallback instead of configuring both out-dir markers.
  out=$(run_setup --agent auto --out-dir "$out_dir")
  rc=$?
  assert_setup_rc 0 "$rc"
  assert_contains 'chrome-devtools' "$(cat "$out_dir/.mcp.json")"
  assert_contains 'chrome-devtools' "$(cat "$out_dir/opencode.json")"
  if [ ! -e "$SANDBOX/project/.mcp.json" ]; then _ok "cwd was not written"; else _fail "cwd was written"; fi
  if [ ! -e "$SANDBOX/project/opencode.json" ]; then _ok "cwd remained empty"; else _fail "cwd received a marker target"; fi
else
  _fail "host node unavailable"
fi

test_case "setup auto: an opencode marker beats a PATH-only claude"
stub_cmd uname "echo Darwin"
stub_cmd npx "exit 0"
stub_cmd claude "exit 0"
if link_host_tool node; then
  printf "%s\n" "{\"mcp\":{}}" > "$SANDBOX/project/opencode.json"
  # A reverted command -v claude arm would select both targets; marker-only
  # detection must select just the opencode marker.
  out=$(run_setup --agent auto)
  rc=$?
  assert_setup_rc 0 "$rc"
  assert_contains "chrome-devtools" "$(cat "$SANDBOX/project/opencode.json")"
  if [ ! -e "$SANDBOX/project/.mcp.json" ]; then _ok "PATH-only claude was ignored"; else _fail "PATH-only claude was selected"; fi
else
  _fail "host node unavailable"
fi

test_case "setup auto: a PATH-only opencode does not select opencode"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
stub_cmd opencode 'exit 0'
out=$(run_setup --agent auto)
rc=$?
assert_setup_rc 0 "$rc"
if [ -f "$SANDBOX/project/.mcp.json" ]; then _ok "fallback wrote .mcp.json"; else _fail "fallback did not write .mcp.json"; fi
if [ ! -e "$SANDBOX/project/opencode.json" ]; then _ok "PATH-only opencode was ignored"; else _fail "PATH-only opencode was selected"; fi

test_case "setup auto: an opencode marker configures opencode"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
if link_host_tool node; then
  printf '%s\n' '{"mcp":{}}' > "$SANDBOX/project/opencode.json"
  out=$(run_setup --agent auto)
  rc=$?
  assert_setup_rc 0 "$rc"
  assert_contains 'chrome-devtools' "$(cat "$SANDBOX/project/opencode.json")"
  if [ ! -e "$SANDBOX/project/.mcp.json" ]; then _ok "claude was not selected"; else _fail "claude was selected"; fi
else
  _fail "host node unavailable"
fi

test_case "setup auto: a .claude marker beats a PATH-only opencode"
stub_cmd uname "echo Darwin"
stub_cmd npx "exit 0"
stub_cmd opencode "exit 0"
mkdir "$SANDBOX/project/.claude"
# A reverted command -v opencode arm would select both targets; this marker
# case must select claude without creating an OpenCode config.
out=$(run_setup --agent auto)
rc=$?
assert_setup_rc 0 "$rc"
if [ -f "$SANDBOX/project/.mcp.json" ]; then _ok ".claude marker selected claude"; else _fail ".claude marker did not select claude"; fi
if [ ! -e "$SANDBOX/project/opencode.json" ]; then _ok "opencode was not selected"; else _fail "opencode was selected"; fi

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
  ( cd "$SANDBOX/project" && sh "$REPO_ROOT/skills/chromeagent/scripts/setup-mcp.sh" "$@" >/dev/null 2>&1 ) &
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

test_case "setup: a trailing --out-dir is a usage error, not an infinite loop"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
out=$(run_setup_timeout 5 --agent claude --out-dir)
assert_contains 'rc=2' "$out"
out=$(run_setup --agent claude --out-dir)
rc=$?
assert_setup_rc 2 "$rc"
assert_contains 'setup-mcp: --out-dir requires a value' "$out"

test_case "setup: repeated options are usage errors and terminate"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
out=$(run_setup_timeout 5 --agent claude --agent opencode)
assert_contains 'rc=2' "$out"
out=$(run_setup_timeout 5 --runner bunx --runner pnpm)
assert_contains 'rc=2' "$out"
out=$(run_setup_timeout 5 --channel beta --channel dev)
assert_contains 'rc=2' "$out"
out=$(run_setup_timeout 5 --out-dir "$SANDBOX/project" --out-dir "$SANDBOX/project")
assert_contains 'rc=2' "$out"
out=$(run_setup_timeout 5 --no-redact --no-redact)
assert_contains 'rc=2' "$out"
out=$(run_setup_timeout 5 --force --force)
assert_contains 'rc=2' "$out"

test_case "setup: repeated --out-dir is a usage error"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
out=$(run_setup --agent claude --out-dir "$SANDBOX/project" --out-dir "$SANDBOX/project")
rc=$?
assert_setup_rc 2 "$rc"
assert_contains 'setup-mcp: repeated option --out-dir' "$out"

test_case "setup: empty and option-looking values terminate"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
out=$(run_setup_timeout 5 --agent "")
assert_contains 'rc=2' "$out"
out=$(run_setup_timeout 5 --channel "")
assert_contains 'rc=2' "$out"
out=$(run_setup --out-dir "")
rc=$?
assert_setup_rc 2 "$rc"
assert_contains 'setup-mcp: --out-dir requires a value' "$out"
out=$(run_setup_timeout 5 --runner --agent)
assert_contains 'rc=0' "$out"
out=$(run_setup_timeout 5 --)
assert_contains 'rc=2' "$out"

test_case "setup: an empty --runner value terminates"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
out=$(run_setup_timeout 5 --runner "")
assert_contains 'rc=0' "$out"

test_case "setup: the plugin manifest and both setup scripts pin one server version"
manifest="$REPO_ROOT/.claude-plugin/plugin.json"
sh_pin=$(sed -n 's/^CDM_PACKAGE=//p' "$REPO_ROOT/skills/chromeagent/scripts/setup-mcp.sh")
ps_pin=$(sed -n "s/^\$CdmPackage = '\(.*\)'$/\1/p" "$REPO_ROOT/skills/chromeagent/scripts/setup-mcp.ps1")
plugin_pin=$(grep -o 'chrome-devtools-mcp@[^"]*' "$manifest" | sed -n '1p')
case "$sh_pin" in
  chrome-devtools-mcp@[0-9]*.[0-9]*.[0-9]*) _ok "setup-mcp.sh pins an exact version ($sh_pin)" ;;
  *) _fail "setup-mcp.sh pin is not an exact version: '$sh_pin'" ;;
esac
if [ "$ps_pin" = "$sh_pin" ]; then _ok "setup-mcp.ps1 pin matches"; else _fail "setup-mcp.ps1 pins '$ps_pin', setup-mcp.sh '$sh_pin'"; fi
if [ "$plugin_pin" = "$sh_pin" ]; then _ok "plugin.json pin matches"; else _fail "plugin.json pins '$plugin_pin', setup-mcp.sh '$sh_pin'"; fi

test_case "setup: the plugin manifest carries the same args setup writes"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
run_setup --agent claude >/dev/null
setup_args=$(sed -n 's/^ *"args": //p' "$SANDBOX/project/.mcp.json" | tr -d ' ')
plugin_args=$(sed -n 's/^ *"args": //p' "$REPO_ROOT/.claude-plugin/plugin.json" | tr -d ' ')
if [ -n "$setup_args" ] && [ "$setup_args" = "$plugin_args" ]; then
  _ok "plugin.json args match setup's defaults"
else
  _fail "plugin.json args '$plugin_args' differ from setup's '$setup_args'"
fi
