test_case "platform: macos is detected from uname"
stub_cmd uname 'echo Darwin'
out=$(run_preflight)
assert_kv PLATFORM macos "$out"

test_case "platform: linux is detected from uname"
stub_cmd uname 'echo Linux'
out=$(run_preflight)
assert_kv PLATFORM linux "$out"

test_case "platform: git bash reports windows"
stub_cmd uname 'echo MINGW64_NT-10.0'
out=$(run_preflight)
assert_kv PLATFORM windows "$out"

test_case "runner: npx is preferred"
stub_cmd npx 'exit 0'
stub_cmd bunx 'exit 0'
out=$(run_preflight)
assert_kv RUNNER npx "$out"
assert_kv RUNNER_CMD "npx -y" "$out"

test_case "runner: bunx is used when npx is absent"
stub_cmd bunx 'exit 0'
out=$(run_preflight)
assert_kv RUNNER bunx "$out"
assert_kv RUNNER_CMD "bunx" "$out"

test_case "runner: pnpm dlx is used when npx and bunx are absent"
stub_cmd pnpm 'exit 0'
out=$(run_preflight)
assert_kv RUNNER pnpm-dlx "$out"
assert_kv RUNNER_CMD "pnpm dlx" "$out"

test_case "runner: a global chrome-devtools-mcp is the last resort"
stub_cmd chrome-devtools-mcp 'exit 0'
out=$(run_preflight)
assert_kv RUNNER global "$out"

test_case "verdict: no runner at all is NODE_MISSING"
out=$(run_preflight)
assert_kv RUNNER none "$out"
assert_status NODE_MISSING "$out"
expected_keys='PLATFORM
RUNNER
RUNNER_CMD
CHROME_PATH
CHROME_CHANNEL
CHROME_VERSION
CHROME_MAJOR
CHROME_OK
USER_DATA_DIR
CHROME_RUNNING
DEBUG_PORT
DEBUG_REACHABLE
MCP_CONFIG_FILE
MCP_CONFIGURED
STATUS'
actual_keys=$(printf '%s\n' "$out" | sed 's/=.*//')
if [ "$actual_keys" = "$expected_keys" ]; then
  _ok 'NODE_MISSING keys are ordered and unique'
else
  _fail "NODE_MISSING key order mismatch: $actual_keys"
fi

# fake_chrome PATH VERSION_OUTPUT — create an executable that prints a version line
fake_chrome() {
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$2" > "$1"
  chmod +x "$1"
}

test_case "chrome: macos stable is found with its profile dir"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
fake_chrome "$CHROMEAGENT_ROOT/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "Google Chrome 145.0.7300.20"
out=$(run_preflight)
assert_kv CHROME_CHANNEL stable "$out"
assert_kv CHROME_VERSION "145.0.7300.20" "$out"
assert_kv CHROME_MAJOR 145 "$out"
assert_kv CHROME_OK yes "$out"
assert_kv USER_DATA_DIR "$HOME/Library/Application Support/Google/Chrome" "$out"

test_case "chrome: macos beta is found when stable is absent, with the beta profile dir"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
fake_chrome "$CHROMEAGENT_ROOT/Applications/Google Chrome Beta.app/Contents/MacOS/Google Chrome Beta" "Google Chrome 146.0.7400.1 beta"
out=$(run_preflight)
assert_kv CHROME_CHANNEL beta "$out"
assert_kv USER_DATA_DIR "$HOME/Library/Application Support/Google/Chrome Beta" "$out"

test_case "chrome: stable wins over beta when both are installed"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
fake_chrome "$CHROMEAGENT_ROOT/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "Google Chrome 145.0.7300.20"
fake_chrome "$CHROMEAGENT_ROOT/Applications/Google Chrome Beta.app/Contents/MacOS/Google Chrome Beta" "Google Chrome 146.0.7400.1 beta"
out=$(run_preflight)
assert_kv CHROME_CHANNEL stable "$out"

test_case "chrome: macos stable in home applications beats beta in root applications"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
fake_chrome "$CHROMEAGENT_ROOT/Applications/Google Chrome Beta.app/Contents/MacOS/Google Chrome Beta" "Google Chrome 146.0.7400.1 beta"
fake_chrome "$HOME/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "Google Chrome 145.0.7300.20"
out=$(run_preflight)
assert_kv CHROME_CHANNEL stable "$out"
assert_kv USER_DATA_DIR "$HOME/Library/Application Support/Google/Chrome" "$out"

