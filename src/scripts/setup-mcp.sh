#!/bin/sh
# setup-mcp.sh — write a project-scope chrome-devtools MCP entry.
# Usage: setup-mcp.sh --agent auto|claude|codex|opencode
#                     [--runner "<argv>"] [--channel beta|dev|canary]
#                     [--out-dir <dir>] [--no-redact]
set -u

AGENT=auto
RUNNER_OVERRIDE=""
CHANNEL=""
CHANNEL_SET=no
OUT_DIR_ARG=""
REDACT=yes
SEEN_AGENT=no
SEEN_RUNNER=no
SEEN_CHANNEL=no
SEEN_OUT_DIR=no
SEEN_NO_REDACT=no

# A value-taking option with no value left is a usage error, not a shift.
# POSIX `shift 2` with one argument remaining shifts nothing and returns 1, so
# an unguarded `shift 2` here spins this loop forever on a trailing --agent,
# --runner or --channel.
need_value() {
  # need_value OPTION REMAINING_ARGC
  if [ "$2" -lt 2 ]; then
    printf 'setup-mcp: %s requires a value\n' "$1" >&2
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --agent)
      [ "$SEEN_AGENT" = no ] || { printf 'setup-mcp: repeated option %s\n' "$1" >&2; exit 2; }
      SEEN_AGENT=yes
      need_value --agent $#; AGENT="$2"; shift 2
      ;;
    --runner)
      [ "$SEEN_RUNNER" = no ] || { printf 'setup-mcp: repeated option %s\n' "$1" >&2; exit 2; }
      SEEN_RUNNER=yes
      need_value --runner $#; RUNNER_OVERRIDE="$2"; shift 2
      ;;
    --channel)
      [ "$SEEN_CHANNEL" = no ] || { printf 'setup-mcp: repeated option %s\n' "$1" >&2; exit 2; }
      SEEN_CHANNEL=yes
      need_value --channel $#; CHANNEL="$2"; CHANNEL_SET=yes; shift 2
      ;;
    --out-dir)
      [ "$SEEN_OUT_DIR" = no ] || { printf 'setup-mcp: repeated option %s\n' "$1" >&2; exit 2; }
      SEEN_OUT_DIR=yes
      need_value --out-dir $#
      [ -n "$2" ] || { printf 'setup-mcp: --out-dir requires a value\n' >&2; exit 2; }
      OUT_DIR_ARG="$2"; shift 2
      ;;
    --no-redact)
      [ "$SEEN_NO_REDACT" = no ] || { printf 'setup-mcp: repeated option %s\n' "$1" >&2; exit 2; }
      SEEN_NO_REDACT=yes
      REDACT=no; shift
      ;;
    -h|--help) printf 'usage: setup-mcp.sh --agent auto|claude|codex|opencode [--runner "<argv>"] [--channel beta|dev|canary] [--out-dir <dir>] [--no-redact]\n'; exit 0 ;;
    *) printf 'setup-mcp: unknown option %s\n' "$1" >&2; exit 2 ;;
  esac
done

case "$AGENT" in
  auto|claude|codex|opencode) : ;;
  *) printf 'setup-mcp: unknown agent %s\n' "$AGENT" >&2; exit 2 ;;
esac

if [ "$CHANNEL_SET" = yes ]; then
  case "$CHANNEL" in
    beta|dev|canary) : ;;
    *) printf 'setup-mcp: invalid channel %s\n' "$CHANNEL" >&2; exit 2 ;;
  esac
fi

if [ "$SEEN_OUT_DIR" = yes ]; then
  out_dir_to_resolve="$OUT_DIR_ARG"
else
  out_dir_to_resolve=.
fi
if OUT_DIR=$(cd -- "$out_dir_to_resolve" 2>/dev/null && pwd); then
  :
else
  if [ "$SEEN_OUT_DIR" = yes ]; then
    printf 'setup-mcp: --out-dir %s is not a directory\n' "$out_dir_to_resolve" >&2
  else
    printf 'setup-mcp: %s is not a directory\n' "$out_dir_to_resolve" >&2
  fi
  exit 2
fi

# Prints "command|arg arg ..." — the launcher prefix.
runner_command() {
  if [ -n "$RUNNER_OVERRIDE" ]; then
    printf '%s|%s\n' "${RUNNER_OVERRIDE%% *}" "$(printf '%s' "$RUNNER_OVERRIDE" | cut -s -d' ' -f2-)"
    return
  fi
  if command -v npx >/dev/null 2>&1; then printf 'npx|-y\n'
  elif command -v bunx >/dev/null 2>&1; then printf 'bunx|\n'
  elif command -v pnpm >/dev/null 2>&1; then printf 'pnpm|dlx\n'
  else printf 'npx|-y\n'
  fi
}

