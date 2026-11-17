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
    if ($RegType -eq 'REG_BINARY') {
        # Data biner ditulis di YAML sebagai heksadesimal tanpa pemisah.
        $hex = -join (@($Actual) | ForEach-Object { '{0:X2}' -f [int]$_ })
        return ($hex -eq ('' + $Expected).ToUpper())
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

function Find-Program {
    # Jalur pertama yang ada di Program Files (64-bit lalu 32-bit), atau $null.
    param([string]$Relative)
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($base) {
            $path = Join-Path $base $Relative
            if (Test-Path -LiteralPath $path) { return $path }
        }
    }
    return $null
}

function Test-AnyBrowser {
    foreach ($relative in @('BraveSoftware\Brave-Browser\Application\brave.exe',
            'Google\Chrome\Application\chrome.exe', 'Mozilla Firefox\firefox.exe')) {
        if (Find-Program $relative) { return $true }
    }
    return $false
}

function Test-VcRuntime {
    param([string]$Architecture)
    foreach ($subKey in @(
            ('SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\{0}' -f $Architecture),
            ('SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\{0}' -f $Architecture))) {
        $read = Read-RegistryValue ([Microsoft.Win32.Registry]::LocalMachine) $subKey 'Installed'
        if ($read.Found -and [int]$read.Data -eq 1) { return $true }
    }
    return $false
}

function Test-UninstallEntry {
    # Ada program terpasang yang DisplayName-nya cocok dengan pola ini (64 dan 32-bit).
    param([string]$Pattern)
    $roots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
    $names = @(Get-ItemProperty -Path $roots -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.DisplayName })
    return [bool](@($names | Where-Object { $_ -match $Pattern }).Count)
}

