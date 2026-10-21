<#
.SYNOPSIS
    DeskAgent Physical NIC & Hardware Driver Optimization Script
.DESCRIPTION
    Configures physical Network Interface Cards (NIC) at the NDIS miniport driver
    level for ultra-low latency remote desktop streaming across LAN and VLANs.
    Tuning targets:
      1. Hardware Offload (IPv4, TCP, UDP Checksum ASIC offload)
      2. Ring Buffers expansion (Receive/Transmit ring buffers)
      3. Latency tuning (Interrupt Moderation Rate -> Low)
      4. Disabling Energy Efficient Ethernet (EEE / 802.3az) and power-saving sleep latency
      5. Windows TCP/IP stack & QoS (DSCP 46 Expedited Forwarding for DeskAgent)
.PARAMETER Revert
    Reverts settings back to standard Windows defaults.
.PARAMETER TargetAdapter
    Specific adapter name (e.g. "Ethernet"). If omitted, tunes all active physical adapters.
#>

[CmdletBinding()]
param (
    [switch]$Revert,
    [string]$TargetAdapter = ""
)

$ErrorActionPreference = "SilentlyContinue"

# Require Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Requires Administrator privilege. Please run in an elevated PowerShell session."
    exit 1
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " DeskAgent Hardware NIC Driver & Network Optimizer        " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Locate physical adapters
$physicalAdapters = Get-NetAdapter -Physical | Where-Object {
    if ($TargetAdapter) {
        $_.Name -eq $TargetAdapter
    } else {
        $_.Status -eq "Up"
    }
}

if (-not $physicalAdapters) {
    Write-Warning "No active physical network adapters found."
    exit 0
}

function Set-AdapterPropertySafe {
    param (
        [string]$AdapterName,
        [string]$DisplayName,
        [string]$Value
    )
    $prop = Get-NetAdapterAdvancedProperty -Name $AdapterName -DisplayName $DisplayName -ErrorAction SilentlyContinue
    if ($prop) {
        try {
            Set-NetAdapterAdvancedProperty -Name $AdapterName -DisplayName $DisplayName -DisplayValue $Value -NoRestart -ErrorAction Stop
            Write-Host "  [+] $AdapterName : $DisplayName -> $Value" -ForegroundColor Green
        } catch {
            Write-Host "  [-] $AdapterName : $DisplayName (not supported or invalid value '$Value')" -ForegroundColor DarkGray
        }
    }
}

foreach ($adapter in $physicalAdapters) {
    Write-Host "`n[*] Tuning Physical Adapter: $($adapter.Name) ($($adapter.InterfaceDescription))" -ForegroundColor Yellow

    if ($Revert) {
        Write-Host "  --> Reverting to factory/standard defaults..." -ForegroundColor Yellow
        Set-AdapterPropertySafe -AdapterName $adapter.Name -DisplayName "Energy Efficient Ethernet" -Value "On"
        Set-AdapterPropertySafe -AdapterName $adapter.Name -DisplayName "Interrupt Moderation Rate" -Value "Adaptive"
        Set-AdapterPropertySafe -AdapterName $adapter.Name -DisplayName "Receive Buffers" -Value "256"
        Set-AdapterPropertySafe -AdapterName $adapter.Name -DisplayName "Transmit Buffers" -Value "512"
        Set-AdapterPropertySafe -AdapterName $adapter.Name -DisplayName "PCI Express Link Power Saving" -Value "Enabled"
        Set-AdapterPropertySafe -AdapterName $adapter.Name -DisplayName "Ultra Low Power Mode" -Value "Enabled"
        continue
    }

    # 1. Hardware Checksum Offload (ASIC does calculation, 0% CPU overhead)
    Set-AdapterPropertySafe -AdapterName $adapter.Name -DisplayName "IPv4 Checksum Offload" -Value "Rx & Tx Enabled"
    Set-AdapterPropertySafe -AdapterName $adapter.Name -DisplayName "TCP Checksum Offload (IPv4)" -Value "Rx & Tx Enabled"
    Set-AdapterPropertySafe -AdapterName $adapter.Name -DisplayName "UDP Checksum Offload (IPv4)" -Value "Rx & Tx Enabled"
    Set-AdapterPropertySafe -AdapterName $adapter.Name -DisplayName "Flow Control" -Value "Rx & Tx Enabled"

    # 2. Eliminate Sleep/Wake Latency Spikes (EEE, Green Ethernet, PCIe ASPM)
    # EEE (802.3az) drops PHY into sleep, adding 20-50us latency and micro-stuttering on bursts.
    Set-AdapterPropertySafe -AdapterName $adapter.Name -DisplayName "Energy Efficient Ethernet" -Value "Off"
    Set-AdapterPropertySafe -AdapterName $adapter.Name -DisplayName "Green Ethernet" -Value "Disabled"
    Set-AdapterPropertySafe -AdapterName $adapter.Name -DisplayName "PCI Express Link Power Saving" -Value "Disabled"
    Set-AdapterPropertySafe -AdapterName $adapter.Name -DisplayName "System Idle Power Saver" -Value "Disabled"
    Set-AdapterPropertySafe -AdapterName $adapter.Name -DisplayName "Ultra Low Power Mode" -Value "Disabled"
    Set-AdapterPropertySafe -AdapterName $adapter.Name -DisplayName "Link Speed Battery Saver" -Value "Disabled"

    # 3. Latency Tuning: Interrupt Moderation Rate -> Low
    # Low latency mode ensures immediate hardware interrupt on packet arrival.
    Set-AdapterPropertySafe -AdapterName $adapter.Name -DisplayName "Interrupt Moderation Rate" -Value "Low"

    # 4. Ring Buffers: Prevent packet drops during high-FPS video bursts
    Set-AdapterPropertySafe -AdapterName $adapter.Name -DisplayName "Receive Buffers" -Value "1024"
    Set-AdapterPropertySafe -AdapterName $adapter.Name -DisplayName "Transmit Buffers" -Value "1024"

    # 5. Receive Side Scaling (RSS)
    try {
        Enable-NetAdapterRss -Name $adapter.Name -NoRestart -ErrorAction Stop
        Write-Host "  [+] $adapter.Name : Receive Side Scaling (RSS) Enabled" -ForegroundColor Green
    } catch {
        # ignore if not supported
    }

    # Restart adapter once cleanly to commit NDIS register states
    Restart-NetAdapter -Name $adapter.Name
}

