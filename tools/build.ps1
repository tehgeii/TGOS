<#
.SYNOPSIS
    Mengemas src\ menjadi release\TGOS-v<versi>.apbx.

.DESCRIPTION
    1. Menjalankan tools\validate.py (butuh Python 3 dan PyYAML).
    2. Mengarsipkan isi src\ sebagai 7z berpassword "malte" dengan ekstensi .apbx.
    3. Bila password distribusi diisi, membungkus .apbx ke dalam .7z berpassword itu.

    Butuh 7-Zip (https://www.7-zip.org).

.PARAMETER DistPassword
    Password pembungkus distribusi. Default: variabel lingkungan TGOS_DIST_PASSWORD.
    Jangan pernah menulis password ini di dalam repo.

.PARAMETER SkipValidation
    Melewati tools\validate.py. Hanya untuk keadaan darurat.

.EXAMPLE
    .\tools\build.ps1

.EXAMPLE
    $env:TGOS_DIST_PASSWORD = 'password-distribusi'
    .\tools\build.ps1
#>
[CmdletBinding()]
param(
    [string]$DistPassword = $env:TGOS_DIST_PASSWORD,
    [switch]$SkipValidation
)

$ErrorActionPreference = 'Stop'

# Password .apbx ditentukan AME Wizard dan tidak bisa diganti: Wizard hanya membuka
# playbook yang dienkripsi dengan password ini. Ini bukan rahasia.
$ApbxPassword = 'malte'

$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root 'src'
$out  = Join-Path $root 'release'

function Find-SevenZip {
    foreach ($name in @('7z', '7zz', '7za')) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($command) { return $command.Source }
    }
    $candidates = @()
    if ($env:ProgramFiles)        { $candidates += (Join-Path $env:ProgramFiles '7-Zip\7z.exe') }
    if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe') }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw '7-Zip tidak ditemukan. Pasang dari https://www.7-zip.org lalu jalankan lagi.'
}

function Find-Python {
    foreach ($name in @('py', 'python3', 'python')) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($command) { return $command.Source }
    }
    return $null
}

function Invoke-Checked {
    param(
        [string]$File,
        [string[]]$Arguments,
        [string]$What
    )
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw ('{0} gagal (kode keluar {1}).' -f $What, $LASTEXITCODE)
    }
}

$sevenZip = Find-SevenZip

if ($SkipValidation) {
    Write-Warning 'Validasi dilewati (-SkipValidation).'
}
else {
    $python = Find-Python
    if (-not $python) {
        throw 'Python tidak ditemukan. Pasang Python 3 dan PyYAML (pip install pyyaml), atau pakai -SkipValidation.'
    }
    Invoke-Checked -File $python -Arguments @((Join-Path $root 'tools\validate.py')) -What 'Validasi'
}

$conf = New-Object System.Xml.XmlDocument
$conf.Load((Join-Path $src 'playbook.conf'))
$versionNode = $conf.SelectSingleNode('/Playbook/Version')
if ($null -eq $versionNode -or -not $versionNode.InnerText.Trim()) {
    throw 'Versi tidak bisa dibaca dari src\playbook.conf.'
}
$version = $versionNode.InnerText.Trim()

$apbxName    = 'TGOS-v{0}.apbx' -f $version
$wrapperName = 'TGOS-v{0}.7z' -f $version
$apbx    = Join-Path $out $apbxName
$wrapper = Join-Path $out $wrapperName

if (-not (Test-Path -LiteralPath $out)) {
    New-Item -ItemType Directory -Path $out | Out-Null
}
foreach ($stale in @($apbx, $wrapper)) {
    if (Test-Path -LiteralPath $stale) { Remove-Item -LiteralPath $stale -Force }
}

# Yang diarsipkan adalah ISI src\, bukan foldernya: playbook.conf harus di akar arsip.
$items = @('playbook.conf', 'Configuration', 'Executables')
if (Test-Path -LiteralPath (Join-Path $src 'playbook.png')) {
    $items += 'playbook.png'
}
Push-Location $src
try {
    Invoke-Checked -File $sevenZip -What 'Pengemasan .apbx' -Arguments (@(
        'a', '-t7z', '-mx=9', ('-p' + $ApbxPassword), '-bso0', '-bsp0', $apbx) + $items)
}
finally {
    Pop-Location
}
Invoke-Checked -File $sevenZip -What 'Uji arsip .apbx' -Arguments @(
    't', ('-p' + $ApbxPassword), '-bso0', '-bsp0', $apbx)
Write-Host ('Dibuat: release\{0}' -f $apbxName)

if ($DistPassword) {
    # Pembungkus distribusi: nama file ikut dienkripsi (-mhe=on) dan tanpa kompresi
    # (-mx=0) karena .apbx di dalamnya sudah terkompresi.
    Push-Location $out
    try {
        Invoke-Checked -File $sevenZip -What 'Pembuatan pembungkus .7z' -Arguments @(
            'a', '-t7z', '-mx=0', '-mhe=on', ('-p' + $DistPassword), '-bso0', '-bsp0',
            $wrapper, $apbxName)
    }
    finally {
        Pop-Location
    }
    Invoke-Checked -File $sevenZip -What 'Uji pembungkus .7z' -Arguments @(
        't', ('-p' + $DistPassword), '-bso0', '-bsp0', $wrapper)
    Write-Host ('Dibuat: release\{0}' -f $wrapperName)
}
else {
    Write-Host 'TGOS_DIST_PASSWORD tidak diisi: pembungkus distribusi .7z dilewati.'
}
