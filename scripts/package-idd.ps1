param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$ManifestSha256,
    [Parameter(Mandatory=$true)][string]$Destination
)
$ErrorActionPreference = 'Stop'
if ($ManifestSha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'Supply independently verified SHA256 for idd-sha256.json' }
$manifest = Join-Path $Source 'idd-sha256.json'
if ((Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash -ne $ManifestSha256) { throw 'IDD manifest hash mismatch' }
$hashes = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
$files = @('dylib_virtual_display.dll', 'RustDeskIddDriver/rustdeskidddriver.cat', 'RustDeskIddDriver/RustDeskIddDriver.dll', 'RustDeskIddDriver/RustDeskIddDriver.inf')
foreach ($file in $files) {
    $hash = $hashes.$file
    if ($hash -notmatch '^[0-9a-fA-F]{64}$' -or (Get-FileHash -LiteralPath (Join-Path $Source $file) -Algorithm SHA256).Hash -ne $hash) { throw "IDD payload hash mismatch: $file" }
}
$signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $Source $files[1])
if ($signature.Status -ne 'Valid' -or !$signature.SignerCertificate -or
    $signature.SignerCertificate.Thumbprint -eq 'D1DBB672D5A500B9809689CAEA1CE49E799767F0' -or
    $signature.SignerCertificate.Subject -match '(?i)test|WDK') { throw 'IDD catalog requires trusted production signer; test signing forbidden' }
# Only allowlisted payload enters release; never execute archive helpers or import certificates.
foreach ($file in $files) {
    $target = Join-Path $Destination $file
    New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $Source $file) -Destination $target -Force
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $hashes.$file) { throw "Copied IDD hash mismatch: $file" }
}