# 2. Windows Kernel TCP/IP Global Optimization
Write-Host "`n[*] Configuring Windows Kernel TCP/IP Stack..." -ForegroundColor Yellow
if ($Revert) {
    netsh int tcp set global autotuninglevel=normal | Out-Null
    netsh int tcp set global timestamps=allowed | Out-Null
    Remove-NetQosPolicy -Name "DeskAgent-DirectIP" -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetQosPolicy -Name "DeskAgent-Relay" -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetQosPolicy -Name "DeskAgent-Discovery" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  [+] QoS policies removed and TCP defaults restored." -ForegroundColor Green
} else {
    netsh int tcp set global autotuninglevel=normal | Out-Null
    netsh int tcp set global timestamps=disabled | Out-Null
    netsh int tcp set global ecncapability=enabled | Out-Null
    Write-Host "  [+] TCP AutoTuning = Normal" -ForegroundColor Green
    Write-Host "  [+] TCP Timestamps = Disabled (-12 bytes overhead per packet)" -ForegroundColor Green
    Write-Host "  [+] TCP ECN = Enabled" -ForegroundColor Green

    # 3. Policy-Based QoS (DSCP 46 - Expedited Forwarding for DeskAgent)
    # Ensures L3 enterprise switches/routers prioritize DeskAgent video/audio frames across VLANs.
    Write-Host "`n[*] Configuring Enterprise QoS Policies (DSCP 46 EF)..." -ForegroundColor Yellow

    Remove-NetQosPolicy -Name "DeskAgent-DirectIP" -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetQosPolicy -Name "DeskAgent-Relay" -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetQosPolicy -Name "DeskAgent-Discovery" -Confirm:$false -ErrorAction SilentlyContinue

    New-NetQosPolicy -Name "DeskAgent-DirectIP" -AppPathNameMatchCondition "deskagent.exe" -IPPortMatchCondition 21118 -DSCPAction 46 -NetworkProfile All -ErrorAction SilentlyContinue | Out-Null
    New-NetQosPolicy -Name "DeskAgent-Relay" -AppPathNameMatchCondition "deskagent.exe" -IPPortMatchCondition 21116 -DSCPAction 46 -NetworkProfile All -ErrorAction SilentlyContinue | Out-Null
    New-NetQosPolicy -Name "DeskAgent-Discovery" -AppPathNameMatchCondition "deskagent.exe" -IPPortMatchCondition 21119 -DSCPAction 46 -NetworkProfile All -ErrorAction SilentlyContinue | Out-Null

    Write-Host "  [+] QoS Policy 'DeskAgent-DirectIP' (Port 21118 -> DSCP 46 EF)" -ForegroundColor Green
    Write-Host "  [+] QoS Policy 'DeskAgent-Relay'    (Port 21116 -> DSCP 46 EF)" -ForegroundColor Green
    Write-Host "  [+] QoS Policy 'DeskAgent-Discovery'(Port 21119 -> DSCP 46 EF)" -ForegroundColor Green
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " Hardware NIC & Driver Optimization Complete!            " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
