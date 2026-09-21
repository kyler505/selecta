#!/usr/bin/env pwsh
# selecta.ps1: destination picker for new terminal windows on Windows.
#
# Counterpart of the zsh `selecta` (macOS/ghostty, and a shell inside WSL).
# WezTerm runs this as its default_prog; see the repo README for the exact
# default_prog line. No fzf here - it is not installed on Windows and three
# entries do not need fuzzy search.

[CmdletBinding()]
param(
  # Print the command an entry would run, and exit. Used by tests.
  [string]$Print
)

$script:SelectaAccent = "$([char]27)[38;2;137;220;235m"
$script:SelectaDim = "$([char]27)[38;2;166;173;200m"
$script:SelectaReset = "$([char]27)[0m"

$script:SelectaLabels = @{
  pwsh  = 'PowerShell 7'
  wsl   = 'WSL (Ubuntu)'
  herdr = 'herdr (Windows)'
}

function Get-SelectaDistro {
  if ($env:SELECTA_WSL_DISTRO) { return $env:SELECTA_WSL_DISTRO }
  return 'Ubuntu'
}

function Test-SelectaCommand {
  param([Parameter(Mandatory)][string]$Name)
  return [bool](Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue)
}

function Get-SelectaEntries {
  # Fixed order; an entry is omitted when its binary is missing. `pwsh` is
  # always present - it is the process running this script.
  $entries = @('pwsh')
  if (Test-SelectaCommand 'wsl') { $entries += 'wsl' }
  if (Test-SelectaCommand 'herdr') { $entries += 'herdr' }
  return $entries
}

function Get-SelectaTarget {
  # Single source of truth for dispatch: what to run, and whether a shell
  # follows it. Unknown entries fall back to the plain shell.
  param([string]$Entry)
  switch ($Entry) {
    'wsl' {
      # The home directory is reached with a shell-side `cd ~`, not `wsl --cd ~`:
      # PowerShell resolves a bare `~` argument to the Windows home before
      # wsl.exe sees it, so `--cd ~` lands in /mnt/c/Users/<user>. /bin/sh runs
      # the cd because `sh -c` reads no rc files; zsh then replaces it.
      return [pscustomobject]@{
        File      = 'wsl.exe'
        Arguments = @('-d', (Get-SelectaDistro), '--', '/bin/sh', '-c', 'cd ~ && exec /usr/bin/zsh -l')
        ThenShell = $false
      }
    }
    'herdr' {
      # Same rule as the zsh version: herdr runs in the foreground and leaves
      # you at a shell after detach, instead of closing the window.
      return [pscustomobject]@{
        File      = 'herdr'
        Arguments = @()
        ThenShell = $true
      }
    }
    default {
      return [pscustomobject]@{
        File      = 'pwsh'
        Arguments = @('-NoLogo')
        ThenShell = $false
      }
    }
  }
}

function Get-SelectaCommand {
  param([string]$Entry)
  $target = Get-SelectaTarget -Entry $Entry
  $parts = @($target.File) + $target.Arguments
  $command = $parts -join ' '
  if ($target.ThenShell) { $command = "$command; pwsh -NoLogo" }
  return $command
}

function Show-SelectaMenu {
  param([Parameter(Mandatory)][string[]]$Entries)

  $hint = "Up/Down or 1-$($Entries.Count), Enter to open, Esc for a plain shell"
  Write-Host ''
  Write-Host "  ${script:SelectaAccent}Open:${script:SelectaReset} ${script:SelectaDim}${hint}${script:SelectaReset}"
  Write-Host ''

  $index = 0
  $origin = [Console]::CursorTop
  $cursorWasVisible = [Console]::CursorVisible
  # Ctrl-C must land on a plain shell like the zsh version, so read it as a key
  # instead of letting it kill the script.
  $treatCtrlC = [Console]::TreatControlCAsInput
  [Console]::CursorVisible = $false
  [Console]::TreatControlCAsInput = $true
  try {
    while ($true) {
      [Console]::SetCursorPosition(0, $origin)
      for ($i = 0; $i -lt $Entries.Count; $i++) {
        $label = $script:SelectaLabels[$Entries[$i]]
        if (-not $label) { $label = $Entries[$i] }
        $row = "$($i + 1)  $label"
        if ($i -eq $index) {
          Write-Host "  ${script:SelectaAccent}> $row${script:SelectaReset}"
        }
        else {
          Write-Host "    $row"
        }
      }

      $key = [Console]::ReadKey($true)
      switch ($key.Key) {
        'UpArrow' { $index = ($index - 1 + $Entries.Count) % $Entries.Count }
        'DownArrow' { $index = ($index + 1) % $Entries.Count }
        'K' { $index = ($index - 1 + $Entries.Count) % $Entries.Count }
        'J' { $index = ($index + 1) % $Entries.Count }
        'Enter' { return $Entries[$index] }
        'Escape' { return 'pwsh' }
        'C' {
          if ($key.Modifiers -band [ConsoleModifiers]::Control) { return 'pwsh' }
        }
        default {
          $digit = $key.KeyChar
          if ($digit -match '^[1-9]$') {
            $pick = [int]::Parse($digit) - 1
            if ($pick -lt $Entries.Count) { return $Entries[$pick] }
          }
        }
      }
    }
  }
  finally {
    [Console]::CursorVisible = $cursorWasVisible
    [Console]::TreatControlCAsInput = $treatCtrlC
  }
}

function Invoke-SelectaEntry {
  # PowerShell has no exec, so the target runs as a child in this console and
  # this script exits with its code: closing the destination closes the pane.
  param([string]$Entry)
  $target = Get-SelectaTarget -Entry $Entry
  if ($target.Arguments.Count -gt 0) {
    & $target.File @($target.Arguments)
  }
  else {
    & $target.File
  }
  $code = $LASTEXITCODE
  if ($target.ThenShell) {
    & 'pwsh' '-NoLogo'
    $code = $LASTEXITCODE
  }
  exit $code
}

function main {
  if ($Print) {
    Get-SelectaCommand -Entry $Print
    return
  }
  if ($env:SELECTA_SKIP -eq '1') {
    Invoke-SelectaEntry -Entry 'pwsh'
  }
  if ([Console]::IsInputRedirected) {
    Write-Host 'selecta: no interactive console; starting PowerShell'
    Invoke-SelectaEntry -Entry 'pwsh'
  }
  $entry = Show-SelectaMenu -Entries (Get-SelectaEntries)
  # Leave the pane as clean as a normal shell start; the prompt says where you
  # landed, so the menu does not need to stay in the scrollback.
  [Console]::Clear()
  Invoke-SelectaEntry -Entry $entry
}

# Dot-sourcing (tests) loads the functions only.
if ($MyInvocation.InvocationName -ne '.') { main }
