#!/bin/sh
# setup-mcp.sh — write a project-scope chrome-devtools MCP entry.
# Usage: setup-mcp.sh --agent auto|claude|opencode
#                     [--runner "<argv>"] [--channel beta|dev|canary]
#                     [--out-dir <dir>] [--no-redact]
set -u

# The server version every config is written with. Pinned rather than @latest:
# npx would otherwise fetch and run whatever was last published, at every
# launch, inside a process attached to the user's real browser profile. Keep it
# equal to the pin in .claude-plugin/plugin.json and setup-mcp.ps1; the suite
# checks that they agree.
CDM_PACKAGE=chrome-devtools-mcp@1.12.0

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
    -h|--help) printf 'usage: setup-mcp.sh --agent auto|claude|opencode [--runner "<argv>"] [--channel beta|dev|canary] [--out-dir <dir>] [--no-redact]\n'; exit 0 ;;
    *) printf 'setup-mcp: unknown option %s\n' "$1" >&2; exit 2 ;;
  esac
done

case "$AGENT" in
  auto|claude|opencode) : ;;
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
  printf '%s --autoConnect' "$CDM_PACKAGE"
  [ "$REDACT" = yes ] && printf ' --redactNetworkHeaders'
  # Performance traces otherwise send the traced URLs to the CrUX API; with a
  # real profile those URLs can be private.
  printf ' --no-performance-crux'
  # Navigations the agent performs cannot open file: URLs, so a page that
  # talks the agent into it cannot read local files through the browser.
  printf ' --no-file-navigations'
  # Google otherwise collects usage data about the agent's tool calls.
  printf ' --no-usage-statistics'
  [ -n "$CHANNEL" ] && printf ' --channel %s' "$CHANNEL"
  printf '\n'
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Prints a JSON array of the full args list, e.g. ["-y","chrome-devtools-mcp@1.12.0",...]
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

# merge_json_with_node FILE KEY ENTRY_JSON [SCHEMA_URL]
# Sets FILE's KEY["chrome-devtools"] to ENTRY_JSON, keeping everything else, and
# sets "$schema" when SCHEMA_URL is given. Writes through a temp file and a
# rename, so a failure leaves the original untouched.
merge_json_with_node() {
  node -e '
    const fs=require("fs");
    const path=require("path");
    const [file,key,entry,schema]=process.argv.slice(1);
    let doc={};
    try{doc=JSON.parse(fs.readFileSync(file,"utf8"))}catch(e){
      console.error("setup-mcp: "+file+" is not valid JSON; not modifying it");process.exit(3)}
    if(doc===null||typeof doc!=="object"||Array.isArray(doc)){
      console.error("setup-mcp: "+file+" must contain a JSON object at the root; not modifying it");process.exit(3)}
    if(schema)doc.$schema=schema;
    if(doc[key]===null||typeof doc[key]!=="object"||Array.isArray(doc[key])) doc[key]={};
    doc[key]["chrome-devtools"]=JSON.parse(entry);
    const rendered=JSON.stringify(doc,null,2)+"\n";
    const tempFile=path.join(path.dirname(file),
      "."+path.basename(file)+".tmp-"+process.pid+"-"+Date.now()+"-"+Math.random().toString(16).slice(2));
    let fd=-1;
    let created=false;
    try{
      fd=fs.openSync(tempFile,"wx");
      created=true;
      fs.writeFileSync(fd,rendered,"utf8");
      fs.closeSync(fd);
      fd=-1;
      fs.renameSync(tempFile,file);
    }catch(e){
      if(fd!==-1){try{fs.closeSync(fd)}catch(_){}}
      if(created){try{fs.unlinkSync(tempFile)}catch(_){}}
      throw e;
    }
  ' "$@"
}

# write_json_config TARGET KEY ENTRY_JSON SNIPPET [SCHEMA_URL]
# Writes SNIPPET to a new TARGET, or merges ENTRY_JSON into an existing one.
# Without node an existing file is left alone and SNIPPET is printed for a
# manual merge.
write_json_config() {
  target="$1"; key="$2"; entry="$3"; snippet="$4"; schema="${5:-}"

  if [ -L "$target" ]; then
    printf 'setup-mcp: refusing to write through symlink %s\n' "$target" >&2
    return 3
  fi

  if [ ! -f "$target" ]; then
    if printf '%s\n' "$snippet" > "$target"; then
      printf 'setup-mcp: wrote %s\n' "$target"
      return 0
    fi
    printf 'setup-mcp: failed to write %s\n' "$target" >&2
    return 3
  fi

  if command -v node >/dev/null 2>&1; then
    if merge_json_with_node "$target" "$key" "$entry" $schema; then
      printf 'setup-mcp: merged chrome-devtools into %s\n' "$target"
      return 0
    fi
    return 3
  fi

  printf 'setup-mcp: %s already exists and Node is unavailable, so it was left untouched.\n' "$target"
  printf 'setup-mcp: please merge this entry by hand:\n'
  printf '%s\n' "$snippet"
  return 3
}

write_claude() {
  rc=$(runner_command)
  cmd=${rc%%|*}
  prefix=${rc#*|}
  args=$(args_json "$prefix")
  entry=$(printf '{"command": "%s", "args": %s}' "$(json_escape "$cmd")" "$args")
  write_json_config "$OUT_DIR/.mcp.json" mcpServers "$entry" "$(claude_snippet "$cmd" "$args")"
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

write_opencode() {
  cj=$(command_json)
  entry=$(printf '{"type": "local", "enabled": true, "command": %s}' "$cj")
  write_json_config "$OUT_DIR/opencode.json" mcp "$entry" "$(opencode_snippet "$cj")" \
    https://opencode.ai/config.json
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
  auto)
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
