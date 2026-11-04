# setup-mcp.ps1 — write a project-scope chrome-devtools MCP entry.
# Keep the script entry point unbound so PowerShell does not reject malformed
# argv (especially a literal --) before the setup-mcp usage parser can run.
$ErrorActionPreference = 'Stop'
$script:ExitCode = 0
# Pinned rather than @latest, for the reason given in setup-mcp.sh. Keep it equal
# to CDM_PACKAGE there and the pin in .claude-plugin/plugin.json.
$CdmPackage = 'chrome-devtools-mcp@1.12.0'

function Write-Info([string]$Message) {
  [Console]::Out.WriteLine($Message)
}

function Write-ErrorLine([string]$Message) {
  [Console]::Error.WriteLine($Message)
}

function Set-ExitCode([int]$Code) {
  if ($Code -gt $script:ExitCode) { $script:ExitCode = $Code }
}

function Get-RawArguments {
  param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$RawArguments
  )
  return @($RawArguments)
}

# Pass the automatic raw argv array explicitly so the collector also receives
# the -- token that pwsh -File otherwise treats as a parameter terminator.
$rawArguments = @(Get-RawArguments -RawArguments @($args))

function Write-Usage {
  Write-Info 'usage: setup-mcp.ps1 -Agent auto|claude|opencode [-Runner "<argv>"] [-Channel beta|dev|canary] [-OutDir <dir>] [-NoRedact]'
}

function Stop-Usage([string]$Message) {
  Write-ErrorLine "setup-mcp: $Message"
  exit 2
}

# Parse by index. Every non-exit path advances by one or two positions, so a
# malformed trailing value can never leave the loop at the same index. Each
# option is accepted once, as -Name value or -Name:value.
$values = @{}
$NoRedact = $false
$noRedactSeen = $false
$index = 0
while ($index -lt $rawArguments.Count) {
  $option = [string]$rawArguments[$index]
  $optionName = $option
  $attachedValue = $null
  $colon = $option.IndexOf(':')
  if ($colon -gt 1) {
    $optionName = $option.Substring(0, $colon)
    $attachedValue = $option.Substring($colon + 1)
  }

  if (($optionName -ieq '-h') -or ($optionName -ieq '--help')) {
    Write-Usage
    exit 0
  }

  $key = @('Agent', 'Runner', 'Channel', 'OutDir') | Where-Object { $optionName -ieq "-$_" } | Select-Object -First 1
  if ($key) {
    # -OutDir errors name the option canonically; the others echo the token.
    $label = if ($key -eq 'OutDir') { '-OutDir' } else { $option }
    if ($values.ContainsKey($key)) { Stop-Usage "repeated option $label" }
    if ($null -ne $attachedValue) {
      if ($attachedValue.Length -eq 0) { Stop-Usage "$label requires a value" }
      $value = $attachedValue
      $index += 1
    } elseif (($index + 1) -ge $rawArguments.Count) {
      Stop-Usage "$label requires a value"
    } else {
      $value = [string]$rawArguments[$index + 1]
      if (($key -eq 'OutDir') -and ($value.Length -eq 0)) { Stop-Usage "$label requires a value" }
      $index += 2
    }
    $values[$key] = $value
    continue
  }

  if ($optionName -ieq '-NoRedact') {
    if ($noRedactSeen) { Stop-Usage "repeated option $option" }
    $noRedactSeen = $true
    if ($null -eq $attachedValue) {
      $NoRedact = $true
    } elseif (@('true', '$true') -contains $attachedValue) {
      $NoRedact = $true
    } elseif (@('false', '$false') -contains $attachedValue) {
      $NoRedact = $false
    } else {
      Stop-Usage "invalid value for $option"
    }
    $index += 1
    continue
  }

  Stop-Usage "unknown option $option"
}

$Agent = if ($values.ContainsKey('Agent')) { $values['Agent'] } else { 'auto' }
$Runner = if ($values.ContainsKey('Runner')) { $values['Runner'] } else { '' }
$ChannelSet = $values.ContainsKey('Channel')
$Channel = if ($ChannelSet) { $values['Channel'] } else { '' }
$OutDirSet = $values.ContainsKey('OutDir')
$OutDir = if ($OutDirSet) { $values['OutDir'] } else { '' }

# Validate manually so a bad value follows setup-mcp.sh's exit-2 contract.
if (@('auto', 'claude', 'opencode') -cnotcontains $Agent) {
  Write-ErrorLine "setup-mcp: unknown agent $Agent"
  exit 2
}
if ($ChannelSet -and @('beta', 'dev', 'canary') -cnotcontains $Channel) {
  Write-ErrorLine "setup-mcp: invalid channel $Channel"
  exit 2
}

