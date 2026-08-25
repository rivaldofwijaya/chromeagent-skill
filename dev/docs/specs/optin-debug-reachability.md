# Spec: detect Chrome's opt-in debugging endpoint

Status: implemented — landed 2026-08-12 in 66f42a8, 40ea059, ccb60c4, 3abb29d.
This is a record of a design that shipped, not work to be executed. See §8 for a later
correction to §2 goal 4.
Scope: `scripts/preflight.sh`, `scripts/preflight.ps1`, `tests/test_preflight.sh`,
`tests/test_ps1_contract.sh`, `SKILL.md`, `references/troubleshooting.md`

## 1. Problem

Preflight reports `STATUS=NEEDS_OPT_IN` for a Chrome that has **already** been opted in via
`chrome://inspect/#remote-debugging`. The skill then tells the user to go tick a box that is
already ticked, which is a dead end: re-running preflight produces the same verdict forever.

### Observed evidence

Reproduced on macOS, Chrome 151 stable, opt-in granted, `chrome://inspect` showing
"Server running at: 127.0.0.1:9222":

```
$ lsof -nP -iTCP:9222 -sTCP:LISTEN
Google  39923 … TCP 127.0.0.1:9222 (LISTEN)

$ curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:9222/json/version
404
$ for p in /json /json/list /json/protocol; do curl … "$p"; done
404 404 404

$ cat "$HOME/Library/Application Support/Google/Chrome/DevToolsActivePort"
9222
/devtools/browser/7dceb011-9401-472e-ac2d-a264a3653609

$ curl … -H 'Connection: Upgrade' -H 'Upgrade: websocket' … \
    http://127.0.0.1:9222/devtools/browser/7dceb011-…
(connection accepted and held open until the client timeout — the upgrade succeeds)
```

Meanwhile `chrome-devtools-mcp` attached and drove the browser successfully.

### Root cause

The opt-in debugging server is **WebSocket-only**. It exposes exactly the browser endpoint named
on line 2 of `DevToolsActivePort` and serves `404` for every HTTP path, including the entire
`/json/*` family. This is a deliberate narrowing versus the classic
`--remote-debugging-port=<n>` launch, which does serve `/json/version` with `200`.

`preflight.sh:205` probes with:

```sh
curl -fsS -m 2 "http://127.0.0.1:$1/json/version" >/dev/null 2>&1 && …
```

`-f` makes curl exit non-zero on any 4xx. So **a healthy opt-in server (404) and a dead port
(connection refused) both collapse to `DEBUG_REACHABLE=no`** — the probe cannot tell "nothing is
listening" from "something is listening but does not speak this dialect".

`preflight.ps1:75` has the same defect by a different mechanism: `Invoke-WebRequest` throws on
non-2xx, and the `catch` returns `no` without inspecting whether a response arrived at all.

The existing safety net at `preflight.sh:294` only rescues `DEBUG_REACHABLE=unknown` (the
no-probe-tool case). It never fires here, because a machine with `curl` gets a definite-looking
`no`. `PORT_FILE_FOUND=yes` is therefore ignored precisely when it holds the correct answer.

### Why it was not caught

`tests/test_preflight.sh:250` stubs the failure as `stub_cmd curl 'exit 7'` — a *transport*
failure. There is no fixture for a server that answers with a non-200 status, so the conflation
is invisible to the suite.

### Blast radius

Only the fallback path. `SKILL.md` §1 tells the agent to call `list_pages` first and use that as
the real check, so a session with the MCP tools loaded never consults preflight. The bug bites
when the tools are absent or `list_pages` failed for an unrelated reason — exactly the moment the
user is relying on preflight to be right — and it emits a confidently wrong instruction.

## 2. Goals

1. A Chrome that has been opted in reports `STATUS=READY`.
2. A Chrome that has not been opted in still reports `STATUS=NEEDS_OPT_IN`. No weakening: the
   fix must not turn the opt-in gate into a rubber stamp.
3. The two launch modes stay distinguishable in the output, because they differ in what an agent
   can do afterwards (see §3.2).
4. Behaviour is identical on POSIX and native Windows.
5. The 15-key output contract is unchanged in **key set and order**.

### Non-goals

- Performing the opt-in. It is a deliberate human gate; nothing here automates it.
- Probing the WebSocket endpoint by actually completing a handshake. Preflight stays a
  shell/PowerShell script with no WS client; a TCP-level answer plus the port file is sufficient
  evidence, and the real connection remains the final test.
- Any change to `setup-mcp.sh` / `setup-mcp.ps1`.

