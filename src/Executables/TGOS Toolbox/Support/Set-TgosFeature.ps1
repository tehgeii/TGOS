<#
.SYNOPSIS
    Menyalakan atau mematikan satu fitur Windows yang diatur TGOS.

.DESCRIPTION
    Dipanggil oleh file .cmd di TGOS Toolbox. "On" berarti fitur Windows itu aktif
    (keadaan bawaan Windows); "Off" berarti dimatikan demi performa.

      Defender     pemindaian Windows Defender (real-time, perilaku, saat akses)
      Vbs          Virtualization-Based Security dan Memory Integrity
      Mitigations  mitigasi CPU Spectre/Meltdown
      AutoUpdate   unduh dan pasang update otomatis
      Indexing     layanan Windows Search
      Hibernation  hibernasi dan Fast Startup
      CoreParking  core parking CPU pada skema daya aktif
      ExtraServices layanan printer, diagnostik, dan penemuan jaringan (opsi
                   "Trim extra services")
      Telemetry    program pengumpul data Windows (CompatTelRunner, DeviceCensus) dan
                   perekam telemetri otomatis. Nyalakan sebelum upgrade fitur Windows.
      UpdatePause  "Off" = Windows Update di-pause lewat fitur pause bawaan Settings
                   (batas pause 3650 hari, ditahan 10 tahun); "On" = dilanjutkan.
                   Sama dengan tombol "Resume updates" di Settings > Windows Update.
      DriverUpdates  driver dari Windows Update ("Off" = tidak ikut update).
      BackgroundApps aplikasi Store berjalan di latar belakang.
      LockScreen   layar kunci bergambar sebelum kotak login ("Off" = dilewati;
                   password/PIN tetap diminta).
      GameBar      Xbox Game Bar: tombol controller, View + Menu, policy perekaman, dan
                   penangan pengganti protokol ms-gamebar dari TGOS. "On" mencabut
                   semuanya; aplikasi Game Bar sendiri dipasang lagi dari Microsoft Store.
      LoginTheme   gambar layar kunci/login TGO ("On" = gambar TGO, "Off" = bawaan
                   Windows). Satu-satunya fitur yang "On"-nya berarti pengaturan TGOS.
      ReservedStorage ruang disk yang dicadangkan Windows untuk update (DISM).

    Harus dijalankan sebagai Administrator. Sebagian besar perubahan baru berlaku
    setelah restart.

    Kode keluar: 0 berhasil, 1 gagal, 2 butuh tindakan pengguna (Tamper Protection),
    3 fitur tidak didukung di PC ini (tidak ada yang diubah).

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Defender', 'Vbs', 'Mitigations', 'AutoUpdate', 'Indexing', 'Hibernation',
        'CoreParking', 'ExtraServices', 'Telemetry', 'UpdatePause', 'DriverUpdates',
        'BackgroundApps', 'LockScreen', 'GameBar', 'LoginTheme', 'ReservedStorage')]
    [string]$Feature,

    [Parameter(Mandatory = $true)]
    [ValidateSet('On', 'Off')]
    [string]$State
)

$ErrorActionPreference = 'Stop'

function Set-Dword {
    param([string]$Path, [string]$Name, [int]$Value)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Type DWord
}

function Set-Text {
    param([string]$Path, [string]$Name, [string]$Value, [string]$Type = 'String')
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Type $Type
}

function Remove-Value {
    param([string]$Path, [string]$Name)
    if (Test-Path -LiteralPath $Path) {
        Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    }
}

