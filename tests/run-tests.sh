#!/bin/sh
# Test harness for chromeagent-skill. POSIX sh, no dependencies.
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP_ROOT="$REPO_ROOT/tests/.tmp"
PASS=0
FAIL=0
CURRENT=""
HOST_PATH=${PATH-}

# Real utilities the scripts under test are allowed to rely on.
REAL_TOOLS="sh uname grep sed tr cat ls mkdir rm cp mv printf pwd dirname basename sort head tail wc env chmod mktemp ln cut sleep"

host_tool_path() {
  tool_name="$1"
  saved_ifs=${IFS- }
  IFS=:
  set -- $HOST_PATH
  IFS=$saved_ifs
  for path_entry do
    [ -n "$path_entry" ] || path_entry=.
    if [ -x "$path_entry/$tool_name" ] && [ ! -d "$path_entry/$tool_name" ]; then
      printf '%s\n' "$path_entry/$tool_name"
      return 0
    fi
  done
  return 1
}

link_host_tool() {
  tool_name="$1"
  host_tool=$(host_tool_path "$tool_name") || return 1
  linker=$(host_tool_path ln) || return 1
  "$linker" -sf "$host_tool" "$SANDBOX/bin/$tool_name"
}

sandbox_new() {
  SANDBOX=$(mktemp -d "$TMP_ROOT/sbXXXXXX")
  mkdir -p "$SANDBOX/bin" "$SANDBOX/home" "$SANDBOX/root" "$SANDBOX/project"
  for t in $REAL_TOOLS; do
    link_host_tool "$t" 2>/dev/null || true
  done
  HOME="$SANDBOX/home"
  PATH="$SANDBOX/bin"
  CHROMEAGENT_ROOT="$SANDBOX/root"
  export HOME PATH CHROMEAGENT_ROOT
  unset CHROMEAGENT_PLATFORM 2>/dev/null || true
}

# stub_cmd NAME BODY  — create a fake executable on the sandbox PATH.
stub_cmd() {
  rm -f "$SANDBOX/bin/$1"
  printf '#!/bin/sh\n%s\n' "$2" > "$SANDBOX/bin/$1"
  chmod +x "$SANDBOX/bin/$1"
}

run_preflight() {
  (cd "$SANDBOX/project" && sh "$REPO_ROOT/scripts/preflight.sh" 2>/dev/null)
}

run_setup() {
  (cd "$SANDBOX/project" && sh "$REPO_ROOT/scripts/setup-mcp.sh" "$@" 2>&1)
}

test_case() { CURRENT="$1"; sandbox_new; }

_ok()   { PASS=$((PASS+1)); printf 'ok   %s — %s\n' "$CURRENT" "$1"; }
_fail() { FAIL=$((FAIL+1)); printf 'FAIL %s — %s\n' "$CURRENT" "$1"; }

assert_kv() {
  # assert_kv KEY VALUE OUTPUT
  if printf '%s\n' "$3" | grep -q "^$1=$2$"; then _ok "$1=$2"
  else _fail "expected $1=$2, got: $(printf '%s\n' "$3" | grep "^$1=" || echo '<absent>')"; fi
}

assert_status() {
  # assert_status VALUE OUTPUT — also enforces exactly one STATUS line
  n=$(printf '%s\n' "$2" | grep -c '^STATUS=')
  if [ "$n" -ne 1 ]; then _fail "expected exactly 1 STATUS line, got $n"; return; fi
  assert_kv STATUS "$1" "$2"
}

assert_contains() {
  if printf '%s\n' "$2" | grep -q -- "$1"; then _ok "contains '$1'"
  else _fail "missing '$1' in output"; fi
}

assert_not_contains() {
  if printf '%s\n' "$2" | grep -q -- "$1"; then _fail "unexpected '$1' in output"
  else _ok "does not contain '$1'"; fi
}

finish() {
  printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}

mkdir -p "$TMP_ROOT"
rm -rf "$TMP_ROOT"/sb* 2>/dev/null || true

for f in "$REPO_ROOT"/tests/test_*.sh; do
  [ -f "$f" ] || continue
  printf '\n== %s ==\n' "$(basename "$f")"
  . "$f"
done

finish
