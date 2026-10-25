<#
Clean-BingWallpaperCache.ps1
Cleans the wallpaper caches that the upstream winapp2.ini entry
"[Microsoft Bing Wallpapers *]" never touches.

Cleaned:
    LocalState\images\$$Content$$    downloaded wallpapers (daily Bing UHD
                                     images + theme-pack images)
    LocalState\AnimAssets            animated wallpaper scene assets
    LocalState\images\thumbnails     gallery thumbnails

Deliberately NOT touched:
    LocalState\images\images.db      app index, ~1.5 MB; deleting it buys
                                     almost nothing and forces a re-index
    LocalState\BingWallpaper_Widget  widget WebView cache, already covered
                                     by the upstream winapp2 entry
    AC\ TempState\ Settings\         also covered by the upstream entry

Notes:
    - The source file of the CURRENT desktop wallpaper may live in
      $$Content$$. Windows renders from its own transcoded copy, so the
      desktop keeps working; use -KeepNewest 1 to also keep the newest
      source file.
    - Files locked by a running app are skipped, not fatal.
    - Supports -WhatIf and -Confirm.

Examples:
    .\Clean-BingWallpaperCache.ps1 -WhatIf            preview only
    .\Clean-BingWallpaperCache.ps1                    clean everything
    .\Clean-BingWallpaperCache.ps1 -KeepNewest 7      keep the 7 newest files
    .\Clean-BingWallpaperCache.ps1 -SkipAnimated      leave AnimAssets alone
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateRange(0, 10000)]
    [int]$KeepNewest = 0,
    [switch]$SkipAnimated
)

$ErrorActionPreference = 'Stop'

$localState = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.BingWallpaper_8wekyb3d8bbwe\LocalState'
if (-not (Test-Path -LiteralPath $localState)) {
    Write-Warning "Bing Wallpaper LocalState not found: $localState"
    exit 1
}

$contentDir   = Join-Path $localState 'images\$$Content$$'
$animDir      = Join-Path $localState 'AnimAssets'
$thumbnailDir = Join-Path $localState 'images\thumbnails'

function Get-TreeBytes {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [long]0 }
    $m = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
         Measure-Object -Property Length -Sum
    if ($null -eq $m.Sum) { return [long]0 }
    return [long]$m.Sum
}

$bytesBefore = (Get-TreeBytes $contentDir) + (Get-TreeBytes $animDir) + (Get-TreeBytes $thumbnailDir)

$jobs = @(
    @{ Path = $contentDir;   Label = 'images\$$Content$$'; Keep = $KeepNewest }
    @{ Path = $thumbnailDir; Label = 'images\thumbnails';  Keep = 0 }
)
if (-not $SkipAnimated) {
    $jobs += @{ Path = $animDir; Label = 'AnimAssets'; Keep = 0 }
}

$deletedCount   = 0
$lockedCount    = 0
$selectedCount  = 0
$selectedBytes  = [long]0

foreach ($job in $jobs) {
    if (-not (Test-Path -LiteralPath $job.Path)) {
        Write-Host ("[skip] {0}: not present" -f $job.Label)
        continue
    }
    $files = @(Get-ChildItem -LiteralPath $job.Path -Recurse -File -Force -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending)
    $targets = $files
    if ($job.Keep -gt 0) { $targets = @($files | Select-Object -Skip $job.Keep) }

    $sum = ($targets | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { $sum = [long]0 }
    $selectedCount += $targets.Count
    $selectedBytes += [long]$sum

    Write-Host ("[{0}] {1} file(s) found, {2} selected, {3:N0} bytes" -f $job.Label, $files.Count, $targets.Count, [long]$sum)

    foreach ($f in $targets) {
        if ($PSCmdlet.ShouldProcess($f.FullName, 'delete')) {
            try {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                $deletedCount++
            } catch {
                Write-Warning ("locked, skipped: {0}" -f $f.Name)
                $lockedCount++
            }
        }
    }

    # drop scene subfolders that became empty (each root folder is kept)
    if (-not $WhatIfPreference) {
        Get-ChildItem -LiteralPath $job.Path -Directory -Recurse -ErrorAction SilentlyContinue |
            Sort-Object { $_.FullName.Length } -Descending |
            ForEach-Object {
                if (-not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue)) {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                }
            }
    }
}

Write-Host ''
if ($WhatIfPreference) {
    Write-Host ("[WhatIf] would delete {0} file(s), about {1:N0} bytes" -f $selectedCount, $selectedBytes)
} else {
    $bytesAfter = (Get-TreeBytes $contentDir) + (Get-TreeBytes $animDir) + (Get-TreeBytes $thumbnailDir)
    Write-Host ("deleted {0} file(s), skipped {1} locked, freed {2:N0} bytes, cache now {3:N0} bytes" -f `
        $deletedCount, $lockedCount, ($bytesBefore - $bytesAfter), $bytesAfter)
}
