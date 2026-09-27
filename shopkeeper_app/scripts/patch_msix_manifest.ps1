# Patch MSIX manifest: white tile/installer background + desktop shortcut.
# Run after: dart run msix:build
# Then run: dart run msix:pack
# Expects AppxManifest.xml under build\windows\runner\Release (or same folder as .msix build output).

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$buildRoot = Join-Path $root "build"
$manifestPath = $null

# Find AppxManifest.xml (msix:build puts it in build folder)
foreach ($dir in @(
    (Join-Path $buildRoot "windows\runner\Release"),
    (Join-Path $buildRoot "windows\x64\Release"),
    $buildRoot
)) {
    $p = Join-Path $dir "AppxManifest.xml"
    if (Test-Path $p) {
        $manifestPath = $p
        break
    }
}
if (-not $manifestPath) {
    Get-ChildItem -Path $buildRoot -Recurse -Filter "AppxManifest.xml" -ErrorAction SilentlyContinue | ForEach-Object {
        $manifestPath = $_.FullName
        return
    }
}
if (-not $manifestPath -or -not (Test-Path $manifestPath)) {
    Write-Error "AppxManifest.xml not found under $buildRoot. Run 'dart run msix:build' first."
    exit 1
}

[xml]$doc = Get-Content -Path $manifestPath -Encoding UTF8
$ns = @{
    uap = "http://schemas.microsoft.com/appx/manifest/uap/windows10"
    desktop7 = "http://schemas.microsoft.com/appx/manifest/desktop/windows10/7"
    desktop10 = "http://schemas.microsoft.com/appx/manifest/desktop/windows10/10"
}

# 1) Ensure desktop7 and desktop10 namespaces on Package
$pkg = $doc.Package
if (-not $pkg.GetAttribute("desktop7")) {
    $pkg.SetAttribute("xmlns:desktop7", $ns.desktop7)
}
if (-not $pkg.GetAttribute("desktop10")) {
    $pkg.SetAttribute("xmlns:desktop10", $ns.desktop10)
}

# 2) White background: set BackgroundColor on uap:VisualElements
$ve = $doc.SelectSingleNode("//*[local-name()='VisualElements']", (New-Object System.Xml.XmlNamespaceManager($doc.NameTable)))
if ($ve) {
    $ve.SetAttribute("BackgroundColor", "#FFFFFF")
    Write-Host "Set VisualElements BackgroundColor to #FFFFFF"
} else {
    Write-Warning "VisualElements not found; BackgroundColor not set."
}

# 3) Desktop shortcut: add desktop7:Extension under Application > Extensions
$app = $doc.SelectSingleNode("//*[local-name()='Applications']/*[local-name()='Application']", (New-Object System.Xml.XmlNamespaceManager($doc.NameTable)))
if (-not $app) {
    Write-Warning "Application element not found; desktop shortcut not added."
} else {
    $extensions = $app.SelectSingleNode("*[local-name()='Extensions']", (New-Object System.Xml.XmlNamespaceManager($doc.NameTable)))
    if (-not $extensions) {
        $extensions = $doc.CreateElement("Extensions", $app.NamespaceURI)
        $app.AppendChild($extensions) | Out-Null
    }
    $exeName = $app.GetAttribute("Executable")
    if (-not $exeName) { $exeName = "shopkeeper_app.exe" }
    # MSIX path constant for user Desktop (see desktop7:Shortcut schema)
    $shortcutFile = '$$(Desktop)\Qprint Shop.lnk'
    $displayName = "Qprint Shop"

    # Avoid adding duplicate
    $existing = $extensions.SelectSingleNode("*[local-name()='Extension'][@Category='windows.shortcut']", (New-Object System.Xml.XmlNamespaceManager($doc.NameTable)))
    if ($existing) {
        Write-Host "Desktop shortcut extension already present."
    } else {
        $ext = $doc.CreateElement("desktop7", "Extension", $ns.desktop7)
        $ext.SetAttribute("Category", "windows.shortcut")
        $shortcut = $doc.CreateElement("desktop7", "Shortcut", $ns.desktop7)
        $shortcut.SetAttribute("File", $shortcutFile)
        $shortcut.SetAttribute("Icon", $exeName)
        $shortcut.SetAttribute("desktop10:DisplayName", $displayName)
        $ext.AppendChild($shortcut) | Out-Null
        $extensions.AppendChild($ext) | Out-Null
        Write-Host "Added desktop shortcut: $shortcutFile (Icon: $exeName)"
    }
}

$doc.Save($manifestPath)
Write-Host "Patched: $manifestPath"
