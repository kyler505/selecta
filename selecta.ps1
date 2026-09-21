#!/usr/bin/env pwsh
# selecta.ps1: destination picker for new terminal windows on Windows.
#
# Port of the zsh `selecta`, function for function: same fzf menu, same entry
# order (multiplexer, second local target, plain shell, then one entry per ssh
# host), same `--print` dry-run, same `SELECTA_SKIP` bypass, same fallback to a
# plain shell on Esc / Ctrl-C / missing fzf. Only the destinations differ,
# because the platform does: `tmux` becomes `wsl`, and the plain shell is
# PowerShell 7 instead of zsh.
#
# WezTerm runs this as its default_prog; see the README for the exact line.

[CmdletBinding()]
param(
  # Print the command an entry would run instead of running it. Tests use this.
  [string]$Print
)

function Get-SelectaHosts {
  $config = if ($env:SELECTA_SSH_CONFIG_FILE) { $env:SELECTA_SSH_CONFIG_FILE } else { "$HOME\.ssh\config" }
  if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { return @() }
  $hosts = foreach ($line in Get-Content -LiteralPath $config) {
    $line = ($line -split '#', 2)[0]                          # strip comments
    if ($line -notmatch '^\s*[Hh][Oo][Ss][Tt]\s') { continue }
    foreach ($h in ($line -replace '^\s*[Hh][Oo][Ss][Tt]\s+', '') -split '\s+') {
      if (-not $h) { continue }
      if ($h -match '[*?!]') { continue }                     # patterns are not hosts
      $h
    }
  }
  return @($hosts | Sort-Object -Unique)
}

function Test-SelectaCommand {
  param([Parameter(Mandatory)][string]$Name)
  return [bool](Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue)
}

function Get-SelectaDistro {
  if ($env:SELECTA_WSL_DISTRO) { return $env:SELECTA_WSL_DISTRO }
  return 'Ubuntu'
}

function Get-SelectaEntries {
  # Fixed order, omitting entries whose binary is missing. `shell` is always
  # available: it is the process running this script.
  $entries = @()
  if (Test-SelectaCommand 'herdr') { $entries += 'herdr' }
  if (Test-SelectaCommand 'wsl') { $entries += 'wsl' }
  $entries += 'shell'
  foreach ($h in Get-SelectaHosts) { $entries += "ssh: $h" }
  return $entries
}

function Get-SelectaTarget {
  # Single source of truth for dispatch: the executable, its arguments, and
  # whether a plain shell follows. Unknown entries fall back to the shell.
  param([string]$Entry)

  if ($Entry -like 'ssh: *') {
    $remote = 'export PATH="$HOME/.local/bin:$PATH"; command -v fastfetch >/dev/null 2>&1 && fastfetch; exec "${SHELL:-/bin/sh}" -l'
    return [pscustomobject]@{
      File      = 'ssh'
      Arguments = @('-t', $Entry.Substring(5), $remote)
      ThenShell = $false
    }
  }

  switch ($Entry) {
    'herdr' {
      # Same rule as the zsh version: herdr runs in the foreground and leaves
      # you at a shell after detach instead of closing the window.
      return [pscustomobject]@{ File = 'herdr'; Arguments = @(); ThenShell = $true }
    }
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
    default {
      return [pscustomobject]@{ File = 'pwsh'; Arguments = @('-NoLogo'); ThenShell = $false }
    }
  }
}

function Get-SelectaCommand {
  param([string]$Entry)
  $target = Get-SelectaTarget -Entry $Entry
  $parts = @($target.File) + @($target.Arguments | ForEach-Object {
      if ($_ -match '\s') { "'$_'" } else { $_ }
    })
  $command = $parts -join ' '
  if ($target.ThenShell) { $command = "$command; pwsh -NoLogo" }
  return $command
}

function Invoke-SelectaEntry {
  # PowerShell has no exec, so the target runs as a child in this console and
  # this script exits with its code: closing the destination closes the pane,
  # the same way `exec` ends the zsh version's window.
  param([string]$Entry)
  $target = Get-SelectaTarget -Entry $Entry
  if ($target.Arguments.Count -gt 0) { & $target.File @($target.Arguments) } else { & $target.File }
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
    Invoke-SelectaEntry -Entry 'shell'
  }
  if (-not (Test-SelectaCommand 'fzf')) {
    Write-Host 'selecta: fzf not found; starting plain shell'
    Invoke-SelectaEntry -Entry 'shell'
  }
  $entries = Get-SelectaEntries
  $header = 'herdr  wsl  shell  ssh: <host>   (Esc = plain shell)'
  $selection = $entries | fzf --height=100% --border --no-multi --header=$header --prompt='Open: '
  if ($LASTEXITCODE -ne 0 -or -not $selection) {
    Invoke-SelectaEntry -Entry 'shell'
  }
  Invoke-SelectaEntry -Entry $selection
}

# Dot-sourcing (tests) loads the functions only.
if ($MyInvocation.InvocationName -ne '.') { main }
