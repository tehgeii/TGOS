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

    Harus dijalankan sebagai Administrator. Sebagian besar perubahan baru berlaku
    setelah restart.

    Kode keluar: 0 berhasil, 1 gagal, 2 butuh tindakan pengguna (Tamper Protection),
    3 fitur tidak didukung di PC ini (tidak ada yang diubah).

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Defender', 'Vbs', 'Mitigations', 'AutoUpdate', 'Indexing', 'Hibernation')]
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
