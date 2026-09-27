# Install the Qprint publisher certificate so the MSIX can be installed (fixes 0x800B010A).
# Run this once on each PC where you want to install the .msix. Uses Current User store (no admin).
# Optional: pass path to .cer or .pfx; otherwise uses shopkeeper_app\windows\Qprint.cer or Qprint.pfx.

$ErrorActionPreference = "Stop"
$appRoot = Split-Path -Parent $PSScriptRoot
$certDir = Join-Path $appRoot "windows"
$cerPath = Join-Path $certDir "Qprint.cer"
$pfxPath = Join-Path $certDir "Qprint.pfx"
$password = "QprintMSIX"

$certToInstall = $null
if ($args.Count -ge 1 -and (Test-Path $args[0])) {
    $certToInstall = $args[0]
} elseif (Test-Path $cerPath) {
    $certToInstall = $cerPath
} elseif (Test-Path $pfxPath) {
    $certToInstall = $pfxPath
} else {
    Write-Error "No certificate found. Run create_signing_cert.ps1 first, or pass path to Qprint.cer or Qprint.pfx."
    exit 1
}

Write-Host "Installing publisher certificate so MSIX can be installed (Trusted Publishers - Current User)..."
if ($certToInstall -match '\.pfx$') {
    $certPass = ConvertTo-SecureString -String $password -Force -AsPlainText
    Import-PfxCertificate -FilePath $certToInstall -CertStoreLocation "Cert:\CurrentUser\TrustedPublisher" -Password $certPass | Out-Null
} else {
    Import-Certificate -FilePath $certToInstall -CertStoreLocation "Cert:\CurrentUser\TrustedPublisher" | Out-Null
}
Write-Host "Done. You can now install the Qprint Shop .msix on this PC."
