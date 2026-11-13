# Fungsi bersama untuk skrip TGOS. Dimuat dengan dot-sourcing:
#     . (Join-Path $PSScriptRoot 'Common.ps1')
#
# File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.

function Get-TgosVersion {
    <#
    .SYNOPSIS
        Membaca versi TGOS dari playbook.conf supaya nomor versi hanya ditulis di satu tempat.
    #>
    param(
        [string]$ConfPath
    )

    if (-not $ConfPath) {
        # Skrip ada di <playbook>\Executables\Scripts, playbook.conf di <playbook>.
        $playbookRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $ConfPath = Join-Path $playbookRoot 'playbook.conf'
    }

    if (-not (Test-Path -LiteralPath $ConfPath)) {
        return 'unknown'
    }

    try {
        $conf = New-Object System.Xml.XmlDocument
        $conf.Load($ConfPath)
        $versionNode = $conf.SelectSingleNode('/Playbook/Version')
        if ($null -ne $versionNode -and $versionNode.InnerText) {
            return $versionNode.InnerText.Trim()
        }
    }
    catch {
        return 'unknown'
    }
    return 'unknown'
}

function Get-TgosDataDirectory {
    <#
    .SYNOPSIS
        Mengembalikan folder data TGOS (%ProgramData%\TGOS) dan membuatnya bila belum ada.
    #>
    param(
        [string]$Path
    )

    if (-not $Path) {
        $Path = Join-Path $env:ProgramData 'TGOS'
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    return $Path
}
