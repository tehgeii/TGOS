<#
.SYNOPSIS
    Menonaktifkan tugas terjadwal yang terdaftar di Executables\TGOS\scheduled-tasks.txt.

.DESCRIPTION
    Tugas yang tidak ada di sistem dilewati (daftar tugas berbeda antar-build Windows).
    Tugas tidak pernah dihapus: hanya dinonaktifkan, jadi bisa diaktifkan lagi lewat
    Task Scheduler.

    Tidak fatal: kode keluar selalu 0. Hasil akhirnya diperiksa Test-TgosResult.ps1.

    Parameter hanya dipakai untuk pengujian.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$ListPath
)

$ErrorActionPreference = 'Stop'

if (-not $ListPath) {
    $ListPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'TGOS\scheduled-tasks.txt'
}

$disabled = 0
$missing = 0
$failed = 0

try {
    $entries = @(Get-Content -LiteralPath $ListPath | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') })
}
catch {
    Write-Output ("WARNING: could not read the task list {0}: {1}" -f $ListPath, $_.Exception.Message)
    exit 0
}

foreach ($entry in $entries) {
    # '\Microsoft\Windows\Maps\MapsUpdateTask' -> folder '\Microsoft\Windows\Maps\', nama 'MapsUpdateTask'
    $separator = $entry.LastIndexOf('\')
    if ($separator -lt 0) {
        Write-Output ("WARNING: not a task path: {0}" -f $entry)
        $failed++
        continue
    }
    $taskPath = $entry.Substring(0, $separator + 1)
    $taskName = $entry.Substring($separator + 1)

    try {
        $task = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
        if ($null -eq $task) {
            Write-Output ("TGOS: task not present, skipped: {0}" -f $entry)
            $missing++
            continue
        }
        if ($task.State -eq 'Disabled') {
            Write-Output ("TGOS: task already disabled: {0}" -f $entry)
            $disabled++
            continue
        }
        Disable-ScheduledTask -TaskPath $taskPath -TaskName $taskName | Out-Null
        Write-Output ("TGOS: task disabled: {0}" -f $entry)
        $disabled++
    }
    catch {
        $reason = ($_.Exception.Message -replace '\s+', ' ').Trim()
        Write-Output ("WARNING: could not disable {0}: {1}" -f $entry, $reason)
        $failed++
    }
}

Write-Output ("TGOS: scheduled tasks - disabled {0}, not present {1}, failed {2}" -f $disabled, $missing, $failed)
exit 0
