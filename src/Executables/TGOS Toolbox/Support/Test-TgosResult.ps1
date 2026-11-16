<#
.SYNOPSIS
    Memeriksa apakah setiap perubahan TGOS benar-benar ada di sistem.

.DESCRIPTION
    Membaca expected-state.json (dibuat dari YAML playbook) dan mencocokkan tiap butir
    dengan keadaan sistem. Hasil per butir:

      PASS  sesuai
      FAIL  tidak sesuai
      SKIP  tidak berlaku atau tidak bisa diperiksa (opsi tidak dipilih, build lain,
            layanan atau tugas tidak ada di build ini)
      WARN  perlu diketahui tetapi bukan kegagalan

    Nilai HKCU diperiksa pada pengguna yang sedang login (hive yang termuat di HKU).

    Skrip ini hanya membaca. Satu-satunya yang ditulisnya adalah file laporan.
    Kode keluar 0, kecuali -FailOnMismatch diberikan dan ada FAIL (dipakai di CI).

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$ExpectedStatePath,
    [string]$ReportPath,
    [string]$InstallInfoPath,
    [switch]$FailOnMismatch
)

$ErrorActionPreference = 'Stop'

if (-not $ExpectedStatePath) {
    $ExpectedStatePath = Join-Path $PSScriptRoot 'expected-state.json'
}
$programData = $env:ProgramData
if (-not $programData) { $programData = [System.IO.Path]::GetTempPath() }
$dataDirectory = Join-Path $programData 'TGOS'
if (-not $InstallInfoPath) {
    $InstallInfoPath = Join-Path $dataDirectory 'install-info.txt'
}
if (-not $ReportPath) {
    $ReportPath = Join-Path $dataDirectory 'verify-report.txt'
}

$script:results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param([string]$Status, [string]$Kind, [string]$Item, [string]$Detail, [string]$Source)
    $script:results.Add([pscustomobject]@{
            Status = $Status; Kind = $Kind; Item = $Item; Detail = $Detail; Source = $Source
        })
}

# --- Keadaan saat ini --------------------------------------------------------------

