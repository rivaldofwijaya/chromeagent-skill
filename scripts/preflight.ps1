# preflight.ps1 — chromeagent-skill status probe (Windows PowerShell / pwsh).
# Emits the same KEY=value contract as preflight.sh and always exits 0.
$ErrorActionPreference = 'SilentlyContinue'
$CHROME_MIN_MAJOR = 144
$Root = $env:CHROMEAGENT_ROOT

function Test-Cmd([string]$name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }

function Get-Runner {
  if (Test-Cmd 'npx')  { return @('npx', 'npx -y') }
  if (Test-Cmd 'bunx') { return @('bunx', 'bunx') }
  if (Test-Cmd 'pnpm') { return @('pnpm-dlx', 'pnpm dlx') }
  if (Test-Cmd 'chrome-devtools-mcp') { return @('global', 'chrome-devtools-mcp') }
  return @('none', '')
}

function Get-ChromeCandidates {
  $lad  = $env:LOCALAPPDATA
  $bases = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $lad) | Where-Object { $_ }
  foreach ($c in @(
    @('stable', 'Chrome'),
    @('beta',   'Chrome Beta'),
    @('dev',    'Chrome Dev'),
    @('canary', 'Chrome SxS'))) {
    foreach ($b in $bases) {
      $exe = Join-Path $b "Google\$($c[1])\Application\chrome.exe"
      if ($Root) { $exe = Join-Path $Root ($exe -replace '^[A-Za-z]:[\\/]', '') }
      [pscustomobject]@{
        Channel = $c[0]
        Path    = $exe
        UserDataDir = Join-Path $lad "Google\$($c[1])\User Data"
      }
    }
  }
  # Last resort: the registry App Paths entry.
  $reg = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe'
  $p = (Get-ItemProperty $reg -ErrorAction SilentlyContinue).'(default)'
  if ($p) {
    [pscustomobject]@{ Channel = 'stable'; Path = $p; UserDataDir = Join-Path $lad 'Google\Chrome\User Data' }
  }
}

function Get-ChromeInfo {
  if ($env:CHROMEAGENT_FAKE_CHROME) {
    $p = $env:CHROMEAGENT_FAKE_CHROME -split '\|'
    return [pscustomobject]@{ Channel=$p[0]; Path=$p[1]; Version=$p[2]; UserDataDir=$p[3] }
  }
  foreach ($c in Get-ChromeCandidates) {
    if (Test-Path -LiteralPath $c.Path) {
      $v = (Get-Item -LiteralPath $c.Path).VersionInfo.ProductVersion
      if (-not $v) { $v = 'unknown' }
      return [pscustomobject]@{ Channel=$c.Channel; Path=$c.Path; Version=$v; UserDataDir=$c.UserDataDir }
    }
  }
  return $null
}

function Get-Major([string]$v) {
  if ($v -match '^(\d+)\.') { return [int]$Matches[1] }
  return 0
}

function Get-DebugPort([string]$udd) {
  $script:PortFileFound = $false
  if ($udd) {
    $f = Join-Path $udd 'DevToolsActivePort'
    if (Test-Path -LiteralPath $f) {
      $line = (Get-Content -LiteralPath $f -TotalCount 1).Trim()
      if ($line -match '^\d+$') { $script:PortFileFound = $true; return $line }
    }
  }
  return '9222'
}

function Get-DebugReachable([string]$port) {
  try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:$port/json/version" -TimeoutSec 2 -UseBasicParsing
    if ($r.StatusCode -eq 200) { return 'yes' }
    return 'no'
  } catch { return 'no' }
}

function Get-ConfigFile {
  $paths = @(
    './.mcp.json', './.vscode/mcp.json', './.cursor/mcp.json', './opencode.json',
    './.codex/config.toml',
    (Join-Path $HOME '.codex/config.toml'),
    (Join-Path $HOME '.config/opencode/opencode.json')
  )
  foreach ($p in $paths) {
    if (Test-Path -LiteralPath $p) {
      $t = Get-Content -LiteralPath $p -Raw
      if ($t -cmatch 'chrome-devtools' -and $t -cmatch 'autoConnect') { return $p }
    }
  }
  return $null
}

$runner = Get-Runner
$chrome = $null
$version = 'unknown'
$major = 0
$udd = ''
if ($runner[0] -ne 'none') {
  $chrome = Get-ChromeInfo
  if ($chrome) {
    $version = $chrome.Version
    $major = Get-Major $version
    $udd = $chrome.UserDataDir
  }
}
$running = if (Get-Process -Name 'chrome' -ErrorAction SilentlyContinue) { 'yes' } else { 'no' }
$port    = Get-DebugPort $udd
$reach   = if ($running -eq 'yes') { Get-DebugReachable $port } else { 'no' }
$cfg     = Get-ConfigFile

"PLATFORM=windows"
"RUNNER=$($runner[0])"
"RUNNER_CMD=$($runner[1])"
"CHROME_PATH=$(if ($chrome) { $chrome.Path } else { 'none' })"
"CHROME_CHANNEL=$(if ($chrome) { $chrome.Channel } else { 'none' })"
"CHROME_VERSION=$version"
"CHROME_MAJOR=$major"
"CHROME_OK=$(if ($major -ge $CHROME_MIN_MAJOR) { 'yes' } else { 'no' })"
"USER_DATA_DIR=$udd"
"CHROME_RUNNING=$running"
"DEBUG_PORT=$port"
"DEBUG_REACHABLE=$reach"
"MCP_CONFIG_FILE=$(if ($cfg) { $cfg } else { 'none' })"
"MCP_CONFIGURED=$(if ($cfg) { 'yes' } else { 'no' })"

$status =
  if ($runner[0] -eq 'none') { 'NODE_MISSING' }
  elseif (-not $chrome) { 'CHROME_MISSING' }
  elseif ($major -lt $CHROME_MIN_MAJOR) { 'CHROME_TOO_OLD' }
  elseif (-not $cfg) { 'NOT_CONFIGURED' }
  elseif ($running -eq 'no') { 'CHROME_NOT_RUNNING' }
  elseif ($reach -eq 'yes') { 'READY' }
  elseif ($reach -eq 'unknown' -and $script:PortFileFound) { 'READY' }
  else { 'NEEDS_OPT_IN' }
"STATUS=$status"
exit 0
