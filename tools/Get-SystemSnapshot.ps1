<#
.SYNOPSIS
    Memotret keadaan Windows ke satu file JSON, untuk membandingkan sebelum dan sesudah TGOS.

.DESCRIPTION
    Skrip ini HANYA MEMBACA. Satu-satunya yang ditulisnya adalah file hasil:
        TGOS-snapshot-<label>.json   (default: di Desktop)

    Isinya: edisi dan build Windows, jumlah proses/thread/handle, RAM dan disk terpakai,
    daftar layanan, paket AppX, tugas terjadwal, restore point, status Defender, dan isi
    install-info.txt TGOS bila ada.

    Yang sengaja TIDAK dikumpulkan: nama komputer, nama pengguna, alamat jaringan, dan
    isi file pribadi. Catatan: beberapa nama tugas terjadwal memuat SID pengguna; SID itu
    disamarkan menjadi "S-1-5-21-***".

    Jalankan di PowerShell sebagai Administrator, 5 menit setelah boot supaya angkanya
    stabil:

        powershell -ExecutionPolicy Bypass -File .\Get-SystemSnapshot.ps1 -Label before

    Lalu terapkan TGOS, restart, tunggu 5 menit, dan jalankan lagi dengan -Label after.
    Bandingkan keduanya dengan tools\compare-snapshots.py.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.

.PARAMETER Label
    Nama potret, mis. before atau after. Hanya huruf, angka, tanda hubung, garis bawah.

.PARAMETER OutputDirectory
    Folder tujuan. Default: Desktop pengguna yang menjalankan skrip.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$Label,

    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'

function Hide-Sid {
    param([string]$Text)
    if ($null -eq $Text) { return $null }
    return ($Text -replace 'S-1-5-21-[0-9-]+', 'S-1-5-21-***')
}

function Invoke-Section {
    <#
    Menjalankan satu bagian pengumpulan. Bila gagal, galatnya dicatat di $errors dan
    bagian itu bernilai $null, supaya satu kegagalan tidak membatalkan seluruh potret.
    #>
    param(
        [string]$Name,
        [scriptblock]$Script
    )
    try {
        return (& $Script)
    }
    catch {
        $script:errors += ('{0}: {1}' -f $Name, $_.Exception.Message)
        return $null
    }
}

$script:errors = @()

$isAdmin = $false
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
catch {
    $script:errors += ('admin-check: {0}' -f $_.Exception.Message)
}
if (-not $isAdmin) {
    Write-Warning 'Not running as Administrator. The AppX and provisioned package lists will be incomplete.'
}

$os = Invoke-Section 'os' {
    $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [ordered]@{
        edition        = [string]$cv.EditionID
        displayVersion = [string]$cv.DisplayVersion
        build          = [int]$cv.CurrentBuildNumber
        updateRevision = [int]$cv.UBR
        architecture   = [string]$env:PROCESSOR_ARCHITECTURE
    }
}

$counts = Invoke-Section 'counts' {
    $processes = @(Get-Process)
    [ordered]@{
        processes = $processes.Count
        threads   = [int](($processes | ForEach-Object { $_.Threads.Count } | Measure-Object -Sum).Sum)
        handles   = [int](($processes | Measure-Object -Property HandleCount -Sum).Sum)
    }
}

$memory = Invoke-Section 'memory' {
    $info = Get-CimInstance -ClassName Win32_OperatingSystem
    $totalMb = [math]::Round($info.TotalVisibleMemorySize / 1024)
    $freeMb = [math]::Round($info.FreePhysicalMemory / 1024)
    [ordered]@{
        totalMb = $totalMb
        inUseMb = $totalMb - $freeMb
    }
}

$disk = Invoke-Section 'disk' {
    $filter = "DeviceID='{0}'" -f $env:SystemDrive
    $volume = Get-CimInstance -ClassName Win32_LogicalDisk -Filter $filter
    [ordered]@{
        drive   = [string]$env:SystemDrive
        sizeGb  = [math]::Round($volume.Size / 1GB, 2)
        usedGb  = [math]::Round(($volume.Size - $volume.FreeSpace) / 1GB, 2)
    }
}

