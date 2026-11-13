<#
.SYNOPSIS
    Mencatat informasi instalasi TGOS ke %ProgramData%\TGOS\install-info.txt.

.DESCRIPTION
    Dua cara pakai:

    1. Tanpa -AppendOption: menulis ulang install-info.txt (versi TGOS, waktu, edisi,
       build, hasil restore point, modul yang dijalankan).
    2. Dengan -AppendOption <nama>: menambah satu baris "Option selected" ke file yang
       sudah ada. Playbook memanggilnya sekali per opsi yang dipilih di Wizard.

    Parameter -ConfPath dan -DataDirectory hanya dipakai untuk pengujian.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$Modules,
    [string]$AppendOption,
    [string]$ConfPath,
    [string]$DataDirectory
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

try {
    $dataDir = Get-TgosDataDirectory -Path $DataDirectory
    $outFile = Join-Path $dataDir 'install-info.txt'

    if ($AppendOption) {
        if ($AppendOption -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
            throw ("invalid option name '{0}'" -f $AppendOption)
        }
        Add-Content -LiteralPath $outFile -Value ('Option selected : {0}' -f $AppendOption) -Encoding ASCII
        Write-Output ("TGOS: recorded option {0}" -f $AppendOption)
        exit 0
    }

    $version = Get-TgosVersion -ConfPath $ConfPath

    $edition = ''
    $build = ''
    $displayVersion = ''
    $cvPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    if (Test-Path -LiteralPath $cvPath) {
        $cv = Get-ItemProperty -LiteralPath $cvPath
        $edition = [string]$cv.EditionID
        $build = ('{0}.{1}' -f $cv.CurrentBuildNumber, $cv.UBR)
        $displayVersion = [string]$cv.DisplayVersion
    }

    $restorePoint = 'not attempted'
    $restorePointFile = Join-Path $dataDir 'restore-point.txt'
    if (Test-Path -LiteralPath $restorePointFile) {
        $restorePoint = (Get-Content -LiteralPath $restorePointFile -TotalCount 1)
    }

    $lines = @(
        'TGOS (Tech Gameplay Operating System)',
        ('TGOS version    : {0}' -f $version),
        ('Installed at    : {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
        ('Windows edition : {0}' -f $edition),
        ('Windows version : {0}' -f $displayVersion),
        ('Windows build   : {0}' -f $build),
        ('Restore point   : {0}' -f $restorePoint),
        ('Modules run     : {0}' -f $Modules)
    )

    Set-Content -LiteralPath $outFile -Value $lines -Encoding ASCII

    Write-Output ("TGOS: install info written to {0}" -f $outFile)
    exit 0
}
catch {
    Write-Output ("ERROR: failed to write install info: {0}" -f $_.Exception.Message)
    exit 1
}
