# Unpack the .msix from msix:create, patch manifest (white background + desktop shortcut), repack.
# Ensures the installer is created by msix:create first, then we add our customizations.
# Requires: Windows SDK MakeAppx.exe (usually with Visual Studio / Build Tools).

$ErrorActionPreference = "Stop"
# App root = shopkeeper_app (build output and assets live here)
$appRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $appRoot "build\windows"

# Find .msix (Flutter can output to runner\Release or x64\runner\Release)
$msix = $null
foreach ($dir in @(
    (Join-Path $buildRoot "runner\Release"),
    (Join-Path $buildRoot "x64\runner\Release")
)) {
    if (Test-Path $dir) {
        $m = Get-ChildItem -Path $dir -Filter "*.msix" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($m) { $msix = $m; break }
    }
}
if (-not $msix) {
    Write-Error "No .msix found under $buildRoot. Run 'dart run msix:create' first."
    exit 1
}
Write-Host "Found installer: $($msix.FullName)"

# Find MakeAppx.exe (Windows SDK)
$makeAppx = $null
$sdkRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
if (Test-Path $sdkRoot) {
    $versions = Get-ChildItem -Path $sdkRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
    foreach ($ver in $versions) {
        $p = Join-Path $ver.FullName "x64\MakeAppx.exe"
        if (Test-Path $p) {
            $makeAppx = $p
            break
        }
    }
}
if (-not $makeAppx) {
    $makeAppx = (Get-Command MakeAppx.exe -ErrorAction SilentlyContinue).Source
}
if (-not $makeAppx -or -not (Test-Path $makeAppx)) {
    Write-Error "MakeAppx.exe not found. Install Windows SDK or Build Tools for Visual Studio (Desktop development with C++)."
    exit 1
}
Write-Host "Using MakeAppx: $makeAppx"

