<#
.SYNOPSIS
    Membersihkan disk: file sementara, cache update, laporan error, file dump, dan
    komponen Windows yang sudah tidak dipakai.

.DESCRIPTION
    Dipakai opsi "Deep clean" dan "Deep clean+" di akhir instalasi TGOS, dan tombol
    "Deep Clean" di TGOS Toolbox.

    Deep clean (selalu aman dibatalkan efeknya; yang dihapus hanya sampah):
      - %SystemRoot%\Temp dan folder Temp tiap profil pengguna
      - cache unduhan Windows Update (SoftwareDistribution\Download); layanan Windows
        Update dan BITS dihentikan sebentar lalu dikembalikan seperti semula
      - cache Delivery Optimization
      - laporan error Windows (WER) dan file dump crash (Minidump, MEMORY.DMP,
        LiveKernelReports)
      - arsip log CBS lama (*.cab)
      - DISM /StartComponentCleanup: versi komponen Windows yang sudah diganti
      - Reserved Storage dimatikan (DISM /Set-ReservedStorageState): ruang yang
        dicadangkan Windows untuk update dikembalikan. Bisa dinyalakan lagi lewat
        "Reserved Storage - Turn ON" di TGOS Toolbox.
        Bila Windows sedang memakai cadangan itu, dicoba lagi otomatis sekali setelah
        restart (tugas terjadwal tersembunyi yang menghapus dirinya sendiri).

    -Plus (Deep clean+), TIDAK BISA DIBATALKAN:
      - Windows.old, $WINDOWS.~BT, $Windows.~WS, dan C:\ESD (sisa upgrade Windows):
        fitur "Go back" ke versi Windows sebelumnya hilang
      - DISM /StartComponentCleanup /ResetBase: update yang sudah terpasang tidak bisa
        di-uninstall lagi

    Yang TIDAK pernah disentuh: Prefetch, Recycle Bin, Event Log, dokumen dan data
    pengguna, browser, game. Folder playbook yang sedang berjalan dan folder AME
    dilewati. Folder dihapus dengan "rd /s /q", yang menghapus junction/symlink sebagai
    tautan dan TIDAK mengikutinya (Windows.old berisi junction yang bisa menunjuk ke
    folder pengguna yang sekarang). File yang sedang dipakai dilewati.

    -Playbook: dipanggil playbook. Bila opsi "deep-clean-plus" juga dipilih, panggilan
    tanpa -Plus tidak melakukan apa-apa (panggilan -Plus mengerjakan semuanya).

    Hasil dicatat di <folder data TGOS>\deep-clean.txt. Tidak fatal: kode keluar selalu 0.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [switch]$Plus,
    [switch]$Playbook,
    [string]$DataDirectory
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

$systemDrive = '{0}\' -f $env:SystemDrive
$lines = @()

function Get-FreeBytes {
    return ([IO.DriveInfo]::new($systemDrive)).AvailableFreeSpace
}

function Add-Line {
    param([string]$Text)
    $script:lines += $Text
    Write-Output ('TGOS: {0}' -f $Text)
}

