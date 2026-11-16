<#
.SYNOPSIS
    Menghapus Microsoft Edge dengan uninstaller milik Edge sendiri. EKSPERIMENTAL.

.DESCRIPTION
    1. Mencari setup.exe Edge versi terpasang.
    2. Menandai Edge boleh di-uninstall (nilai AllowUninstall yang dibaca setup.exe).
    3. Menjalankan "setup.exe --uninstall --msedge --system-level --force-uninstall".

    Microsoft Edge WebView2 Runtime TIDAK dihapus: itu produk terpisah yang dipakai
    banyak launcher dan aplikasi.

    Microsoft bisa menolak uninstall ini di sebagian wilayah atau build, dan update
    Windows bisa memasang Edge lagi. Karena itu skrip ini tidak fatal (kode keluar
    selalu 0) dan hasil sebenarnya diperiksa Test-TgosResult.ps1.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

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
    if (-not $edgeRoot) {
        Write-Output 'TGOS: Microsoft Edge is not installed; nothing to remove'
        exit 0
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

    $allowKey = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev'
    if (-not (Test-Path -LiteralPath $allowKey)) {
        New-Item -Path $allowKey -Force | Out-Null
    }
    Set-ItemProperty -LiteralPath $allowKey -Name 'AllowUninstall' -Value '' -Type String

    Get-Process -Name 'msedge' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    Write-Output ("TGOS: running {0} --uninstall --msedge --system-level --force-uninstall" -f $setup)
    $process = Start-Process -FilePath $setup -PassThru -WindowStyle Hidden `
        -ArgumentList '--uninstall', '--msedge', '--system-level', '--verbose-logging', '--force-uninstall'
    if (-not $process.WaitForExit(300000)) {
        Write-Output 'WARNING: the Edge uninstaller did not finish within 5 minutes'
        exit 0
    }
    Write-Output ("TGOS: Edge uninstaller exit code {0}" -f $process.ExitCode)

    if (Test-Path -LiteralPath (Join-Path $edgeRoot 'msedge.exe')) {
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
    Write-Output ("WARNING: could not remove Microsoft Edge: {0}" -f (($_.Exception.Message -replace '\s+', ' ').Trim()))
}

exit 0
