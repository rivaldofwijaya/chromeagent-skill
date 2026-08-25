# Spec: probe Chrome unconditionally, and stop emitting guesses as findings

Status: implemented — landed 2026-08-12 in 582fb5a, aabfef0, 7e8c8d9, fca3f1f.
This is a record of a design that shipped, not work to be executed.
Scope: `scripts/preflight.sh`, `scripts/preflight.ps1`, `tests/test_preflight.sh`,
`tests/test_skill_md.sh`, `SKILL.md`

Origin: Windows test report of 2026-08-12 (Windows 11 26200, Chrome 151.0.7922.138, pwsh 7.6.4 and
Windows PowerShell 5.1.26100.8875). This spec covers findings **F2, F3, F6, F4, F7** of that report.
F9 (stale `DevToolsActivePort`) and the F1 `CHROME_RUNNING` semantics are explicit non-goals — see
§2.1.

## 1. Problem

### 1.1 A missing runner blanks six Chrome fields (F2)

`preflight.ps1:119` and `preflight.sh:256` gate **all** Chrome discovery behind `RUNNER != none`:

```powershell
if ($runner[0] -ne 'none') { $chrome = Get-ChromeInfo; ... }
```

```sh
if [ "$RUNNER" != none ]; then hit=$(find_chrome "$PLATFORM" | sed -n '1p'); ... fi
```

The gate is deliberate and consistent across both scripts. The **output** is not honest about it.
On a machine with a perfectly good Chrome 151 and no Node, preflight reported:

| Field | Reported | Truth on that machine |
|---|---|---|
| `CHROME_PATH` | `none` | `C:\Program Files\Google\Chrome\Application\chrome.exe` |
| `CHROME_CHANNEL` | `none` | `stable` |
| `CHROME_VERSION` | `unknown` | `151.0.7922.138` |
| `CHROME_MAJOR` | `0` | `151` |
| `CHROME_OK` | `no` | `yes` (151 ≥ 144) |
| `USER_DATA_DIR` | *(empty)* | `%LOCALAPPDATA%\Google\Chrome\User Data` |

`CHROME_OK=no` is the sharpest failure: preflight asserts, as a positive finding, that a
more-than-adequate Chrome is not OK. The sentinel values are indistinguishable from genuine negative
findings, so a reader who has not read the source will remediate the wrong thing. On the `.ps1` path
`CHROME_RUNNING=yes` prints three lines below `CHROME_PATH=none`, which reads as self-contradictory.

Confirmed by a controlled single-variable re-test: installing Node changed nothing about Chrome and
did not restart the browser, yet all six fields became correct at once. Those fields were never
wrong about Chrome — they were never asked.

### 1.2 The blank `USER_DATA_DIR` defeats port discovery (F3)

Consequence chain, all inside the `RUNNER=none` window:

1. `USER_DATA_DIR` is empty.
2. `Get-DebugPort ''` (`preflight.ps1:63-73`) / `debug_port ""` (`preflight.sh:191-202`) therefore
   never reads `DevToolsActivePort` and falls through to the hardcoded `9222`.
3. Chrome's `chrome://inspect` opt-in binds an ephemeral port, not necessarily 9222, so the probe
   can be aimed at the wrong port entirely.
4. `PortFileFound` / `PORT_FILE_FOUND` stays false, and it is a **required conjunct** for two of the
   three `READY` routes (`preflight.ps1:154-155`, `preflight.sh:316-319`).

So while `RUNNER=none`, the `optin` and `unknown` routes to `READY` are structurally unreachable:
even a correctly measured `DEBUG_REACHABLE=optin` could not be believed. The fallback port and the
port-file guard fail in the same direction, compounding rather than cancelling.

This is not merely cosmetic in the way F2 is. It means the `DEBUG_REACHABLE` line — which
`references/troubleshooting.md` tells readers to consult *because* it prints regardless of `STATUS`
— is a measurement artifact whenever the runner is missing.

### 1.3 `preflight.sh` emits a mixed-separator `USER_DATA_DIR` on Windows (F6)

```
USER_DATA_DIR=C:\Users\Alice\AppData\Local/Google/Chrome/User Data
```

