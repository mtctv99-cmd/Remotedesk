$ErrorActionPreference = 'Stop'
$testDir = Join-Path $env:TEMP ('idd-test-' + [guid]::NewGuid().ToString())
$destDir = Join-Path $testDir 'dest'
$srcDir = Join-Path $testDir 'src'
New-Item -ItemType Directory -Path (Join-Path $srcDir 'RustDeskIddDriver') -Force | Out-Null
New-Item -ItemType Directory -Path $destDir -Force | Out-Null

$dummy = [byte[]]@(0..10)
[System.IO.File]::WriteAllBytes((Join-Path $srcDir 'dylib_virtual_display.dll'), $dummy)
[System.IO.File]::WriteAllBytes((Join-Path $srcDir 'RustDeskIddDriver\rustdeskidddriver.cat'), $dummy)
[System.IO.File]::WriteAllBytes((Join-Path $srcDir 'RustDeskIddDriver\RustDeskIddDriver.dll'), $dummy)
[System.IO.File]::WriteAllBytes((Join-Path $srcDir 'RustDeskIddDriver\RustDeskIddDriver.inf'), $dummy)

$hashes = [ordered]@{
    'dylib_virtual_display.dll' = (Get-FileHash -LiteralPath (Join-Path $srcDir 'dylib_virtual_display.dll') -Algorithm SHA256).Hash
    'RustDeskIddDriver/rustdeskidddriver.cat' = (Get-FileHash -LiteralPath (Join-Path $srcDir 'RustDeskIddDriver\rustdeskidddriver.cat') -Algorithm SHA256).Hash
    'RustDeskIddDriver/RustDeskIddDriver.dll' = (Get-FileHash -LiteralPath (Join-Path $srcDir 'RustDeskIddDriver\RustDeskIddDriver.dll') -Algorithm SHA256).Hash
    'RustDeskIddDriver/RustDeskIddDriver.inf' = (Get-FileHash -LiteralPath (Join-Path $srcDir 'RustDeskIddDriver\RustDeskIddDriver.inf') -Algorithm SHA256).Hash
}
$manifest = Join-Path $srcDir 'idd-sha256.json'
Set-Content -LiteralPath $manifest -Value ($hashes | ConvertTo-Json)
$manifestHash = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash

$packagingScript = Join-Path $PSScriptRoot 'package-idd.ps1'
try {
    & $packagingScript -Source $srcDir -ManifestSha256 $manifestHash -Destination $destDir
    throw 'Check failed: untrusted driver must be rejected'
} catch {
    if ($_ -match 'trusted production signer') {
        Write-Output 'IDD check passed: untrusted/test certificate rejected'
    } else {
        throw $_
    }
} finally {
    Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
}
