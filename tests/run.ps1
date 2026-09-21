#!/usr/bin/env pwsh
# Tests for selecta.ps1 (Windows). The zsh script has its own tests/run.sh.
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
  check 'entries with wsl+herdr present' 'pwsh wsl herdr' ((Get-SelectaEntries) -join ' ')

  $env:PATH = $bareBin
  check 'entries without wsl/herdr' 'pwsh' ((Get-SelectaEntries) -join ' ')
}
finally {
  $env:PATH = $realPath
  Remove-Item -Recurse -Force $fakeBin, $bareBin
}
# Dispatch, rendered as commands instead of executed.
check 'command pwsh' 'pwsh -NoLogo' (Get-SelectaCommand -Entry 'pwsh')
check 'command wsl' 'wsl.exe -d Ubuntu -- /bin/sh -c cd ~ && exec /usr/bin/zsh -l' (Get-SelectaCommand -Entry 'wsl')
check 'command herdr' 'herdr; pwsh -NoLogo' (Get-SelectaCommand -Entry 'herdr')
check 'command garbage' 'pwsh -NoLogo' (Get-SelectaCommand -Entry 'bogus')

$env:SELECTA_WSL_DISTRO = 'Debian'
try {
  check 'command wsl honors SELECTA_WSL_DISTRO' `
    'wsl.exe -d Debian -- /bin/sh -c cd ~ && exec /usr/bin/zsh -l' (Get-SelectaCommand -Entry 'wsl')
}
finally {
  Remove-Item Env:SELECTA_WSL_DISTRO
}

exit $script:fail
