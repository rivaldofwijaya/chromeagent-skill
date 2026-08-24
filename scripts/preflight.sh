#!/bin/sh
# preflight.sh — chromeagent-skill status probe.
# Prints KEY=value lines and exactly one STATUS= verdict. Always exits 0.
#
# Test-only overrides:
#   CHROMEAGENT_ROOT      prefix prepended to absolute system paths
#   CHROMEAGENT_PLATFORM  force macos|linux|windows
#   CHROMEAGENT_LIB=1     define functions only, skip main
set -u

CHROME_MIN_MAJOR=144
ROOT="${CHROMEAGENT_ROOT:-}"

detect_platform() {
  if [ -n "${CHROMEAGENT_PLATFORM:-}" ]; then
    printf '%s\n' "$CHROMEAGENT_PLATFORM"
    return
  fi
  case "$(uname -s 2>/dev/null || echo unknown)" in
    Darwin) printf 'macos\n' ;;
    Linux) printf 'linux\n' ;;
    CYGWIN*|MINGW*|MSYS*|Windows_NT) printf 'windows\n' ;;
    *) printf 'linux\n' ;;
  esac
}

# Prints "RUNNER|RUNNER_CMD".
detect_runner() {
  if command -v npx >/dev/null 2>&1; then printf 'npx|npx -y\n'
  elif command -v bunx >/dev/null 2>&1; then printf 'bunx|bunx\n'
  elif command -v pnpm >/dev/null 2>&1; then printf 'pnpm-dlx|pnpm dlx\n'
  elif command -v chrome-devtools-mcp >/dev/null 2>&1; then printf 'global|chrome-devtools-mcp\n'
  else printf 'none|\n'
  fi
}

# Emits "channel|binary|user_data_dir" lines, most-preferred first.
# Binaries may be bare names (resolved on PATH) or absolute paths (ROOT-prefixed).
chrome_candidates() {
  case "$1" in
    macos)
      for channel in stable beta dev canary chromium; do
        for base in "$ROOT/Applications" "$HOME/Applications"; do
          case "$channel" in
            stable)
              printf 'stable|%s/Google Chrome.app/Contents/MacOS/Google Chrome|%s\n' \
                "$base" "$HOME/Library/Application Support/Google/Chrome"
              ;;
            beta)
              printf 'beta|%s/Google Chrome Beta.app/Contents/MacOS/Google Chrome Beta|%s\n' \
                "$base" "$HOME/Library/Application Support/Google/Chrome Beta"
              ;;
            dev)
              printf 'dev|%s/Google Chrome Dev.app/Contents/MacOS/Google Chrome Dev|%s\n' \
                "$base" "$HOME/Library/Application Support/Google/Chrome Dev"
              ;;
            canary)
              printf 'canary|%s/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary|%s\n' \
                "$base" "$HOME/Library/Application Support/Google/Chrome Canary"
              ;;
            chromium)
              printf 'chromium|%s/Chromium.app/Contents/MacOS/Chromium|%s\n' \
                "$base" "$HOME/Library/Application Support/Chromium"
              ;;
          esac
        done
      done
      ;;
    linux)
      printf 'stable|google-chrome-stable|%s/.config/google-chrome\n' "$HOME"
      printf 'stable|google-chrome|%s/.config/google-chrome\n' "$HOME"
      printf 'stable|%s/opt/google/chrome/chrome|%s/.config/google-chrome\n' "$ROOT" "$HOME"
      printf 'beta|google-chrome-beta|%s/.config/google-chrome-beta\n' "$HOME"
      printf 'dev|google-chrome-unstable|%s/.config/google-chrome-unstable\n' "$HOME"
      printf 'chromium|%s/snap/bin/chromium|%s/snap/chromium/common/chromium\n' "$ROOT" "$HOME"
      printf 'chromium|chromium|%s/.config/chromium\n' "$HOME"
      printf 'chromium|chromium-browser|%s/.config/chromium\n' "$HOME"
      printf 'chromium|%s/var/lib/flatpak/exports/bin/org.chromium.Chromium|%s/.var/app/org.chromium.Chromium/config/chromium\n' "$ROOT" "$HOME"
      ;;
    windows)
      pf="${ProgramFiles:-C:/Program Files}"
      pf86="${ProgramFiles_x86:-$(env | sed -n 's/^ProgramFiles(x86)=//p')}"
      [ -n "$pf86" ] || pf86='C:/Program Files (x86)'
      lad="${LOCALAPPDATA:-$HOME/AppData/Local}"
      # Windows sets these with backslashes. Normalise at the source so
      # CHROME_PATH, USER_DATA_DIR, and the DevToolsActivePort path built from
      # it share one convention by construction — and there is one place to be
      # wrong instead of six. Forward slashes are what this script's consumers
      # expect, and what `-f` needs in Git Bash.
      pf=$(printf '%s' "$pf" | tr '\\' '/')
      pf86=$(printf '%s' "$pf86" | tr '\\' '/')
      lad=$(printf '%s' "$lad" | tr '\\' '/')
      for channel in stable beta dev canary; do
        for base in "$ROOT$pf" "$ROOT$pf86" "$ROOT$lad"; do
          case "$channel" in
            stable)
              printf 'stable|%s/Google/Chrome/Application/chrome.exe|%s/Google/Chrome/User Data\n' "$base" "$lad"
              ;;
            beta)
              printf 'beta|%s/Google/Chrome Beta/Application/chrome.exe|%s/Google/Chrome Beta/User Data\n' "$base" "$lad"
              ;;
            dev)
              printf 'dev|%s/Google/Chrome Dev/Application/chrome.exe|%s/Google/Chrome Dev/User Data\n' "$base" "$lad"
              ;;
            canary)
              printf 'canary|%s/Google/Chrome SxS/Application/chrome.exe|%s/Google/Chrome SxS/User Data\n' "$base" "$lad"
              ;;
          esac
        done
      done
      ;;
  esac
}

