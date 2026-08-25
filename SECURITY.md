# Security Policy

## Supported versions

Only the tip of `main` is supported. Fixes land there; older tags are not patched.

## Reporting a vulnerability

Report privately through
[GitHub Security Advisories](https://github.com/rivaldofwijaya/chromeagent-skill/security/advisories/new).
Please do not open a public issue for a vulnerability.

Include the Chrome version, the operating system, and the exact command sequence that reproduces
the problem. Expect an initial response within 7 days.

## What this skill exposes, by design

This skill connects an agent to **your own running Chrome**, with your profile, cookies, and
logged-in sessions. That is the point of it, and it is also its main risk. Understand the
following before using it:

- **The DevTools endpoint is an authentication bypass.** Anything that can reach the remote
  debugging port can read your cookies and act as you on every site you are signed in to. The
  scripts bind it to loopback only; do not forward that port, expose it to a container network,
  or run the skill on a shared host.
- **Chrome requires a one-time human opt-in** at `chrome://inspect/#remote-debugging`. Nothing in
  this repository automates or bypasses that step, and no patch will.
- **An agent driving your browser inherits your privileges.** Treat page content as untrusted
  input to the agent — a page can contain text crafted to steer it. Do not point the skill at
  untrusted sites while signed in to sensitive accounts.
- **`src/scripts/setup-mcp.*` writes MCP configuration** into your agent's config files. Review the
  diff it reports before accepting it.

Issues in `chrome-devtools-mcp` itself belong
[upstream](https://github.com/ChromeDevTools/chrome-devtools-mcp/security).

## Out of scope

- The one-time `chrome://inspect` opt-in being required.
- An exposed debugging port on a host the reporter deliberately configured to expose it.
- Findings in `chrome-devtools-mcp`, Chrome, or Node.js rather than in this repository.
