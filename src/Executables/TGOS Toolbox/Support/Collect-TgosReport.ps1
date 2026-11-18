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

    Tidak mengubah pengaturan Windows. Tidak mengumpulkan alamat jaringan atau file
    pribadi. Sebelum di-zip, semua file teks laporan disamarkan (ConvertTo-PrivateText): log
    AME memuat jalur profil pengguna, jadi nama folder pengguna diganti <user>, nama
    komputer diganti <computer>, dan bagian mesin dari SID akun diganti <machine>.

    Harus dijalankan sebagai Administrator.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [string]$Label = 'after'
)

$ErrorActionPreference = 'Stop'

function ConvertTo-PrivateText {
    <#
    .SYNOPSIS
        Menyamarkan nama folder pengguna, nama komputer, dan bagian mesin dari SID akun.

    .DESCRIPTION
        X:\Users\<nama> (juga X:\\Users\\<nama> di JSON) menjadi X:\Users\<user>; folder
        bersama Windows (Public, Default, Default User, All Users) tidak diubah.
        S-1-5-21-a-b-c-1001 menjadi S-1-5-21-<machine>-1001 (nomor akun tetap, supaya akun
        yang berbeda masih bisa dibedakan). Nama komputer (3 huruf atau lebih, sebagai kata
        utuh) menjadi <computer>. Diuji di tools/selftest.py.
    #>
    param([string]$Text, [string]$ComputerName)
    if (-not $Text) { return $Text }
    $users = '(?i)\b([A-Z]:(\\{1,2})Users\2)(?!(?:Public|Default|All Users)(?=\\|"|\s|$))[^\\"\r\n]+?(?=\\|"|\r|\n|$)'
    $result = [regex]::Replace($Text, $users, '$1<user>')
    $result = [regex]::Replace($result, 'S-1-5-21-\d+-\d+-\d+(?=-\d)', 'S-1-5-21-<machine>')
    if ($ComputerName -and $ComputerName.Length -ge 3) {
        $result = [regex]::Replace($result, ('(?i)\b{0}\b' -f [regex]::Escape($ComputerName)), '<computer>')
    }
    return $result
}

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
        # Nama pengguna dan nama komputer disamarkan bersama file lain sebelum di-zip.
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

    # Semua file teks laporan disamarkan; encoding dan BOM tiap file dipertahankan.
    foreach ($file in @(Get-ChildItem -LiteralPath $work -Recurse -File | Where-Object { $_.Extension -in '.txt', '.log', '.yml', '.conf', '.json', '.xml' })) {
        try {
            $bytes = [IO.File]::ReadAllBytes($file.FullName)
            $encoding = New-Object System.Text.UTF8Encoding($false)
            if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $encoding = New-Object System.Text.UTF8Encoding($true) }
            elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $encoding = [System.Text.Encoding]::Unicode }
            $text = [IO.File]::ReadAllText($file.FullName, $encoding)
            $private = ConvertTo-PrivateText -Text $text -ComputerName $env:COMPUTERNAME
            if ($private -cne $text) { [IO.File]::WriteAllText($file.FullName, $private, $encoding) }
        }
        catch {
            # File yang tidak bisa disamarkan tidak ikut dikirim.
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            $notes += ('private: {0} left out: {1}' -f $file.Name, $_.Exception.Message)
        }
    }

    if ($notes.Count -gt 0) {
        $notes = @($notes | ForEach-Object { ConvertTo-PrivateText -Text ('' + $_) -ComputerName $env:COMPUTERNAME })
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
