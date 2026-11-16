<#
.SYNOPSIS
    Menghapus program Microsoft Copilot dengan uninstaller miliknya sendiri.

.DESCRIPTION
    Di Windows 11 26H2, Copilot bukan paket Microsoft Store. Ia program biasa di
    "%ProgramFiles(x86)%\Microsoft\Copilot" (sekitar 1,7 GB) yang terdaftar di
        HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Copilot
    dengan uninstaller sejenis uninstaller Edge:
        copilot_setup.exe --uninstall --mscopilot --channel=stable --system-level

    Skrip ini:
      1. Membaca UninstallString dari registry (tidak menebak jalurnya).
      2. Mencatat ID produk Copilot di EdgeUpdate dan memasang policy supaya EdgeUpdate
         tidak memasangnya lagi.
      3. Menjalankan uninstaller itu lewat Remove-TgosChromiumProduct (Common.ps1),
         cara yang sama dengan yang berhasil untuk Edge.

    Harus dijalankan SEBELUM paket Microsoft.MicrosoftOfficeHub dihapus: paket itu
    adalah identitas aplikasi Copilot di Start dan taskbar.

    Bila Copilot tidak terpasang (build lama, edisi lain), skrip tidak melakukan apa-apa.
    Tidak fatal (kode keluar selalu 0); hasilnya diperiksa Test-TgosResult.ps1.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

function Get-CopilotEntry {
    # Kunci yang diketahui lebih dulu, lalu pencarian menurut isi (nama kunci bisa berubah).
    $roots = @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($root in $roots) {
        $known = Join-Path $root 'Microsoft Copilot'
        if (Test-Path -LiteralPath $known) {
            $item = Get-ItemProperty -LiteralPath $known -ErrorAction SilentlyContinue
            if ($item -and $item.UninstallString) { return @{ Key = $known; Item = $item } }
        }
    }
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            if ($item -and ('' + $item.UninstallString) -match '--mscopilot|copilot_setup\.exe') {
                return @{ Key = $key.PSPath; Item = $item }
            }
        }
    }
    return $null
}

try {
    $entry = Get-CopilotEntry
    if (-not $entry) {
        Write-Output 'TGOS: the Copilot program is not installed; nothing to remove'
        exit 0
    }

    $command = Split-TgosCommandLine ('' + $entry.Item.UninstallString)
    if (-not $command -or -not (Test-Path -LiteralPath $command.File)) {
        Write-Output ("WARNING: the Copilot uninstaller was not found: {0}" -f $entry.Item.UninstallString)
        exit 0
    }
    $arguments = $command.Arguments
    if ($arguments -notmatch '--force-uninstall') {
        $arguments = ($arguments + ' --force-uninstall').Trim()
    }
    $installLocation = ('' + $entry.Item.InstallLocation).TrimEnd('\')

    # ID produk Copilot di EdgeUpdate, dibaca sebelum uninstall menghapusnya.
    $productGuid = $null
    $clients = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients'
    if (Test-Path -LiteralPath $clients) {
        foreach ($client in (Get-ChildItem -LiteralPath $clients -ErrorAction SilentlyContinue)) {
            $name = (Get-ItemProperty -LiteralPath $client.PSPath -ErrorAction SilentlyContinue).name
            if (('' + $name) -match 'Copilot') { $productGuid = $client.PSChildName; break }
        }
    }
    if ($productGuid) {
        $policy = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'
        if (-not (Test-Path -LiteralPath $policy)) { New-Item -Path $policy -Force | Out-Null }
        Set-ItemProperty -LiteralPath $policy -Name ('Install{0}' -f $productGuid) -Value 0 -Type DWord
        Write-Output ("TGOS: EdgeUpdate will not reinstall Copilot (product {0})" -f $productGuid)
    }
    else {
        Write-Output 'TGOS: no Copilot product id found in EdgeUpdate; no reinstall policy written'
    }

    $entryKey = $entry.Key
    $isInstalled = { Test-Path -LiteralPath $entryKey }
    $stopCopilot = {
        if ($installLocation) {
            Get-Process -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -and $_.Path.StartsWith($installLocation, [System.StringComparison]::OrdinalIgnoreCase) } |
                Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }
    Remove-TgosChromiumProduct -Label 'Copilot' -Setup $command.File -Arguments $arguments `
        -TestInstalled $isInstalled -StopProcesses $stopCopilot -ClientStateGuid $productGuid

    if (& $isInstalled) {
        Write-Output 'WARNING: the Copilot program is still installed; Windows refused the uninstall'
    }
    else {
        Write-Output 'TGOS: the Copilot program was removed'
        # Folder kosong yang kadang tertinggal. Hanya dihapus bila benar folder Copilot.
        $folder = Split-Path -Parent $installLocation
        if ($folder -and $folder.EndsWith('\Microsoft\Copilot', [System.StringComparison]::OrdinalIgnoreCase) -and
            (Test-Path -LiteralPath $folder)) {
            Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
catch {
    Write-Output ("WARNING: could not remove the Copilot program: {0}" -f (Format-TgosError $_))
}

exit 0
