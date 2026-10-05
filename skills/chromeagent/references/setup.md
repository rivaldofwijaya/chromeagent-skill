# Setup reference

The full contract of `setup-mcp.sh` and `setup-mcp.ps1`. SKILL.md's `NOT_CONFIGURED` row is enough
for a stable Chrome under Claude Code or OpenCode; read this for a non-stable channel, Codex, a
non-zero exit, or any flag beyond `--agent`.

## Target and scope

`auto` configures project-scoped agents only (Claude Code and OpenCode); Codex requires an explicit `--agent codex` and writes the user's global `~/.codex/config.toml`.

For `auto`, markers in the resolved output directory select the project target: `.mcp.json` or `.claude/` selects Claude Code, and `opencode.json` selects OpenCode. With no marker, `auto` falls back to Claude Code. It never writes Codex's global config. When Codex is present, POSIX prints `setup-mcp: codex detected but not configured; run --agent codex to update your global Codex config.` and PowerShell prints `setup-mcp: codex detected but not configured; run -Agent codex to update your global Codex config.`

Codex configuration is global: it applies to every project on the machine, so say that you are writing it before you do. Setup merges into an existing config rather than replacing it. For the POSIX existing-JSON/no-Node case described below, hand the manual-merge snippet to the user rather than overwriting the file to get past it. Other exit-3 failures need diagnosis; they do not promise a snippet.

For project targets: A successful setup prints the absolute path it wrote; check that path against the project root. For Codex there is no printed path to check: success is the line `setup-mcp: registered chrome-devtools with the Codex CLI` and exit 0, and the file written is `~/.codex/config.toml`, not the project root; the output override does not change its global scope. `--out-dir` and `-OutDir` require an existing directory; neither script creates it.

## Commands

Default invocations, from the project root:

- Claude Code or OpenCode: `sh /path/to/chromeagent-skill/scripts/setup-mcp.sh --agent auto`, or on native Windows `pwsh -File /path/to/chromeagent-skill/scripts/setup-mcp.ps1 -Agent auto`.
- Codex: `sh /path/to/chromeagent-skill/scripts/setup-mcp.sh --agent codex`, or on native Windows `pwsh -File /path/to/chromeagent-skill/scripts/setup-mcp.ps1 -Agent codex`.

If preflight reports `CHROME_CHANNEL` as `beta`, `dev`, or `canary`, pass that exact reported value through.
For Claude Code or OpenCode, on POSIX use `sh /path/to/chromeagent-skill/scripts/setup-mcp.sh --agent auto --channel "$CHROME_CHANNEL"`;
on native Windows use `pwsh -File /path/to/chromeagent-skill/scripts/setup-mcp.ps1 -Agent auto -Channel $CHROME_CHANNEL`.
Under Codex use `sh /path/to/chromeagent-skill/scripts/setup-mcp.sh --agent codex --channel "$CHROME_CHANNEL"`
or `pwsh -File /path/to/chromeagent-skill/scripts/setup-mcp.ps1 -Agent codex -Channel $CHROME_CHANNEL`.
A non-stable Chrome keeps its
profile in a different directory and `--autoConnect` must be told which one. Omit the channel flag for
`stable`.

If preflight reports `CHROME_CHANNEL=chromium`, do not pass `--channel chromium` or `-Channel chromium`:
neither setup CLI accepts that value. Offer the `--browserUrl` fallback in SKILL.md, using a Chromium
instance the user launches with remote debugging, or ask the user to use a supported Chrome channel.

## Flags and exit codes

The POSIX setup CLI accepts agents `auto|claude|codex|opencode`, plus `--runner "<argv>"`,
`--channel beta|dev|canary`, `--out-dir <dir>`, and `--no-redact`. The native PowerShell spelling is `-Agent`, `-Runner`, `-Channel`, and `-NoRedact`; add `-OutDir <dir>` for the output-directory override. It accepts the same three channel values. Both setup CLIs use exit 0
for success and exit 2 for bad usage or invalid agent/channel values. Exit 3 is a setup failure on
either platform, not a preflight verdict and not synonymous with manual merge.

The help output is:

`usage: setup-mcp.sh --agent auto|claude|codex|opencode [--runner "<argv>"] [--channel beta|dev|canary] [--out-dir <dir>] [--no-redact]`

`usage: setup-mcp.ps1 -Agent auto|claude|codex|opencode [-Runner "<argv>"] [-Channel beta|dev|canary] [-OutDir <dir>] [-NoRedact]`

The setup defaults are exactly `--autoConnect`, `--redactNetworkHeaders`, `--no-performance-crux`, in
that order; `--no-redact` (or `-NoRedact`) drops the redaction flag, and a channel flag follows those
defaults.

## Merging an existing config

For `setup-mcp.sh`, an existing config with no Node available for JSON merging is left untouched, a
manual-merge snippet is printed, and the command exits 3. Invalid JSON during a Node merge and Codex
registration failures also exit 3. `setup-mcp.ps1` always merges an existing config natively with its
PowerShell JSON parser; invalid existing JSON and Codex registration failures can also exit 3, but it
does not use the sh manual-merge branch. This cross-platform difference is deliberate.