function Write-Log {
    param([string]$Message)
    try {
        $directory = Join-Path $env:ProgramData 'TGOS'
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath (Join-Path $directory 'toolbox.log') -Value $line -Encoding ASCII
    }
    catch {
        # Log hanya catatan; kegagalannya tidak boleh menggagalkan perubahan.
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'This script must run as Administrator.'
    exit 1
}

$restart = $true

try {
    switch ($Feature) {
        'Defender' {
            $policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'
            $names = @('DisableRealtimeMonitoring', 'DisableBehaviorMonitoring',
                'DisableOnAccessProtection', 'DisableScanOnRealtimeEnable', 'DisableIOAVProtection')

            if ($State -eq 'Off') {
                $tamper = $false
                try { $tamper = [bool](Get-MpComputerStatus).IsTamperProtected } catch { $tamper = $false }
                if ($tamper) {
                    Write-Host ''
                    Write-Host 'Tamper Protection is ON, so Windows will ignore this change.'
                    Write-Host ''
                    Write-Host 'Do this first, then run this file again:'
                    Write-Host '  1. Open Windows Security > Virus & threat protection.'
                    Write-Host '  2. Click "Manage settings" under Virus & threat protection settings.'
                    Write-Host '  3. Turn OFF "Tamper Protection".'
                    Write-Host ''
                    Write-Host 'Matikan dulu Tamper Protection di Windows Security, lalu jalankan lagi.'
                    try { Start-Process 'windowsdefender://threatsettings' } catch { }
                    Write-Log 'Defender Off: blocked by Tamper Protection'
                    exit 2
                }
                foreach ($name in $names) { Set-Dword -Path $policy -Name $name -Value 1 }
                try { Set-MpPreference -DisableRealtimeMonitoring $true } catch { }
                Write-Host 'Windows Defender scanning is now OFF.'
                Write-Host 'WARNING: this PC has no antivirus protection. Be careful with cracks, cheats and mods.'
            }
            else {
                foreach ($name in $names) { Remove-Value -Path $policy -Name $name }
                try { Set-MpPreference -DisableRealtimeMonitoring $false } catch { }
                Write-Host 'Windows Defender scanning is now ON.'
            }
        }
        'Vbs' {
            $deviceGuard = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
            $hvci = Join-Path $deviceGuard 'Scenarios\HypervisorEnforcedCodeIntegrity'
            if ($State -eq 'Off') { $value = 0 } else { $value = 1 }
            Set-Dword -Path $deviceGuard -Name 'EnableVirtualizationBasedSecurity' -Value $value
            Set-Dword -Path $hvci -Name 'Enabled' -Value $value
            Write-Host ('Virtualization-Based Security and Memory Integrity: {0}.' -f $State.ToUpper())
        }
        'Mitigations' {
            $memory = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
            if ($State -eq 'Off') {
                Set-Dword -Path $memory -Name 'FeatureSettingsOverride' -Value 3
                Set-Dword -Path $memory -Name 'FeatureSettingsOverrideMask' -Value 3
                Write-Host 'CPU mitigations (Spectre/Meltdown) are now OFF.'
            }
            else {
                Remove-Value -Path $memory -Name 'FeatureSettingsOverride'
                Remove-Value -Path $memory -Name 'FeatureSettingsOverrideMask'
                Write-Host 'CPU mitigations are back to the Windows default (ON).'
            }
        }
        'AutoUpdate' {
            $policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
            if ($State -eq 'Off') {
                Set-Dword -Path $policy -Name 'NoAutoUpdate' -Value 1
                Write-Host 'Automatic Windows updates are now OFF. You can still update manually in Settings.'
            }
            else {
                Remove-Value -Path $policy -Name 'NoAutoUpdate'
                Write-Host 'Automatic Windows updates are now ON.'
            }
        }
        'Indexing' {
            $service = 'HKLM:\SYSTEM\CurrentControlSet\Services\WSearch'
            if ($State -eq 'Off') {
                Set-Dword -Path $service -Name 'Start' -Value 4
                Stop-Service -Name 'WSearch' -Force -ErrorAction SilentlyContinue
                Write-Host 'Windows Search indexing is now OFF.'
            }
            else {
                Set-Dword -Path $service -Name 'Start' -Value 2
                Set-Dword -Path $service -Name 'DelayedAutostart' -Value 1
                Start-Service -Name 'WSearch' -ErrorAction SilentlyContinue
                Write-Host 'Windows Search indexing is now ON.'
            }
            $restart = $false
        }
        'Hibernation' {
            $power = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
            if ($State -eq 'Off') { $switch = 'off' } else { $switch = 'on' }
            # Lewat cmd supaya pesan error powercfg tertangkap sebagai teks biasa.
            $output = (& cmd.exe /c ('powercfg.exe /hibernate {0} 2>&1' -f $switch) | Out-String).Trim()
            if ($LASTEXITCODE -ne 0) {
                # Umum di mesin virtual dan sebagian desktop: firmware tidak mendukung hibernasi.
                Write-Host ('Hibernation cannot be turned {0} on this PC: {1}' -f $switch, ($output -replace '\s+', ' '))
                Write-Host 'Hibernasi tidak didukung di PC ini; tidak ada yang diubah.'
                Write-Log ('Hibernation {0}: not supported: {1}' -f $State, ($output -replace '\s+', ' '))
                exit 3
            }
            if ($State -eq 'Off') {
                Set-Dword -Path $power -Name 'HiberbootEnabled' -Value 0
                Write-Host 'Hibernation and Fast Startup are now OFF.'
            }
            else {
                Set-Dword -Path $power -Name 'HiberbootEnabled' -Value 1
                Write-Host 'Hibernation and Fast Startup are now ON.'
            }
        }
        'CoreParking' {
            # "Processor performance core parking min cores", kelas core 0 dan 1.
            $subgroup = '54533251-82be-4824-96c1-47b60b740d00'
            $settings = @('0cc5b647-c1df-4637-891a-dec35c318583', '0cc5b647-c1df-4637-891a-dec35c318584')
            $record = Join-Path (Join-Path $env:ProgramData 'TGOS') 'core-parking-previous.txt'

            $active = (& cmd.exe /c 'powercfg.exe /getactivescheme 2>&1' | Out-String)
            if ($active -notmatch '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}') {
                throw 'could not read the active power scheme'
            }
            $scheme = $Matches[0].ToLower()

            # Pengaturan core parking disembunyikan Windows; powercfg /query baru
            # menampilkan nilainya setelah dibuat terlihat.
            foreach ($setting in $settings) {
                & cmd.exe /c ('powercfg.exe /attributes {0} {1} -ATTRIB_HIDE 2>&1' -f $subgroup, $setting) | Out-Null
            }

            if ($State -eq 'Off') {
                $lines = @()
                $applied = 0
                foreach ($setting in $settings) {
                    $query = (& cmd.exe /c ('powercfg.exe /query {0} {1} {2} 2>&1' -f $scheme, $subgroup, $setting) | Out-String)
                    if ($LASTEXITCODE -ne 0) { continue }
                    $values = @([regex]::Matches($query, '0x[0-9a-fA-F]{8}') | ForEach-Object { [Convert]::ToInt32($_.Value, 16) })
                    if ($values.Count -ge 2) {
                        $lines += ('{0};{1};{2};{3}' -f $scheme, $setting, $values[$values.Count - 2], $values[$values.Count - 1])
                    }
                    & cmd.exe /c ('powercfg.exe /setacvalueindex {0} {1} {2} 100 2>&1' -f $scheme, $subgroup, $setting) | Out-Null
                    & cmd.exe /c ('powercfg.exe /setdcvalueindex {0} {1} {2} 100 2>&1' -f $scheme, $subgroup, $setting) | Out-Null
                    $applied++
                }
                if ($applied -eq 0) {
                    Write-Host 'The core parking setting is not available on this PC. Nothing was changed.'
                    Write-Log 'CoreParking Off: not supported'
                    exit 3
                }
                if ($lines.Count -gt 0 -and -not (Test-Path -LiteralPath $record)) {
                    Set-Content -LiteralPath $record -Value $lines -Encoding ASCII
                }
                & cmd.exe /c ('powercfg.exe /setactive {0} 2>&1' -f $scheme) | Out-Null
                Write-Host 'CPU core parking is now OFF (all cores stay active).'
            }
            else {
                if (-not (Test-Path -LiteralPath $record)) {
                    Write-Host 'No earlier core parking values were recorded, so there is nothing to restore.'
                    Write-Host 'Tidak ada nilai sebelumnya yang tercatat; tidak ada yang diubah.'
                    Write-Log 'CoreParking On: nothing recorded'
                    exit 3
                }
                foreach ($line in (Get-Content -LiteralPath $record)) {
                    $parts = $line -split ';'
                    if ($parts.Count -ne 4) { continue }
                    & cmd.exe /c ('powercfg.exe /setacvalueindex {0} {1} {2} {3} 2>&1' -f $parts[0], $subgroup, $parts[1], $parts[2]) | Out-Null
                    & cmd.exe /c ('powercfg.exe /setdcvalueindex {0} {1} {2} {3} 2>&1' -f $parts[0], $subgroup, $parts[1], $parts[3]) | Out-Null
                }
                & cmd.exe /c ('powercfg.exe /setactive {0} 2>&1' -f $scheme) | Out-Null
                Remove-Item -LiteralPath $record -Force -ErrorAction SilentlyContinue
                Write-Host 'CPU core parking is back to its earlier values.'
            }
            $restart = $false
        }
        'ExtraServices' {
            # Daftar layanan diambil dari expected-state.json (opsi "trim-services"),
            # supaya selalu sama dengan yang dimatikan playbook.
            $statePath = Join-Path $PSScriptRoot 'expected-state.json'
            # Jangan beri nama $state: PowerShell tidak membedakan huruf besar-kecil, jadi
            # nama itu sama dengan parameter $State.
            $expected = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            $names = @($expected.checks | Where-Object { $_.type -eq 'service' -and $_.option -eq 'trim-services' } |
                    ForEach-Object { [string]$_.name })
            if ($names.Count -eq 0) { throw 'no extra services listed in expected-state.json' }

            # Nilai Start sebelum TGOS, dicatat playbook. Cadangannya nilai bawaan Windows 11.
            $before = @{}
            $record = Join-Path (Join-Path $env:ProgramData 'TGOS') 'services-before.txt'
            if (Test-Path -LiteralPath $record) {
                foreach ($line in (Get-Content -LiteralPath $record)) {
                    if ($line -match '^(?<name>[^=]+)=(?<start>\d+)$') { $before[$Matches['name']] = [int]$Matches['start'] }
                }
            }
            $defaults = @{ Spooler = 2; DPS = 2; PcaSvc = 2 }

            # Lewat sc.exe (Service Control Manager), bukan menulis registry langsung:
            # sebagian kunci layanan hanya bisa ditulis sistem, dan Administrator ditolak
            # ("Requested registry access is not allowed"). Tiap layanan ditangani sendiri,
            # jadi satu kegagalan tidak menghentikan yang lain, dan yang gagal disebut.
            $modes = @{ 2 = 'auto'; 3 = 'demand'; 4 = 'disabled' }
            $changed = 0
            $failed = @()
            foreach ($name in $names) {
                $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\{0}' -f $name
                if (-not (Test-Path -LiteralPath $key)) { continue }
                if ($State -eq 'Off') { $value = 4 }
                elseif ($before.ContainsKey($name) -and $before[$name] -ne 4) { $value = $before[$name] }
                elseif ($defaults.ContainsKey($name)) { $value = $defaults[$name] }
                else { $value = 3 }
                if (-not $modes.ContainsKey($value)) { $value = 3 }

                $output = (& cmd.exe /c ('sc.exe config "{0}" start= {1} 2>&1' -f $name, $modes[$value]) | Out-String)
                if ($LASTEXITCODE -ne 0) {
                    try { Set-Dword -Path $key -Name 'Start' -Value $value }
                    catch { }
                }
                $now = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).Start
                if ($now -eq $value) {
                    $changed++
                }
                else {
                    $failed += $name
                    Write-Log ('ExtraServices {0}: {1} not changed: {2}' -f $State, $name, ($output -replace '\s+', ' ').Trim())
                }
            }
            if ($State -eq 'Off') {
                Write-Host ('{0} extra services (printing, diagnostics, network discovery) are now OFF.' -f $changed)
            }
            else {
                Write-Host ('{0} extra services (printing, diagnostics, network discovery) are back ON.' -f $changed)
            }
            if ($failed.Count -gt 0) {
                Write-Host ('FAILED: these services could not be changed: {0}' -f ($failed -join ', '))
                Write-Host 'Layanan di atas tidak bisa diubah; detailnya ada di C:\ProgramData\TGOS\toolbox.log.'
                Write-Log ('ExtraServices {0}: failed for {1}' -f $State, ($failed -join ', '))
                exit 1
            }
        }
        'Telemetry' {
            $ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
            $collectors = @('CompatTelRunner.exe', 'DeviceCensus.exe')
            $loggers = @(
                'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener',
                'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\SQMLogger')
            if ($State -eq 'Off') {
                foreach ($collector in $collectors) {
                    $key = Join-Path $ifeo $collector
                    if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
                    Set-ItemProperty -LiteralPath $key -Name 'Debugger' -Value '%windir%\System32\taskkill.exe' -Type String
                }
                foreach ($logger in $loggers) { Set-Dword -Path $logger -Name 'Start' -Value 0 }
                Write-Host 'Windows telemetry collectors are now OFF (blocked).'
            }
            else {
                foreach ($collector in $collectors) { Remove-Value -Path (Join-Path $ifeo $collector) -Name 'Debugger' }
                foreach ($logger in $loggers) {
                    if (Test-Path -LiteralPath $logger) { Set-Dword -Path $logger -Name 'Start' -Value 1 }
                }
                Write-Host 'Windows telemetry collectors are now ON (allowed to run).'
                Write-Host 'This is needed for Windows feature upgrades. Turn them OFF again afterwards.'
            }
        }
        'UpdatePause' {
            # Nilai yang ditulis halaman Settings > Windows Update saat tombol pause
            # diklik. FlightSettingsMaxPauseDays menaikkan batas pause (bawaan 35 hari).
            $ux = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
            $startNames = @('PauseFeatureUpdatesStartTime', 'PauseQualityUpdatesStartTime', 'PauseUpdatesStartTime')
            $endNames = @('PauseFeatureUpdatesEndTime', 'PauseQualityUpdatesEndTime', 'PauseUpdatesExpiryTime')
            if ($State -eq 'Off') {
                $days = 3650
                $now = [DateTime]::UtcNow
                $until = $now.AddDays($days)
                $format = "yyyy-MM-dd'T'HH:mm:ss'Z'"
                $culture = [Globalization.CultureInfo]::InvariantCulture
                Set-Dword -Path $ux -Name 'FlightSettingsMaxPauseDays' -Value $days
                foreach ($name in $startNames) { Set-Text -Path $ux -Name $name -Value $now.ToString($format, $culture) }
                foreach ($name in $endNames) { Set-Text -Path $ux -Name $name -Value $until.ToString($format, $culture) }
                Write-Host ('Windows updates are now PAUSED until {0}.' -f $until.ToString('yyyy-MM-dd', $culture))
                Write-Host 'To get updates again, click "Resume updates" in Settings > Windows Update,'
                Write-Host 'or run "Windows Updates - Resume" in the TGOS Toolbox.'
                Write-Host 'Update Windows di-pause. Untuk update lagi, klik "Resume updates" di Settings.'
            }
            else {
                foreach ($name in ($startNames + $endNames + @('FlightSettingsMaxPauseDays'))) {
                    Remove-Value -Path $ux -Name $name
                }
                Write-Host 'Windows updates are no longer paused.'
                $manual = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction SilentlyContinue).NoAutoUpdate
                if ($manual -eq 1) {
                    Write-Host 'Updates stay manual: Windows installs them when you click "Check for updates".'
                    Write-Host 'For automatic updates, also run "Automatic Updates - Turn ON".'
                }
            }
            $restart = $false
        }
        'DriverUpdates' {
            $policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
            if ($State -eq 'Off') {
                Set-Dword -Path $policy -Name 'ExcludeWUDriversInQualityUpdate' -Value 1
                Write-Host 'Windows Update no longer installs drivers. Your own GPU driver stays.'
            }
            else {
                Remove-Value -Path $policy -Name 'ExcludeWUDriversInQualityUpdate'
                Write-Host 'Windows Update may install drivers again.'
            }
            $restart = $false
        }
        'BackgroundApps' {
            $policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
            if ($State -eq 'Off') {
                Set-Dword -Path $policy -Name 'LetAppsRunInBackground' -Value 2
                Write-Host 'Microsoft Store apps can no longer run in the background.'
            }
            else {
                Remove-Value -Path $policy -Name 'LetAppsRunInBackground'
                Write-Host 'Microsoft Store apps may run in the background again.'
            }
        }
        'LockScreen' {
            $policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
            if ($State -eq 'Off') {
                Set-Dword -Path $policy -Name 'NoLockScreen' -Value 1
                Write-Host 'The lock screen is now skipped. Your password or PIN is still required.'
            }
            else {
                Remove-Value -Path $policy -Name 'NoLockScreen'
                Write-Host 'The lock screen is back.'
            }
            $restart = $false
        }
        'GameBar' {
            $gameBar = 'HKCU:\SOFTWARE\Microsoft\GameBar'
            $policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'
            $protocols = @('ms-gamebar', 'ms-gamebarservices', 'ms-gamingoverlay')
            $handler = '"%SystemRoot%\System32\systray.exe"'
            # Tempat penangan protokol: HKLM (semua pengguna) dan kelas tiap profil yang
            # sedang dimuat (di Windows 11 kunci per pengguna menimpa HKLM).
            $classRoots = @('HKLM:\SOFTWARE\Classes')
            $userRoots = @(Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
                    Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' } |
                    ForEach-Object { 'Registry::HKEY_USERS\{0}' -f $_.PSChildName })
            foreach ($userRoot in $userRoots) { $classRoots += ('{0}\Software\Classes' -f $userRoot) }
            if ($State -eq 'Off') {
                Set-Dword -Path $gameBar -Name 'UseNexusForGameBarEnabled' -Value 0
                Set-Dword -Path $gameBar -Name 'GamepadNexusChordEnabled' -Value 0
                Set-Dword -Path $policy -Name 'AllowGameDVR' -Value 0
                foreach ($protocol in $protocols) {
                    foreach ($classRoot in $classRoots) {
                        $key = '{0}\{1}' -f $classRoot, $protocol
                        Set-Text -Path $key -Name '(default)' -Value ('URL:{0}' -f $protocol)
                        Set-Text -Path $key -Name 'URL Protocol' -Value ''
                        Set-Text -Path $key -Name 'NoOpenWith' -Value ''
                        Set-Text -Path (Join-Path $key 'shell\open\command') -Name '(default)' -Value $handler -Type 'ExpandString'
                    }
                    # Pilihan aplikasi yang masih menunjuk ke Game Bar yang sudah dihapus
                    # membuat Windows bertanya "Pick an app"; dicabut supaya penangan di
                    # atas yang dipakai.
                    foreach ($userRoot in $userRoots) {
                        $choice = '{0}\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\{1}' -f $userRoot, $protocol
                        if (Test-Path -LiteralPath $choice) {
                            Remove-Item -LiteralPath $choice -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
                Write-Host 'Xbox Game Bar is now OFF: the controller buttons and Win+G no longer open it.'
            }
            else {
                Remove-Value -Path $gameBar -Name 'UseNexusForGameBarEnabled'
                Remove-Value -Path $gameBar -Name 'GamepadNexusChordEnabled'
                Remove-Value -Path $policy -Name 'AllowGameDVR'
                foreach ($protocol in $protocols) {
                    foreach ($classRoot in $classRoots) {
                        # Hanya penangan pengganti buatan TGOS yang dicabut.
                        $key = '{0}\{1}' -f $classRoot, $protocol
                        $command = Join-Path $key 'shell\open\command'
                        $current = ''
                        if (Test-Path -LiteralPath $command) {
                            $current = [string](Get-Item -LiteralPath $command).GetValue('', '', 'DoNotExpandEnvironmentNames')
                        }
                        if ($current -match '(?i)systray\.exe') {
                            Remove-Item -LiteralPath $key -Recurse -Force
                        }
                    }
                }
                Write-Host 'The TGOS Game Bar blocks are removed.'
                Write-Host 'If the Xbox Game Bar app was removed, install it again from the Microsoft Store.'
            }
        }
        'ReservedStorage' {
            if ($State -eq 'Off') { $value = 'Disabled' } else { $value = 'Enabled' }
            $dism = Join-Path $env:SystemRoot 'System32\dism.exe'
            $output = (& cmd.exe /c ('"{0}" /Online /Set-ReservedStorageState /State:{1} 2>&1' -f $dism, $value) | Out-String)
            $code = $LASTEXITCODE
            if ($output -match '(?i)not supported|0x80070032') {
                Write-Host 'Reserved storage is not supported on this PC. Nothing was changed.'
                Write-Log ('ReservedStorage {0}: not supported' -f $State)
                exit 3
            }
            if ($code -ne 0) {
                # Contoh: Windows sedang memakai cadangan itu untuk update yang belum selesai.
                throw ('DISM returned {0}: {1}' -f $code, (($output -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 2) -join ' '))
            }
            if ($State -eq 'Off') {
                Write-Host 'Reserved storage is now OFF: the space Windows kept for updates is free again.'
            }
            else {
                Write-Host 'Reserved storage is now ON: Windows keeps some space for updates again.'
            }
            $restart = $false
        }
        'LoginTheme' {
            $csp = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
            $image = Join-Path $env:SystemRoot 'Web\Wallpaper\TGOS\TGOS.png'
            if ($State -eq 'On') {
                if (-not (Test-Path -LiteralPath $image)) { throw ('the TGO image is missing: {0}' -f $image) }
                Set-Text -Path $csp -Name 'LockScreenImagePath' -Value $image
                Set-Text -Path $csp -Name 'LockScreenImageUrl' -Value $image
                Set-Dword -Path $csp -Name 'LockScreenImageStatus' -Value 1
                Write-Host 'The lock and sign-in screens now use the TGO image.'
            }
            else {
                foreach ($name in @('LockScreenImagePath', 'LockScreenImageUrl', 'LockScreenImageStatus')) {
                    Remove-Value -Path $csp -Name $name
                }
                Write-Host 'The lock and sign-in screens are back to the Windows picture.'
                Write-Host 'You can choose your own picture in Settings > Personalization > Lock screen.'
            }
            $restart = $false
        }
    }

    Write-Log ('{0} {1}: ok' -f $Feature, $State)
    if ($restart) {
        Write-Host 'Restart Windows for the change to take full effect.'
    }
    exit 0
}
catch {
    $reason = ($_.Exception.Message -replace '\s+', ' ').Trim()
    Write-Host ('FAILED: {0}' -f $reason)
    Write-Log ('{0} {1}: FAILED: {2}' -f $Feature, $State, $reason)
    exit 1
}
