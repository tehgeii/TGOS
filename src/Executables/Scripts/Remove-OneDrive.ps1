<#
.SYNOPSIS
    Menghapus OneDrive dengan uninstaller resminya.

.DESCRIPTION
    Dijalankan sebagai pengguna yang sedang login, karena OneDrive terpasang per
    pengguna. Hanya memanggil "OneDriveSetup.exe /uninstall"; file pengguna di folder
    OneDrive tidak disentuh.

    Tidak fatal: kode keluar selalu 0. Hasilnya diperiksa Test-TgosResult.ps1.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    $candidates = @(
        (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'),
        (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe')
    )
    $setup = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

    if (-not $setup) {
        Write-Output 'TGOS: OneDriveSetup.exe not found; nothing to uninstall'
        exit 0
    }

    Write-Output ("TGOS: running {0} /uninstall" -f $setup)
    $process = Start-Process -FilePath $setup -ArgumentList '/uninstall' -PassThru -WindowStyle Hidden
    if (-not $process.WaitForExit(180000)) {
        Write-Output 'WARNING: the OneDrive uninstaller did not finish within 3 minutes'
        exit 0
    }

    $installed = Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'
    if (Test-Path -LiteralPath $installed) {
        Write-Output ("WARNING: OneDrive is still present at {0}" -f $installed)
    }
    else {
        Write-Output 'TGOS: OneDrive uninstalled for the current user'
    }
}
catch {
    Write-Output ("WARNING: could not uninstall OneDrive: {0}" -f (($_.Exception.Message -replace '\s+', ' ').Trim()))
}

exit 0