$build = 0
try {
    $build = [int](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
}
catch {
    $build = 0
}

$installInfo = @()
if (Test-Path -LiteralPath $InstallInfoPath) {
    $installInfo = @(Get-Content -LiteralPath $InstallInfoPath)
}
$selectedOptions = @($installInfo | Where-Object { $_ -match '^Option selected\s*:\s*(.+)$' } |
    ForEach-Object { ($_ -replace '^Option selected\s*:\s*', '').Trim() })

# --- Syarat, sama dengan aturan AME Wizard -----------------------------------------

function Test-Option {
    param([string]$Option)
    if (-not $Option) { return $true }
    if ($Option.Contains('&')) {
        foreach ($part in $Option.Split('&')) {
            if (-not (Test-Option $part)) { return $false }
        }
        return $true
    }
    $negative = $Option.StartsWith('!')
    $name = $Option.TrimStart('!')
    $present = $selectedOptions -contains $name
    if ($negative) { return (-not $present) }
    return $present
}

function Test-BuildFilter {
    param([string]$Filter)
    $negative = $Filter.StartsWith('!')
    $text = $Filter.TrimStart('!')
    $result = $false
    if ($text.StartsWith('>=')) { $result = $build -ge [int]$text.Substring(2) }
    elseif ($text.StartsWith('<=')) { $result = $build -le [int]$text.Substring(2) }
    elseif ($text.StartsWith('>')) { $result = $build -gt [int]$text.Substring(1) }
    elseif ($text.StartsWith('<')) { $result = $build -lt [int]$text.Substring(1) }
    else { $result = $build -eq [int]$text }
    if ($negative) { return (-not $result) }
    return $result
}

function Test-Builds {
    param($Builds)
    if ($null -eq $Builds) { return $true }
    $list = @($Builds)
    $positive = @($list | Where-Object { -not $_.StartsWith('!') })
    $negative = @($list | Where-Object { $_.StartsWith('!') })
    # Aturan AME: harus ada butir tanpa '!' yang cocok, dan semua butir '!' terpenuhi.
    if (-not ($positive | Where-Object { Test-BuildFilter $_ })) { return $false }
    foreach ($item in $negative) {
        if (-not (Test-BuildFilter $item)) { return $false }
    }
    return $true
}

function Get-SkipReason {
    param($Check)
    if (-not (Test-Option $Check.option)) { return ("option '{0}' not selected" -f $Check.option) }
    if (-not (Test-Builds $Check.builds)) { return ("build {0} outside {1}" -f $build, (@($Check.builds) -join ',')) }
    return $null
}

# --- Registry ------------------------------------------------------------------------

function Get-UserHives {
    # Sama dengan AME: pengguna yang sedang login punya kunci "Volatile Environment".
    $hives = @()
    try {
        $users = [Microsoft.Win32.Registry]::Users
        foreach ($name in $users.GetSubKeyNames()) {
            if ($name -notmatch '^S-1-5-21-' -or $name.EndsWith('_Classes')) { continue }
            $key = $users.OpenSubKey($name)
            if ($null -eq $key) { continue }
            try {
                if ($key.GetSubKeyNames() -contains 'Volatile Environment') { $hives += $name }
            }
            finally { $key.Dispose() }
        }
    }
    catch {
        $hives = @()
    }
    return $hives
}

$userHives = @(Get-UserHives)

function Read-RegistryValue {
    <# Mengembalikan @{ Found = bool; Data = object } untuk satu jalur lengkap. #>
    param([Microsoft.Win32.RegistryKey]$Root, [string]$SubKey, [string]$Name)
    $key = $Root.OpenSubKey($SubKey)
    if ($null -eq $key) { return @{ Found = $false; Data = $null } }
    try {
        if ($key.GetValueNames() -notcontains $Name) { return @{ Found = $false; Data = $null } }
        $data = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        return @{ Found = $true; Data = $data }
    }
    finally { $key.Dispose() }
}

function Compare-RegistryData {
    param($Actual, [string]$Expected, [string]$RegType)
    if ($RegType -eq 'REG_DWORD') {
        # DWORD dibaca sebagai Int32; bandingkan sebagai bilangan tak bertanda.
        $unsigned = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$Actual), 0)
        return ($unsigned -eq [uint32]$Expected)
    }
    if ($RegType -eq 'REG_QWORD') {
        $unsigned = [BitConverter]::ToUInt64([BitConverter]::GetBytes([long]$Actual), 0)
        return ($unsigned -eq [uint64]$Expected)
    }
    return ([string]$Actual -eq $Expected)
}

