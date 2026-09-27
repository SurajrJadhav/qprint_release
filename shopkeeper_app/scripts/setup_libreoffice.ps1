# Download LibreOffice portable for Windows Word/PPT→PDF conversion.
# Idempotent: skips if a valid soffice.exe already exists.
# Safe downloads: temp installer, size check, verify soffice after extract;
# removes incomplete LibreOffice folders on failure.
# Run from repo root or shopkeeper_app.

$ErrorActionPreference = "Stop"
$version = "24.8.7"
$urlPrimary = "https://download.documentfoundation.org/libreoffice/portable/$version/LibreOfficePortablePrevious_${version}_MultilingualStandard.paf.exe"
$urlFallback = "https://sourceforge.net/projects/portableapps/files/LibreOffice%20Portable/LibreOfficePortable_7.6.4_English.paf.exe/download"
$appRoot = if (Test-Path ".\shopkeeper_app") { ".\shopkeeper_app" } else { "." }
$libreOfficeDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) (Join-Path $appRoot "windows\runner\bin\LibreOffice")))
$parentDir = Split-Path $libreOfficeDir -Parent
$sofficeExe = Join-Path $libreOfficeDir "App\libreoffice\program\soffice.exe"
$minInstallerBytes = 80 * 1024 * 1024  # ~80 MB
$minSofficeBytes = 100 * 1024          # soffice.exe should be at least ~100 KB

function Test-ValidLibreOffice {
  return (Test-Path $sofficeExe) -and ((Get-Item $sofficeExe).Length -ge $minSofficeBytes)
}

function Remove-IncompleteLibreOffice {
  if ((Test-Path $libreOfficeDir) -and -not (Test-ValidLibreOffice)) {
    Write-Warning "Removing incomplete LibreOffice folder: $libreOfficeDir"
    Remove-Item -Recurse -Force $libreOfficeDir -ErrorAction SilentlyContinue
  }
}

Write-Host "LibreOffice target: $libreOfficeDir"

if (Test-ValidLibreOffice) {
  Write-Host "LibreOffice already installed. Skipping download."
  Write-Host "Delete $libreOfficeDir to force reinstall."
  exit 0
}

Remove-IncompleteLibreOffice

# Adopt existing LibreOfficePortable / loose App tree if complete
$portableDir = Join-Path $parentDir "LibreOfficePortable"
$portableSoffice = Join-Path $portableDir "App\libreoffice\program\soffice.exe"
if ((Test-Path $portableSoffice) -and ((Get-Item $portableSoffice).Length -ge $minSofficeBytes)) {
  Write-Host "LibreOfficePortable found. Renaming to LibreOffice..."
  if (Test-Path $libreOfficeDir) { Remove-Item -Recurse -Force $libreOfficeDir -ErrorAction SilentlyContinue }
  Rename-Item -Path $portableDir -NewName "LibreOffice" -Force
  if (Test-ValidLibreOffice) { Write-Host "Done. Skipping download."; exit 0 }
}

$binAppSoffice = Join-Path $parentDir "App\libreoffice\program\soffice.exe"
if ((Test-Path $binAppSoffice) -and ((Get-Item $binAppSoffice).Length -ge $minSofficeBytes)) {
  Write-Host "LibreOffice App tree found in bin. Moving into LibreOffice folder..."
  if (-not (Test-Path $libreOfficeDir)) { New-Item -ItemType Directory -Path $libreOfficeDir -Force | Out-Null }
  @("App", "Data", "Other") | ForEach-Object {
    $src = Join-Path $parentDir $_
    if (Test-Path $src) { Move-Item -Path $src -Destination (Join-Path $libreOfficeDir $_) -Force }
  }
  if (Test-ValidLibreOffice) { Write-Host "Done. Skipping download."; exit 0 }
}

if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }

$installer = Join-Path $env:TEMP "LibreOfficePortable_$version.partial.paf.exe"
$installerFinal = Join-Path $env:TEMP "LibreOfficePortable_$version.paf.exe"
if (Test-Path $installer) { Remove-Item $installer -Force -ErrorAction SilentlyContinue }

Write-Host "Downloading LibreOffice Portable (~200MB). This is one-time unless you delete it..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"
$downloaded = $false

foreach ($url in @($urlPrimary, $urlFallback)) {
  if ($downloaded) { break }
  Write-Host "Trying: $url"
  if (Test-Path $installer) { Remove-Item $installer -Force -ErrorAction SilentlyContinue }
  try {
    Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing -MaximumRedirection 5
    if ((Test-Path $installer) -and ((Get-Item $installer).Length -ge $minInstallerBytes)) { $downloaded = $true }
  } catch {
    Write-Warning "Invoke-WebRequest failed: $($_.Exception.Message)"
  }
  if (-not $downloaded -and (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    Write-Host "Trying curl.exe ..."
    if (Test-Path $installer) { Remove-Item $installer -Force -ErrorAction SilentlyContinue }
    & curl.exe -L -o $installer --fail --retry 3 --retry-delay 5 $url
    if ((Test-Path $installer) -and ((Get-Item $installer).Length -ge $minInstallerBytes)) { $downloaded = $true }
  }
  if (-not $downloaded) {
    Write-Warning "Download incomplete or too small. Discarding partial file."
    if (Test-Path $installer) { Remove-Item $installer -Force -ErrorAction SilentlyContinue }
  }
}

if (-not $downloaded) {
  Write-Host ""
  Write-Host "ERROR: Download failed. Nothing installed."
  Write-Host "Manual:"
  Write-Host "  1. https://www.libreoffice.org/download/portable-versions/"
  Write-Host "  2. Extract to $parentDir as LibreOfficePortable, then rename to LibreOffice"
  Write-Host "  3. Ensure: $sofficeExe"
  exit 1
}

Move-Item -Path $installer -Destination $installerFinal -Force

Write-Host "Extracting LibreOffice Portable (may take a few minutes)..."
$extractArgs = @("/S", "/D=$parentDir")
$proc = Start-Process -FilePath $installerFinal -ArgumentList $extractArgs -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -ne 0) {
  Remove-Item $installerFinal -Force -ErrorAction SilentlyContinue
  Remove-IncompleteLibreOffice
  Write-Host "ERROR: Installer failed (exit $($proc.ExitCode)). Partial install cleaned up."
  exit 1
}

$portableFolder = Join-Path $parentDir "LibreOfficePortable"
if ((Test-Path $portableFolder) -and -not (Test-Path $libreOfficeDir)) {
  Move-Item -Path $portableFolder -Destination $libreOfficeDir -Force
}

Remove-Item $installerFinal -Force -ErrorAction SilentlyContinue

if (-not (Test-ValidLibreOffice)) {
  Remove-IncompleteLibreOffice
  if (Test-Path $portableFolder) { Remove-Item -Recurse -Force $portableFolder -ErrorAction SilentlyContinue }
  Write-Host "ERROR: soffice.exe missing/invalid after extract. Incomplete install removed."
  exit 1
}

Write-Host "Done. LibreOffice -> $libreOfficeDir"
Write-Host "soffice.exe -> $sofficeExe"
exit 0