`chrome_candidates` (`preflight.sh:84,89-99`) interpolates `$LOCALAPPDATA` verbatim — backslashed,
as Windows sets it — and appends forward-slashed segments. `CHROME_PATH` from the same run is fully
forward-slashed because `$ProgramFiles` happened to be normalised upstream, so the two keys of one
run disagree with each other.

It still satisfies the script's own `-f` tests, so preflight is not broken by it. But `USER_DATA_DIR`
is part of a documented output contract meant for other consumers, and a mixed-separator path is a
trap for anything that string-matches, splits on a separator, or passes it to a native API.

### 1.4 SKILL.md gives script paths that do not resolve (F4)

§2 states the rule correctly: *"Invoke the scripts by their absolute path from the project-root
shell."* Two later passages contradict it with bare relative paths that fail from the project root,
because `scripts/` lives under the installed skill directory, not the project:

- `SKILL.md:56`, the `NOT_CONFIGURED` row — `sh scripts/setup-mcp.sh --agent auto` /
  `pwsh -File scripts/setup-mcp.ps1 -Agent auto`.
- `SKILL.md:67-68` and `SKILL.md:73-74`, §4 — the `--channel` and PowerShell-spelling examples.

The tester followed the relative form first and it failed. The CWD-vs-script-location split is
genuinely subtle here, since preflight scans config **relative to CWD** with no `-OutDir` escape,
so the two paths in play are legitimately different directories.

### 1.5 Installing Node does not take effect in the running shell (F7)

After a successful `winget install OpenJS.NodeJS.LTS`, a shell started before the install still
reports `RUNNER=none` / `STATUS=NODE_MISSING`, because it inherited the pre-install `PATH`. The
tester had to rebuild `PATH` from the Machine and User environment blocks by hand.

This sits directly on the skill's own remediation path: the `NODE_MISSING` row (`SKILL.md:61`) says
install Node then "re-probe". Followed literally in the same terminal, that yields an unchanged
`NODE_MISSING`, and the reasonable conclusion is that the install failed. Preflight itself is
correct here — it accurately reports the environment it was handed. This is a documentation defect.

## 2. Goals

1. Every emitted field is either a measurement or an honest absence. No field reports a negative
   finding it did not test for.
2. `USER_DATA_DIR` is populated whenever Chrome is found, so `DevToolsActivePort` is actually read
   and `DEBUG_PORT` can be discovered rather than guessed.
3. `USER_DATA_DIR` and `CHROME_PATH` from a single run use one separator convention.
4. Every script invocation shown in `SKILL.md` resolves as written from the documented CWD.
5. The `NODE_MISSING` remediation succeeds when followed literally.
6. The 15-key output contract is unchanged in key set, order, and count. `STATUS` precedence and
   every existing verdict are unchanged.

### 2.1 Non-goals

- **F9, the stale `DevToolsActivePort`.** Already analysed and documented at
  `references/troubleshooting.md:112-123`. The Windows run corroborates the macOS conclusion —
  Chrome rewrites the file on grant and never deletes it on revoke — so the live risk remains the
  squatter false-`READY` that is already written up. Whether to harden `debug_port` with a freshness
  check is a separate decision, deliberately not taken here.
- **F1, the `CHROME_RUNNING` semantic split.** `preflight.ps1:127` matches any process named
  `chrome`; `preflight.sh:172-188` is documented as matching the exact resolved binary. On Windows
  both are in fact name-based (`Get-Process` vs `tasklist | grep -i chrome.exe`) and the observed
  divergence came solely from `preflight.sh:173`'s `[ "$2" != none ]` guard tripping on the field
  F2 had blanked. §3.1 therefore removes the *observed* divergence as a side effect. The underlying
  question of which contract is intended stays open and unaddressed.
- Surfacing `PORT_FILE_FOUND` as a 16th key. It would break the key-count contract asserted by
  `tests/test_ps1_contract.sh` and `tests/test_skill_md.sh`; separate decision.
- Any change to `setup-mcp.sh` / `setup-mcp.ps1`.

## 3. Design

### 3.1 Probe Chrome unconditionally

