<#
.SYNOPSIS
    Mengumpulkan semua yang dibutuhkan untuk memeriksa hasil instalasi TGOS ke satu file zip.

.DESCRIPTION
    Membuat TGOS-report.zip di Desktop, berisi:
      - verify-report.txt     hasil pemeriksaan tiap tweak (PASS / FAIL / SKIP / WARN)
      - TGOS-snapshot-after.json  potret sistem (proses, RAM, layanan, aplikasi, tugas)
      - isi %ProgramData%\TGOS (install-info.txt, restore-point.txt, dan lainnya)
      - servicing.txt         keadaan servicing Windows: Reserved Storage, .NET 3.5,
                              layanan Windows Update, tanda restart tertunda, langkah
                              yang menunggu restart, entri RunOnce, akhir dism.log
      - log AME bila ditemukan

    Tidak mengubah pengaturan Windows. Tidak mengumpulkan nama komputer, nama pengguna,
    alamat jaringan, atau file pribadi (nama folder pengguna di servicing.txt diganti
    <user>, nama komputer diganti <computer>).

    Harus dijalankan sebagai Administrator.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [string]$Label = 'after'
)

$ErrorActionPreference = 'Stop'

if (-not $OutputDirectory) {
    $OutputDirectory = [Environment]::GetFolderPath('Desktop')
}