## 3. Design

### 3.1 Widen the probe's answer domain

`DEBUG_REACHABLE` gains a fourth value. The domain becomes:

| Value | Meaning | Evidence |
|---|---|---|
| `yes` | Classic HTTP DevTools endpoint | `/json/version` answered `200` |
| `optin` | Opt-in WebSocket-only endpoint | the port answered HTTP with any non-200 status |
| `no` | Nothing is listening | no response: refused, reset, or timed out |
| `unknown` | Could not probe | no `curl`, `wget`, or `node` available |

The distinction that matters is **"did anything answer"**, not "was the answer 200". The current
code asks the second question and reports it as the first.

### 3.2 Why `optin` is a distinct value, not folded into `yes`

Because the two modes are not interchangeable downstream:

- Classic mode serves `/json/list`, so tabs can be enumerated over plain HTTP.
- Opt-in mode serves nothing but the single browser WebSocket. Any tooling or troubleshooting
  step that reaches for `/json/list` will get a `404` and must not read that as a broken setup.

`references/troubleshooting.md` needs to be able to tell a reader which mode they are in.
Collapsing the values would delete that information and re-create a subtler version of this same
bug the next time someone writes an HTTP-shaped check.

### 3.3 Guard against a false `READY`

An arbitrary unrelated service squatting on the port would also "answer HTTP with a non-200
status". `optin` alone therefore does not earn `READY`; it must be corroborated by
`PORT_FILE_FOUND=yes`, i.e. Chrome's own `DevToolsActivePort` exists in the resolved profile
directory with a numeric first line.

The conjunction required for `READY` via this path is: Chrome process running **and** the port
file present **and** something answering HTTP on the port named by that file. That is strong
enough; a bare listener with no port file stays `NEEDS_OPT_IN`.

`PORT_FILE_FOUND` remains internal — it is not added to the output contract. Line 2 of the port
file (the `/devtools/browser/<uuid>` path) is deliberately **not** validated: it is a useful
signal but not a documented guarantee, and requiring it would trade a false positive for a worse
false negative.

### 3.4 Verdict table

`STATUS` precedence is unchanged (`NODE_MISSING` > `CHROME_MISSING` > `CHROME_TOO_OLD` >
`NOT_CONFIGURED` > `CHROME_NOT_RUNNING` > `NEEDS_OPT_IN` > `READY`). Only the final two-way split
changes:

| `DEBUG_REACHABLE` | `PORT_FILE_FOUND` | `STATUS` | Change |
|---|---|---|---|
| `yes` | any | `READY` | unchanged |
| `optin` | `yes` | `READY` | **new — the bug being fixed** |
| `optin` | `no` | `NEEDS_OPT_IN` | new value, conservative verdict |
| `unknown` | `yes` | `READY` | unchanged |
| `unknown` | `no` | `NEEDS_OPT_IN` | unchanged |
| `no` | any | `NEEDS_OPT_IN` | unchanged |

Every previously-`READY` input stays `READY`. The only verdict that moves is the one that was
wrong.

### 3.5 Probe implementation per tool

Each backend must report three outcomes; the mapping differs because their failure signalling
differs.

**curl** — replace `-fsS` (which cannot distinguish 404 from refused) with an explicit status
write-out:

```sh
code=$(curl -s -o /dev/null -w '%{http_code}' -m 2 "$url" 2>/dev/null)
```

`%{http_code}` is `000` when no response was received; curl's exit status is not consulted, since
`000` already covers refused/timeout/reset. Map: `200` → `yes`; `000` or empty → `no`; anything
else → `optin`.

**wget** — `wget -q -T 2 -O /dev/null "$url"`; exit `0` → `yes`, exit `8` (server issued an error
response — a response nonetheless) → `optin`, any other exit → `no`.

**node** — `http.get`, then: `statusCode === 200` → exit 0 (`yes`), any other status → exit 3
(`optin`), `error` event or the 2 s timer → exit 1 (`no`).

**PowerShell** — prefer `Invoke-WebRequest -SkipHttpErrorCheck` when the parameter exists
(PowerShell 7+, which `pwsh -File` implies) and branch on `$r.StatusCode`. Retain a `catch` that
inspects `$_.Exception.Response.StatusCode`: a present response object means a status arrived →
`optin`; its absence means a transport failure → `no`. The fallback keeps Windows PowerShell 5.1
correct if anyone runs the script with `powershell.exe`.

### 3.6 Output contract

