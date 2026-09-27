# Download SumatraPDF portable (64-bit) for Windows PDF printing via CLI.
# Run from repo root or shopkeeper_app. Places SumatraPDF.exe in windows/runner/bin/.
$ErrorActionPreference = "Stop"
$version = "3.5.2"
$url = "https://www.sumatrapdfreader.org/dl/rel/$version/SumatraPDF-$version-64.zip"
$appRoot = if (Test-Path ".\shopkeeper_app") { ".\shopkeeper_app" } else { "." }
$binDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) (Join-Path $appRoot "windows\runner\bin")))
$zip = Join-Path $env:TEMP "SumatraPDF-$version-64.zip"
$minBytes = 2 * 1024 * 1024  # ~2 MB

Write-Host "SumatraPDF bin dir: $binDir"

if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir -Force | Out-Null }

Write-Host "Downloading $url ..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$downloaded = $false
try {
  Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
  if ((Test-Path $zip) -and ((Get-Item $zip).Length -ge $minBytes)) { $downloaded = $true }
} catch { Write-Warning "Invoke-WebRequest failed: $_" }

if (-not $downloaded -and (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
  Write-Host "Trying curl.exe ..."
  try {
    curl.exe -sSL -o $zip --fail $url
    if ((Test-Path $zip) -and ((Get-Item $zip).Length -ge $minBytes)) { $downloaded = $true }
  } catch { Write-Warning "curl failed: $_" }
}

if (-not $downloaded -or -not (Test-Path $zip)) {
  Write-Host "ERROR: Download failed. Download manually from:"
  Write-Host "  $url"
  Write-Host "Extract SumatraPDF.exe to $binDir"
  exit 1
}

Write-Host "Extracting ..."
$extractDir = Join-Path $env:TEMP "SumatraPDF-extract"
if (Test-Path $extractDir) { Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue }
Expand-Archive -Path $zip -DestinationPath $extractDir -Force
$exe = Join-Path $extractDir "SumatraPDF.exe"
if (-not (Test-Path $exe)) {
  Write-Host "ERROR: SumatraPDF.exe not found in zip."
  exit 1
}
$dest = Join-Path $binDir "SumatraPDF.exe"
Copy-Item -Path $exe -Destination $dest -Force
Remove-Item $zip -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue

if (-not (Test-Path $dest)) {
  Write-Host "ERROR: Copy failed. SumatraPDF.exe not at $dest"
  exit 1
}
Write-Host "Done. SumatraPDF.exe -> $dest"
Write-Host "Run: flutter clean; flutter pub get; flutter build windows"
