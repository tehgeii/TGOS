<#
.SYNOPSIS
    Menjalankan Explorer lagi bila sedang tidak berjalan.

.DESCRIPTION
    Set-ShellLayout.ps1 menghentikan Explorer untuk menyusun ulang pin. Skrip ini
    dijalankan playbook sesudahnya SEBAGAI PENGGUNA YANG LOGIN (bukan TrustedInstaller),
    supaya Explorer hidup lagi dengan hak pengguna biasa.

    Bila Explorer sudah berjalan, tidak ada yang dilakukan (menjalankannya lagi hanya
    membuka jendela File Explorer).

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param()

try {
    if (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue) {
        Write-Output 'TGOS: Explorer is already running'
    }
    else {
        Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe')
        Write-Output 'TGOS: Explorer started'
    }
}
catch {
    Write-Output ("WARNING: could not start Explorer: {0}" -f (($_.Exception.Message -replace '\s+', ' ').Trim()))
}

exit 0
