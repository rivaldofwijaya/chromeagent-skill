# Setup reference

The full contract of `setup-mcp.sh` and `setup-mcp.ps1`. SKILL.md's `NOT_CONFIGURED` row is enough
for a stable Chrome; read this for a non-stable channel, a non-zero exit, or any flag beyond
`--agent`.

## Target

Name the agent when you know it: `--agent claude` writes `.mcp.json`, `--agent opencode` writes `opencode.json`. For `auto`, markers in the resolved output directory select the target: `.mcp.json` or `.claude/` selects Claude Code, and `opencode.json` selects OpenCode. With no marker, `auto` falls back to Claude Code, which is wrong for an OpenCode project that has no `opencode.json` yet.

The runner is the first of `npx`, `bunx`, `pnpm dlx`, or a globally installed `chrome-devtools-mcp` found on `PATH`, the same order preflight reports in `RUNNER`. The global binary, detected or named with `--runner`, is written without the package spec: it takes server flags only, and its version is whatever is installed, not the pin.

Setup merges into an existing config rather than replacing it. For the POSIX existing-JSON/no-Node case described below, hand the manual-merge snippet to the user rather than overwriting the file to get past it. Other exit-3 failures need diagnosis; they do not promise a snippet.

An existing `chrome-devtools` entry that lacks `--autoConnect` is treated as a deliberate fallback (`--browserUrl`, `--isolated`): setup exits 3 and leaves it alone. `--force` (`-Force`) replaces it; pass it only when the user has asked to return to `--autoConnect`.

A successful setup prints the absolute path it wrote; check that path against the project root. `--out-dir` and `-OutDir` require an existing directory; neither script creates it.

## Commands

Default invocation, from the project root: `sh /path/to/chromeagent-skill/scripts/setup-mcp.sh --agent auto`, or on native Windows `pwsh -File /path/to/chromeagent-skill/scripts/setup-mcp.ps1 -Agent auto`.

If preflight reports `CHROME_CHANNEL` as `beta`, `dev`, or `canary`, pass that exact reported value through.
On POSIX use `sh /path/to/chromeagent-skill/scripts/setup-mcp.sh --agent auto --channel "$CHROME_CHANNEL"`;
on native Windows use `pwsh -File /path/to/chromeagent-skill/scripts/setup-mcp.ps1 -Agent auto -Channel $CHROME_CHANNEL`.
A non-stable Chrome keeps its
profile in a different directory and `--autoConnect` must be told which one. Omit the channel flag for
`stable`.

If preflight reports `CHROME_CHANNEL=chromium`, do not pass `--channel chromium` or `-Channel chromium`:
neither setup CLI accepts that value. Offer the `--browserUrl` fallback in SKILL.md, using a Chromium
instance the user launches with remote debugging, or ask the user to use a supported Chrome channel.

## Flags and exit codes

The POSIX setup CLI accepts agents `auto|claude|opencode`, plus `--runner "<argv>"`,
`--channel beta|dev|canary`, `--out-dir <dir>`, `--no-redact`, and `--force`. The native PowerShell spelling is `-Agent`, `-Runner`, `-Channel`, `-NoRedact`, and `-Force`; add `-OutDir <dir>` for the output-directory override. It accepts the same three channel values. Both setup CLIs use exit 0
for success and exit 2 for bad usage or invalid agent/channel values. Exit 3 is a setup failure on
either platform, not a preflight verdict and not synonymous with manual merge.

The help output is:

`usage: setup-mcp.sh --agent auto|claude|opencode [--runner "<argv>"] [--channel beta|dev|canary] [--out-dir <dir>] [--no-redact] [--force]`

`usage: setup-mcp.ps1 -Agent auto|claude|opencode [-Runner "<argv>"] [-Channel beta|dev|canary] [-OutDir <dir>] [-NoRedact] [-Force]`

The setup defaults are exactly `--autoConnect`, `--redactNetworkHeaders`, `--no-performance-crux`,
`--no-file-navigations`, `--no-usage-statistics`, in that order; `--no-redact` (or `-NoRedact`) drops the redaction flag, and a channel flag follows those
defaults.

## Merging an existing config

For `setup-mcp.sh`, an existing config with no Node available for JSON merging is left untouched, a
manual-merge snippet is printed, and the command exits 3. Invalid JSON during a Node merge also
exits 3. `setup-mcp.ps1` always merges an existing config natively with its PowerShell JSON parser;
invalid existing JSON can also exit 3, but it does not use the sh manual-merge branch. This
cross-platform difference is deliberate.
