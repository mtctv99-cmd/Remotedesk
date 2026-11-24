#Requires -RunAsAdministrator
<#
First-run / upgrade installer for the DeskAgent Windows client package.

The zip produced by scripts\make-client-package.ps1 contains the Release files
next to this script. Running install-client.cmd (or this file from an elevated
shell) installs the files under Program Files, registers the Windows service so
the SYSTEM daemon can auto-update/accept sessions, and starts the tray UI.

The install is staged: files are copied to a sibling directory, the service is
stopped through the SCM, the old directory is moved aside, and the staged one
takes its place. The previous directory is kept until the new build is running,
so a failed start restores it instead of leaving Program Files half-updated.
#>

$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$dst = Join-Path $env:ProgramFiles 'DeskAgent'
$svcName = 'DeskAgent'
$srcExe = Join-Path $src 'deskagent.exe'
$dstExe = Join-Path $dst 'deskagent.exe'

if (-not (Test-Path $srcExe)) {
    throw "deskagent.exe not found next to install-client.ps1 ($src)"
}

$stamp = Get-Date -Format 'yyyyMMddHHmmssfff'
$stage = Join-Path $env:ProgramFiles "DeskAgent.new-$stamp"
$old = Join-Path $env:ProgramFiles "DeskAgent.old-$stamp"
$keep = @('meta.toml')

function Get-AgentService { Get-Service -Name $svcName -ErrorAction SilentlyContinue }

function Stop-Agent {
    $svc = Get-AgentService
    if ($svc -and $svc.Status -ne 'Stopped') {
        Write-Host "Stopping DeskAgent service ($($svc.Status)) ..."
        Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
        try { (Get-AgentService).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20)) } catch { Write-Warning "Service stop wait: $_" }
    }
    # Only the tray processes need a direct kill; the service exits via the SCM.
    Get-Process deskagent -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            if ($_.Path -and $_.Path.StartsWith($dst, 'OrdinalIgnoreCase')) {
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    Start-Sleep -Seconds 1
}

Write-Host "Installing DeskAgent to $dst ..."
$samePath = (Resolve-Path $src).Path -eq $dst
$swapped = $false

function Restore-PreviousInstall {
    if (-not $swapped) { return }
    Write-Warning 'The new build did not start; restoring the previous install.'
    Stop-Agent
    Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue
    Move-Item -LiteralPath $old -Destination $dst -ErrorAction SilentlyContinue
    $restored = Get-AgentService
    if ($restored -and $restored.Status -ne 'Running') {
        Start-Service -Name $svcName -ErrorAction SilentlyContinue
    }
}

if (-not $samePath) {
    Write-Host 'Staging files ...'
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Get-ChildItem $src -Force | Where-Object {
        $_.Name -notin @('install-client.ps1', 'install-client.cmd', 'README.txt') -and
        $_.Extension -ne '.zip'
    } | ForEach-Object {
        Copy-Item $_.FullName $stage -Recurse -Force
    }
    if (Test-Path $dst) {
        foreach ($name in $keep) {
            $saved = Join-Path $dst $name
            if (Test-Path $saved) { Copy-Item $saved $stage -Force }
        }
    }

    Stop-Agent
    try {
        if (Test-Path $dst) {
            Move-Item -LiteralPath $dst -Destination $old -ErrorAction Stop
            $swapped = $true
        }
        Move-Item -LiteralPath $stage -Destination $dst -ErrorAction Stop
    } catch {
        Write-Warning "Install swap failed: $_"
        if ($swapped) {
            Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue
            Move-Item -LiteralPath $old -Destination $dst -ErrorAction SilentlyContinue
        }
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
} else {
    Stop-Agent
}

$svc = Get-AgentService
if (-not $svc) {
    Write-Host 'Registering DeskAgent Windows service ...'
    & $dstExe --install-service
    Start-Sleep -Seconds 5
    $svc = Get-AgentService
    if ($svc) {
        try { $svc.WaitForStatus('Running', [TimeSpan]::FromSeconds(30)) } catch { Write-Warning "Service start wait: $_" }
    }
} else {
    # A previous install may point the service at another directory; repoint it
    # instead of calling --install-service (sc create fails on an existing name
    # and the failure path disables the service).
    & sc.exe config $svcName binPath= "`"$dstExe`" --service" start= auto | Out-Null
    if ($svc.Status -ne 'Running') {
        Start-Service -Name $svcName
    }
    try { (Get-AgentService).WaitForStatus('Running', [TimeSpan]::FromSeconds(30)) } catch { Write-Warning "Service start wait: $_" }
}

$svc = Get-AgentService
if (-not $svc -or $svc.Status -ne 'Running') {
    Restore-PreviousInstall
    $state = if ($svc) { $svc.Status } else { 'not registered' }
    throw "DeskAgent service is not running ($state)"
}

$installed = (& $dstExe --version 2>$null | Select-Object -First 1)
Write-Host "Installed version: $installed"
Remove-Item $old -Recurse -Force -ErrorAction SilentlyContinue

if ([System.Diagnostics.Process]::GetCurrentProcess().SessionId -ne 0) {
    $tray = Get-Process deskagent -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($dst, 'OrdinalIgnoreCase') } catch { $false }
    }
    if (-not $tray) {
        Write-Host 'Starting DeskAgent tray ...'
        Start-Process -FilePath $dstExe -ArgumentList '--tray'
    }
}

Write-Host 'Done. DeskAgent is installed and the SYSTEM service will handle updates.'