Remove the runner gate in both scripts. Chrome discovery becomes unconditional:

```powershell
$chrome = Get-ChromeInfo
if ($chrome) { $version = $chrome.Version; $major = Get-Major $version; $udd = $chrome.UserDataDir }
```

```sh
hit=$(find_chrome "$PLATFORM" | sed -n '1p')
if [ -n "$hit" ]; then ... fi
```

**Why this cannot change any verdict.** `STATUS` precedence already tests the runner first
(`preflight.ps1:148`, `preflight.sh:304`). `RUNNER=none` still short-circuits to `NODE_MISSING`
before `CHROME_MISSING`, `CHROME_TOO_OLD`, or anything downstream is consulted. Populating the
Chrome fields can only change the *diagnostic* lines, never the verdict. This is what makes the
change safe to make unconditionally rather than behind a new sentinel.

**Why not a `not_probed` sentinel instead.** The report offers it as an alternative: keep the gate,
but emit a value distinguishable from a genuine negative. Rejected — it widens the value domain of
six keys to solve a problem that has no cost justification in the first place. Chrome discovery is
filesystem probing; the gate saves nothing worth a contract change.

**Accepted cost.** Discovery is not entirely free on one path: `chrome_version`
(`preflight.sh:115-129`) spawns `powershell.exe` to read the file version on Windows, so the Git
Bash `NODE_MISSING` run gains one process spawn it did not previously pay for. `NODE_MISSING` is a
one-shot state on the remediation path, not a polling loop, and §1.1 is the price of skipping it.
Accepted knowingly.

**Side effect on `CHROME_RUNNING`.** With `CHROME_PATH` populated, `preflight.sh:173`'s guard stops
tripping and the two scripts agree on Windows. This is a consequence, not the fix; see §2.1.

### 3.2 Normalise Windows path separators in `preflight.sh`

Normalise the environment-derived bases at the top of the `windows` branch of `chrome_candidates`,
where they enter the script, rather than at each `printf` or at emit time:

```sh
pf=$(printf '%s' "$pf" | tr '\\' '/')
pf86=$(printf '%s' "$pf86" | tr '\\' '/')
lad=$(printf '%s' "$lad" | tr '\\' '/')
```

Normalising at the source keeps `CHROME_PATH`, `USER_DATA_DIR`, and the `DevToolsActivePort` path
built from it consistent by construction, and leaves one place to be wrong instead of six.

**Convention: forward slashes for `preflight.sh`, backslashes for `preflight.ps1`.** Each script
emits its own shell's idiom, which is what a consumer of that script's output expects, and it is
what `CHROME_PATH` already does today on both. The two scripts are therefore *internally*
consistent but not identical to each other. This is the accepted outcome: goal 3 is one convention
per run, not one convention across implementations. Windows APIs and PowerShell's `Test-Path` accept
both forms, and `-f` in Git Bash requires the forward-slashed form.

### 3.3 Documentation changes

**`SKILL.md:56`** (`NOT_CONFIGURED` row) — replace the bare relative commands with the same
`/path/to/chromeagent-skill/scripts/...` placeholder form §2 and the README already use, so a reader
who copies the row gets the shape that works.

**`SKILL.md:67-68` and `SKILL.md:73-74`** (§4) — same substitution for the `--channel` examples and
the "on native Windows, use ..." sentence.

**`SKILL.md:25`** — add one worked example making the two directories explicit, since the rule is
correct but easy to read past: the project root is the CWD, the skill directory is where the scripts
live, and they are not the same place.

**`SKILL.md:61`** (`NODE_MISSING` row) — after "install, re-probe", add that a shell started before
the install still has the old `PATH`: open a new terminal (or refresh `PATH`) before re-probing, or
the re-probe will report `NODE_MISSING` again and look like a failed install.

## 4. Test plan

### 4.1 New cases in `tests/test_preflight.sh`

The suite's `NODE_MISSING` case (line 40) asserts only `RUNNER`, `STATUS`, and key order, and its
sandbox contains no Chrome, so it keeps passing unchanged. The new coverage is the combination the
suite has never built: **a sandbox with Chrome present and no runner stubbed.**

