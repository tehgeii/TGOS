<#
.SYNOPSIS
    Menghentikan layanan yang sudah dijadikan Disabled, sekarang juga.

.DESCRIPTION
    Aksi !service di playbook hanya mengubah Startup type (tools/validate.py melarang
    operasi lain), jadi layanan yang sedang berjalan tetap jalan sampai Windows restart.

    Untuk DiagTrack (Connected User Experiences and Telemetry) itu bermasalah. Di uji VM
    v1.0.0 nilai Start perekam "AutoLogger-Diagtrack-Listener" yang ditulis TGOS sudah
    hilang setelah restart: DiagTrack masih berjalan selama instalasi dan menulis ulang
    konfigurasi perekamnya sendiri saat dihentikan ketika shutdown. Karena itu DiagTrack
    dihentikan di sini dulu, dan playbook menulis nilai perekam SESUDAH skrip ini.

    -Names: daftar nama layanan, dipisah koma (mis. "DiagTrack"). Tanpa wildcard.

    Hanya layanan yang Startup type-nya sudah Disabled (Start = 4) yang dihentikan;
    layanan lain dibiarkan dengan pesan. Tidak fatal: kode keluar selalu 0.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Names
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

foreach ($name in @($Names -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
    try {
        if ($name -notmatch '^[A-Za-z0-9_.\-]+$') {
            Write-Output ("WARNING: '{0}' is not a plain service name; skipped" -f $name)
            continue
        }
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $service) {
            Write-Output ("TGOS: service {0} is not present; nothing to stop" -f $name)
            continue
        }
        $start = (Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Services\{0}' -f $name) -Name 'Start' -ErrorAction SilentlyContinue).Start
        if ($start -ne 4) {
            Write-Output ("WARNING: service {0} is not Disabled (Start={1}); it was not stopped" -f $name, $start)
            continue
        }
        if ($service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
            Write-Output ("TGOS: service {0} is already stopped" -f $name)
            continue
        }
        $service.Stop()
        $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(30))
        Write-Output ("TGOS: service {0} stopped" -f $name)
    }
    catch {
        Write-Output ("WARNING: could not stop service {0}: {1}" -f $name, (Format-TgosError $_))
    }
}

exit 0