Unchanged: 15 keys, same names, same order, exactly one `STATUS=` line, always exit 0 when a
verdict is produced. Only the *value domain* of `DEBUG_REACHABLE` widens. `tests/test_skill_md.sh`
and `tests/test_ps1_contract.sh` assert key names and order, so both keep passing unmodified on
that axis.

## 4. Test plan

### 4.1 Fixture-harness change

The existing curl stubs signal via exit code only (`stub_cmd curl 'exit 0'` / `'exit 7'`). The new
probe reads **stdout**. Every curl stub in `tests/test_preflight.sh` must be updated to print a
status code:

- `stub_cmd curl 'exit 0'` → `stub_cmd curl 'printf 200'` (lines 261, 270, 310)
- `stub_cmd curl 'exit 7'` → `stub_cmd curl 'printf 000; exit 7'` (line 250)

This is mechanical, but it is the reason the bug survived: the stub contract must model *what the
probe actually reads*, not merely produce the right verdict by accident.

### 4.2 New cases in `tests/test_preflight.sh`

1. **opt-in endpoint with a port file is READY** — port file `9222\n/devtools/browser/abc`,
   `stub_cmd curl 'printf 404'` → `DEBUG_REACHABLE=optin`, `STATUS=READY`. This is the regression
   test for the reported failure; it must fail against the current implementation.
2. **a non-200 answer with no port file is NEEDS_OPT_IN** — same stub, no port file →
   `DEBUG_REACHABLE=optin`, `STATUS=NEEDS_OPT_IN`. Pins the §3.3 guard.
3. **a refused connection is still NEEDS_OPT_IN** — `printf 000; exit 7`, with a port file present
   → `DEBUG_REACHABLE=no`, `STATUS=NEEDS_OPT_IN`. Proves the port file does not rescue a dead port
   and that goal 2 holds.
4. **500 from a squatting service is treated as optin** — `printf 500` with a port file → `READY`.
   Documents the accepted residual imprecision rather than pretending it does not exist.
5. **wget-only and node-only paths** — with `curl` absent, assert each backend yields `optin` on a
   non-200 answer, so the three implementations do not drift apart.

Case 1 was written first and observed failing before the fix landed
(`superpowers:test-driven-development`).

### 4.3 `tests/test_ps1_contract.sh`

Stays contract-level: the PowerShell suite cannot stub `Invoke-WebRequest` through the existing
`link_host_tool` harness. It continues to assert the 15-key shape. The PowerShell probe is verified
by mirroring §3.5 exactly and by a manual check against a real opted-in Chrome on Windows, recorded
in the PR description.

## 5. Documentation changes

**`SKILL.md`** — §2 lists key names only, so the contract paragraph is untouched. No new `STATUS`
value, so the §3 branch table is untouched. Nothing to change unless a value glossary is added.

**`references/troubleshooting.md`**:

- `NEEDS_OPT_IN` — after "If you already allowed it: fully quit Chrome…", add that the opt-in
  endpoint is WebSocket-only and serves `404` for `/json/version`, so a manual `curl` check
  against that URL is not evidence of failure. Give
  `lsof -nP -iTCP:9222 -sTCP:LISTEN` and reading `DevToolsActivePort` as the checks that do work.
- *Other `READY` checks* — document `DEBUG_REACHABLE=optin` alongside the existing `unknown` bullet:
  what it means, that it is the normal value for a `chrome://inspect` opt-in, and that `yes` means
  the classic `--remote-debugging-port` launch.
- `CHROME_TOO_OLD` — the `--browserUrl` fallback bullet describes a classic launch; note that this
  is the mode that yields `DEBUG_REACHABLE=yes`, to keep the two paths legible against each other.

## 6. Acceptance criteria

1. Against a real opted-in Chrome, `sh scripts/preflight.sh` prints `DEBUG_REACHABLE=optin` and
   `STATUS=READY`.
2. With Chrome running and not opted in, `STATUS=NEEDS_OPT_IN` — unchanged.
3. With Chrome launched classically on `--remote-debugging-port`, `DEBUG_REACHABLE=yes` and
   `STATUS=READY` — unchanged.
4. `sh tests/run-tests.sh` passes, including every new case in §4.2.
5. Case §4.2.1 was demonstrated failing before the fix and passing after.
6. `scripts/preflight.ps1` implements §3.4 and §3.5 identically, and manual verification against an
   opted-in Chrome on Windows is recorded.
7. `references/troubleshooting.md` no longer implies `/json/version` is a valid manual health check.

## 7. Commits as landed

1. `66f42a8` test(preflight): cover a WebSocket-only opt-in endpoint — harness stub change plus the
   red cases from §4.2.
