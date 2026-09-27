# Download SumatraPDF portable (64-bit) for Windows PDF printing via CLI.
# Idempotent: skips if a valid SumatraPDF.exe already exists.
# Safe downloads: writes to a temp file, verifies size, only then installs.
# Run from repo root or shopkeeper_app.

$ErrorActionPreference = "Stop"
$version = "3.5.2"
$url = "https://www.sumatrapdfreader.org/dl/rel/$version/SumatraPDF-$version-64.zip"
$appRoot = if (Test-Path ".\shopkeeper_app") { ".\shopkeeper_app" } else { "." }
$binDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) (Join-Path $appRoot "windows\runner\bin")))
$dest = Join-Path $binDir "SumatraPDF.exe"
$minExeBytes = 2 * 1024 * 1024   # ~2 MB
$minZipBytes = 2 * 1024 * 1024

function Test-ValidSumatra([string]$path) {
  return (Test-Path $path) -and ((Get-Item $path).Length -ge $minExeBytes)
}

Write-Host "SumatraPDF target: $dest"

if (Test-ValidSumatra $dest) {
  Write-Host "SumatraPDF already installed ($( [math]::Round((Get-Item $dest).Length/1MB, 1) ) MB). Skipping download."
  exit 0
}

if (Test-Path $dest) {
  Write-Warning "Existing SumatraPDF.exe looks incomplete. Removing..."
  Remove-Item $dest -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir -Force | Out-Null }

$zip = Join-Path $env:TEMP "SumatraPDF-$version-64.partial.zip"
$zipFinal = Join-Path $env:TEMP "SumatraPDF-$version-64.zip"
if (Test-Path $zip) { Remove-Item $zip -Force -ErrorAction SilentlyContinue }

Write-Host "Downloading $url ..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$downloaded = $false

try {
  Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
  if ((Test-Path $zip) -and ((Get-Item $zip).Length -ge $minZipBytes)) { $downloaded = $true }
} catch {
  Write-Warning "Invoke-WebRequest failed: $_"
}

if (-not $downloaded -and (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
  Write-Host "Trying curl.exe ..."
  if (Test-Path $zip) { Remove-Item $zip -Force -ErrorAction SilentlyContinue }
  & curl.exe -sSL -o $zip --fail --retry 3 --retry-delay 2 $url
  if ((Test-Path $zip) -and ((Get-Item $zip).Length -ge $minZipBytes)) { $downloaded = $true }
}

if (-not $downloaded) {
  if (Test-Path $zip) { Remove-Item $zip -Force -ErrorAction SilentlyContinue }
  Write-Host "ERROR: Download failed or incomplete. Nothing installed."
  Write-Host "Manual: download $url and extract SumatraPDF.exe to $binDir"
  exit 1
}

Move-Item -Path $zip -Destination $zipFinal -Force

Write-Host "Extracting ..."
$extractDir = Join-Path $env:TEMP "SumatraPDF-extract-$version"
if (Test-Path $extractDir) { Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue }
try {
  Expand-Archive -Path $zipFinal -DestinationPath $extractDir -Force
} catch {
  Remove-Item $zipFinal -Force -ErrorAction SilentlyContinue
  Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue
  Write-Host "ERROR: Zip extract failed (corrupt/partial download). Cleared temp files."
  exit 1
}

$exe = Join-Path $extractDir "SumatraPDF.exe"
if (-not (Test-ValidSumatra $exe)) {
  Remove-Item $zipFinal -Force -ErrorAction SilentlyContinue
  Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue
  Write-Host "ERROR: SumatraPDF.exe missing or too small in zip. Cleared temp files."
  exit 1
}

Copy-Item -Path $exe -Destination $dest -Force
Remove-Item $zipFinal -Force -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue

if (-not (Test-ValidSumatra $dest)) {
  if (Test-Path $dest) { Remove-Item $dest -Force -ErrorAction SilentlyContinue }
  Write-Host "ERROR: Install verification failed. Partial file removed."
  exit 1
}

Write-Host "Done. SumatraPDF.exe -> $dest"
exit 0
