#!/bin/sh
# Test harness for chromeagent-skill. POSIX sh, no dependencies.
set -u

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP_ROOT="$REPO_ROOT/dev/tests/.tmp"
PASS=0
FAIL=0
SKIP=0
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
  if [ -n "$DLL_DIR" ]; then
    host_dir=$(dirname "$host_tool")
    if [ ! -f "$host_dir/msys-2.0.dll" ] && [ ! -f "$host_dir/cygwin1.dll" ]; then
      # A native Windows program (pwsh, node): MSYS's `ln -s` would copy the
      # bare .exe away from the runtime files beside it, so exec it in place.
      rm -f "$SANDBOX/bin/$tool_name"
      printf '#!/bin/sh\nexec "%s" "$@"\n' "$host_tool" > "$SANDBOX/bin/$tool_name"
      chmod +x "$SANDBOX/bin/$tool_name"
      return
    fi
  fi
  "$linker" -sf "$host_tool" "$SANDBOX/bin/$tool_name"
}

# MSYS2 / Git Bash / Cygwin: `ln -s` copies by default, and a copied tool
# still needs the runtime DLLs beside the host binaries. Windows resolves DLLs
# through PATH, so put a directory holding only those DLLs, no executables, on
# the sandbox PATH; command lookup stays confined to $SANDBOX/bin.
DLL_DIR=""
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    DLL_DIR="$TMP_ROOT/dll"
    if [ ! -d "$DLL_DIR" ]; then
      host_sh=$(host_tool_path sh) || { echo "run-tests: no host sh" >&2; exit 1; }
      host_bin=$(dirname "$host_sh")
      rm -rf "$DLL_DIR.partial"
      mkdir -p "$DLL_DIR.partial" &&
        cp "$host_bin"/*.dll "$DLL_DIR.partial"/ &&
        mv "$DLL_DIR.partial" "$DLL_DIR" ||
        { echo "run-tests: cannot stage runtime DLLs from $host_bin" >&2; exit 1; }
    fi
    # Resolved now, while the host PATH is still in force.
    HOST_SH_WIN=$(cygpath -w "$(host_tool_path sh)") ||
      { echo "run-tests: cannot resolve the host sh" >&2; exit 1; }
    ICACLS=$(host_tool_path icacls) || { echo "run-tests: no icacls" >&2; exit 1; }
    ;;
esac

# win_dir DIR — DIR in Windows form (D:/x/y) on MSYS; unchanged elsewhere.
win_dir() {
  if [ -n "$DLL_DIR" ]; then (cd "$1" && pwd -W); else printf '%s\n' "$1"; fi
}

# ps_arg PATH — PATH as a native program such as pwsh receives it: MSYS
# rewrites a /d/x argument to D:/x. Only the parent directory has to exist.
ps_arg() {
  if [ -n "$DLL_DIR" ]; then printf '%s/%s\n' "$(win_dir "$(dirname "$1")")" "$(basename "$1")"
  else printf '%s\n' "$1"; fi
}

# ps_path PATH — PATH as PowerShell prints a resolved path: Windows separators
# on Windows. Compare with assert_contains_text, since \ is a grep escape.
ps_path() {
  if [ -n "$DLL_DIR" ]; then ps_arg "$1" | tr '/' '\\'; else printf '%s\n' "$1"; fi
}

# deny_writes DIR / allow_writes DIR — make DIR refuse new entries, and undo
# it. chmod does this on Unix; on Windows chmod does not reach the ACL, so a
# deny entry for the current user does the same job. deny_writes exits 1, with
# DIR left writable, when the denial does not hold: root ignores chmod, and an
# elevated Windows process (a CI runner) gets backup privileges from MSYS that
# bypass the ACL. Callers skip rather than report a false failure.
deny_writes() {
  if [ -n "$DLL_DIR" ]; then
    MSYS2_ARG_CONV_EXCL='*' "$ICACLS" "$(win_dir "$1")" /deny "$USERNAME:(WD,AD,DC)" >/dev/null
  else
    chmod 500 "$1"
  fi
  if ( : > "$1/.deny-writes-probe" ) 2>/dev/null; then
    rm -f "$1/.deny-writes-probe"
    allow_writes "$1"
    return 1
  fi
}
allow_writes() {
  if [ -n "$DLL_DIR" ]; then
    MSYS2_ARG_CONV_EXCL='*' "$ICACLS" "$(win_dir "$1")" /remove:d "$USERNAME" >/dev/null
  else
    chmod 700 "$1"
  fi
}

# make_symlink TARGET LINK — a real symlink, or exit 1 where the platform will
# not make one: MSYS `ln -s` silently copies unless told otherwise, and Windows
# grants symlink creation only to admins or with Developer Mode on.
make_symlink() {
  MSYS=winsymlinks:nativestrict ln -s "$1" "$2" 2>/dev/null && [ -L "$2" ]
}

sandbox_new() {
  # Every path below is "$SANDBOX/…": an empty SANDBOX would aim the stubs,
  # chmods, and rms at /bin, /root, and /project, so stop instead.
  SANDBOX=$(mktemp -d "$TMP_ROOT/sbXXXXXX") && [ -n "$SANDBOX" ] && [ -d "$SANDBOX" ] ||
    { echo "run-tests: cannot create a sandbox under $TMP_ROOT" >&2; exit 1; }
  mkdir -p "$SANDBOX/bin" "$SANDBOX/home" "$SANDBOX/root" "$SANDBOX/project" ||
    { echo "run-tests: cannot populate sandbox $SANDBOX" >&2; exit 1; }
  if [ -n "${TOOL_TEMPLATE:-}" ]; then
    # One copy instead of a process per tool: about 0.4s against 5s on Windows.
    "$HOST_CP" -p "$TOOL_TEMPLATE"/* "$SANDBOX/bin/" ||
      { echo "run-tests: cannot copy tools into $SANDBOX" >&2; exit 1; }
  else
    for t in $REAL_TOOLS; do
      link_host_tool "$t" 2>/dev/null || true
    done
  fi
  HOME="$SANDBOX/home"
  PATH="$SANDBOX/bin${DLL_DIR:+:$DLL_DIR}"
  CHROMEAGENT_ROOT="$SANDBOX/root"
  export HOME PATH CHROMEAGENT_ROOT
  if [ -n "$DLL_DIR" ]; then
    # Native Windows programs take the home directory from USERPROFILE, not
    # HOME; left alone it is the developer's real profile.
    USERPROFILE=$(win_dir "$HOME")
    export USERPROFILE
  fi
  unset CHROMEAGENT_PLATFORM 2>/dev/null || true
  # preflight reads Claude Code's config from here when it is set; a host value
  # would point the probe at the developer's real ~/.claude.json.
  unset CLAUDE_CONFIG_DIR 2>/dev/null || true
  # Claude Code sets this in its shells, and under it preflight counts the
  # plugin manifest beside the scripts; a run from inside a session must not.
  unset CLAUDECODE 2>/dev/null || true
}

# stub_cmd NAME BODY  — create a fake executable on the sandbox PATH.
stub_cmd() {
  rm -f "$SANDBOX/bin/$1" "$SANDBOX/bin/$1.cmd"
  printf '#!/bin/sh\n%s\n' "$2" > "$SANDBOX/bin/$1"
  chmod +x "$SANDBOX/bin/$1"
  if [ -n "$DLL_DIR" ]; then
    # PowerShell on Windows cannot run an extensionless script; it runs
    # NAME.cmd, as with the real npx.cmd, so hand that on to the sh stub.
    printf '@"%s" "%%~dp0%s" %%*\r\n' "$HOST_SH_WIN" "$1" > "$SANDBOX/bin/$1.cmd"
  fi
}

run_preflight() {
  (cd "$SANDBOX/project" && sh "$REPO_ROOT/skills/chromeagent/scripts/preflight.sh" 2>/dev/null)
}

run_setup() {
  (cd "$SANDBOX/project" && sh "$REPO_ROOT/skills/chromeagent/scripts/setup-mcp.sh" "$@" 2>&1)
}

test_case() { CURRENT="$1"; sandbox_new; }

_ok()   { PASS=$((PASS+1)); printf 'ok   %s — %s\n' "$CURRENT" "$1"; }
_fail() { FAIL=$((FAIL+1)); printf 'FAIL %s — %s\n' "$CURRENT" "$1"; }
_skip() { SKIP=$((SKIP+1)); printf 'skip %s — %s\n' "$CURRENT" "$1"; }

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

assert_contains_text() {
  # Fixed-string match, for expected text holding regex characters such as \.
  if printf '%s\n' "$2" | grep -q -F -- "$1"; then _ok "contains '$1'"
  else _fail "missing '$1' in output"; fi
}

assert_not_contains() {
  if printf '%s\n' "$2" | grep -q -- "$1"; then _fail "unexpected '$1' in output"
  else _ok "does not contain '$1'"; fi
}

finish() {
  printf '\n%s passed, %s failed, %s skipped\n' "$PASS" "$FAIL" "$SKIP"
  [ "$FAIL" -eq 0 ]
}

mkdir -p "$TMP_ROOT"
if [ -n "$DLL_DIR" ]; then
  # An interrupted run can leave a deny_writes entry behind, which would make
  # the sandbox undeletable; reset the ACLs to inherited ones first.
  for sb in "$TMP_ROOT"/sb*; do
    [ -d "$sb" ] && MSYS2_ARG_CONV_EXCL='*' "$ICACLS" "$(win_dir "$sb")" /reset /T /Q >/dev/null 2>&1
  done
fi
rm -rf "$TMP_ROOT"/sb* 2>/dev/null || true

TOOL_TEMPLATE=""
if [ -n "$DLL_DIR" ]; then
  # Process creation is slow on Windows, so link the real tools once, into a
  # template every sandbox copies, rebuilt each run so it tracks the host.
  HOST_CP=$(host_tool_path cp) || { echo "run-tests: no host cp" >&2; exit 1; }
  rm -rf "$TMP_ROOT/tools"
  mkdir -p "$TMP_ROOT/tools/bin" || { echo "run-tests: cannot build the tool template" >&2; exit 1; }
  SANDBOX="$TMP_ROOT/tools"
  for t in $REAL_TOOLS; do
    link_host_tool "$t" 2>/dev/null || true
  done
  SANDBOX=""
  TOOL_TEMPLATE="$TMP_ROOT/tools/bin"
fi

# run-tests.sh [test_file.sh ...] — every test file by default, or just those named.
if [ "$#" -eq 0 ]; then set -- "$REPO_ROOT"/dev/tests/test_*.sh; fi
for f do
  case "$f" in */*) ;; *) f="$REPO_ROOT/dev/tests/$f" ;; esac
  [ -f "$f" ] || { echo "run-tests: no such test file: $f" >&2; exit 2; }
  printf '\n== %s ==\n' "$(basename "$f")"
  . "$f"
done

finish
