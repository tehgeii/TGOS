<#
.SYNOPSIS
    Mencatat nilai Start layanan sebelum TGOS mengubahnya.

.DESCRIPTION
    Membaca daftar layanan dari expected-state.json (semua layanan yang bisa diubah
    playbook, termasuk yang bergantung opsi) dan menulis nilai Start-nya saat ini ke
    <folder data TGOS>\services-before.txt, satu baris "Nama=Nilai".

    Nilai yang sudah tercatat TIDAK ditimpa, jadi file itu tetap berisi keadaan sebelum
    TGOS pertama kali dipasang walaupun playbook dijalankan lagi. TGOS Toolbox memakai
    catatan ini untuk mengembalikan layanan persis seperti semula.

    Hanya membaca registry. Tidak fatal: kode keluar selalu 0.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$ExpectedStatePath,
    [string]$DataDirectory
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

try {
    if (-not $ExpectedStatePath) {
        # Skrip ada di <playbook>\Executables\Scripts.
        $ExpectedStatePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'TGOS Toolbox\Support\expected-state.json'
    }
    $DataDirectory = Get-TgosDataDirectory -Path $DataDirectory
    $file = Join-Path $DataDirectory 'services-before.txt'

    $known = @{}
    if (Test-Path -LiteralPath $file) {
        foreach ($line in (Get-Content -LiteralPath $file)) {
            if ($line -match '^(?<name>[^=]+)=(?<start>\d+)$') { $known[$Matches['name']] = $Matches['start'] }
        }
    }

    $state = Get-Content -LiteralPath $ExpectedStatePath -Raw | ConvertFrom-Json
    $names = @($state.checks | Where-Object { $_.type -eq 'service' } | ForEach-Object { [string]$_.name } | Sort-Object -Unique)
    $added = 0
    foreach ($name in $names) {
        if ($known.ContainsKey($name)) { continue }
        $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\{0}' -f $name
        $start = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).Start
        if ($null -ne $start) {
            $known[$name] = [string][int]$start
            $added++
        }
    }

    $lines = @($known.Keys | Sort-Object | ForEach-Object { '{0}={1}' -f $_, $known[$_] })
    Set-Content -LiteralPath $file -Value $lines -Encoding ASCII
    Write-Output ("TGOS: service start values recorded - {0} new, {1} total" -f $added, $lines.Count)
}
catch {
    Write-Output ("WARNING: could not record the service start values: {0}" -f (Format-TgosError $_))
}

exit 0
