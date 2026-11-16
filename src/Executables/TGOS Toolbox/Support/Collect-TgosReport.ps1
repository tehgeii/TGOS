<#
.SYNOPSIS
    Mengumpulkan semua yang dibutuhkan untuk memeriksa hasil instalasi TGOS ke satu file zip.

.DESCRIPTION
    Membuat TGOS-report.zip di Desktop, berisi:
      - verify-report.txt     hasil pemeriksaan tiap tweak (PASS / FAIL / SKIP / WARN)
      - TGOS-snapshot-after.json  potret sistem (proses, RAM, layanan, aplikasi, tugas)
      - isi %ProgramData%\TGOS (install-info.txt, restore-point.txt, dan lainnya)
      - log AME bila ditemukan

    Tidak mengubah pengaturan Windows. Tidak mengumpulkan nama komputer, nama pengguna,
    alamat jaringan, atau file pribadi.

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