test_case "chrome: linux stable is found on PATH with the xdg profile dir"
stub_cmd uname 'echo Linux'
stub_cmd npx 'exit 0'
stub_cmd google-chrome-stable 'echo "Google Chrome 144.0.7100.5"'
out=$(run_preflight)
assert_kv CHROME_CHANNEL stable "$out"
assert_kv CHROME_MAJOR 144 "$out"
assert_kv USER_DATA_DIR "$HOME/.config/google-chrome" "$out"

test_case "chrome: linux chromium snap is found with its snap profile dir"
stub_cmd uname 'echo Linux'
stub_cmd npx 'exit 0'
fake_chrome "$CHROMEAGENT_ROOT/snap/bin/chromium" "Chromium 145.0.7300.0 snap"
out=$(run_preflight)
assert_kv CHROME_CHANNEL chromium "$out"
assert_kv USER_DATA_DIR "$HOME/snap/chromium/common/chromium" "$out"

test_case "verdict: no chrome anywhere is CHROME_MISSING"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
out=$(run_preflight)
assert_kv CHROME_PATH none "$out"
assert_kv CHROME_CHANNEL none "$out"
assert_status CHROME_MISSING "$out"

test_case "verdict: chrome 143 is CHROME_TOO_OLD"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
fake_chrome "$CHROMEAGENT_ROOT/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "Google Chrome 143.0.7000.1"
out=$(run_preflight)
assert_kv CHROME_MAJOR 143 "$out"
assert_kv CHROME_OK no "$out"
assert_status CHROME_TOO_OLD "$out"

test_case "chrome: an unparseable version is major 0 and too old"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
fake_chrome "$CHROMEAGENT_ROOT/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "no version here"
out=$(run_preflight)
assert_kv CHROME_VERSION unknown "$out"
assert_kv CHROME_MAJOR 0 "$out"
assert_kv CHROME_OK no "$out"
assert_status CHROME_TOO_OLD "$out"

# ready_chrome — a sandbox with a runner and a modern Chrome, macOS table
ready_chrome() {
  stub_cmd uname 'echo Darwin'
  stub_cmd npx 'exit 0'
  fake_chrome "$CHROMEAGENT_ROOT/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "Google Chrome 145.0.7300.20"
}

write_mcp_json() {
  # write_mcp_json PATH
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'JSON'
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["-y", "chrome-devtools-mcp@latest", "--autoConnect", "--redactNetworkHeaders"]
    }
  }
}
JSON
}

test_case "config: an unconfigured project is NOT_CONFIGURED"
ready_chrome
out=$(run_preflight)
assert_kv MCP_CONFIGURED no "$out"
assert_kv MCP_CONFIG_FILE none "$out"
assert_status NOT_CONFIGURED "$out"

test_case "config: project .mcp.json with autoConnect is detected"
ready_chrome
write_mcp_json "$SANDBOX/project/.mcp.json"
out=$(run_preflight)
assert_kv MCP_CONFIGURED yes "$out"
assert_contains "MCP_CONFIG_FILE=.*\.mcp\.json" "$out"
assert_not_contains "STATUS=NOT_CONFIGURED" "$out"

test_case "config: wrongly-cased autoConnect is not detected"
ready_chrome
cat > "$SANDBOX/project/.mcp.json" <<'JSON'
{"mcpServers":{"chrome-devtools":{"command":"npx","args":["--autoconnect"]}}}
JSON
out=$(run_preflight)
assert_kv MCP_CONFIGURED no "$out"
assert_status NOT_CONFIGURED "$out"

test_case "config: .vscode/mcp.json is detected"
ready_chrome
write_mcp_json "$SANDBOX/project/.vscode/mcp.json"
out=$(run_preflight)
assert_kv MCP_CONFIGURED yes "$out"

test_case "config: .cursor/mcp.json is detected"
ready_chrome
write_mcp_json "$SANDBOX/project/.cursor/mcp.json"
out=$(run_preflight)
assert_kv MCP_CONFIGURED yes "$out"

test_case "config: the global codex config is detected"
ready_chrome
mkdir -p "$HOME/.codex"
cat > "$HOME/.codex/config.toml" <<'TOML'
[mcp_servers.chrome-devtools]
command = "npx"
args = ["-y", "chrome-devtools-mcp@latest", "--autoConnect", "--redactNetworkHeaders"]
TOML
out=$(run_preflight)
assert_kv MCP_CONFIGURED yes "$out"

test_case "config: a chrome-devtools entry without autoConnect does not count"
ready_chrome
mkdir -p "$SANDBOX/project"
cat > "$SANDBOX/project/.mcp.json" <<'JSON'
{"mcpServers":{"chrome-devtools":{"command":"npx","args":["-y","chrome-devtools-mcp@latest","--isolated"]}}}
JSON
out=$(run_preflight)
assert_kv MCP_CONFIGURED no "$out"
assert_status NOT_CONFIGURED "$out"