# Folder yang tidak boleh dihapus: playbook yang sedang berjalan (skrip ini ada di
# <playbook>\Executables\Scripts) dan folder AME.
$protected = @((Join-Path $env:ProgramData 'AME'))
if ($Playbook) {
    $protected += (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
}

function Test-Protected {
    param([string]$Path)
    $full = $Path.TrimEnd('\')
    foreach ($item in $protected) {
        # Dilewati bila sama dengan, atau berisi, folder yang dilindungi.
        if ($item -eq $full -or $item.StartsWith($full + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return ((Split-Path -Leaf $full) -match '(?i)^(AME|TrustedUninstaller)')
}

function Remove-TgosItem {
    # Menghapus satu file atau folder. Junction/symlink dihapus sebagai tautan saja.
    param($Item)
    if (Test-Protected $Item.FullName) { return }
    try {
        $isLink = ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
        if ($Item.PSIsContainer) {
            if ($isLink) { & cmd.exe /c ('rd "{0}" 2>nul' -f $Item.FullName) | Out-Null }
            else { & cmd.exe /c ('rd /s /q "{0}" 2>nul' -f $Item.FullName) | Out-Null }
        }
        else {
            Remove-Item -LiteralPath $Item.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    catch { }
}

function Clear-Folder {
    # Isi folder dihapus, foldernya sendiri dibiarkan.
    param([string]$Path, [string]$Filter = '*')
    if (-not (Test-Path -LiteralPath $Path)) { return }
    foreach ($item in @(Get-ChildItem -LiteralPath $Path -Filter $Filter -Force -ErrorAction SilentlyContinue)) {
        Remove-TgosItem $item
    }
}

function Invoke-Step {
    param([string]$Name, [scriptblock]$Action)
    $before = Get-FreeBytes
    try {
        & $Action
        $freed = ((Get-FreeBytes) - $before) / 1MB
        if ($freed -lt 0) { $freed = 0 }
        Add-Line ('{0}: done, {1:N0} MB freed' -f $Name, $freed)
    }
    catch {
        Add-Line ('{0}: WARNING {1}' -f $Name, (Format-TgosError $_))
    }
}

function Invoke-Dism {
    param([string]$Arguments, [int]$Minutes)
    $code = Invoke-TgosProcess -File (Join-Path $env:SystemRoot 'System32\dism.exe') -Arguments $Arguments -TimeoutMilliseconds ($Minutes * 60000)
    if ($null -eq $code) { throw ('DISM did not finish within {0} minutes' -f $Minutes) }
    if (@(0, 3010) -notcontains $code) { throw ('DISM returned exit code {0}' -f $code) }
}

try {
    $DataDirectory = Get-TgosDataDirectory -Path $DataDirectory
    if ($Playbook -and -not $Plus) {
        $info = Join-Path $DataDirectory 'install-info.txt'
        if ((Test-Path -LiteralPath $info) -and (@(Get-Content -LiteralPath $info) -match '^Option selected\s*:\s*deep-clean-plus\s*$').Count) {
            Write-Output 'TGOS: deep clean runs in the Deep clean+ step instead'
            exit 0
        }
    }

    $start = Get-FreeBytes
    $mode = 'Deep clean'
    if ($Plus) { $mode = 'Deep clean+' }
    Add-Line ('{0} started, {1:N1} GB free on {2}' -f $mode, ($start / 1GB), $env:SystemDrive)

    Invoke-Step 'temporary files' {
        Clear-Folder (Join-Path $env:SystemRoot 'Temp')
        foreach ($userProfile in (Get-TgosUserProfiles)) {
            Clear-Folder (Join-Path $userProfile.Path 'AppData\Local\Temp')
        }
        if ($env:TEMP) { Clear-Folder $env:TEMP }
    }

    Invoke-Step 'Windows Update download cache' {
        $services = @('wuauserv', 'bits')
        $running = @($services | Where-Object { (Get-Service -Name $_ -ErrorAction SilentlyContinue).Status -eq 'Running' })
        foreach ($name in $services) { Stop-Service -Name $name -Force -ErrorAction SilentlyContinue }
        try {
            Clear-Folder (Join-Path $env:SystemRoot 'SoftwareDistribution\Download')
        }
        finally {
            foreach ($name in $running) { Start-Service -Name $name -ErrorAction SilentlyContinue }
        }
    }

    Invoke-Step 'Delivery Optimization cache' {
        if (Get-Command -Name 'Delete-DeliveryOptimizationCache' -ErrorAction SilentlyContinue) {
            Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }

    Invoke-Step 'error reports and crash dumps' {
        foreach ($folder in @('ReportArchive', 'ReportQueue', 'Temp')) {
            Clear-Folder (Join-Path $env:ProgramData ('Microsoft\Windows\WER\{0}' -f $folder))
        }
        Clear-Folder (Join-Path $env:SystemRoot 'Minidump')
        Clear-Folder (Join-Path $env:SystemRoot 'LiveKernelReports') '*.dmp'
        $dump = Join-Path $env:SystemRoot 'MEMORY.DMP'
        if (Test-Path -LiteralPath $dump) { Remove-Item -LiteralPath $dump -Force -ErrorAction SilentlyContinue }
        Clear-Folder (Join-Path $env:SystemRoot 'Logs\CBS') '*.cab'
    }

    if ($Plus) {
        Invoke-Step 'previous Windows installation (Windows.old)' {
            foreach ($name in @('Windows.old', '$WINDOWS.~BT', '$Windows.~WS', 'ESD')) {
                $path = Join-Path $systemDrive $name
                if (Test-Path -LiteralPath $path) {
                    & cmd.exe /c ('rd /s /q "{0}" 2>nul' -f $path) | Out-Null
                    if (Test-Path -LiteralPath $path) { Add-Line ('{0} could only be removed in part' -f $path) }
                }
            }
        }
        Invoke-Step 'component store cleanup with ResetBase' {
            Invoke-Dism -Arguments '/Online /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet' -Minutes 90
        }
    }
    else {
        Invoke-Step 'component store cleanup' {
            Invoke-Dism -Arguments '/Online /Cleanup-Image /StartComponentCleanup /Quiet' -Minutes 60
        }
    }

    Invoke-Step 'reserved storage off' {
        try {
            Invoke-Dism -Arguments '/Online /Set-ReservedStorageState /State:Disabled /Quiet' -Minutes 10
        }
        catch {
            # -2146498187 = 0x800F0975: Windows sedang memakai cadangan itu untuk operasi
            # servicing (mis. update yang sedang disiapkan; uji VM revisi kedua 1.0.0).
            # Biasanya selesai setelah restart, jadi dicoba lagi otomatis saat startup.
            if ((Format-TgosError $_) -notmatch '-2146498187') { throw }
            Register-TgosReservedStorageRetry
            throw 'Windows is using it for an update right now; it is turned off automatically after the next restart'
        }
    }

    $end = Get-FreeBytes
    Add-Line ('{0} completed: {1:N2} GB freed, {2:N1} GB free on {3}' -f $mode, (($end - $start) / 1GB), ($end / 1GB), $env:SystemDrive)
}
catch {
    Add-Line ('WARNING: deep clean stopped: {0}' -f (Format-TgosError $_))
}
finally {
    try {
        $record = Join-Path $DataDirectory 'deep-clean.txt'
        Set-Content -LiteralPath $record -Value (@(('Run at {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))) + $lines) -Encoding ASCII
    }
    catch { }
}

exit 0
