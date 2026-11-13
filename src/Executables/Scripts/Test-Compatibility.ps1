<#
.SYNOPSIS
    Menghentikan playbook TGOS bila sistem bukan target yang didukung.

.DESCRIPTION
    Dijalankan sebagai aksi pertama playbook. Keluar dengan kode 0 hanya bila:
      - edisi Windows adalah Pro (EditionID = Professional),
      - build Windows 22621 (Windows 11 22H2) atau lebih baru,
      - arsitektur x64.
    Kode keluar selain 0 membuat AME Wizard menghentikan playbook
    (handleExitCodes: { "!0": halt }) sebelum ada perubahan pada sistem.

    Parameter hanya dipakai untuk pengujian. Tanpa parameter, nilai dibaca dari sistem.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.

.OUTPUTS
    Kode keluar:
       0  kompatibel
       1  galat tak terduga saat memeriksa
      10  edisi tidak didukung
      11  build tidak didukung
      12  arsitektur tidak didukung
#>
[CmdletBinding()]
param(
    [string]$EditionId,
    [int]$Build,
    [string]$Architecture
)

$ErrorActionPreference = 'Stop'

$MinimumBuild    = 22621
$AllowedEditions = @('Professional')

try {
    if (-not $EditionId -or -not $Build) {
        # Selalu baca tampilan registry 64-bit, juga bila proses ini 32-bit.
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64)
        try {
            $key = $baseKey.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion')
            if ($null -eq $key) {
                throw 'Registry key CurrentVersion was not found.'
            }
            try {
                if (-not $EditionId) { $EditionId = [string]$key.GetValue('EditionID') }
                if (-not $Build)     { $Build     = [int]$key.GetValue('CurrentBuildNumber') }
            }
            finally {
                $key.Dispose()
            }
        }
        finally {
            $baseKey.Dispose()
        }
    }

    if (-not $Architecture) {
        # PROCESSOR_ARCHITEW6432 terisi bila proses 32-bit berjalan di OS 64-bit.
        if ($env:PROCESSOR_ARCHITEW6432) {
            $Architecture = $env:PROCESSOR_ARCHITEW6432
        }
        else {
            $Architecture = $env:PROCESSOR_ARCHITECTURE
        }
    }

    Write-Output ("TGOS preflight: edition={0} build={1} architecture={2}" -f $EditionId, $Build, $Architecture)

    if ($AllowedEditions -notcontains $EditionId) {
        Write-Output ("REJECTED: TGOS only supports Windows 11 Pro. Detected edition: '{0}'." -f $EditionId)
        exit 10
    }

    if ($Build -lt $MinimumBuild) {
        Write-Output ("REJECTED: TGOS requires Windows 11 22H2 (build {0}) or newer. Detected build: {1}." -f $MinimumBuild, $Build)
        exit 11
    }

    if ($Architecture -ne 'AMD64') {
        Write-Output ("REJECTED: TGOS only supports x64. Detected architecture: '{0}'." -f $Architecture)
        exit 12
    }

    Write-Output 'PASSED: this system is compatible with TGOS.'
    exit 0
}
catch {
    Write-Output ("ERROR: compatibility check failed: {0}" -f $_.Exception.Message)
    exit 1
}