# configured_chrome — runner + modern chrome + a project .mcp.json
configured_chrome() {
  ready_chrome
  write_mcp_json "$SANDBOX/project/.mcp.json"
}

profile_dir() { printf '%s/Library/Application Support/Google/Chrome\n' "$HOME"; }

test_case "runtime: no chrome process is CHROME_NOT_RUNNING"
configured_chrome
stub_cmd pgrep 'exit 1'
out=$(run_preflight)
assert_kv CHROME_RUNNING no "$out"
assert_status CHROME_NOT_RUNNING "$out"

test_case "runtime: running chrome with no debug endpoint is NEEDS_OPT_IN"
configured_chrome
stub_cmd pgrep 'echo 4321'
stub_cmd curl 'exit 7'
out=$(run_preflight)
assert_kv CHROME_RUNNING yes "$out"
assert_kv DEBUG_REACHABLE no "$out"
assert_status NEEDS_OPT_IN "$out"

test_case "runtime: a reachable endpoint on the port-file port is READY"
configured_chrome
mkdir -p "$(profile_dir)"
printf '9333\n/devtools/browser/abc\n' > "$(profile_dir)/DevToolsActivePort"
stub_cmd pgrep 'echo 4321'
stub_cmd curl 'exit 0'
out=$(run_preflight)
assert_kv DEBUG_PORT 9333 "$out"
assert_kv DEBUG_REACHABLE yes "$out"
assert_status READY "$out"

test_case "runtime: with no port file the probe falls back to 9222"
configured_chrome
stub_cmd pgrep 'echo 4321'
stub_cmd curl 'exit 0'
out=$(run_preflight)
assert_kv DEBUG_PORT 9222 "$out"
assert_status READY "$out"

test_case "runtime: no http client plus a port file is READY with unknown reachability"
configured_chrome
mkdir -p "$(profile_dir)"
printf '9333\n' > "$(profile_dir)/DevToolsActivePort"
stub_cmd pgrep 'echo 4321'
out=$(run_preflight)
assert_kv DEBUG_REACHABLE unknown "$out"
assert_status READY "$out"

test_case "runtime: no http client and no port file is NEEDS_OPT_IN"
configured_chrome
mkdir -p "$(profile_dir)"
printf '9333\n' > "$(profile_dir)/DevToolsActivePort"
stub_cmd pgrep 'echo 4321'
with_port_file=$(run_preflight)
assert_kv DEBUG_PORT 9333 "$with_port_file"
assert_status READY "$with_port_file"
rm -f "$(profile_dir)/DevToolsActivePort"
out=$(run_preflight)
assert_kv DEBUG_PORT 9222 "$out"
assert_kv DEBUG_REACHABLE unknown "$out"
assert_status NEEDS_OPT_IN "$out"

test_case "precedence: an old chrome outranks a missing config"
stub_cmd uname 'echo Darwin'
stub_cmd npx 'exit 0'
fake_chrome "$CHROMEAGENT_ROOT/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "Google Chrome 143.0.7000.1"
out=$(run_preflight)
assert_status CHROME_TOO_OLD "$out"

test_case "contract: a READY run prints every documented key exactly once"
configured_chrome
mkdir -p "$(profile_dir)"
printf '9333\n' > "$(profile_dir)/DevToolsActivePort"
stub_cmd pgrep 'echo 4321'
stub_cmd curl 'exit 0'
out=$(run_preflight)
for k in PLATFORM RUNNER RUNNER_CMD CHROME_PATH CHROME_CHANNEL CHROME_VERSION CHROME_MAJOR \
         CHROME_OK USER_DATA_DIR CHROME_RUNNING DEBUG_PORT DEBUG_REACHABLE MCP_CONFIG_FILE \
         MCP_CONFIGURED STATUS; do
  n=$(printf '%s\n' "$out" | grep -c "^$k=")
  if [ "$n" -eq 1 ]; then _ok "$k printed once"; else _fail "$k printed $n times"; fi
done

test_case "runtime: a malformed port file falls back and needs opt-in"
configured_chrome
mkdir -p "$(profile_dir)"
printf 'not-a-port\n' > "$(profile_dir)/DevToolsActivePort"
stub_cmd pgrep 'echo 4321'
out=$(run_preflight)
assert_kv DEBUG_PORT 9222 "$out"
assert_kv DEBUG_REACHABLE unknown "$out"
assert_status NEEDS_OPT_IN "$out"