$work = Join-Path $env:TEMP ('tgos-report-{0}' -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$notes = @()

try {
    Write-Host 'Checking every TGOS change...'
    try {
        & (Join-Path $PSScriptRoot 'Test-TgosResult.ps1') -ReportPath (Join-Path $work 'verify-report.txt') | Out-Null
    }
    catch {
        $notes += ('verify: {0}' -f $_.Exception.Message)
    }

    Write-Host 'Taking a system snapshot...'
    try {
        & (Join-Path $PSScriptRoot 'Get-SystemSnapshot.ps1') -Label $Label -OutputDirectory $work | Out-Null
    }
    catch {
        $notes += ('snapshot: {0}' -f $_.Exception.Message)
    }

    Write-Host 'Reading the Windows servicing state...'
    try {
        $lines = @()
        $dism = Join-Path $env:SystemRoot 'System32\dism.exe'
        $lines += '[reserved storage]'
        $lines += @(& cmd.exe /c ('"{0}" /Online /Get-ReservedStorageState 2>&1' -f $dism) | Where-Object { $_.Trim() } | Select-Object -Last 3)
        $lines += '', '[.NET Framework 3.5]'
        $lines += ('NDP\v3.5 Install = {0}' -f (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5' -ErrorAction SilentlyContinue).Install)
        $lines += '', '[services]'
        foreach ($serviceName in @('wuauserv', 'UsoSvc', 'BITS', 'DoSvc', 'TrustedInstaller')) {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service) { $lines += ('{0}: {1}, {2}' -f $serviceName, $service.Status, $service.StartType) }
        }
        $lines += '', '[restart pending]'
        $lines += ('CBS RebootPending: {0}' -f (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'))
        $lines += ('Windows Update RebootRequired: {0}' -f (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'))
        $lines += ('WinSxS pending.xml: {0}' -f (Test-Path -LiteralPath (Join-Path $env:SystemRoot 'WinSxS\pending.xml')))
        $renames = @((Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue).PendingFileRenameOperations | Where-Object { $_ })
        $lines += ('PendingFileRenameOperations: {0} path(s)' -f $renames.Count)
        $lines += '', '[after restart]'
        $afterRestart = Join-Path $env:ProgramData 'TGOS\after-restart.txt'
        if (Test-Path -LiteralPath $afterRestart) { $lines += @(Get-Content -LiteralPath $afterRestart) } else { $lines += 'no steps waiting' }
        $task = Get-ScheduledTask -TaskPath '\TGOS\' -TaskName 'Finish after restart' -ErrorAction SilentlyContinue
        if ($task) {
            $info = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
            $lines += ('task \TGOS\Finish after restart: {0}, last run {1}, last result 0x{2:X8}' -f $task.State, $info.LastRunTime, [int64]$info.LastTaskResult)
        }
        else { $lines += 'task \TGOS\Finish after restart: not registered' }
        $lines += '', '[RunOnce]'
        $keys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce')
        $keys += @(Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
                Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' } |
                ForEach-Object { 'Registry::HKEY_USERS\{0}\Software\Microsoft\Windows\CurrentVersion\RunOnce' -f $_.PSChildName })
        foreach ($key in $keys) {
            $item = Get-Item -LiteralPath $key -ErrorAction SilentlyContinue
            if (-not $item) { continue }
            foreach ($valueName in @($item.GetValueNames())) {
                $lines += ('{0} | {1} = {2}' -f ($key -replace '^Registry::HKEY_USERS\\S-1-5-21-[\d-]+', 'HKU\<user>'), $valueName, $item.GetValue($valueName, '', 'DoNotExpandEnvironmentNames'))
            }
        }
        $lines += '', '[dism.log, last 80 lines]'
        $dismLog = Join-Path $env:SystemRoot 'Logs\DISM\dism.log'
        if (Test-Path -LiteralPath $dismLog) { $lines += @(Get-Content -LiteralPath $dismLog -Tail 80 -ErrorAction SilentlyContinue) }
        # Tanpa nama pengguna dan nama komputer.
        $lines = @($lines | ForEach-Object { ('' + $_) -replace '(?i)([A-Z]:\\Users\\)[^\\"]+?(?=\\|"|\s*$)', '$1<user>' })
        if ($env:COMPUTERNAME -and $env:COMPUTERNAME.Length -ge 3) {
            $lines = @($lines | ForEach-Object { $_ -replace [regex]::Escape($env:COMPUTERNAME), '<computer>' })
        }
        Set-Content -LiteralPath (Join-Path $work 'servicing.txt') -Value $lines -Encoding ASCII
    }
    catch {
        $notes += ('servicing: {0}' -f $_.Exception.Message)
    }

    $data = Join-Path $env:ProgramData 'TGOS'
    if (Test-Path -LiteralPath $data) {
        $target = Join-Path $work 'ProgramData-TGOS'
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Get-ChildItem -LiteralPath $data -File | Where-Object { $_.Length -lt 5MB } |
            Copy-Item -Destination $target -Force
    }
    else {
        $notes += 'ProgramData\TGOS not found: the playbook may not have run'
    }

    # Lokasi log AME tidak terdokumentasi; ambil yang ada dari tempat yang umum.
    $budget = 20MB
    foreach ($root in @((Join-Path $env:ProgramData 'AME'), (Join-Path $env:LOCALAPPDATA 'AME'))) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $name = 'AME-' + ((Split-Path -Parent $root) | Split-Path -Leaf)
        $target = Join-Path $work $name
        Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in '.txt', '.log', '.yml', '.conf', '.json' -and $_.Length -lt 5MB } |
            ForEach-Object {
                if ($budget -gt $_.Length) {
                    $budget -= $_.Length
                    $relative = $_.FullName.Substring($root.Length).TrimStart('\')
                    $destination = Join-Path $target $relative
                    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
                    Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
                }
            }
    }

    if ($notes.Count -gt 0) {
        Set-Content -LiteralPath (Join-Path $work 'collect-notes.txt') -Value $notes -Encoding ASCII
    }

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }
    $zip = Join-Path $OutputDirectory 'TGOS-report.zip'
    if (Test-Path -LiteralPath $zip) {
        Remove-Item -LiteralPath $zip -Force
    }
    Compress-Archive -Path (Join-Path $work '*') -DestinationPath $zip

    Write-Host ''
    Write-Host ('Report saved to: {0}' -f $zip)
    Write-Host 'Send that one file. / Kirim satu file itu.'
    $report = Join-Path $work 'verify-report.txt'
    if (Test-Path -LiteralPath $report) {
        Write-Host ''
        Get-Content -LiteralPath $report -Tail 8 | ForEach-Object { Write-Host $_ }
    }
    exit 0
}
catch {
    Write-Host ('FAILED: {0}' -f (($_.Exception.Message -replace '\s+', ' ').Trim()))
    exit 1
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