$services = Invoke-Section 'services' {
    @(Get-CimInstance -ClassName Win32_Service | Sort-Object Name | ForEach-Object {
        [ordered]@{
            name      = Hide-Sid ([string]$_.Name)
            state     = [string]$_.State
            startMode = [string]$_.StartMode
        }
    })
}

$appx = Invoke-Section 'appx' {
    $packages = if ($isAdmin) { Get-AppxPackage -AllUsers } else { Get-AppxPackage }
    @($packages | Sort-Object Name, Version -Unique | ForEach-Object {
        [ordered]@{
            name         = [string]$_.Name
            familyName   = [string]$_.PackageFamilyName
            version      = [string]$_.Version
            isFramework  = [bool]$_.IsFramework
            nonRemovable = [bool]$_.NonRemovable
            signature    = [string]$_.SignatureKind
        }
    })
}

$provisioned = Invoke-Section 'provisioned' {
    if (-not $isAdmin) { throw 'requires Administrator' }
    @(Get-AppxProvisionedPackage -Online | Sort-Object DisplayName | ForEach-Object {
        [ordered]@{
            name    = [string]$_.DisplayName
            version = [string]$_.Version
        }
    })
}

$tasks = Invoke-Section 'scheduledTasks' {
    @(Get-ScheduledTask | Sort-Object TaskPath, TaskName | ForEach-Object {
        [ordered]@{
            path  = Hide-Sid (([string]$_.TaskPath) + ([string]$_.TaskName))
            state = [string]$_.State
        }
    })
}

$restorePoints = Invoke-Section 'restorePoints' {
    if (-not $isAdmin) { throw 'requires Administrator' }
    @(Get-ComputerRestorePoint | ForEach-Object { [string]$_.Description })
}

$defender = Invoke-Section 'defender' {
    $status = Get-MpComputerStatus
    [ordered]@{
        antivirusEnabled          = [bool]$status.AntivirusEnabled
        realTimeProtectionEnabled = [bool]$status.RealTimeProtectionEnabled
        tamperProtected           = [bool]$status.IsTamperProtected
    }
}

$tgos = Invoke-Section 'tgos' {
    $infoFile = Join-Path $env:ProgramData 'TGOS\install-info.txt'
    if (Test-Path -LiteralPath $infoFile) {
        @(Get-Content -LiteralPath $infoFile)
    }
    else {
        @()
    }
}

$snapshot = [ordered]@{
    schema         = 1
    label          = $Label
    collectedAt    = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    isAdmin        = $isAdmin
    os             = $os
    counts         = $counts
    memory         = $memory
    disk           = $disk
    defender       = $defender
    tgosInstallInfo = $tgos
    restorePoints  = $restorePoints
    services       = $services
    appx           = $appx
    provisioned    = $provisioned
    scheduledTasks = $tasks
    errors         = $script:errors
}

if (-not $OutputDirectory) {
    $OutputDirectory = [Environment]::GetFolderPath('Desktop')
}
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$outFile = Join-Path $OutputDirectory ('TGOS-snapshot-{0}.json' -f $Label)
$json = $snapshot | ConvertTo-Json -Depth 6
# UTF-8 tanpa BOM, sama di Windows PowerShell 5.1 dan PowerShell 7.
[System.IO.File]::WriteAllText($outFile, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ('Snapshot written to {0}' -f $outFile)
if ($counts) {
    Write-Host ('  processes: {0}   threads: {1}' -f $counts.processes, $counts.threads)
}
if ($memory) {
    Write-Host ('  memory in use: {0} MB of {1} MB' -f $memory.inUseMb, $memory.totalMb)
}
if ($script:errors.Count -gt 0) {
    Write-Warning ('{0} section(s) could not be collected:' -f $script:errors.Count)
    $script:errors | ForEach-Object { Write-Warning ('  ' + $_) }
}
