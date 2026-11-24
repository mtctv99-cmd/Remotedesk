#Requires -RunAsAdministrator
<#
First-run installer for the DeskAgent Windows client package.

The zip produced by scripts\make-client-package.ps1 contains the Release files
next to this script. Running install-client.cmd (or this file from an elevated
shell) installs the files under Program Files, registers the Windows service so
the SYSTEM daemon can auto-update/accept sessions, and starts the tray UI.
#>

$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$dst = Join-Path $env:ProgramFiles 'DeskAgent'
$srcExe = Join-Path $src 'deskagent.exe'
$dstExe = Join-Path $dst 'deskagent.exe'

if (-not (Test-Path $srcExe)) {
    throw "deskagent.exe not found next to install-client.ps1 ($src)"
}

Write-Host "Installing DeskAgent to $dst ..."
Get-Process deskagent -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

New-Item -ItemType Directory -Force -Path $dst | Out-Null
$keep = @('manager_client_id', 'meta.toml')
$backup = Join-Path $env:TEMP ('DeskAgent-config-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $backup | Out-Null
foreach ($name in $keep) {
    $path = Join-Path $dst $name
    if (Test-Path $path) { Copy-Item $path $backup -Force }
}

if ((Resolve-Path $src).Path -ne (Resolve-Path $dst).Path) {
    Get-ChildItem $src -Force | Where-Object {
        $_.Name -notin @('install-client.ps1', 'install-client.cmd', 'README.txt') -and
        $_.Extension -ne '.zip'
    } | ForEach-Object {
        Copy-Item $_.FullName $dst -Recurse -Force
    }
}

foreach ($name in $keep) {
    $saved = Join-Path $backup $name
    if (Test-Path $saved) { Copy-Item $saved $dst -Force }
}
Remove-Item $backup -Recurse -Force -ErrorAction SilentlyContinue

Write-Host 'Registering DeskAgent Windows service ...'
& $dstExe --install-service
Start-Sleep -Seconds 5

Write-Host 'Starting DeskAgent tray ...'
Start-Process -FilePath $dstExe -ArgumentList '--tray'

Write-Host 'Done. DeskAgent is installed and the SYSTEM service will handle updates.'