# Prints the server args, space separated, package first.
mcp_args() {
  printf 'chrome-devtools-mcp@latest --autoConnect'
  [ "$REDACT" = yes ] && printf ' --redactNetworkHeaders'
  [ -n "$CHANNEL" ] && printf ' --channel %s' "$CHANNEL"
  printf '\n'
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Prints a JSON array of the full args list, e.g. ["-y","chrome-devtools-mcp@latest",...]
args_json() {
  prefix="$1"
  first=1
  printf '['
  for a in $prefix $(mcp_args); do
    [ -n "$a" ] || continue
    [ $first -eq 1 ] || printf ', '
    escaped=$(json_escape "$a")
    printf '"%s"' "$escaped"
    first=0
  done
  printf ']'
}

claude_snippet() {
  cmd="$1"; args="$2"
  escaped_cmd=$(json_escape "$cmd")
  cat <<EOF
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "$escaped_cmd",
      "args": $args
    }
  }
}
EOF
}

merge_json_with_node() {
  # merge_json_with_node FILE KEY_PATH COMMAND ARGS_JSON
  file="$1"; keypath="$2"; cmd="$3"; args="$4"
  node -e '
    const fs=require("fs");
    const path=require("path");
    const [file,keypath,cmd,args]=process.argv.slice(1);
    let doc={};
    try{doc=JSON.parse(fs.readFileSync(file,"utf8"))}catch(e){
      console.error("setup-mcp: "+file+" is not valid JSON; not modifying it");process.exit(3)}
    if(doc===null||typeof doc!=="object"||Array.isArray(doc)){
      console.error("setup-mcp: "+file+" must contain a JSON object at the root; not modifying it");process.exit(3)}
    if(doc[keypath]===null||typeof doc[keypath]!=="object"||Array.isArray(doc[keypath])) doc[keypath]={};
    doc[keypath]["chrome-devtools"]={command:cmd,args:JSON.parse(args)};
    const rendered=JSON.stringify(doc,null,2)+"\n";
    const dir=path.dirname(file);
    const base=path.basename(file);
    let tempFile;
    let tempCreated=false;
    let fd=-1;
    try{
      tempFile=path.join(dir,"."+base+".tmp-"+process.pid+"-"+Date.now()+"-"+Math.random().toString(16).slice(2));
      fd=fs.openSync(tempFile,"wx");
      tempCreated=true;
      fs.writeFileSync(fd,rendered,"utf8");
      fs.closeSync(fd);
      fd=-1;
      fs.renameSync(tempFile,file);
      tempFile=undefined;
    }catch(e){
      if(fd !== -1){try{fs.closeSync(fd)}catch(_){}}
      if(tempCreated){try{fs.unlinkSync(tempFile)}catch(_){}}
      throw e;
    }
  ' "$file" "$keypath" "$cmd" "$args"
}

