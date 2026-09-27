# Check which .so files in the built AAB/APK are NOT 16 KB aligned (Google Play requirement).
# Run from customer_app: .\scripts\check_16kb_alignment.ps1
# Or from repo root: .\customer_app\scripts\check_16kb_alignment.ps1
# Optional: -AabPath "path\to\app-release.aab"

param(
    [string]$AabPath = ""
)

$ErrorActionPreference = "Stop"
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$appDir = Split-Path -Parent $scriptDir
if (-not $AabPath) {
    $AabPath = Join-Path $appDir "build\app\outputs\bundle\release\app-release.aab"
}
$AabPath = [System.IO.Path]::GetFullPath($AabPath)
if (-not (Test-Path $AabPath)) {
    Write-Host "AAB not found: $AabPath" -ForegroundColor Red
    Write-Host "Build first: flutter build appbundle" -ForegroundColor Yellow
    exit 1
}

$ndkVersion = "29.0.14033849"
$ndkRoot = $env:ANDROID_HOME
if (-not $ndkRoot) { $ndkRoot = $env:ANDROID_SDK_ROOT }
if (-not $ndkRoot) {
    Write-Host "Set ANDROID_HOME or ANDROID_SDK_ROOT" -ForegroundColor Red
    exit 1
}
$isWindows = $env:OS -match "Windows"
$objdump = Join-Path $ndkRoot "ndk\$ndkVersion\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-objdump.exe"
if (-not (Test-Path $objdump)) {
    $objdump = Join-Path $ndkRoot "ndk\$ndkVersion\toolchains\llvm\prebuilt\linux-x86_64\bin\llvm-objdump"
}
if (-not (Test-Path $objdump)) {
    Write-Host "llvm-objdump not found. Install NDK $ndkVersion (SDK Manager -> NDK)." -ForegroundColor Red
    exit 1
}

$tempDir = Join-Path $env:TEMP "16kb_check_$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
try {
    Copy-Item -LiteralPath $AabPath -Destination (Join-Path $tempDir "app.zip") -Force
    Expand-Archive -LiteralPath (Join-Path $tempDir "app.zip") -DestinationPath (Join-Path $tempDir "aab") -Force
    $libDir = Join-Path $tempDir "aab\base\lib\arm64-v8a"
    if (-not (Test-Path $libDir)) {
        Write-Host "No arm64-v8a libs in AAB. Checking base module..." -ForegroundColor Yellow
        $libDir = Join-Path $tempDir "aab\lib\arm64-v8a"
    }
    if (-not (Test-Path $libDir)) {
        Write-Host "No arm64-v8a folder found in AAB." -ForegroundColor Red
        exit 1
    }
    $soFiles = Get-ChildItem -Path $libDir -Filter "*.so" -File
    $unaligned = @()
    foreach ($so in $soFiles) {
        $out = & $objdump -p $so.FullName 2>&1 | Out-String
        $loadLines = $out -split "`n" | Where-Object { $_ -match "LOAD" }
        $bad = $false
        foreach ($line in $loadLines) {
            if ($line -match "align\s+2\*\*(\d+)") {
                $exp = [int]$Matches[1]
                # 2**12 = 4096 (4KB) = not compliant. Need 2**14 (16KB) or 2**16 (64KB).
                if ($exp -lt 14) { $bad = $true; break }
            }
        }
        if ($bad) { $unaligned += $so.Name }
    }
    Write-Host "`n16 KB page size check (arm64-v8a):" -ForegroundColor Cyan
    if ($unaligned.Count -eq 0) {
        Write-Host "All $($soFiles.Count) .so files are 16 KB aligned." -ForegroundColor Green
        exit 0
    }
    Write-Host "UNALIGNED (these cause Play Store rejection):" -ForegroundColor Red
    $unaligned | ForEach-Object { Write-Host "  $_" }
    Write-Host "`nUpdate or replace the plugin that ships each .so above (e.g. mobile_scanner, razorpay, firebase)." -ForegroundColor Yellow
    exit 1
} finally {
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
}