$resolvedOutDir = $null
$outDirToResolve = if ($OutDirSet) { $OutDir } else { '.' }
try {
  $resolvedPath = Resolve-Path -LiteralPath $outDirToResolve -ErrorAction Stop
  if (-not (Test-Path -LiteralPath $resolvedPath.Path -PathType Container)) {
    throw 'not a directory'
  }
  $resolvedOutDir = $resolvedPath.Path
} catch {
  if ($OutDirSet) {
    Write-ErrorLine "setup-mcp: -OutDir $outDirToResolve is not a directory"
  } else {
    Write-ErrorLine "setup-mcp: $outDirToResolve is not a directory"
  }
  exit 2
}

function Get-RunnerParts {
  if ($Runner) {
    $parts = @($Runner -split ' +')
    if ($parts.Count -eq 1) {
      return [pscustomobject]@{ Command = $parts[0]; Args = @() }
    }
    return [pscustomobject]@{
      Command = $parts[0]
      Args    = @($parts[1..($parts.Count - 1)])
    }
  }
  if (Get-Command npx -ErrorAction SilentlyContinue) {
    return [pscustomobject]@{ Command = 'npx'; Args = @('-y') }
  }
  if (Get-Command bunx -ErrorAction SilentlyContinue) {
    return [pscustomobject]@{ Command = 'bunx'; Args = @() }
  }
  if (Get-Command pnpm -ErrorAction SilentlyContinue) {
    return [pscustomobject]@{ Command = 'pnpm'; Args = @('dlx') }
  }
  return [pscustomobject]@{ Command = 'npx'; Args = @('-y') }
}

function Get-ServerArgs {
  $argsList = @($CdmPackage, '--autoConnect')
  if (-not $NoRedact) { $argsList += '--redactNetworkHeaders' }
  # Performance traces otherwise send the traced URLs to the CrUX API; with a
  # real profile those URLs can be private.
  $argsList += '--no-performance-crux'
  # Navigations the agent performs cannot open file: URLs, so a page that
  # talks the agent into it cannot read local files through the browser.
  $argsList += '--no-file-navigations'
  # Google otherwise collects usage data about the agent's tool calls.
  $argsList += '--no-usage-statistics'
  if ($Channel) { $argsList += @('--channel', $Channel) }
  return @($argsList)
}

# ConvertFrom-Json returns PSCustomObject on Windows PowerShell 5.1. Walk it
# recursively into ordered dictionaries so the merge code can use string keys
# without requiring the PowerShell 6+ -AsHashtable parameter.
function ConvertTo-OrderedHashtable($Value) {
  if ($null -eq $Value) { return $null }

  if ($Value -is [System.Collections.IDictionary]) {
    $result = [ordered]@{}
    foreach ($entry in $Value.GetEnumerator()) {
      $result[$entry.Key] = ConvertTo-OrderedHashtable $entry.Value
    }
    return $result
  }

  if ($Value -is [System.Management.Automation.PSCustomObject]) {
    $result = [ordered]@{}
    foreach ($property in $Value.PSObject.Properties) {
      $result[$property.Name] = ConvertTo-OrderedHashtable $property.Value
    }
    return $result
  }

  if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
    $result = @()
    foreach ($item in $Value) {
      $result += ,(ConvertTo-OrderedHashtable $item)
    }
    return ,$result
  }

  return $Value
}

function Test-MapKey([System.Collections.IDictionary]$Map, [string]$Key) {
  return $Map.Contains($Key)
}

function Read-JsonFile([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return [ordered]@{}
  }

  try {
    $raw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path)
    if (-not $raw.Trim()) {
      throw "setup-mcp: $Path is not valid JSON; not modifying it"
    }
    $parsed = ConvertFrom-Json -InputObject $raw
    $doc = ConvertTo-OrderedHashtable $parsed
    if (($null -eq $doc) -or -not ($doc -is [System.Collections.IDictionary])) {
      throw "setup-mcp: $Path is not valid JSON; not modifying it"
    }
    return $doc
  } catch {
    if ($_.Exception.Message -like 'setup-mcp:*') { throw }
    throw "setup-mcp: $Path is not valid JSON; not modifying it"
  }
}