1. **Chrome is reported while the runner is missing** — macOS sandbox, `fake_chrome` at the stable
   path, no runner stub. Assert `RUNNER=none`, `STATUS=NODE_MISSING`, and `CHROME_PATH`,
   `CHROME_CHANNEL=stable`, `CHROME_VERSION`, `CHROME_MAJOR`, `CHROME_OK=yes`, `USER_DATA_DIR` all
   populated. This is the regression test for §1.1 and must be observed failing first.
2. **`STATUS` is unchanged by the new fields** — the same sandbox additionally given a modern Chrome
   and a project `.mcp.json`; assert `STATUS=NODE_MISSING` still wins over `NOT_CONFIGURED`. Pins
   the precedence claim §3.1 rests on.
3. **Port discovery works without a runner** — the same sandbox plus a `DevToolsActivePort` naming a
   **non-9222** port, and a curl stub printing `404`. Assert `DEBUG_PORT` is the port from the file,
   not `9222`, and `DEBUG_REACHABLE=optin`. This is the §1.2 regression test, and it closes the
   value-discovery gap the Windows run could not close (the real opt-in bound 9222, which collides
   with the fallback and makes discovery indistinguishable from the default).
4. **Windows `USER_DATA_DIR` uses one separator** — windows sandbox with `LOCALAPPDATA` set to a
   backslashed value; assert `USER_DATA_DIR` contains no `\` and matches `CHROME_PATH`'s convention.
   The §1.3 regression test.

### 4.2 `tests/test_ps1_contract.sh`

Unchanged in kind: it asserts the 15-key shape and cannot stub `Get-ChromeInfo`. The `.ps1` half of
§3.1 is verified by mirroring the `.sh` change exactly and by re-running the Windows matrix — the
one field to confirm is that `CHROME_*` populate under `STATUS=NODE_MISSING`.

### 4.3 `tests/test_skill_md.sh`

`tests/test_skill_md.sh:73-74` asserts the current **relative** spellings verbatim:

```
'sh scripts/setup-mcp.sh --agent auto --channel "$CHROME_CHANNEL"'
'pwsh -File scripts/setup-mcp.ps1 -Agent auto -Channel $CHROME_CHANNEL'
```

Both must be updated to the absolute placeholder form alongside §3.3, or the doc fix fails the
suite. Add an assertion that `SKILL.md` contains no bare `sh scripts/setup-mcp.sh` or
`pwsh -File scripts/setup-mcp.ps1` occurrence, so the contradiction cannot creep back.

## 5. Acceptance criteria

1. On a machine with Chrome installed and no Node, both scripts report the true `CHROME_PATH`,
   `CHROME_CHANNEL`, `CHROME_VERSION`, `CHROME_MAJOR`, `CHROME_OK`, and `USER_DATA_DIR` alongside
   `STATUS=NODE_MISSING`.
2. In that same state, a present `DevToolsActivePort` naming a non-9222 port is read, and
   `DEBUG_PORT` reports that port.
3. Every previously-produced `STATUS` for a given machine state is unchanged.
4. `sh scripts/preflight.sh` on Windows emits `USER_DATA_DIR` and `CHROME_PATH` with the same
   separator, and no mixed-separator path.
5. Every script invocation in `SKILL.md` resolves as written from the project root.
6. The `NODE_MISSING` row tells the reader to open a new terminal or refresh `PATH` before
   re-probing.
7. `sh tests/run-tests.sh` passes, including every new case in §4.1.
8. Case §4.1.1 was demonstrated failing before the fix and passing after
   (`superpowers:test-driven-development`).

## 6. Commits as landed

1. `582fb5a` test(preflight): cover Chrome discovery with no runner present — §4.1 cases 1-4, red.
2. `aabfef0` fix(preflight.sh): probe Chrome even when no runner is installed — §3.1 POSIX half, §3.2.
3. `7e8c8d9` fix(preflight.ps1): mirror unconditional Chrome discovery — §3.1 PowerShell half.
4. `fca3f1f` docs(skill): use resolvable script paths and warn about a stale PATH — §3.3, §4.3.
