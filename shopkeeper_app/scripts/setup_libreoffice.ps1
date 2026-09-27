# Download LibreOffice portable for Windows Word/PPT→PDF conversion.
# Run from repo root or shopkeeper_app. Places LibreOffice in windows/runner/bin/LibreOffice/.
$ErrorActionPreference = "Stop"
$version = "24.8.7"
# Direct download from Document Foundation (avoids SourceForge redirect issues)
$urlPrimary = "https://download.documentfoundation.org/libreoffice/portable/$version/LibreOfficePortablePrevious_${version}_MultilingualStandard.paf.exe"
$urlFallback = "https://sourceforge.net/projects/portableapps/files/LibreOffice%20Portable/LibreOfficePortable_7.6.4_English.paf.exe/download"
$appRoot = if (Test-Path ".\shopkeeper_app") { ".\shopkeeper_app" } else { "." }
$libreOfficeDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) (Join-Path $appRoot "windows\runner\bin\LibreOffice")))
$installer = Join-Path $env:TEMP "LibreOfficePortable_$version.paf.exe"
$minBytes = 80 * 1024 * 1024  # ~80 MB (Multilingual Standard ~196MB)

Write-Host "LibreOffice bin dir: $libreOfficeDir"

if (-not (Test-Path $libreOfficeDir)) { New-Item -ItemType Directory -Path $libreOfficeDir -Force | Out-Null }

# Check if already present (LibreOffice or LibreOfficePortable)
$sofficeExe = Join-Path $libreOfficeDir "App\libreoffice\program\soffice.exe"
if (Test-Path $sofficeExe) {
  Write-Host "LibreOffice already exists at $libreOfficeDir"
  Write-Host "Skipping download. Delete $libreOfficeDir to reinstall."
  exit 0
}
$parentDir = Split-Path $libreOfficeDir -Parent
$portableDir = Join-Path $parentDir "LibreOfficePortable"
$portableSoffice = Join-Path $portableDir "App\libreoffice\program\soffice.exe"
if (Test-Path $portableSoffice) {
  Write-Host "LibreOfficePortable found at $portableDir. Renaming to LibreOffice..."
  if (-not (Test-Path $libreOfficeDir)) {
    Rename-Item -Path $portableDir -NewName "LibreOffice" -Force
    Write-Host "Done. Skipping download."
  } else {
    Write-Host "LibreOffice folder already exists. Skipping download. Delete one if you need to reinstall."
  }
  exit 0
}
$binAppSoffice = Join-Path $parentDir "App\libreoffice\program\soffice.exe"
if (Test-Path $binAppSoffice) {
  Write-Host "LibreOffice found (App in bin). Moving into LibreOffice folder..."
  if (-not (Test-Path $libreOfficeDir)) { New-Item -ItemType Directory -Path $libreOfficeDir -Force | Out-Null }
  @("App", "Data", "Other") | ForEach-Object {
    $src = Join-Path $parentDir $_
    if (Test-Path $src) { Move-Item -Path $src -Destination (Join-Path $libreOfficeDir $_) -Force }
  }
  Write-Host "Done. Skipping download."
  exit 0
}

Write-Host "Downloading LibreOffice Portable (this may take a while, ~200MB)..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"
$downloaded = $false

foreach ($url in @($urlPrimary, $urlFallback)) {
  if ($downloaded) { break }
  Write-Host "Trying: $url"
  try {
    Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing -MaximumRedirection 5
    if ((Test-Path $installer) -and ((Get-Item $installer).Length -ge $minBytes)) { $downloaded = $true }
  } catch {
    Write-Warning "Invoke-WebRequest failed: $($_.Exception.Message)"
  }
  if (-not $downloaded -and (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    Write-Host "Trying curl.exe ..."
    try {
      $curlOut = curl.exe -L -o $installer --fail --retry 2 --retry-delay 5 $url 2>&1
      if ((Test-Path $installer) -and ((Get-Item $installer).Length -ge $minBytes)) { $downloaded = $true }
    } catch { Write-Warning "curl failed: $_" }
  }
  if (-not $downloaded -and $url -eq $urlPrimary) { Write-Host "Primary URL failed. Trying fallback..." }
}

if (-not $downloaded -or -not (Test-Path $installer)) {
  Write-Host ""
  Write-Host "ERROR: Download failed. Download manually:"
  Write-Host "  1. Open: https://www.libreoffice.org/download/portable-versions/"
  Write-Host "  2. Download 'LibreOffice Portable Multilingual Standard' (.paf.exe)"
  Write-Host "  3. Run the installer; choose extraction folder: $(Split-Path $libreOfficeDir -Parent)"
  Write-Host "     (It will create 'LibreOfficePortable' there.)"
  Write-Host "  4. Rename 'LibreOfficePortable' to 'LibreOffice'"
  Write-Host "  5. Ensure: $sofficeExe"
  Write-Host ""
  exit 1
}

Write-Host "Extracting LibreOffice Portable (this may take a few minutes)..."
# PortableApps installer: /S = silent, /D= = destination directory (parent of LibreOfficePortable folder)
$parentDir = Split-Path $libreOfficeDir -Parent
if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }
# PortableApps extracts to a folder named "LibreOfficePortable" in the destination
# We want it in $libreOfficeDir, so extract to parent and then move/rename if needed
$extractArgs = @("/S", "/D=$parentDir")
$proc = Start-Process -FilePath $installer -ArgumentList $extractArgs -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -ne 0) {
  Write-Host "ERROR: LibreOffice installer failed with exit code $($proc.ExitCode)"
  exit 1
}
# PortableApps may create "LibreOfficePortable" folder; rename to "LibreOffice" if needed
$portableFolder = Join-Path $parentDir "LibreOfficePortable"
if ((Test-Path $portableFolder) -and -not (Test-Path $libreOfficeDir)) {
  Write-Host "Renaming LibreOfficePortable to LibreOffice..."
  Move-Item -Path $portableFolder -Destination $libreOfficeDir -Force
}

# Verify extraction
if (-not (Test-Path $sofficeExe)) {
  Write-Host "ERROR: soffice.exe not found at $sofficeExe"
  Write-Host "LibreOffice extraction may have failed. Check $libreOfficeDir"
  exit 1
}

# Cleanup installer
Remove-Item $installer -ErrorAction SilentlyContinue

Write-Host "Done. LibreOffice -> $libreOfficeDir"
Write-Host "soffice.exe -> $sofficeExe"
Write-Host "Run: flutter clean; flutter pub get; flutter build windows"
