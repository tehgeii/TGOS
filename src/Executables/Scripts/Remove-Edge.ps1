<#
.SYNOPSIS
    Menghapus Microsoft Edge dengan uninstaller milik Edge sendiri.

.DESCRIPTION
    Uninstaller Edge (setup.exe) menolak bekerja di banyak instalasi Windows 11: di
    Windows 11 Pro 26H2 uninstall biasa keluar dengan kode 93 tanpa menghapus apa pun.
    Skrip ini memakai Remove-TgosChromiumProduct di Common.ps1, yang mencoba dua cara
    berurutan. Di uji Windows 11 Pro 26H2 (TGOS 0.9.1) cara pertama berhasil.

    Microsoft Edge WebView2 Runtime TIDAK dihapus: itu produk terpisah yang dipakai
    banyak launcher dan aplikasi. Update Windows bisa memasang Edge lagi.

    -RequireBrowser
        Edge TIDAK dihapus bila tidak ada browser lain yang terpasang. Dipakai playbook
        ketika pengguna memilih browser untuk dipasang: bila pemasangannya gagal, Edge
        dibiarkan supaya pengguna tidak kehilangan browser.

    Skrip ini tidak fatal (kode keluar selalu 0); hasil sebenarnya diperiksa
    Test-TgosResult.ps1.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [switch]$RequireBrowser
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

$EdgeGuid = '{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'
$UninstallArguments = '--uninstall --msedge --system-level --channel=stable --verbose-logging --force-uninstall'

function Get-EdgeRoot {
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if ($base) {
            $root = Join-Path $base 'Microsoft\Edge\Application'
            if (Test-Path -LiteralPath $root) { return $root }
        }
    }
    return $null
}

try {
    $edgeRoot = Get-EdgeRoot
    if (-not $edgeRoot -or -not (Test-Path -LiteralPath (Join-Path $edgeRoot 'msedge.exe'))) {
        Write-Output 'TGOS: Microsoft Edge is not installed; nothing to remove'
        exit 0
    }

    if ($RequireBrowser) {
        $other = @(Get-TgosInstalledBrowsers)
        if ($other.Count -eq 0) {
            Write-Output 'WARNING: Microsoft Edge was kept: the selected browser is not installed, and removing Edge would leave no browser'
            exit 0
        }
        Write-Output ("TGOS: another browser is installed ({0}); removing Microsoft Edge" -f (($other | ForEach-Object { $_.Name }) -join ', '))
    }

    $setup = Get-ChildItem -LiteralPath $edgeRoot -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'Installer\setup.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Sort-Object -Descending |
        Select-Object -First 1
    if (-not $setup) {
        Write-Output ("WARNING: no Edge setup.exe found under {0}" -f $edgeRoot)
        exit 0
    }

    $isInstalled = { Test-Path -LiteralPath (Join-Path $edgeRoot 'msedge.exe') }
    $stopEdge = {
        Get-Process -Name 'msedge' -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Remove-TgosChromiumProduct -Label 'Edge' -Setup $setup -Arguments $UninstallArguments `
        -TestInstalled $isInstalled -StopProcesses $stopEdge -ClientStateGuid $EdgeGuid

    if (& $isInstalled) {
        Write-Output 'WARNING: Microsoft Edge is still installed; Windows refused the uninstall'
    }
    else {
        Write-Output 'TGOS: Microsoft Edge removed (WebView2 Runtime kept)'
        foreach ($shortcut in @(
                (Join-Path $env:PUBLIC 'Desktop\Microsoft Edge.lnk'),
                (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk'))) {
            if (Test-Path -LiteralPath $shortcut) {
                Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
catch {
    Write-Output ("WARNING: could not remove Microsoft Edge: {0}" -f (Format-TgosError $_))
}

exit 0
