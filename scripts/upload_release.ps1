# Upload release artifacts to qprint_release repo (no source code).
# Run from repo root: .\scripts\upload_release.ps1
# Prerequisites: build shopkeeper (build_installer.bat) and customer APK (frontend: npm run build, cap sync, then Android Studio or: cd android && .\gradlew assembleRelease).

$ErrorActionPreference = "Stop"
$ProjectRoot = (Get-Item $PSScriptRoot).Parent.FullName
$ReleaseRepo = "G:\qprint_release"

if (-not (Test-Path $ReleaseRepo)) {
    Write-Error "Release repo not found at $ReleaseRepo. Clone it first: git clone git@github.com:SurajrJadhav/qprint_release.git G:\qprint_release"
    exit 1
}

# Paths in main repo (build outputs)
$ShopkeeperInstaller = Join-Path $ProjectRoot "shopkeeper_app\build\windows\installer\QprintShop_Setup.exe"
$ShopkeeperReleaseX64 = Join-Path $ProjectRoot "shopkeeper_app\build\windows\x64\runner\Release"
$ShopkeeperReleaseLegacy = Join-Path $ProjectRoot "shopkeeper_app\build\windows\runner\Release"
$CustomerApkDir = Join-Path $ProjectRoot "frontend\android\app\build\outputs\apk\release"

# Destinations in release repo
$ReleaseShopkeeper = Join-Path $ReleaseRepo "shopkeeper"
$ReleaseCustomer = Join-Path $ReleaseRepo "customer"
New-Item -ItemType Directory -Path $ReleaseShopkeeper -Force | Out-Null
New-Item -ItemType Directory -Path $ReleaseCustomer -Force | Out-Null

$any = $false

# --- Shopkeeper: Windows installer ---
if (Test-Path $ShopkeeperInstaller) {
    Copy-Item -Path $ShopkeeperInstaller -Destination (Join-Path $ReleaseShopkeeper "QprintShop_Setup.exe") -Force
    Write-Host "Copied shopkeeper installer -> shopkeeper/QprintShop_Setup.exe"
    $any = $true
} else {
    Write-Warning "Shopkeeper installer not found. Build it: cd shopkeeper_app && build_installer.bat"
}

# --- Shopkeeper: Portable (zip of Release folder) ---
$releaseDir = $null
if (Test-Path (Join-Path $ShopkeeperReleaseX64 "shopkeeper_app.exe")) { $releaseDir = $ShopkeeperReleaseX64 }
elseif (Test-Path (Join-Path $ShopkeeperReleaseLegacy "shopkeeper_app.exe")) { $releaseDir = $ShopkeeperReleaseLegacy }
if ($releaseDir) {
    $portableZip = Join-Path $ReleaseShopkeeper "QprintShop_Portable.zip"
    if (Test-Path $portableZip) { Remove-Item $portableZip -Force }
    Compress-Archive -Path (Join-Path $releaseDir "*") -DestinationPath $portableZip -Force
    Write-Host "Created shopkeeper portable -> shopkeeper/QprintShop_Portable.zip"
    $any = $true
} else {
    Write-Warning "Shopkeeper Release folder not found. Build Windows first: cd shopkeeper_app && flutter build windows"
}

# --- Customer: APK ---
$apkFiles = Get-ChildItem -Path $CustomerApkDir -Filter "*.apk" -ErrorAction SilentlyContinue
if ($apkFiles) {
    foreach ($f in $apkFiles) {
        Copy-Item -Path $f.FullName -Destination (Join-Path $ReleaseCustomer $f.Name) -Force
        Write-Host "Copied customer APK -> customer/$($f.Name)"
        $any = $true
    }
} else {
    Write-Warning "Customer APK not found. Build: cd frontend && npm run build && npx cap sync android && cd android && .\gradlew assembleRelease"
}

if (-not $any) {
    Write-Error "No release artifacts found. Build shopkeeper and customer app first."
    exit 1
}

# --- Commit and push release repo ---
Push-Location $ReleaseRepo
try {
    # Ensure we have a branch (empty clone may have none)
    $branch = git branch --show-current 2>$null
    if (-not $branch) { git checkout -b main | Out-Null }
    git add -A
    $status = git status --porcelain
    if (-not $status) {
        Write-Host "No changes to commit in release repo."
        exit 0
    }
    $date = Get-Date -Format "yyyy-MM-dd"
    git commit -m "Release $date - shopkeeper installer/portable, customer APK"
    git push -u origin main 2>$null
    if ($LASTEXITCODE -ne 0) { git push origin main }
    Write-Host "Pushed to git@github.com:SurajrJadhav/qprint_release.git"
} finally {
    Pop-Location
}
