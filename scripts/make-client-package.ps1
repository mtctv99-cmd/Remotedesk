# Build the Windows client package that the admin console serves.
#
# The console offers the newest file that ends in .zip or that is named
# deskagent-*-install.exe out of its data directory. This builds the zip:
# the client build, the zero config installer and a short note.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\make-client-package.ps1
#
# The result goes to the desktop of the build machine; copy it into the
# data directory of the manager on the server:
#   scp DeskAgent-Windows-x64.zip ubuntu@<server>:~/deskagent/deploy/manager-data/

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$releaseTag = 'deskagent-release-20261124'

Push-Location $root
try {
    & git diff --exit-code $releaseTag 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Source has drifted from $releaseTag. Restore it or create a new release tag before packaging."
    }
    $untracked = & git ls-files --others --exclude-standard flutter/lib
    if ($untracked) {
        throw "Untracked UI files found: $($untracked -join ', ')"
    }
} finally {
    Pop-Location
}

$release = Join-Path $root 'flutter\build\windows\x64\runner\Release'
$stage = Join-Path $env:TEMP "pkg\DeskAgent-Windows-x64"
$zip = Join-Path $env:TEMP 'DeskAgent-Windows-x64.zip'

if (-not (Test-Path (Join-Path $release 'deskagent.exe'))) {
    Write-Host "No client build in $release. Run scripts\deskagent-build.cmd first." -ForegroundColor Red
    exit 1
}

Remove-Item (Split-Path $stage -Parent) -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item "$release\*" $stage -Recurse -Force

# The zero config installer, so a fresh machine can be set up from the
# download: it writes the server address and the key into every user
# profile, registers the service, opens the firewall and sets the password.
Copy-Item (Join-Path $root 'scripts\install-client.ps1') $stage -Force

@"
DeskAgent v1.5.2 - client package for Windows x64.

Fresh install:
  1. Unpack this archive anywhere.
  2. Run install-client.ps1 as Administrator.
  3. The client registers itself with the manager and starts reporting its
     inventory and its events.

Upgrade of an existing install:
  The admin console unpacks this archive over the running client and
  restarts it; nothing else is needed.
"@ | Set-Content "$stage\README.txt" -Encoding utf8

Remove-Item $zip -Force -ErrorAction SilentlyContinue
Compress-Archive -Path "$stage\*" -DestinationPath $zip -Force
Write-Host ("package: {0} ({1} MB)" -f $zip, [math]::Round((Get-Item $zip).Length / 1MB, 1))
