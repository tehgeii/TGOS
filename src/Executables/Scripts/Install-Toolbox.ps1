<#
.SYNOPSIS
    Memasang TGOS Toolbox dan wallpaper TGO ke sistem.

.DESCRIPTION
    1. Menyalin folder "TGOS Toolbox" dari playbook ke <drive sistem>\TGOS Toolbox.
    2. Membuat pintasan "TGOS Toolbox" di Desktop semua pengguna.
    3. Menyalin wallpaper ke %SystemRoot%\Web\Wallpaper\TGOS\TGOS.png.
    4. Menyalin layout taskbar ke %ProgramData%\TGOS\TaskbarLayout.xml. File itu
       ditunjuk policy "Start Layout" yang dipasang modul antarmuka.

    Kode keluar 1 hanya bila Toolbox gagal disalin. Langkah lain tidak fatal.

    Parameter hanya dipakai untuk pengujian.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$SourceRoot,
    [string]$ToolboxDestination,
    [string]$WallpaperDestination,
    [string]$ShortcutDirectory,
    [string]$DataDirectory
)

$ErrorActionPreference = 'Stop'

if (-not $SourceRoot) {
    # Skrip ada di <playbook>\Executables\Scripts.
    $SourceRoot = Split-Path -Parent $PSScriptRoot
}
if (-not $ToolboxDestination) {
    $ToolboxDestination = Join-Path ('{0}\' -f $env:SystemDrive) 'TGOS Toolbox'
}
if (-not $WallpaperDestination) {
    $WallpaperDestination = Join-Path $env:SystemRoot 'Web\Wallpaper\TGOS'
}
if (-not $ShortcutDirectory) {
    $ShortcutDirectory = Join-Path $env:PUBLIC 'Desktop'
}
if (-not $DataDirectory) {
    $DataDirectory = Join-Path $env:ProgramData 'TGOS'
}

try {
    $toolboxSource = Join-Path $SourceRoot 'TGOS Toolbox'
    if (-not (Test-Path -LiteralPath $toolboxSource)) {
        throw ("Toolbox source not found: {0}" -f $toolboxSource)
    }
    if (Test-Path -LiteralPath $ToolboxDestination) {
        Remove-Item -LiteralPath $ToolboxDestination -Recurse -Force
    }
    Copy-Item -LiteralPath $toolboxSource -Destination $ToolboxDestination -Recurse -Force
    Write-Output ("TGOS: Toolbox installed to {0}" -f $ToolboxDestination)
}
catch {
    Write-Output ("ERROR: could not install the TGOS Toolbox: {0}" -f (($_.Exception.Message -replace '\s+', ' ').Trim()))
    exit 1
}

try {
    if (-not (Test-Path -LiteralPath $ShortcutDirectory)) {
        New-Item -ItemType Directory -Path $ShortcutDirectory -Force | Out-Null
    }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path $ShortcutDirectory 'TGOS Toolbox.lnk'))
    $shortcut.TargetPath = $ToolboxDestination
    $shortcut.Description = 'TGOS Toolbox'
    $shortcut.Save()
    Write-Output 'TGOS: desktop shortcut created'
}
catch {
    Write-Output ("WARNING: could not create the desktop shortcut: {0}" -f (($_.Exception.Message -replace '\s+', ' ').Trim()))
}

try {
    $wallpaperSource = Join-Path $SourceRoot 'TGOS\TGOS.png'
    if (-not (Test-Path -LiteralPath $WallpaperDestination)) {
        New-Item -ItemType Directory -Path $WallpaperDestination -Force | Out-Null
    }
    Copy-Item -LiteralPath $wallpaperSource -Destination (Join-Path $WallpaperDestination 'TGOS.png') -Force
    Write-Output ("TGOS: wallpaper copied to {0}" -f $WallpaperDestination)
}
catch {
    Write-Output ("WARNING: could not copy the wallpaper: {0}" -f (($_.Exception.Message -replace '\s+', ' ').Trim()))
}

try {
    $layoutSource = Join-Path $SourceRoot 'TGOS\TaskbarLayout.xml'
    if (-not (Test-Path -LiteralPath $DataDirectory)) {
        New-Item -ItemType Directory -Path $DataDirectory -Force | Out-Null
    }
    Copy-Item -LiteralPath $layoutSource -Destination (Join-Path $DataDirectory 'TaskbarLayout.xml') -Force
    Write-Output ("TGOS: taskbar layout copied to {0}" -f $DataDirectory)
}
catch {
    Write-Output ("WARNING: could not copy the taskbar layout: {0}" -f (($_.Exception.Message -replace '\s+', ' ').Trim()))
}

exit 0