# major_of VERSION -> integer or 0
major_of() {
  m=$(printf '%s\n' "$1" | sed -n 's/^\([0-9][0-9]*\)\..*/\1/p')
  [ -n "$m" ] || m=0
  printf '%s\n' "$m"
}

# chrome_version BINARY PLATFORM -> full version or "unknown"
chrome_version() {
  raw=""
  if [ "$2" = windows ]; then
    # The Windows binary does not print --version; ask Windows for the file version.
    if command -v powershell.exe >/dev/null 2>&1; then
      raw=$(powershell.exe -NoProfile -Command \
        "(Get-Item '$1').VersionInfo.ProductVersion" 2>/dev/null | tr -d '\r')
    fi
  else
    raw=$("$1" --version 2>/dev/null)
  fi
  v=$(printf '%s\n' "$raw" | tr ' ' '\n' | grep -m1 '^[0-9][0-9]*\.[0-9]' )
  [ -n "$v" ] || v=unknown
  printf '%s\n' "$v"
}

# Prints the first found candidate; prints nothing when no candidate is found.
find_chrome() {
  CHROME_PATH=none
  CHROME_CHANNEL=none
  USER_DATA_DIR=""
  chrome_candidates "$1" | while IFS='|' read -r ch bin udd; do
    [ -n "$bin" ] || continue
    case "$bin" in
      /*|?:*) [ -x "$bin" ] || continue; resolved=$bin ;;
      *) resolved=$(command -v "$bin" 2>/dev/null) || continue ;;
    esac
    printf '%s|%s|%s\n' "$ch" "$resolved" "$udd"
    break
  done
}

# Prints the path of the first config that configures chrome-devtools with
# --autoConnect. Prints nothing when none does.
scan_config() {
  for f in \
    "./.mcp.json" \
    "./.vscode/mcp.json" \
    "./.cursor/mcp.json" \
    "./opencode.json" \
    "./.codex/config.toml" \
    "$HOME/.codex/config.toml" \
    "$HOME/.config/opencode/opencode.json"
  do
    [ -f "$f" ] || continue
    grep -q 'chrome-devtools' "$f" 2>/dev/null || continue
    grep -q 'autoConnect' "$f" 2>/dev/null || continue
    printf '%s\n' "$f"
    return 0
  done
  return 1
}

# chrome_running PLATFORM CHROME_PATH — exit 0 when that exact binary is running.
# Matching the resolved path, not the substring "chrom", keeps other Chromium
# browsers, the MCP server itself, and any process whose arguments merely mention
# chrome out of the verdict.
chrome_running() {
  [ -n "${2:-}" ] && [ "$2" != none ] || return 1
  if [ "$1" = windows ]; then
    if command -v tasklist >/dev/null 2>&1; then
      tasklist 2>/dev/null | grep -qi 'chrome.exe' && return 0
    fi
    return 1
  fi
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -f "$(printf '%s' "$2" | sed 's/[.[$^*+?(){}|]/\\&/g')" >/dev/null 2>&1 && return 0
    return 1
  fi
  if command -v ps >/dev/null 2>&1; then
    ps ax 2>/dev/null | grep -v grep | grep -qF "$2" && return 0
  fi
  return 1
}

# debug_port USER_DATA_DIR -> port. Sets PORT_FILE_FOUND to yes|no.
debug_port() {
  PORT_FILE_FOUND=no
  f="$1/DevToolsActivePort"
  if [ -n "$1" ] && [ -f "$f" ]; then
    p=$(sed -n '1p' "$f" 2>/dev/null | tr -d '\r')
    case "$p" in
      ''|*[!0-9]*) : ;;
      *) PORT_FILE_FOUND=yes; printf '%s\n' "$p"; return 0 ;;
    esac
  fi
  printf '9222\n'
}

# debug_reachable PORT -> yes|optin|no|unknown
# The question is "did anything answer", not "was the answer 200". Chrome's
# chrome://inspect opt-in endpoint is WebSocket-only and serves 404 for every
# HTTP path, including /json/version; a dead port answers nothing at all.
# The probe must reach loopback directly: curl and wget both send a 127.0.0.1
# URL through http_proxy if one is set, which would let a proxy answer for
# Chrome. Clearing the variables works for every client, including BusyBox
# wget, which rejects --no-proxy.
debug_reachable() {
  url="http://127.0.0.1:$1/json/version"
  no_proxy_env="http_proxy= HTTP_PROXY= https_proxy= HTTPS_PROXY= all_proxy= ALL_PROXY="
  if command -v curl >/dev/null 2>&1; then
    # %{http_code} is 000 when no response was received, so curl's exit
    # status is not consulted.
    code=$(env $no_proxy_env curl -s -o /dev/null -w '%{http_code}' \
      --noproxy '*' -m 2 "$url" 2>/dev/null)
    case "$code" in
      200) printf 'yes\n' ;;
      ''|000|0|*[!0-9]*) printf 'no\n' ;;
      *) printf 'optin\n' ;;
    esac
    return
  fi
  if command -v wget >/dev/null 2>&1; then
    env $no_proxy_env wget -q -T 2 -O /dev/null "$url" >/dev/null 2>&1
    rc=$?
    case "$rc" in
      0) printf 'yes\n' ;;
      8) printf 'optin\n' ;;  # server issued an error response — a response nonetheless
      *) printf 'no\n' ;;
    esac
    return
  fi
  if command -v node >/dev/null 2>&1; then
    # No scrubbing here: node's http.get ignores the proxy environment.
    node -e "const t=setTimeout(()=>process.exit(1),2000);require('http').get('$url',r=>{clearTimeout(t);r.resume();process.exit(r.statusCode===200?0:3)}).on('error',()=>{clearTimeout(t);process.exit(1)})" \
      >/dev/null 2>&1
    rc=$?
    case "$rc" in
      0) printf 'yes\n' ;;
      3) printf 'optin\n' ;;
      *) printf 'no\n' ;;
    esac
    return
  fi
  printf 'unknown\n'
}

main() {
  PLATFORM=$(detect_platform)
  runner=$(detect_runner)
  RUNNER=${runner%%|*}
  RUNNER_CMD=${runner#*|}
  CHROME_CHANNEL=none
  CHROME_PATH=none
  USER_DATA_DIR=""
  CHROME_VERSION=unknown
  CHROME_MAJOR=0

  # Chrome discovery is unconditional: a missing runner is not evidence about
  # Chrome. STATUS precedence still tests RUNNER first, so this cannot change a
  # verdict — only the diagnostic fields.
  hit=$(find_chrome "$PLATFORM" | sed -n '1p')
  if [ -n "$hit" ]; then
    CHROME_CHANNEL=${hit%%|*}
    rest=${hit#*|}
    CHROME_PATH=${rest%%|*}
    USER_DATA_DIR=${rest#*|}
    CHROME_VERSION=$(chrome_version "$CHROME_PATH" "$PLATFORM")
    CHROME_MAJOR=$(major_of "$CHROME_VERSION")
  fi

  if [ "$CHROME_MAJOR" -ge "$CHROME_MIN_MAJOR" ]; then CHROME_OK=yes; else CHROME_OK=no; fi

  MCP_CONFIG_FILE=$(scan_config) || MCP_CONFIG_FILE=""
  if [ -n "$MCP_CONFIG_FILE" ]; then MCP_CONFIGURED=yes; else MCP_CONFIGURED=no; MCP_CONFIG_FILE=none; fi

  if chrome_running "$PLATFORM" "$CHROME_PATH"; then CHROME_RUNNING=yes; else CHROME_RUNNING=no; fi
  PORT_FILE_FOUND=no
  DEBUG_PORT=$(debug_port "$USER_DATA_DIR")
  if [ -n "$USER_DATA_DIR" ] && [ -f "$USER_DATA_DIR/DevToolsActivePort" ]; then
    port_line=$(sed -n '1p' "$USER_DATA_DIR/DevToolsActivePort" 2>/dev/null | tr -d '\r')
    case "$port_line" in
      ''|*[!0-9]*) : ;;
      *) PORT_FILE_FOUND=yes ;;
    esac
  fi
  if [ "$CHROME_RUNNING" = yes ]; then
    DEBUG_REACHABLE=$(debug_reachable "$DEBUG_PORT")
  else
    DEBUG_REACHABLE=no
  fi

  printf 'PLATFORM=%s\n' "$PLATFORM"
  printf 'RUNNER=%s\n' "$RUNNER"
  printf 'RUNNER_CMD=%s\n' "$RUNNER_CMD"
  printf 'CHROME_PATH=%s\n' "$CHROME_PATH"
  printf 'CHROME_CHANNEL=%s\n' "$CHROME_CHANNEL"
  printf 'CHROME_VERSION=%s\n' "$CHROME_VERSION"
  printf 'CHROME_MAJOR=%s\n' "$CHROME_MAJOR"
  printf 'CHROME_OK=%s\n' "$CHROME_OK"
  printf 'USER_DATA_DIR=%s\n' "$USER_DATA_DIR"
  printf 'CHROME_RUNNING=%s\n' "$CHROME_RUNNING"
  printf 'DEBUG_PORT=%s\n' "$DEBUG_PORT"
  printf 'DEBUG_REACHABLE=%s\n' "$DEBUG_REACHABLE"
  printf 'MCP_CONFIG_FILE=%s\n' "$MCP_CONFIG_FILE"
  printf 'MCP_CONFIGURED=%s\n' "$MCP_CONFIGURED"

  if [ "$RUNNER" = none ]; then
    printf 'STATUS=NODE_MISSING\n'
  elif [ "$CHROME_PATH" = none ]; then
    printf 'STATUS=CHROME_MISSING\n'
  elif [ "$CHROME_OK" = no ]; then
    printf 'STATUS=CHROME_TOO_OLD\n'
  elif [ "$MCP_CONFIGURED" = no ]; then
    printf 'STATUS=NOT_CONFIGURED\n'
  elif [ "$CHROME_RUNNING" = no ]; then
    printf 'STATUS=CHROME_NOT_RUNNING\n'
  elif [ "$DEBUG_REACHABLE" = yes ]; then
    printf 'STATUS=READY\n'
  elif [ "$DEBUG_REACHABLE" = optin ] && [ "$PORT_FILE_FOUND" = yes ]; then
    printf 'STATUS=READY\n'
  elif [ "$DEBUG_REACHABLE" = unknown ] && [ "$PORT_FILE_FOUND" = yes ]; then
    printf 'STATUS=READY\n'
  else
    printf 'STATUS=NEEDS_OPT_IN\n'
  fi
  return 0
}

[ "${CHROMEAGENT_LIB:-0}" = 1 ] || main