function Test-RegistryCheck {
    param($Check)

    $item = '{0}\{1}' -f $Check.path, $Check.value
    $separator = $Check.path.IndexOf('\')
    $hive = $Check.path.Substring(0, $separator).ToUpper()
    $subKey = $Check.path.Substring($separator + 1)

    $targets = @()
    if ($hive -eq 'HKLM' -or $hive -eq 'HKEY_LOCAL_MACHINE') {
        $targets += , @([Microsoft.Win32.Registry]::LocalMachine, $subKey, 'HKLM')
    }
    elseif ($hive -eq 'HKCU' -or $hive -eq 'HKEY_CURRENT_USER') {
        if ($userHives.Count -eq 0) {
            Add-Result 'SKIP' 'registry' $item 'no logged-on user hive to check' $Check.source
            return
        }
        foreach ($sid in $userHives) {
            $targets += , @([Microsoft.Win32.Registry]::Users, ('{0}\{1}' -f $sid, $subKey), 'HKU user')
        }
    }
    else {
        Add-Result 'SKIP' 'registry' $item ("hive {0} not checked" -f $hive) $Check.source
        return
    }

    foreach ($target in $targets) {
        $read = Read-RegistryValue -Root $target[0] -SubKey $target[1] -Name $Check.value
        if ($Check.absent) {
            if ($read.Found) {
                Add-Result 'FAIL' 'registry' $item ("should be absent but is '{0}' ({1})" -f $read.Data, $target[2]) $Check.source
                return
            }
            continue
        }
        if (-not $read.Found) {
            Add-Result 'FAIL' 'registry' $item ("expected {0}, value missing ({1})" -f $Check.data, $target[2]) $Check.source
            return
        }
        if (-not (Compare-RegistryData -Actual $read.Data -Expected $Check.data -RegType $Check.regType)) {
            Add-Result 'FAIL' 'registry' $item ("expected {0}, found '{1}' ({2})" -f $Check.data, $read.Data, $target[2]) $Check.source
            return
        }
    }

    if ($Check.absent) { $detail = 'absent' } else { $detail = '= {0}' -f $Check.data }
    Add-Result 'PASS' 'registry' $item $detail $Check.source
}

# --- AppX, layanan, tugas ------------------------------------------------------------

$script:appxFamilies = $null
$script:appxError = $null
try {
    $script:appxFamilies = @(Get-AppxPackage -AllUsers | ForEach-Object { [string]$_.PackageFamilyName } | Sort-Object -Unique)
}
catch {
    $script:appxError = ($_.Exception.Message -replace '\s+', ' ').Trim()
}

function Test-AppxCheck {
    param($Check)
    if ($null -eq $script:appxFamilies) {
        Add-Result 'SKIP' 'appx' $Check.name ("cannot list packages: {0}" -f $script:appxError) $Check.source
        return
    }
    $found = @($script:appxFamilies | Where-Object { $_ -like $Check.name })
    if ($found.Count -gt 0) {
        Add-Result 'FAIL' 'appx' $Check.name ("still installed: {0}" -f ($found -join ', ')) $Check.source
    }
    else {
        Add-Result 'PASS' 'appx' $Check.name 'not installed' $Check.source
    }
}

function Test-ServiceCheck {
    param($Check)
    $read = Read-RegistryValue -Root ([Microsoft.Win32.Registry]::LocalMachine) `
        -SubKey ('SYSTEM\CurrentControlSet\Services\{0}' -f $Check.name) -Name 'Start'
    if (-not $read.Found) {
        Add-Result 'SKIP' 'service' $Check.name 'service not present on this build' $Check.source
        return
    }
    if ([int]$read.Data -eq [int]$Check.startup) {
        Add-Result 'PASS' 'service' $Check.name ("Start = {0}" -f $Check.startup) $Check.source
    }
    else {
        Add-Result 'FAIL' 'service' $Check.name ("expected Start = {0}, found {1}" -f $Check.startup, $read.Data) $Check.source
    }
}

function Test-TaskCheck {
    param($Check)
    $separator = $Check.path.LastIndexOf('\')
    $taskPath = $Check.path.Substring(0, $separator + 1)
    $taskName = $Check.path.Substring($separator + 1)
    try {
        $task = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
    }
    catch {
        Add-Result 'SKIP' 'task' $Check.path ("cannot query: {0}" -f (($_.Exception.Message -replace '\s+', ' ').Trim())) $Check.source
        return
    }
    if ($null -eq $task) {
        Add-Result 'SKIP' 'task' $Check.path 'task not present on this build' $Check.source
    }
    elseif ([string]$task.State -eq 'Disabled') {
        Add-Result 'PASS' 'task' $Check.path 'Disabled' $Check.source
    }
    else {
        Add-Result 'FAIL' 'task' $Check.path ("expected Disabled, found {0}" -f $task.State) $Check.source
    }
}

# --- Pemeriksaan hasil skrip (tidak berasal dari YAML) -------------------------------

function Test-ScriptResults {
    $toolbox = Join-Path ('{0}\' -f $env:SystemDrive) 'TGOS Toolbox'
    if (Test-Path -LiteralPath (Join-Path $toolbox 'Support\Set-TgosFeature.ps1')) {
        Add-Result 'PASS' 'toolbox' $toolbox 'installed' 'Install-Toolbox.ps1'
    }
    else {
        Add-Result 'FAIL' 'toolbox' $toolbox 'not installed' 'Install-Toolbox.ps1'
    }

    $shortcut = Join-Path $env:PUBLIC 'Desktop\TGOS Toolbox.lnk'
    if (Test-Path -LiteralPath $shortcut) {
        Add-Result 'PASS' 'toolbox' 'desktop shortcut' 'present' 'Install-Toolbox.ps1'
    }
    else {
        Add-Result 'WARN' 'toolbox' 'desktop shortcut' 'missing' 'Install-Toolbox.ps1'
    }

    $wallpaper = Join-Path $env:SystemRoot 'Web\Wallpaper\TGOS\TGOS.png'
    if (Test-Path -LiteralPath $wallpaper) {
        Add-Result 'PASS' 'wallpaper' $wallpaper 'present' 'Install-Toolbox.ps1'
    }
    else {
        Add-Result 'FAIL' 'wallpaper' $wallpaper 'missing' 'Install-Toolbox.ps1'
    }

    $restoreLine = @($installInfo | Where-Object { $_ -match '^Restore point\s*:' }) | Select-Object -First 1
    if ($restoreLine -and $restoreLine -match ':\s*created') {
        Add-Result 'PASS' 'restore point' 'Before TGOS' 'created' 'New-RestorePoint.ps1'
    }
    else {
        # Bukan kegagalan playbook: restore point memang dirancang tidak fatal.
        Add-Result 'WARN' 'restore point' 'Before TGOS' ([string]$restoreLine) 'New-RestorePoint.ps1'
    }

    if (Test-Option 'disable-power-saving') {
        $planFile = Join-Path $dataDirectory 'power-plan.txt'
        $expected = $null
        if (Test-Path -LiteralPath $planFile) { $expected = (Get-Content -LiteralPath $planFile -TotalCount 1).Trim().ToLower() }
        $active = (& powercfg.exe /getactivescheme 2>&1 | Out-String).ToLower()
        if ($expected -and $active.Contains($expected)) {
            Add-Result 'PASS' 'power plan' 'TGOS Ultimate Performance' 'active' 'Set-PowerPlan.ps1'
        }
        else {
            Add-Result 'FAIL' 'power plan' 'TGOS Ultimate Performance' ("not active; active scheme: {0}" -f $active.Trim()) 'Set-PowerPlan.ps1'
        }
    }

    if (Test-Option 'disable-hibernation') {
        $read = Read-RegistryValue -Root ([Microsoft.Win32.Registry]::LocalMachine) -SubKey 'SYSTEM\CurrentControlSet\Control\Power' -Name 'HibernateEnabled'
        if ($read.Found -and [int]$read.Data -eq 0) {
            Add-Result 'PASS' 'hibernation' 'HibernateEnabled' '= 0' 'Set-PowerPlan.ps1'
        }
        elseif (-not $read.Found) {
            Add-Result 'SKIP' 'hibernation' 'HibernateEnabled' 'value not present (hibernation not supported here)' 'Set-PowerPlan.ps1'
        }
        else {
            Add-Result 'FAIL' 'hibernation' 'HibernateEnabled' ("expected 0, found {0}" -f $read.Data) 'Set-PowerPlan.ps1'
        }
    }

    if (Test-Option 'remove-onedrive') {
        $copies = @()
        try {
            $copies = @(Get-ChildItem -Path (Join-Path ('{0}\' -f $env:SystemDrive) 'Users\*\AppData\Local\Microsoft\OneDrive\OneDrive.exe') -ErrorAction SilentlyContinue)
        }
        catch { $copies = @() }
        if ($copies.Count -eq 0) {
            Add-Result 'PASS' 'onedrive' 'OneDrive.exe' 'not installed for any user' 'Remove-OneDrive.ps1'
        }
        else {
            Add-Result 'FAIL' 'onedrive' 'OneDrive.exe' ("still installed in {0} profile(s)" -f $copies.Count) 'Remove-OneDrive.ps1'
        }
    }

    if (Test-Option 'remove-edge') {
        $edge = $null
        foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
            if ($base) {
                $candidate = Join-Path $base 'Microsoft\Edge\Application\msedge.exe'
                if (Test-Path -LiteralPath $candidate) { $edge = $candidate }
            }
        }
        if ($edge) {
            Add-Result 'FAIL' 'edge' 'Microsoft Edge' ("still installed: {0}" -f $edge) 'Remove-Edge.ps1'
        }
        else {
            Add-Result 'PASS' 'edge' 'Microsoft Edge' 'not installed' 'Remove-Edge.ps1'
        }
    }
}

# --- Jalankan ------------------------------------------------------------------------

$state = $null
try {
    $state = Get-Content -LiteralPath $ExpectedStatePath -Raw | ConvertFrom-Json
}
catch {
    Add-Result 'FAIL' 'setup' $ExpectedStatePath ("cannot read expected state: {0}" -f $_.Exception.Message) ''
}

if ($installInfo.Count -eq 0) {
    Add-Result 'FAIL' 'setup' $InstallInfoPath 'install-info.txt not found: the playbook did not finish' ''
}

if ($null -ne $state) {
    foreach ($check in $state.checks) {
        try {
            $skip = Get-SkipReason $check
            if ($skip) {
                switch ($check.type) {
                    'registry' { $name = '{0}\{1}' -f $check.path, $check.value }
                    'task' { $name = $check.path }
                    default { $name = $check.name }
                }
                Add-Result 'SKIP' $check.type $name $skip $check.source
                continue
            }
            switch ($check.type) {
                'registry' { Test-RegistryCheck $check }
                'appx' { Test-AppxCheck $check }
                'service' { Test-ServiceCheck $check }
                'task' { Test-TaskCheck $check }
                default { Add-Result 'SKIP' $check.type '' 'unknown check type' $check.source }
            }
        }
        catch {
            Add-Result 'FAIL' ([string]$check.type) ([string]$check.source) ("check crashed: {0}" -f (($_.Exception.Message -replace '\s+', ' ').Trim())) $check.source
        }
    }
    try {
        Test-ScriptResults
    }
    catch {
        Add-Result 'FAIL' 'setup' 'script results' ("check crashed: {0}" -f (($_.Exception.Message -replace '\s+', ' ').Trim())) ''
    }
}

# --- Laporan -------------------------------------------------------------------------

$counts = @{ PASS = 0; FAIL = 0; SKIP = 0; WARN = 0 }
foreach ($result in $script:results) { $counts[$result.Status]++ }

$stateVersion = ''
if ($null -ne $state) { $stateVersion = [string]$state.version }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('TGOS verification report')
$lines.Add(('Checked at       : {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
$lines.Add(('Expected state   : TGOS {0}' -f $stateVersion))
$lines.Add(('Windows build    : {0}' -f $build))
$lines.Add(('Options selected : {0}' -f ($selectedOptions -join ', ')))
$lines.Add(('User hives       : {0}' -f $userHives.Count))
$lines.Add('')

# FAIL dan WARN dulu supaya langsung terlihat.
foreach ($status in @('FAIL', 'WARN', 'PASS', 'SKIP')) {
    foreach ($result in ($script:results | Where-Object { $_.Status -eq $status })) {
        $lines.Add(('{0}  {1,-13} {2}  ->  {3}  [{4}]' -f $result.Status, $result.Kind, $result.Item, $result.Detail, $result.Source))
    }
}

$lines.Add('')
$lines.Add(('SUMMARY: {0} PASS, {1} FAIL, {2} WARN, {3} SKIP' -f $counts['PASS'], $counts['FAIL'], $counts['WARN'], $counts['SKIP']))

try {
    $reportDirectory = Split-Path -Parent $ReportPath
    if ($reportDirectory -and -not (Test-Path -LiteralPath $reportDirectory)) {
        New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
    }
    Set-Content -LiteralPath $ReportPath -Value $lines -Encoding ASCII
    Write-Output ("TGOS: verification report written to {0}" -f $ReportPath)
}
catch {
    Write-Output ("WARNING: could not write the verification report: {0}" -f $_.Exception.Message)
}

Write-Output $lines[$lines.Count - 1]

if ($FailOnMismatch -and $counts['FAIL'] -gt 0) {
    exit 1
}
exit 0
