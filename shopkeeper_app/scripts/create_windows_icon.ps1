# Create a Windows icon image with the logo scaled to FILL the frame (big like VS Code).
# Output: assets/logo_windows_icon.png (256x256). Used by flutter_launcher_icons for Windows.
# Run from shopkeeper_app folder.

$ErrorActionPreference = "Stop"
$appRoot = Split-Path -Parent $PSScriptRoot
$logoPath = Join-Path $appRoot "assets\logo.png"
$outPath = Join-Path $appRoot "assets\logo_windows_icon.png"
$size = 256

if (-not (Test-Path $logoPath)) {
    Write-Warning "Logo not found: $logoPath. Skipping Windows icon."
    exit 0
}

try {
    Add-Type -AssemblyName System.Drawing
    $logo = [System.Drawing.Image]::FromFile((Resolve-Path $logoPath))
    $w = $logo.Width
    $h = $logo.Height
    # Scale so the logo FILLS the icon (like VS Code): smaller side = size, center crop
    # This "zooms in" so the graphic is big even if logo.png has padding
    $scale = $size / [Math]::Min($w, $h)
    $newW = [int]($w * $scale)
    $newH = [int]($h * $scale)
    $x = [int](($size - $newW) / 2)
    $y = [int](($size - $newH) / 2)

    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    # White background so icon is visible on any desktop
    $g.Clear([System.Drawing.Color]::White)
    $g.DrawImage($logo, $x, $y, $newW, $newH)
    $g.Dispose()
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $logo.Dispose()
    Write-Host "Created Windows icon: $outPath (logo fills frame like VS Code)"
} catch {
    Write-Warning "Could not create Windows icon: $_"
    if (Test-Path $logoPath) { Copy-Item -Path $logoPath -Destination $outPath -Force; Write-Host "Copied logo.png to logo_windows_icon.png as fallback." }
    exit 0
}