2. `40ea059` fix(preflight.sh): tell a 404 opt-in endpoint apart from a dead port — §3.1, §3.3–3.5.
3. `ccb60c4` fix(preflight.ps1): mirror the opt-in reachability contract — §3.5 PowerShell half.
4. `3abb29d` docs(troubleshooting): explain the WebSocket-only opt-in endpoint — §5.

A fifth commit, `3c8ab13` docs(troubleshooting): warn that a stale port file plus a squatter can
fake READY, documents the §3.3 residual risk for users. It is the F9 non-goal made visible, not a
change of scope.

## 8. Amendments

**2026-08-24 — the probe must reach loopback directly.** §2 goal 4 claimed behaviour identical on
POSIX and Windows, and §3.5 specified each backend independently. Neither accounted for proxy
configuration: `curl` and `wget` send a `127.0.0.1` URL through `http_proxy` when one is set, while
node's `http.get` ignores the proxy environment entirely, so the three backends disagreed on a
proxied host. A proxy's `502` satisfied the `optin` branch, and with a port file present that
reached `READY` for a Chrome that was never listening.

`debug_reachable` now clears `http_proxy`, `HTTP_PROXY`, `https_proxy`, `HTTPS_PROXY`, `all_proxy`,
and `ALL_PROXY` for the probe, and passes `--noproxy '*'` to curl as well. Clearing the environment
was chosen over per-tool flags because BusyBox wget rejects `--no-proxy` and would exit non-zero,
converting a healthy port into `DEBUG_REACHABLE=no`. `preflight.ps1` passes `-NoProxy` when
`Invoke-WebRequest` has it, capability-probed like `-SkipHttpErrorCheck`; Windows PowerShell 5.1
has no such parameter and relies on .NET's `BypassProxyOnLocal`, which is untested.

Landed in `b77f1a8`, `3c9f931`, `ef8510e`.

**2026-08-24 — troubleshooting must use the emitted values.** §5's manual checks named port 9222
and the stable-channel profile path, contradicting §3 of `unconditional-chrome-probe.md`, which
made a non-9222 port file and beta/dev/canary profiles first-class. `references/troubleshooting.md`
now directs the reader to preflight's own `DEBUG_PORT` and `USER_DATA_DIR`. Landed in `da6a892`.

**2026-08-25 — clearing the environment is not the whole bypass.** The 2026-08-24 amendment above
chose environment clearing *over* per-tool flags. That reasoning held for BusyBox wget, which still
rejects `--no-proxy`, but it was incomplete on both platforms:

- GNU wget also reads a proxy from `/etc/wgetrc` and `~/.wgetrc`, and those outrank the environment.
  A wgetrc proxy therefore answered for Chrome on a host whose environment the probe had just
  scrubbed. `debug_reachable` now passes `--no-proxy` as well, gated on the build advertising it, so
  the BusyBox constraint that motivated the original decision is still honoured.
- Windows PowerShell 5.1's reliance on .NET's `BypassProxyOnLocal` was recorded as untested, and it
  is a property of the configured proxy rather than a guarantee. `Get-DebugReachable` now nulls
  `WebRequest.DefaultWebProxy` for the duration of the probe and restores it in `finally`. The
  PowerShell 7 path is unchanged and still passes `-NoProxy`.

Environment clearing is retained on every POSIX backend; the flags are additive, not a replacement.
Covered by two cases in `tests/test_preflight.sh`, alongside the direct-loopback cases the
2026-08-24 amendment added: one stubs a GNU wget whose proxy answers unless `--no-proxy` is
passed, the other a BusyBox wget that rejects the flag and must still probe via the environment.

Landed in `5b03fdb`.

**Still open, deliberately.** Two known imprecisions were re-raised on 2026-08-24 and left alone:

- §3.3's residual risk stands — a stale `DevToolsActivePort` plus any squatter answering non-200
  still reaches `READY`. §2's non-goal (no WebSocket handshake from a shell script) is unchanged,
  and no decision has been made on a freshness or listener-identity check. `3c8ab13` documents the
  symptom for users. This is F9 of the Windows report; see `unconditional-chrome-probe.md` §2.1.
- §3.5's wget mapping trusts exit `0` as `200`, so a `204` or a followed redirect reports `yes` and
  skips the port-file corroboration that `optin` requires. This widens the squatter hole above
  rather than opening a new one — curl already maps a squatter's genuine `200` to `yes` — and
  closing it means parsing `wget -S` output on a backend that only runs when curl is absent.
