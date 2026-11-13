<#
.SYNOPSIS
    Membuat restore point "Before TGOS <versi>" sebelum playbook mengubah sistem.

.DESCRIPTION
    1. Mengaktifkan System Protection di drive sistem bila belum aktif.
    2. Membuat restore point. Windows menolak membuat lebih dari satu restore point
       dalam 24 jam, jadi batas itu dilonggarkan sementara lalu dikembalikan.
    3. Menulis hasilnya ke <folder data TGOS>\restore-point.txt, yang nanti disalin ke
       install-info.txt.

    Skrip ini TIDAK fatal: apa pun yang terjadi kode keluarnya 0, supaya kegagalan
    membuat restore point tidak menghentikan playbook. Hasilnya tetap tercatat.

    Restore point mengembalikan registry dan file sistem. Aplikasi yang dihapus TGOS
    tidak kembali lewat restore point; pasang lagi dari Microsoft Store.

    Parameter hanya dipakai untuk pengujian.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$ConfPath,
    [string]$DataDirectory
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

$status = 'failed: unknown error'

try {
    $version = Get-TgosVersion -ConfPath $ConfPath
    $description = 'Before TGOS {0}' -f $version
    $systemDrive = '{0}\' -f $env:SystemDrive

    Write-Output ("TGOS: enabling System Protection on {0}" -f $systemDrive)
    Enable-ComputerRestore -Drive $systemDrive

    $frequencyKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $frequencyName = 'SystemRestorePointCreationFrequency'
    $hadValue = $false
    $previousValue = $null
    $existing = Get-ItemProperty -LiteralPath $frequencyKey -Name $frequencyName -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        $hadValue = $true
        $previousValue = $existing.$frequencyName
    }

    try {
        # 0 = tidak ada jeda minimum antar restore point.
        Set-ItemProperty -LiteralPath $frequencyKey -Name $frequencyName -Value 0 -Type DWord
        Write-Output ("TGOS: creating restore point '{0}'" -f $description)
        Checkpoint-Computer -Description $description -RestorePointType 'MODIFY_SETTINGS'
    }
    finally {
        if ($hadValue) {
            Set-ItemProperty -LiteralPath $frequencyKey -Name $frequencyName -Value $previousValue -Type DWord
        }
        else {
            Remove-ItemProperty -LiteralPath $frequencyKey -Name $frequencyName -ErrorAction SilentlyContinue
        }
    }

    # Checkpoint-Computer bisa selesai tanpa error walau restore point tidak terbuat,
    # jadi hasilnya dipastikan dengan membaca daftar restore point.
    $created = Get-ComputerRestorePoint | Where-Object { $_.Description -eq $description }
    if ($created) {
        $status = "created: '{0}'" -f $description
        Write-Output ("TGOS: restore point created: '{0}'" -f $description)
    }
    else {
        $status = 'failed: Windows did not list the restore point after creating it'
        Write-Output 'WARNING: Windows did not list the restore point after creating it.'
    }
}
catch {
    # Satu baris saja, supaya rapi di install-info.txt.
    $reason = ($_.Exception.Message -replace '\s+', ' ').Trim()
    $status = 'failed: {0}' -f $reason
    Write-Output ("WARNING: restore point was not created: {0}" -f $reason)
}

try {
    $dataDir = Get-TgosDataDirectory -Path $DataDirectory
    Set-Content -LiteralPath (Join-Path $dataDir 'restore-point.txt') -Value $status -Encoding ASCII
}
catch {
    Write-Output ("WARNING: could not record the restore point result: {0}" -f $_.Exception.Message)
}

exit 0
