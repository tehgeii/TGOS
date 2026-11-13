<#
.SYNOPSIS
    Mencatat informasi instalasi TGOS ke %ProgramData%\TGOS\install-info.txt.

.DESCRIPTION
    Dijalankan di akhir playbook. Versi TGOS dibaca dari playbook.conf supaya nomor
    versi hanya ditulis di satu tempat.

    Parameter hanya dipakai untuk pengujian. Tanpa parameter, lokasi default dipakai.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$ConfPath,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'

try {
    if (-not $ConfPath) {
        # Skrip ini ada di <playbook>\Executables\Scripts, playbook.conf di <playbook>.
        $playbookRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $ConfPath = Join-Path $playbookRoot 'playbook.conf'
    }
    if (-not $OutputDirectory) {
        $OutputDirectory = Join-Path $env:ProgramData 'TGOS'
    }

    $version = 'tidak diketahui'
    if (Test-Path -LiteralPath $ConfPath) {
        $conf = New-Object System.Xml.XmlDocument
        $conf.Load($ConfPath)
        $versionNode = $conf.SelectSingleNode('/Playbook/Version')
        if ($null -ne $versionNode -and $versionNode.InnerText) {
            $version = $versionNode.InnerText.Trim()
        }
    }

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

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    $lines = @(
        'TGOS (Tech Gameplay Operating System)',
        ('Versi TGOS      : {0}' -f $version),
        ('Waktu instalasi : {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
        ('Edisi Windows   : {0}' -f $edition),
        ('Versi Windows   : {0}' -f $displayVersion),
        ('Build Windows   : {0}' -f $build)
    )

    $outFile = Join-Path $OutputDirectory 'install-info.txt'
    Set-Content -LiteralPath $outFile -Value $lines -Encoding ASCII

    Write-Output ("TGOS: info instalasi ditulis ke {0}" -f $outFile)
    exit 0
}
catch {
    Write-Output ("GALAT: gagal menulis info instalasi: {0}" -f $_.Exception.Message)
    exit 1
}