# Unpack
$unpackDir = Join-Path $env:TEMP "msix_unpack_$([Guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $unpackDir -Force | Out-Null
try {
    $unpackLog = Join-Path $env:TEMP "makeappx_unpack.log"
    & $makeAppx unpack /p $msix.FullName /d $unpackDir /o 2>&1 | Out-File -FilePath $unpackLog -Encoding utf8
    if (-not (Test-Path (Join-Path $unpackDir "AppxManifest.xml"))) {
        Get-Content $unpackLog -ErrorAction SilentlyContinue
        Write-Error "Unpack failed. AppxManifest.xml not found in $unpackDir"
        exit 1
    }
    Write-Host "Unpacked to: $unpackDir"

    # Replace all logo/icon PNGs with white-background versions (install dialog + tile; fixes blue background)
    $logoPath = Join-Path $appRoot "assets\logo.png"
    if (Test-Path $logoPath) {
        try {
            Add-Type -AssemblyName System.Drawing
            $logo = [System.Drawing.Image]::FromFile((Resolve-Path $logoPath))
            $assetsDir = Join-Path $unpackDir "Assets"
            if (Test-Path $assetsDir) {
                $pngs = Get-ChildItem -Path $assetsDir -Filter "*.png" -ErrorAction SilentlyContinue
            } else {
                $pngs = Get-ChildItem -Path $unpackDir -Filter "*.png" -ErrorAction SilentlyContinue
            }
            foreach ($f in $pngs) {
                try {
                    $targetW = 150
                    $targetH = 150
                    if ($f.Name -match "(\d+)x(\d+)") { $targetW = [int]$Matches[1]; $targetH = [int]$Matches[2] }
                    $bmp = New-Object System.Drawing.Bitmap $targetW, $targetH
                    $g = [System.Drawing.Graphics]::FromImage($bmp)
                    $g.Clear([System.Drawing.Color]::White)
                    $g.DrawImage($logo, 0, 0, $targetW, $targetH)
                    $g.Dispose()
                    $bmp.Save($f.FullName, [System.Drawing.Imaging.ImageFormat]::Png)
                    $bmp.Dispose()
                } catch { Write-Warning "Could not replace $($f.Name): $_" }
            }
            $logo.Dispose()
            Write-Host "Replaced all Assets PNGs with white background (install dialog + tile)."
        } catch {
            Write-Warning "Logo replacement skipped (installer/tile may still show blue): $_"
        }
    } else {
        Write-Warning "Logo not found at $logoPath - install dialog/tile may show blue background."
    }

    # Patch manifest
    $manifestPath = Join-Path $unpackDir "AppxManifest.xml"
    [xml]$doc = Get-Content -Path $manifestPath -Encoding UTF8
    $ns = @{
        uap = "http://schemas.microsoft.com/appx/manifest/uap/windows10"
        desktop7 = "http://schemas.microsoft.com/appx/manifest/desktop/windows10/7"
        desktop10 = "http://schemas.microsoft.com/appx/manifest/desktop/windows10/10"
    }

    $pkg = $doc.Package
    if (-not $pkg.GetAttribute("desktop7")) { $pkg.SetAttribute("xmlns:desktop7", $ns.desktop7) }
    if (-not $pkg.GetAttribute("desktop10")) { $pkg.SetAttribute("xmlns:desktop10", $ns.desktop10) }

    $ve = $doc.SelectSingleNode("//*[local-name()='VisualElements']", (New-Object System.Xml.XmlNamespaceManager($doc.NameTable)))
    if ($ve) {
        $ve.SetAttribute("BackgroundColor", "#FFFFFF")
        Write-Host "Set tile/installer background to white."
    }

    $app = $doc.SelectSingleNode("//*[local-name()='Applications']/*[local-name()='Application']", (New-Object System.Xml.XmlNamespaceManager($doc.NameTable)))
    if ($app) {
        $extensions = $app.SelectSingleNode("*[local-name()='Extensions']", (New-Object System.Xml.XmlNamespaceManager($doc.NameTable)))
        if (-not $extensions) {
            $extensions = $doc.CreateElement("Extensions", $app.NamespaceURI)
            $app.AppendChild($extensions) | Out-Null
        }
        $exeName = $app.GetAttribute("Executable")
        if (-not $exeName) { $exeName = "shopkeeper_app.exe" }
        $existing = $extensions.SelectSingleNode("*[local-name()='Extension'][@Category='windows.shortcut']", (New-Object System.Xml.XmlNamespaceManager($doc.NameTable)))
        if (-not $existing) {
            $ext = $doc.CreateElement("desktop7", "Extension", $ns.desktop7)
            $ext.SetAttribute("Category", "windows.shortcut")
            $shortcut = $doc.CreateElement("desktop7", "Shortcut", $ns.desktop7)
            $shortcut.SetAttribute("File", '$$(Desktop)\Qprint Shop.lnk')
            $shortcut.SetAttribute("Icon", $exeName)
            $shortcut.SetAttribute("desktop10:DisplayName", "Qprint Shop")
            $ext.AppendChild($shortcut) | Out-Null
            $extensions.AppendChild($ext) | Out-Null
            Write-Host "Added desktop shortcut: Qprint Shop"
        }
    }

    $doc.Save($manifestPath)

    # Repack (overwrite original)
    $packLog = Join-Path $env:TEMP "makeappx_pack.log"
    & $makeAppx pack /d $unpackDir /p $msix.FullName /o 2>&1 | Out-File -FilePath $packLog -Encoding utf8
    if (-not (Test-Path $msix.FullName)) {
        Get-Content $packLog -ErrorAction SilentlyContinue
        Write-Error "Repack failed."
        exit 1
    }
    Write-Host "Repacked: $($msix.FullName)"
}
finally {
    if (Test-Path $unpackDir) {
        Remove-Item -Path $unpackDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Done. Installer installs to OS drive and creates desktop shortcut."
