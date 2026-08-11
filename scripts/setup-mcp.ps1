# setup-mcp.ps1 — write a project-scope chrome-devtools MCP entry.
# Keep the script entry point unbound so PowerShell does not reject malformed
# argv (especially a literal --) before the setup-mcp usage parser can run.
$ErrorActionPreference = 'Stop'
$script:ExitCode = 0

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
$Agent = 'auto'
$Runner = ''
$Channel = ''
$ChannelSet = $false
$NoRedact = $false
$seenOptions = @{}

function Write-Usage {
  Write-Info 'usage: setup-mcp.ps1 -Agent auto|claude|codex|opencode [-Runner "<argv>"] [-Channel beta|dev|canary] [-NoRedact]'
}

# Parse by index. Every non-exit path advances by one or two positions, so a
# malformed trailing value can never leave the loop at the same index.
$index = 0
while ($index -lt $rawArguments.Count) {
  $option = [string]$rawArguments[$index]
  $optionName = $option
  $attachedValue = $null
  $hasAttachedValue = $false
  $colon = $option.IndexOf(':')
  if ($colon -gt 1) {
    $optionName = $option.Substring(0, $colon)
    $attachedValue = $option.Substring($colon + 1)
    $hasAttachedValue = $true
  }

  if (($optionName -ieq '-h') -or ($optionName -ieq '--help')) {
    Write-Usage
    exit 0
  }

  if ($optionName -ieq '-Agent') {
    if ($seenOptions.ContainsKey('Agent')) {
      Write-ErrorLine "setup-mcp: repeated option $option"
      exit 2
    }
    $seenOptions['Agent'] = $true
    if ($hasAttachedValue) {
      if ($attachedValue.Length -eq 0) {
        Write-ErrorLine "setup-mcp: $option requires a value"
        exit 2
      }
      $Agent = $attachedValue
      $index += 1
    } elseif (($index + 1) -ge $rawArguments.Count) {
      Write-ErrorLine "setup-mcp: $option requires a value"
      exit 2
    } else {
      $Agent = [string]$rawArguments[$index + 1]
      $index += 2
    }
    continue
  }

  if ($optionName -ieq '-Runner') {
    if ($seenOptions.ContainsKey('Runner')) {
      Write-ErrorLine "setup-mcp: repeated option $option"
      exit 2
    }
    $seenOptions['Runner'] = $true
    if ($hasAttachedValue) {
      if ($attachedValue.Length -eq 0) {
        Write-ErrorLine "setup-mcp: $option requires a value"
        exit 2
      }
      $Runner = $attachedValue
      $index += 1
    } elseif (($index + 1) -ge $rawArguments.Count) {
      Write-ErrorLine "setup-mcp: $option requires a value"
      exit 2
    } else {
      $Runner = [string]$rawArguments[$index + 1]
      $index += 2
    }
    continue
  }

  if ($optionName -ieq '-Channel') {
    if ($seenOptions.ContainsKey('Channel')) {
      Write-ErrorLine "setup-mcp: repeated option $option"
      exit 2
    }
    $seenOptions['Channel'] = $true
    $ChannelSet = $true
    if ($hasAttachedValue) {
      if ($attachedValue.Length -eq 0) {
        Write-ErrorLine "setup-mcp: $option requires a value"
        exit 2
      }
      $Channel = $attachedValue
      $index += 1
    } elseif (($index + 1) -ge $rawArguments.Count) {
      Write-ErrorLine "setup-mcp: $option requires a value"
      exit 2
    } else {
      $Channel = [string]$rawArguments[$index + 1]
      $index += 2
    }
    continue
  }

  if ($optionName -ieq '-NoRedact') {
    if ($seenOptions.ContainsKey('NoRedact')) {
      Write-ErrorLine "setup-mcp: repeated option $option"
      exit 2
    }
    $seenOptions['NoRedact'] = $true
    if ($hasAttachedValue) {
      if (@('true', '$true') -contains $attachedValue) {
        $NoRedact = $true
      } elseif (@('false', '$false') -contains $attachedValue) {
        $NoRedact = $false
      } else {
        Write-ErrorLine "setup-mcp: invalid value for $option"
        exit 2
      }
    } else {
      $NoRedact = $true
    }
    $index += 1
    continue
  }

  Write-ErrorLine "setup-mcp: unknown option $option"
  exit 2
}