function Write-JsonFile([string]$Path, $Document) {
  $directory = Split-Path -Parent $Path
  if (-not $directory) { $directory = '.' }
  $base = Split-Path -Leaf $Path
  $pidValue = [System.Diagnostics.Process]::GetCurrentProcess().Id
  $tempPath = Join-Path $directory ".${base}.tmp-${pidValue}-$([Guid]::NewGuid().ToString('N'))"
  $tempCreated = $false
  $stream = $null

  try {
    $rendered = ($Document | ConvertTo-Json -Depth 12) + [Environment]::NewLine
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $bytes = $utf8.GetBytes($rendered)
    $stream = [System.IO.File]::Open(
      $tempPath,
      [System.IO.FileMode]::CreateNew,
      [System.IO.FileAccess]::Write,
      [System.IO.FileShare]::None
    )
    $tempCreated = $true
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
    $stream.Dispose()
    $stream = $null
    Move-Item -LiteralPath $tempPath -Destination $Path -Force
    $tempPath = $null
  } catch {
    if ($null -ne $stream) {
      $stream.Dispose()
      $stream = $null
    }
    if ($tempCreated -and $tempPath -and (Test-Path -LiteralPath $tempPath)) {
      Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
    throw
  }
}

# Native PowerShell merging is deliberate: sh needs Node for JSON parsing, but
# PowerShell can always merge safely, so the sh manual-merge branch is unused;
# its exit 3 remains defined for other merge failures, not this branch.
function Write-Claude {
  $target = Join-Path $resolvedOutDir '.mcp.json'
  $targetItem = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
  if (($null -ne $targetItem) -and ($targetItem.LinkType -eq 'SymbolicLink')) {
    Write-ErrorLine "setup-mcp: refusing to write through symlink $target"
    Set-ExitCode 3
    return
  }
  if (Test-Path -LiteralPath $target -PathType Container) {
    Write-ErrorLine "setup-mcp: failed to write $target"
    Set-ExitCode 3
    return
  }
  $hadFile = Test-Path -LiteralPath $target -PathType Leaf
  try {
    $r = Get-RunnerParts
    $doc = Read-JsonFile $target
    if (-not (Test-MapKey $doc 'mcpServers') -or
        ($null -eq $doc['mcpServers']) -or
        -not ($doc['mcpServers'] -is [System.Collections.IDictionary])) {
      $doc['mcpServers'] = [ordered]@{}
    }
    $doc['mcpServers']['chrome-devtools'] = [ordered]@{
      command = $r.Command
      args    = @($r.Args) + @(Get-ServerArgs)
    }
  } catch {
    Write-ErrorLine $_.Exception.Message
    Set-ExitCode 3
    return
  }
  try {
    Write-JsonFile $target $doc
  } catch {
    Write-ErrorLine "setup-mcp: failed to write $target"
    Set-ExitCode 3
    return
  }
  Write-Info "setup-mcp: $(if ($hadFile) { 'merged chrome-devtools into' } else { 'wrote' }) $target"
}

function Write-Opencode {
  $target = Join-Path $resolvedOutDir 'opencode.json'
  $targetItem = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
  if (($null -ne $targetItem) -and ($targetItem.LinkType -eq 'SymbolicLink')) {
    Write-ErrorLine "setup-mcp: refusing to write through symlink $target"
    Set-ExitCode 3
    return
  }
  if (Test-Path -LiteralPath $target -PathType Container) {
    Write-ErrorLine "setup-mcp: failed to write $target"
    Set-ExitCode 3
    return
  }
  $hadFile = Test-Path -LiteralPath $target -PathType Leaf
  try {
    $r = Get-RunnerParts
    $doc = Read-JsonFile $target
    $doc['$schema'] = 'https://opencode.ai/config.json'
    if (-not (Test-MapKey $doc 'mcp') -or
        ($null -eq $doc['mcp']) -or
        -not ($doc['mcp'] -is [System.Collections.IDictionary])) {
      $doc['mcp'] = [ordered]@{}
    }
    $doc['mcp']['chrome-devtools'] = [ordered]@{
      type    = 'local'
      enabled = $true
      command = @($r.Command) + @($r.Args) + @(Get-ServerArgs)
    }
  } catch {
    Write-ErrorLine $_.Exception.Message
    Set-ExitCode 3
    return
  }
  try {
    Write-JsonFile $target $doc
  } catch {
    Write-ErrorLine "setup-mcp: failed to write $target"
    Set-ExitCode 3
    return
  }
  Write-Info "setup-mcp: $(if ($hadFile) { 'merged chrome-devtools into' } else { 'wrote' }) $target"
}

function Get-DetectedAgents {
  $found = @()
  $claudeConfigPath = Join-Path $resolvedOutDir '.mcp.json'
  $claudeMarkerPath = Join-Path $resolvedOutDir '.claude'
  if ((Test-Path -LiteralPath $claudeConfigPath -PathType Leaf) -or
      (Test-Path -LiteralPath $claudeMarkerPath -PathType Container)) {
    $found += 'claude'
  }
  $opencodeConfigPath = Join-Path $resolvedOutDir 'opencode.json'
  if (Test-Path -LiteralPath $opencodeConfigPath -PathType Leaf) {
    $found += 'opencode'
  }
  if (-not $found) { $found = @('claude') }
  return @($found)
}

try {
  $targets = if ($Agent -eq 'auto') { Get-DetectedAgents } else { @($Agent) }
  foreach ($target in $targets) {
    switch ($target) {
      'claude'   { Write-Claude }
      'opencode' { Write-Opencode }
    }
  }
  Write-Info 'setup-mcp: restart your agent so it loads the MCP server.'
  exit $script:ExitCode
} catch {
  Write-ErrorLine $_.Exception.Message
  exit 3
}