write_claude() {
  rc=$(runner_command)
  cmd=${rc%%|*}
  prefix=${rc#*|}
  args=$(args_json "$prefix")
  target="$OUT_DIR/.mcp.json"

  if [ -L "$target" ]; then
    printf 'setup-mcp: refusing to write through symlink %s\n' "$target" >&2
    return 3
  fi

  if [ ! -f "$target" ]; then
    claude_snippet "$cmd" "$args" > "$target"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      printf 'setup-mcp: wrote %s\n' "$target"
      return 0
    fi
    printf 'setup-mcp: failed to write %s\n' "$target" >&2
    return 3
  fi

  if command -v node >/dev/null 2>&1; then
    if merge_json_with_node "$target" mcpServers "$cmd" "$args"; then
      printf 'setup-mcp: merged chrome-devtools into %s\n' "$target"
      return 0
    fi
    return 3
  fi

  printf 'setup-mcp: %s already exists and Node is unavailable, so it was left untouched.\n' "$target"
  printf 'setup-mcp: please merge this entry by hand:\n'
  claude_snippet "$cmd" "$args"
  return 3
}

# JSON array of the whole command line, for opencode's array-style "command".
command_json() {
  rc=$(runner_command)
  cmd=${rc%%|*}
  prefix=${rc#*|}
  first=1
  printf '['
  for a in "$cmd" $prefix $(mcp_args); do
    [ -n "$a" ] || continue
    [ $first -eq 1 ] || printf ', '
    escaped=$(json_escape "$a")
    printf '"%s"' "$escaped"
    first=0
  done
  printf ']'
}

opencode_snippet() {
  cat <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "mcp": {
    "chrome-devtools": {
      "type": "local",
      "enabled": true,
      "command": $1
    }
  }
}
EOF
}

merge_opencode_with_node() {
  file="$1"; command="$2"
  node -e '
    const fs=require("fs");
    const path=require("path");
    const [file,command]=process.argv.slice(1);
    let doc={};
    try{doc=JSON.parse(fs.readFileSync(file,"utf8"))}catch(e){
      console.error("setup-mcp: "+file+" is not valid JSON; not modifying it");process.exit(3)}
    if(doc===null||typeof doc!=="object"||Array.isArray(doc)){
      console.error("setup-mcp: "+file+" must contain a JSON object at the root; not modifying it");process.exit(3)}
    doc.$schema="https://opencode.ai/config.json";
    doc.mcp=doc.mcp&&typeof doc.mcp==="object"&&!Array.isArray(doc.mcp)?doc.mcp:{};
    doc.mcp["chrome-devtools"]={type:"local",enabled:true,command:JSON.parse(command)};
    const rendered=JSON.stringify(doc,null,2)+"\n";
    const dir=path.dirname(file);
    const base=path.basename(file);
    let tempFile;
    let tempCreated=false;
    let fd=-1;
    try{
      tempFile=path.join(dir,"."+base+".tmp-"+process.pid+"-"+Date.now()+"-"+Math.random().toString(16).slice(2));
      fd=fs.openSync(tempFile,"wx");
      tempCreated=true;
      fs.writeFileSync(fd,rendered,"utf8");
      fs.closeSync(fd);
      fd=-1;
      fs.renameSync(tempFile,file);
      tempFile=undefined;
    }catch(e){
      if(fd !== -1){try{fs.closeSync(fd)}catch(_) {}}
      if(tempCreated){try{fs.unlinkSync(tempFile)}catch(_) {}}
      throw e;
    }
  ' "$file" "$command"
}

write_opencode() {
  cj=$(command_json)
  target="$OUT_DIR/opencode.json"

  if [ -L "$target" ]; then
    printf 'setup-mcp: refusing to write through symlink %s\n' "$target" >&2
    return 3
  fi

  if [ ! -f "$target" ]; then
    opencode_snippet "$cj" > "$target"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      printf 'setup-mcp: wrote %s\n' "$target"
      return 0
    fi
    printf 'setup-mcp: failed to write %s\n' "$target" >&2
    return 3
  fi

  if command -v node >/dev/null 2>&1; then
    if merge_opencode_with_node "$target" "$cj"; then
      printf 'setup-mcp: merged chrome-devtools into %s\n' "$target"
      return 0
    fi
    return 3
  fi

  printf 'setup-mcp: %s already exists and Node is unavailable, so it was left untouched.\n' "$target"
  printf 'setup-mcp: please merge this entry by hand:\n'
  opencode_snippet "$cj"
  return 3
}

write_codex() {
  rc=$(runner_command)
  cmd=${rc%%|*}
  prefix=${rc#*|}
  set -- mcp add chrome-devtools -- "$cmd" $prefix $(mcp_args)
  printf 'setup-mcp: Codex has no project-scoped MCP config; this writes to your GLOBAL Codex config (~/.codex/config.toml).\n'
  printf "setup-mcp: this is Codex's global config, not a project config.\n"
  if command -v codex >/dev/null 2>&1; then
    codex "$@" && {
      printf 'setup-mcp: registered chrome-devtools with the Codex CLI\n'
      return 0
    }
    printf 'setup-mcp: "codex %s" failed; run it yourself:\n' "$*"
    printf 'codex %s\n' "$*"
    return 3
  fi
  printf 'setup-mcp: the codex CLI is not on PATH. Run this yourself:\n'
  printf 'codex %s\n' "$*"
  return 3
}

# Prints the agents in play, space separated.
detect_agents() {
  found=""
  { [ -f "$OUT_DIR/.mcp.json" ] || [ -d "$OUT_DIR/.claude" ]; } && found="$found claude"
  [ -f "$OUT_DIR/opencode.json" ] && found="$found opencode"
  [ -n "$found" ] || found=" claude"
  printf '%s\n' "${found# }"
}

record_rc() {
  rc_final_candidate="$1"
  [ "$rc_final_candidate" -gt "$rc_final" ] && rc_final="$rc_final_candidate"
}

rc_final=0
case "$AGENT" in
  claude)
    write_claude || record_rc "$?"
    ;;
  opencode)
    write_opencode || record_rc "$?"
    ;;
  codex)
    write_codex || record_rc "$?"
    ;;
  auto)
    if [ -f "$HOME/.codex/config.toml" ] || command -v codex >/dev/null 2>&1; then
      printf 'setup-mcp: codex detected but not configured; run --agent codex to update your global Codex config.\n'
    fi
    for a in $(detect_agents); do
      case "$a" in
        claude) write_claude || record_rc "$?" ;;
        opencode) write_opencode || record_rc "$?" ;;
      esac
    done
    ;;
esac
printf 'setup-mcp: restart your agent so it loads the MCP server.\n'
exit "$rc_final"