# Validate manually so a bad value follows setup-mcp.sh's exit-2 contract.
if (@('auto', 'claude', 'codex', 'opencode') -cnotcontains $Agent) {
  Write-ErrorLine "setup-mcp: unknown agent $Agent"
  exit 2
}
if ($ChannelSet -and @('beta', 'dev', 'canary') -cnotcontains $Channel) {
  Write-ErrorLine "setup-mcp: invalid channel $Channel"
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
  $argsList = @('chrome-devtools-mcp@latest', '--autoConnect')
  if (-not $NoRedact) { $argsList += '--redactNetworkHeaders' }
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
  $target = './.mcp.json'
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
    Write-JsonFile $target $doc
    Write-Info "setup-mcp: $(if ($hadFile) { 'merged chrome-devtools into' } else { 'wrote' }) $target"
  } catch {
    Write-ErrorLine $_.Exception.Message
    Set-ExitCode 3
  }
}

function Write-Opencode {
  $target = './opencode.json'
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
    Write-JsonFile $target $doc
    Write-Info "setup-mcp: $(if ($hadFile) { 'merged chrome-devtools into' } else { 'wrote' }) $target"
  } catch {
    Write-ErrorLine $_.Exception.Message
    Set-ExitCode 3
  }
}

function Write-Codex {
  try {
    $r = Get-RunnerParts
    $cmd = @('mcp', 'add', 'chrome-devtools', '--') + @($r.Command) + @($r.Args) + @(Get-ServerArgs)
    Write-Info 'setup-mcp: Codex has no project-scoped MCP config; this writes to your GLOBAL Codex config (~/.codex/config.toml).'
    Write-Info "setup-mcp: this is Codex's global config, not a project config."
    if (Get-Command codex -ErrorAction SilentlyContinue) {
      & codex @cmd
      $codexRc = $LASTEXITCODE
      if ($codexRc -eq 0) {
        Write-Info 'setup-mcp: registered chrome-devtools with the Codex CLI'
      } else {
        Write-ErrorLine "setup-mcp: \"codex $($cmd -join ' ')\" failed; run it yourself:"
        Write-Info "codex $($cmd -join ' ')"
        Set-ExitCode 3
      }
    } else {
      Write-Info 'setup-mcp: the codex CLI is not on PATH. Run this yourself:'
      Write-Info "codex $($cmd -join ' ')"
      Set-ExitCode 3
    }
  } catch {
    Write-ErrorLine $_.Exception.Message
    Set-ExitCode 3
  }
}

function Get-DetectedAgents {
  $found = @()
  if ((Test-Path -LiteralPath './.mcp.json' -PathType Leaf) -or
      (Test-Path -LiteralPath './.claude' -PathType Container) -or
      (Get-Command claude -ErrorAction SilentlyContinue)) {
    $found += 'claude'
  }
  if ((Test-Path -LiteralPath './opencode.json' -PathType Leaf) -or
      (Get-Command opencode -ErrorAction SilentlyContinue)) {
    $found += 'opencode'
  }
  if ((Test-Path -LiteralPath (Join-Path $HOME '.codex/config.toml') -PathType Leaf) -or
      (Get-Command codex -ErrorAction SilentlyContinue)) {
    $found += 'codex'
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
      'codex'    { Write-Codex }
    }
  }
  Write-Info 'setup-mcp: restart your agent so it loads the MCP server.'
  exit $script:ExitCode
} catch {
  Write-ErrorLine $_.Exception.Message
  exit 3
}
