# Create a self-signed certificate for MSIX signing so the installer shows "Publisher: Qprint" instead of "Msix Testing".
# Run once; then build_installer.bat will use windows\Qprint.pfx.
# Users may need to install the cert on their PC before installing the app (or choose "Install anyway").

$ErrorActionPreference = "Stop"
# App root = shopkeeper_app (so cert is at shopkeeper_app\windows\Qprint.pfx for build_installer.bat)
$appRoot = Split-Path -Parent $PSScriptRoot
$certDir = Join-Path $appRoot "windows"
$pfxPath = Join-Path $certDir "Qprint.pfx"
$password = "QprintMSIX"

if (Test-Path $pfxPath) {
    Write-Host "Certificate already exists: $pfxPath"
    exit 0
}

New-Item -ItemType Directory -Path $certDir -Force | Out-Null
$cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=Qprint" -CertStoreLocation "Cert:\CurrentUser\My" -NotAfter (Get-Date).AddYears(5)
$certPass = ConvertTo-SecureString -String $password -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $certPass | Out-Null
# Export public-only .cer so users can trust the publisher without giving them the private key
$cerPath = Join-Path $certDir "Qprint.cer"
Export-Certificate -Cert $cert -FilePath $cerPath -Type CERT | Out-Null
Remove-Item -Path "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue
Write-Host "Created: $pfxPath (Publisher will show as Qprint)"
Write-Host "Public cert for trusting on install PCs: $cerPath"
Write-Host "Password for msix_config: $password"
