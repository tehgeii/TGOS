<#
.SYNOPSIS
    Memasang TGOS Toolbox dan wallpaper TGO ke sistem.

.DESCRIPTION
    1. Menyalin folder "TGOS Toolbox" dari playbook ke <drive sistem>\TGOS Toolbox,
       ditambah tiga skrip playbook yang dipakai tombol Toolbox (Common.ps1,
       Install-Software.ps1, Set-ShellLayout.ps1) ke subfolder Support.
    2. Membuat pintasan "TGOS Toolbox" di Desktop semua pengguna.
    3. Menyalin wallpaper ke %SystemRoot%\Web\Wallpaper\TGOS\TGOS.png.

    -Part memilih langkahnya:
        All       1, 2, dan 3 (bawaan)
        Files     1 dan 3
        Shortcut  hanya 2
    Playbook memakai Files lebih dulu (wallpaper harus sudah ada sebelum Explorer
    dijalankan lagi) dan Shortcut di paling akhir, SETELAH Explorer hidup lagi. Di uji VM
    v1.0.0 pintasan yang dibuat sebelum Explorer dihentikan untuk reset pin muncul di
    tengah Desktop; dibuat sesudahnya, Explorer menaruhnya di petak kosong berikutnya
    seperti pintasan baru biasa.

    Kode keluar 1 hanya bila Toolbox gagal disalin (atau, untuk Shortcut, belum
    terpasang). Langkah lain tidak fatal.

    Parameter selain -Part hanya dipakai untuk pengujian.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [ValidateSet('All', 'Files', 'Shortcut')]
    [string]$Part = 'All',
    [string]$SourceRoot,
    [string]$ToolboxDestination,
    [string]$WallpaperDestination,
    [string]$ShortcutDirectory
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

if ($Part -ne 'Shortcut') {
    try {
        $toolboxSource = Join-Path $SourceRoot 'TGOS Toolbox'
        if (-not (Test-Path -LiteralPath $toolboxSource)) {
            throw ("Toolbox source not found: {0}" -f $toolboxSource)
        }
        if (Test-Path -LiteralPath $ToolboxDestination) {
            Remove-Item -LiteralPath $ToolboxDestination -Recurse -Force
        }
        Copy-Item -LiteralPath $toolboxSource -Destination $ToolboxDestination -Recurse -Force

        # Skrip playbook yang juga dipakai tombol Toolbox (pasang software, susun ulang pin).
        foreach ($name in @('Common.ps1', 'Install-Software.ps1', 'Set-ShellLayout.ps1')) {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $ToolboxDestination 'Support') -Force
        }
        Write-Output ("TGOS: Toolbox installed to {0}" -f $ToolboxDestination)
    }
    catch {
        Write-Output ("ERROR: could not install the TGOS Toolbox: {0}" -f (($_.Exception.Message -replace '\s+', ' ').Trim()))
        exit 1
    }
}

if ($Part -ne 'Files') {
    try {
        if (-not (Test-Path -LiteralPath $ToolboxDestination)) {
            throw ("the Toolbox is not installed at {0}" -f $ToolboxDestination)
        }
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
        if ($Part -eq 'Shortcut') { exit 1 }
    }
}

if ($Part -ne 'Shortcut') {
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
}

exit 0