function Find-UserProgram {
    # Program per pengguna: jalur pertama yang ada di salah satu profil pengguna biasa.
    param([string]$Relative)
    $root = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
        if ($key.PSChildName -notmatch '^S-1-5-21-[\d-]+$') { continue }
        $profilePath = [string](Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
        if (-not $profilePath) { continue }
        $path = Join-Path $profilePath $Relative
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}

function Test-SoftwareResults {
    # Program pilihan pengguna. Yang tidak terpasang bisa diulang dari TGOS Toolbox.
    # Arsitektur asli Windows (bukan arsitektur proses PowerShell ini). Selain browser
    # dan 7-Zip, software TGOS hanya dipasang di Windows x64.
    $native = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -ErrorAction SilentlyContinue).PROCESSOR_ARCHITECTURE
    $x64 = (-not $native) -or $native -eq 'AMD64'
    $programs = @(
        @{ Option = 'browser-brave'; Name = 'Brave'; Relative = @('BraveSoftware\Brave-Browser\Application\brave.exe') },
        @{ Option = 'browser-chrome'; Name = 'Google Chrome'; Relative = @('Google\Chrome\Application\chrome.exe') },
        @{ Option = 'browser-firefox'; Name = 'Mozilla Firefox'; Relative = @('Mozilla Firefox\firefox.exe') },
        @{ Option = 'install-7zip'; Name = '7-Zip'; Relative = @('7-Zip\7z.exe') },
        @{ Option = 'install-steam'; Name = 'Steam'; Relative = @('Steam\steam.exe'); X64Only = $true },
        @{ Option = 'install-epic'; Name = 'Epic Games Launcher'; X64Only = $true
            Relative = @('Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe', 'Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe') },
        @{ Option = 'install-ea'; Name = 'EA app'; Relative = @('Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe'); X64Only = $true },
        @{ Option = 'install-ubisoft'; Name = 'Ubisoft Connect'; X64Only = $true
            Relative = @('Ubisoft\Ubisoft Game Launcher\UbisoftConnect.exe', 'Ubisoft\Ubisoft Game Launcher\upc.exe') },
        @{ Option = 'install-discord'; Name = 'Discord'; UserRelative = 'AppData\Local\Discord\Update.exe'; X64Only = $true },
        @{ Option = 'install-spotify'; Name = 'Spotify'; UserRelative = 'AppData\Roaming\Spotify\Spotify.exe'; X64Only = $true })
    foreach ($program in $programs) {
        if (-not (Test-Option $program.Option)) { continue }
        if ($program.X64Only -and -not $x64) {
            Add-Result 'SKIP' 'software' $program.Name ("installed on x64 Windows only (this PC is {0})" -f $native) 'Install-Software.ps1'
            continue
        }
        $path = $null
        if ($program.UserRelative) { $path = Find-UserProgram $program.UserRelative }
        else { $path = @($program.Relative | ForEach-Object { Find-Program $_ } | Where-Object { $_ }) | Select-Object -First 1 }
        if ($path) {
            Add-Result 'PASS' 'software' $program.Name ("installed: {0}" -f $path) 'Install-Software.ps1'
        }
        else {
            Add-Result 'FAIL' 'software' $program.Name 'not installed; retry from the TGOS Toolbox (needs internet)' 'Install-Software.ps1'
        }
    }

    if (Test-Option 'install-runtimes') {
        if ((Test-VcRuntime 'x64') -and (Test-VcRuntime 'x86')) {
            Add-Result 'PASS' 'software' 'Visual C++ Redistributable' 'x64 and x86 installed' 'Install-Software.ps1'
        }
        else {
            Add-Result 'FAIL' 'software' 'Visual C++ Redistributable' 'x64 or x86 runtime missing; retry from the TGOS Toolbox' 'Install-Software.ps1'
        }
        $legacy = @('System32', 'SysWOW64') | ForEach-Object { Join-Path $env:SystemRoot ('{0}\d3dx9_43.dll' -f $_) } |
            Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($native -and $native -ne 'AMD64') {
            Add-Result 'SKIP' 'software' 'DirectX End-User Runtime' ("installed on x64 Windows only (this PC is {0})" -f $native) 'Install-Software.ps1'
        }
        elseif ($legacy) {
            Add-Result 'PASS' 'software' 'DirectX End-User Runtime' 'legacy DirectX libraries present' 'Install-Software.ps1'
        }
        else {
            Add-Result 'FAIL' 'software' 'DirectX End-User Runtime' 'd3dx9_43.dll missing; retry from the TGOS Toolbox' 'Install-Software.ps1'
        }

        # Visual C++ 2005-2013 (x86 dan x64) dan XNA 4.0, dari daftar program terpasang.
        $runtimes = @(
            @{ Name = 'Visual C++ 2005 x86'; Pattern = 'Visual C\+\+ 2005 Redistributable$' },
            @{ Name = 'Visual C++ 2005 x64'; Pattern = 'Visual C\+\+ 2005 Redistributable \(x64\)' },
            @{ Name = 'Visual C++ 2008 x86'; Pattern = 'Visual C\+\+ 2008 Redistributable - x86' },
            @{ Name = 'Visual C++ 2008 x64'; Pattern = 'Visual C\+\+ 2008 Redistributable - x64' },
            @{ Name = 'Visual C++ 2010 x86'; Pattern = 'Visual C\+\+ 2010\s+x86 Redistributable' },
            @{ Name = 'Visual C++ 2010 x64'; Pattern = 'Visual C\+\+ 2010\s+x64 Redistributable' },
            @{ Name = 'Visual C++ 2012 x86'; Pattern = 'Visual C\+\+ 2012 Redistributable \(x86\)' },
            @{ Name = 'Visual C++ 2012 x64'; Pattern = 'Visual C\+\+ 2012 Redistributable \(x64\)' },
            @{ Name = 'Visual C++ 2013 x86'; Pattern = 'Visual C\+\+ 2013 Redistributable \(x86\)' },
            @{ Name = 'Visual C++ 2013 x64'; Pattern = 'Visual C\+\+ 2013 Redistributable \(x64\)' },
            @{ Name = 'XNA Framework 4.0'; Pattern = '^Microsoft XNA Framework Redistributable 4\.0' })
        foreach ($runtime in $runtimes) {
            if (-not $x64) {
                Add-Result 'SKIP' 'software' $runtime.Name ("installed on x64 Windows only (this PC is {0})" -f $native) 'Install-Software.ps1'
            }
            elseif (Test-UninstallEntry $runtime.Pattern) {
                Add-Result 'PASS' 'software' $runtime.Name 'installed' 'Install-Software.ps1'
            }
            else {
                Add-Result 'FAIL' 'software' $runtime.Name 'not installed; retry from the TGOS Toolbox' 'Install-Software.ps1'
            }
        }
    }

    if (Test-Option 'install-dotnet') {
        $netfx3 = Read-RegistryValue ([Microsoft.Win32.Registry]::LocalMachine) 'SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5' 'Install'
        if ($netfx3.Found -and [int]$netfx3.Data -eq 1) {
            Add-Result 'PASS' 'software' '.NET Framework 3.5' 'installed' 'Install-Software.ps1'
        }
        else {
            Add-Result 'FAIL' 'software' '.NET Framework 3.5' 'not installed; retry from the TGOS Toolbox (needs internet)' 'Install-Software.ps1'
        }
        foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            $label = '.NET Desktop Runtime 10 ({0})' -f $(if ($base -eq $env:ProgramFiles) { 'x64' } else { 'x86' })
            if (-not $x64) {
                Add-Result 'SKIP' 'software' $label ("installed on x64 Windows only (this PC is {0})" -f $native) 'Install-Software.ps1'
                continue
            }
            $folder = Join-Path $base 'dotnet\shared\Microsoft.WindowsDesktop.App'
            $found = @(Get-ChildItem -LiteralPath $folder -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '10.*' })
            if ($found.Count -gt 0) {
                Add-Result 'PASS' 'software' $label ('installed: {0}' -f ($found | Select-Object -Last 1).Name) 'Install-Software.ps1'
            }
            else {
                Add-Result 'FAIL' 'software' $label 'not installed; retry from the TGOS Toolbox' 'Install-Software.ps1'
            }
        }
    }

    if (Test-Option 'disable-core-parking') {
        # Dua angka heksadesimal terakhir = nilai AC dan baterai saat ini.
        $query = (& cmd.exe /c 'powercfg.exe /query SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 0cc5b647-c1df-4637-891a-dec35c318583 2>&1' | Out-String)
        $values = @([regex]::Matches($query, '0x[0-9a-fA-F]{8}') | ForEach-Object { [Convert]::ToInt32($_.Value, 16) })
        if ($values.Count -ge 2 -and $values[$values.Count - 2] -eq 100) {
            Add-Result 'PASS' 'core parking' 'minimum unparked cores' '100% on the active power plan' 'Set-PowerPlan.ps1'
        }
        elseif ($values.Count -lt 2) {
            # Set-PowerPlan.ps1 membuat pengaturan ini terlihat; bila nilainya tetap tidak
            # terbaca, ada yang tidak beres dan perlu dilihat.
            Add-Result 'WARN' 'core parking' 'minimum unparked cores' 'value could not be read (powercfg shows no value for this setting)' 'Set-PowerPlan.ps1'
        }
        else {
            Add-Result 'FAIL' 'core parking' 'minimum unparked cores' ("expected 100, found {0}" -f $values[$values.Count - 2]) 'Set-PowerPlan.ps1'
        }
    }
}

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

    $layout = Join-Path $dataDirectory 'TaskbarLayout.xml'
    if (Test-Path -LiteralPath $layout) {
        Add-Result 'PASS' 'taskbar' $layout 'present' 'Set-ShellLayout.ps1'
    }
    else {
        Add-Result 'FAIL' 'taskbar' $layout 'missing; the taskbar pin policy points to it' 'Set-ShellLayout.ps1'
    }

    $pins = Read-RegistryValue ([Microsoft.Win32.Registry]::LocalMachine) 'SOFTWARE\Policies\Microsoft\Windows\Explorer' 'ConfigureStartPins'
    if ($pins.Found -and ([string]$pins.Data).Contains('pinnedList')) {
        Add-Result 'PASS' 'start menu' 'ConfigureStartPins policy' 'written' 'Set-ShellLayout.ps1'
    }
    else {
        Add-Result 'FAIL' 'start menu' 'ConfigureStartPins policy' 'missing' 'Set-ShellLayout.ps1'
    }

    if (Test-Option 'remove-ai-widgets') {
        # Program Copilot (bukan paket Store) terdaftar di sini selama masih terpasang.
        $copilot = $false
        foreach ($subKey in @(
                'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Copilot',
                'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Copilot')) {
            $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($subKey)
            if ($null -ne $key) { $copilot = $true; $key.Dispose() }
        }
        if ($copilot) {
            Add-Result 'FAIL' 'copilot' 'Copilot program' 'still installed' 'Remove-Copilot.ps1'
        }
        else {
            Add-Result 'PASS' 'copilot' 'Copilot program' 'not installed' 'Remove-Copilot.ps1'
        }
    }

    if (Test-Option 'remove-xbox') {
        # Entri katalog protokol AppX untuk Game Bar yang sudah dihapus membuat Win+G
        # memunculkan "Pick an app" di Windows 11 25H2 (dibersihkan Set-TgosFeature GameBar Off).
        $overlay = @()
        try { $overlay = @(Get-AppxPackage -AllUsers -Name 'Microsoft.XboxGamingOverlay' -ErrorAction Stop) } catch { }
        $roots = @('HKLM:\SOFTWARE\Classes') + @(Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
                Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+_Classes$' } | ForEach-Object { 'Registry::HKEY_USERS\{0}' -f $_.PSChildName })
        $leftovers = 0
        foreach ($root in $roots) {
            foreach ($protocol in @('ms-gamebar', 'ms-gamebarservices', 'ms-gamingoverlay')) {
                $catalog = '{0}\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\PackageRepository\Extensions\windows.protocol\{1}' -f $root, $protocol
                foreach ($entry in @(Get-ChildItem -LiteralPath $catalog -ErrorAction SilentlyContinue)) {
                    if (@($entry.GetValueNames() | Where-Object { $_ -match '^Microsoft\.XboxGamingOverlay_' }).Count) { $leftovers++ }
                }
            }
        }
        if ($overlay.Count) {
            Add-Result 'SKIP' 'game bar' 'Win+G protocol' 'the Xbox Game Bar app is installed again' 'Set-TgosFeature.ps1'
        }
        elseif ($leftovers) {
            Add-Result 'FAIL' 'game bar' 'Win+G protocol' ('{0} leftover registration(s) of the removed Game Bar; run "Xbox Game Bar - Turn OFF" in the Toolbox' -f $leftovers) 'Set-TgosFeature.ps1'
        }
        else {
            Add-Result 'PASS' 'game bar' 'Win+G protocol' 'no leftover registration of the removed Game Bar' 'Set-TgosFeature.ps1'
        }
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
        # Penghematan daya USB mati di skema TGOS. Dua angka heksadesimal terakhir dari
        # powercfg /query = nilai AC dan baterai.
        if ($expected) {
            $usbSettings = @(
                @{ Name = 'USB selective suspend'; Guid = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' },
                @{ Name = 'USB 3 link power management'; Guid = 'd4e98f31-5ffe-4ce1-be31-1b38b384c009' })
            foreach ($usb in $usbSettings) {
                $query = (& cmd.exe /c ('powercfg.exe /query {0} 2a737441-1930-4402-8d77-b2bebba308a3 {1} 2>&1' -f $expected, $usb.Guid) | Out-String)
                $values = @([regex]::Matches($query, '0x[0-9a-fA-F]{8}') | ForEach-Object { [Convert]::ToInt32($_.Value, 16) })
                if ($LASTEXITCODE -ne 0 -or $values.Count -lt 2) {
                    Add-Result 'SKIP' 'power plan' $usb.Name 'setting not available on this PC' 'Set-PowerPlan.ps1'
                }
                elseif ($values[$values.Count - 2] -eq 0 -and $values[$values.Count - 1] -eq 0) {
                    Add-Result 'PASS' 'power plan' $usb.Name 'off on the TGOS plan' 'Set-PowerPlan.ps1'
                }
                else {
                    Add-Result 'FAIL' 'power plan' $usb.Name ("expected 0, found AC {0} / DC {1}" -f $values[$values.Count - 2], $values[$values.Count - 1]) 'Set-PowerPlan.ps1'
                }
            }
        }
    }

    if ((Test-Option 'deep-clean') -or (Test-Option 'deep-clean-plus')) {
        # Ditulis Invoke-DeepClean.ps1. Langkah yang gagal (mis. file terkunci) dicatat
        # sebagai WARNING di file itu; bersih-bersih tetap tidak fatal.
        $record = Join-Path $dataDirectory 'deep-clean.txt'
        if (-not (Test-Path -LiteralPath $record)) {
            Add-Result 'FAIL' 'deep clean' 'deep-clean.txt' 'missing: the deep clean did not run' 'Invoke-DeepClean.ps1'
        }
        else {
            $content = @(Get-Content -LiteralPath $record)
            $done = @($content | Where-Object { $_ -match 'completed:' }) | Select-Object -Last 1
            $warnings = @($content | Where-Object { $_ -match 'WARNING' })
            if ($done -and $warnings.Count -eq 0) {
                Add-Result 'PASS' 'deep clean' 'deep-clean.txt' $done.Trim() 'Invoke-DeepClean.ps1'
            }
            elseif ($done) {
                Add-Result 'WARN' 'deep clean' 'deep-clean.txt' ('{0}; {1}' -f $done.Trim(), $warnings[0].Trim()) 'Invoke-DeepClean.ps1'
            }
            else {
                Add-Result 'WARN' 'deep clean' 'deep-clean.txt' 'did not finish; run Deep Clean in the TGOS Toolbox' 'Invoke-DeepClean.ps1'
            }
        }
        $reserved = (& cmd.exe /c ('"{0}" /Online /Get-ReservedStorageState 2>&1' -f (Join-Path $env:SystemRoot 'System32\dism.exe')) | Out-String)
        if ($reserved -match '(?i)reserved storage is disabled') {
            Add-Result 'PASS' 'deep clean' 'reserved storage' 'off' 'Invoke-DeepClean.ps1'
        }
        elseif ($reserved -match '(?i)reserved storage is enabled') {
            Add-Result 'WARN' 'deep clean' 'reserved storage' 'still on (Windows may be using it for an update); use Reserved Storage - Turn OFF in the Toolbox later' 'Invoke-DeepClean.ps1'
        }
        else {
            Add-Result 'SKIP' 'deep clean' 'reserved storage' 'state could not be read on this PC' 'Invoke-DeepClean.ps1'
        }
    }

    if (Test-Option 'updates-pause') {
        # Ditulis Set-TgosFeature.ps1 -Feature UpdatePause -State Off. Tombol "Resume
        # updates" di Settings menghapusnya, jadi FAIL di sini bisa juga berarti pengguna
        # sudah melanjutkan update sendiri.
        $read = Read-RegistryValue ([Microsoft.Win32.Registry]::LocalMachine) 'SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' 'PauseUpdatesExpiryTime'
        $until = [DateTime]::MinValue
        $styles = [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal
        if (-not $read.Found) {
            Add-Result 'FAIL' 'windows update' 'pause' 'not paused (no pause end date); use Windows Updates - Pause in the Toolbox' 'Set-TgosFeature.ps1'
        }
        elseif (-not [DateTime]::TryParse([string]$read.Data, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$until)) {
            Add-Result 'FAIL' 'windows update' 'pause' ("unreadable pause end date '{0}'" -f $read.Data) 'Set-TgosFeature.ps1'
        }
        elseif ($until -gt [DateTime]::UtcNow.AddDays(30)) {
            Add-Result 'PASS' 'windows update' 'pause' ('paused until {0}' -f $until.ToString('yyyy-MM-dd')) 'Set-TgosFeature.ps1'
        }
        else {
            Add-Result 'FAIL' 'windows update' 'pause' ('pause ends soon: {0}' -f $until.ToString('yyyy-MM-dd')) 'Set-TgosFeature.ps1'
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
        $browserWanted = (Test-Option 'browser-brave') -or (Test-Option 'browser-chrome') -or (Test-Option 'browser-firefox')
        if ($edge -and $browserWanted -and -not (Test-AnyBrowser)) {
            # Bukan kegagalan: Edge sengaja dipertahankan supaya masih ada browser.
            Add-Result 'WARN' 'edge' 'Microsoft Edge' 'kept on purpose: the selected browser is not installed' 'Remove-Edge.ps1'
        }
        elseif ($edge) {
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
    try {
        Test-SoftwareResults
    }
    catch {
        Add-Result 'FAIL' 'setup' 'software results' ("check crashed: {0}" -f (($_.Exception.Message -replace '\s+', ' ').Trim())) ''
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
