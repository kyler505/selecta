#!/usr/bin/env pwsh
# Tests for selecta.ps1, mirroring tests/run.sh: host parsing against the shared
# fixture, entry assembly with fake binaries, and dispatch via -Print.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../selecta.ps1"

$script:fail = 0
function check {
  param([string]$Name, [string]$Expected, [string]$Actual)
  if ($Expected -ne $Actual) {
    Write-Host "FAIL: $Name`nexpected: [$Expected]`nactual:   [$Actual]"
    $script:fail = 1
  }
  else {
    Write-Host "ok: $Name"
  }
}

$env:SELECTA_SSH_CONFIG_FILE = "$PSScriptRoot/fixtures/ssh_config"

check 'hosts parsed, sorted, patterns skipped, case-insensitive directives' `
  'homelab hp lower mixed opmicro upper' ((Get-SelectaHosts) -join ' ')

# Entry assembly: fake binaries in a temp dir, with the real PATH kept out, so
# the "absent" expectations are reachable on any machine.
$realPath = $env:PATH
$fakeBin = Join-Path ([System.IO.Path]::GetTempPath()) "selecta-fake-$PID"
$bareBin = Join-Path ([System.IO.Path]::GetTempPath()) "selecta-bare-$PID"
New-Item -ItemType Directory -Force -Path $fakeBin, $bareBin | Out-Null
try {
  foreach ($fake in 'wsl', 'herdr') {
    Set-Content -Path (Join-Path $fakeBin "$fake.cmd") -Value '@echo off'
  }

  $env:PATH = $fakeBin
  check 'entries with wsl+herdr present' `
    'herdr wsl shell ssh: homelab ssh: hp ssh: lower ssh: mixed ssh: opmicro ssh: upper' `
    ((Get-SelectaEntries) -join ' ')

  $env:PATH = $bareBin
  check 'entries without wsl/herdr' `
    'shell ssh: homelab ssh: hp ssh: lower ssh: mixed ssh: opmicro ssh: upper' `
    ((Get-SelectaEntries) -join ' ')
}
finally {
  $env:PATH = $realPath
  Remove-Item -Recurse -Force $fakeBin, $bareBin
}

$missingConfig = Join-Path ([System.IO.Path]::GetTempPath()) "selecta-no-ssh-$PID"
$env:SELECTA_SSH_CONFIG_FILE = $missingConfig
check 'no ssh config means no ssh entries' 'shell' `
  (((Get-SelectaEntries) | Where-Object { $_ -notin 'herdr', 'wsl' }) -join ' ')
$env:SELECTA_SSH_CONFIG_FILE = "$PSScriptRoot/fixtures/ssh_config"

# Dispatch, rendered as commands instead of executed.
check 'dispatch shell' 'pwsh -NoLogo' (Get-SelectaCommand -Entry 'shell')
check 'dispatch wsl' "wsl.exe -d Ubuntu -- /bin/sh -c 'cd ~ && exec /usr/bin/zsh -l'" `
  (Get-SelectaCommand -Entry 'wsl')
check 'dispatch herdr' 'herdr; pwsh -NoLogo' (Get-SelectaCommand -Entry 'herdr')
check 'dispatch ssh with fastfetch' `
  'ssh -t hp ''export PATH="$HOME/.local/bin:$PATH"; command -v fastfetch >/dev/null 2>&1 && fastfetch; exec "${SHELL:-/bin/sh}" -l''' `
  (Get-SelectaCommand -Entry 'ssh: hp')
check 'dispatch garbage' 'pwsh -NoLogo' (Get-SelectaCommand -Entry 'bogus')

$env:SELECTA_WSL_DISTRO = 'Debian'
try {
  check 'dispatch wsl honors SELECTA_WSL_DISTRO' `
    "wsl.exe -d Debian -- /bin/sh -c 'cd ~ && exec /usr/bin/zsh -l'" (Get-SelectaCommand -Entry 'wsl')
}
finally {
  Remove-Item Env:SELECTA_WSL_DISTRO
  Remove-Item Env:SELECTA_SSH_CONFIG_FILE
}

exit $script:fail
