<#
.SYNOPSIS
    Menjalankan playbook TGOS lewat mesin AME yang asli (TrustedUninstaller.CLI) di CI.

.DESCRIPTION
    Dipakai oleh .github/workflows/test.yml di runner Windows. Urutannya:

      1. Build .apbx dengan tools\build.ps1, lalu ekstrak hasilnya (yang diuji adalah
         arsip yang sama dengan yang dikirim ke pengguna).
      2. Unduh runner command-line AME.
      3. Uji tolak: playbook apa adanya harus berhenti di runner, karena edisi Windows
         runner bukan Pro. Tidak boleh ada perubahan sistem.
      4. Uji lolos: salinan sementara playbook dengan edisi runner diizinkan harus
         selesai tanpa error.
      5. Pemeriksaan diri (Test-TgosResult.ps1) tidak boleh menemukan FAIL.
      6. Tiap fitur TGOS Toolbox dimatikan lalu dinyalakan lagi, dan nilainya dicek.

    Log job sengaja dibuat RINGKAS (hasil tiap pemeriksaan dan cuplikan bila gagal),
    karena log itu dibaca lewat API yang menolak keluaran besar. Log lengkap mesin AME,
    potret sistem, dan laporan ada di artifact job.

    JANGAN jalankan skrip ini di komputer sendiri: skrip ini benar-benar menerapkan
    playbook ke sistem tempat ia dijalankan.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.

.PARAMETER OptionSet
    default = opsi bawaan playbook.conf (kotak yang IsChecked, DefaultOption tiap radio).
    all     = semua kotak centang dicentang; radio tetap bawaan kecuali ditimpa -Options.

.PARAMETER Options
    Opsi tambahan dipisah spasi. Opsi radio di sini menggantikan bawaan halamannya.
#>
[CmdletBinding()]
param(
    [ValidateSet('default', 'all')]
    [string]$OptionSet = 'default',
    [string]$Options = '',
    [string]$WorkDirectory,
    [int]$TimeoutMinutes = 25
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if (-not $env:GITHUB_ACTIONS) {
    throw 'This script applies the playbook to the machine it runs on. It only runs in GitHub Actions.'
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $WorkDirectory) {
    $WorkDirectory = Join-Path $env:RUNNER_TEMP 'tgos'
}
$artifacts = Join-Path $WorkDirectory 'artifacts'
New-Item -ItemType Directory -Path $artifacts -Force | Out-Null

$script:failures = @()
$script:passed = 0

# --- Keluaran ringkas ----------------------------------------------------------------

function Format-LogLine {
    # Hanya ASCII yang bisa dicetak, dan dipotong, supaya log job tetap kecil dan aman.
    param([string]$Line)
    if ($null -eq $Line) { return '' }
    $clean = [regex]::Replace($Line, '[^\x20-\x7E]', '?')
    if ($clean.Length -gt 220) { $clean = $clean.Substring(0, 220) + ' ...' }
    return $clean
}

function Write-Section {
    param([string]$Title)
    Write-Host ('== {0}' -f $Title)
}

function Show-Excerpt {
    # Mencetak paling banyak $Limit baris (yang cocok dengan $Match bila diberikan).
    param([string]$Path, [int]$Limit = 15, [string]$Match)
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host ('   (not found: {0})' -f (Split-Path -Leaf $Path))
        return
    }
    $lines = @(Get-Content -LiteralPath $Path)
    if ($Match) { $lines = @($lines | Where-Object { $_ -match $Match }) }
    $lines | Select-Object -Last $Limit | ForEach-Object { Write-Host ('   | ' + (Format-LogLine $_)) }
}

function Assert-That {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        $script:passed++
        Write-Host ('  ok    {0}' -f $Message)
    }
    else {
        $script:failures += $Message
        Write-Host ('  FAIL  {0}' -f $Message)
        Write-Host ('::error::{0}' -f $Message)
    }
    return $Condition
}

# --- Opsi ------------------------------------------------------------------------------

function Get-PlaybookOptions {
    <#
    Menyusun daftar opsi dari playbook.conf. Runner AME 0.8.4 gagal bila tidak ada opsi
    yang dikirim, jadi daftar selalu dikirim eksplisit.
    #>
    param([string]$ConfPath, [string]$Set, [string[]]$Extra)

    $conf = New-Object System.Xml.XmlDocument
    $conf.Load($ConfPath)
    $selected = New-Object System.Collections.Generic.List[string]

    foreach ($page in $conf.SelectNodes('/Playbook/FeaturePages/*')) {
        $names = @($page.SelectNodes('Options/*/Name') | ForEach-Object { $_.InnerText.Trim() })
        if ($page.Name -eq 'CheckboxPage') {
            foreach ($option in $page.SelectNodes('Options/CheckboxOption')) {
                $name = $option.SelectSingleNode('Name').InnerText.Trim()
                $checked = $option.GetAttribute('IsChecked') -ne 'false'
                if ($Set -eq 'all' -or $checked -or ($Extra -contains $name)) {
                    $selected.Add($name)
                }
            }
        }
        else {
            $override = @($names | Where-Object { $Extra -contains $_ }) | Select-Object -First 1
            if ($override) {
                $selected.Add($override)
            }
            elseif ($page.GetAttribute('DefaultOption')) {
                $selected.Add($page.GetAttribute('DefaultOption'))
            }
        }
    }

    if ($selected.Count -eq 0) {
        # Nama yang tidak dipakai playbook; hanya supaya daftar tidak kosong.
        $selected.Add('tgos-ci-no-options')
    }
    return ($selected | Select-Object -Unique)
}

# --- Mesin AME -------------------------------------------------------------------------

function Invoke-Playbook {
    param(
        [string]$CliDirectory,
        [string]$PlaybookDirectory,
        [string]$OptionList,
        [string]$Name
    )

    $exe = Join-Path $CliDirectory 'TrustedUninstaller.CLI.exe'
    $stdout = Join-Path $artifacts ('{0}-stdout.txt' -f $Name)
    $stderr = Join-Path $artifacts ('{0}-stderr.txt' -f $Name)

    $argumentList = '"{0}" {1}' -f $PlaybookDirectory, $OptionList

    # Jendela tersembunyi sendiri, bukan konsol job: proses anak mesin AME menulis
    # langsung ke konsol, dan itu membanjiri log job.
    $started = Get-Date
    $process = Start-Process -FilePath $exe -ArgumentList $argumentList -WorkingDirectory $CliDirectory `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
    # Tanpa ini ExitCode kosong di Windows PowerShell 5.1 saat keluaran dialihkan.
    $null = $process.Handle

    $timedOut = $false
    if (-not $process.WaitForExit($TimeoutMinutes * 60 * 1000)) {
        $timedOut = $true
        & taskkill.exe /PID $process.Id /T /F | Out-Null
    }
    $process.WaitForExit()
    $seconds = [int]((Get-Date) - $started).TotalSeconds

    $output = ''
    if (Test-Path -LiteralPath $stdout) { $output = Get-Content -LiteralPath $stdout -Raw }
    if ($null -eq $output) { $output = '' }

    # Log mesin AME (Output.txt dan folder Logs di folder kerjanya) dipindah ke artifact
    # supaya uji berikutnya tidak tercampur.
    $logTarget = Join-Path $artifacts ('{0}-logs' -f $Name)
    New-Item -ItemType Directory -Path $logTarget -Force | Out-Null
    foreach ($item in @('Output.txt', 'Logs')) {
        $source = Join-Path $CliDirectory $item
        if (Test-Path -LiteralPath $source) {
            Move-Item -LiteralPath $source -Destination $logTarget -Force
        }
    }

    Write-Host ('   engine exit code {0}, {1}s, timed out: {2}' -f $process.ExitCode, $seconds, $timedOut)
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output   = $output
        TimedOut = $timedOut
        Stdout   = $stdout
        Logs     = $logTarget
    }
}

function Show-EngineProblems {
    # Cuplikan untuk mencari penyebab saat sebuah uji gagal.
    param($Run)
    Write-Host '   last lines of engine output:'
    Show-Excerpt -Path $Run.Stdout -Limit 12
    if (Test-Path -LiteralPath $Run.Logs) {
        Get-ChildItem -LiteralPath $Run.Logs -Recurse -File | ForEach-Object {
            Write-Host ('   {0}: lines mentioning errors' -f $_.Name)
            Show-Excerpt -Path $_.FullName -Limit 14 -Match '[Ee]rror|[Ee]xception|[Ff]ail|REJECTED|halt|WARNING'
        }
    }
}

function Get-EngineLogSummary {
    # Hitungan baris bermasalah di log mesin AME, juga ketika uji hijau.
    param($Run)
    $errors = 0
    $warnings = 0
    $samples = @()
    $files = @()
    if (Test-Path -LiteralPath $Run.Logs) {
        foreach ($file in (Get-ChildItem -LiteralPath $Run.Logs -Recurse -File)) {
            $files += ('{0} ({1} bytes)' -f $file.Name, $file.Length)
            foreach ($line in (Get-Content -LiteralPath $file.FullName)) {
                if ($line -match '\[Error\]|\bERROR:|Exception') {
                    $errors++
                    if ($samples.Count -lt 8) { $samples += $line }
                }
                elseif ($line -match '\[Warning\]|\bWARNING:') {
                    $warnings++
                    if ($samples.Count -lt 8) { $samples += $line }
                }
            }
        }
    }
    return [pscustomobject]@{ Errors = $errors; Warnings = $warnings; Samples = $samples; Files = $files }
}

# =======================================================================================
Write-Section 'System'
$cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$runnerEdition = [string]$cv.EditionID
if ($env:PROCESSOR_ARCHITEW6432) { $runnerArch = $env:PROCESSOR_ARCHITEW6432 } else { $runnerArch = $env:PROCESSOR_ARCHITECTURE }
Write-Host ('   {0} {1} build {2}.{3}, {4}, PowerShell {5}' -f $runnerEdition, $cv.DisplayVersion, $cv.CurrentBuildNumber, $cv.UBR, $runnerArch, $PSVersionTable.PSVersion)

# =======================================================================================
Write-Section 'Build'
$buildOutput = & (Join-Path $repoRoot 'tools\build.ps1') 6>&1 | Out-String
$apbx = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'release') -Filter '*.apbx' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not (Assert-That ($null -ne $apbx) 'build.ps1 produced an .apbx (Windows PowerShell 5.1)')) {
    $buildOutput -split "`r?`n" | Select-Object -Last 15 | ForEach-Object { Write-Host ('   | ' + (Format-LogLine $_)) }
    throw 'No .apbx to test.'
}
Write-Host ('   {0}, {1} bytes' -f $apbx.Name, $apbx.Length)

$sevenZip = Get-Command 7z -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($sevenZip) { $sevenZip = $sevenZip.Source } else { $sevenZip = Join-Path $env:ProgramFiles '7-Zip\7z.exe' }

$playbook = Join-Path $WorkDirectory 'playbook'
& $sevenZip x ('-o' + $playbook) '-pmalte' '-y' '-bso0' '-bsp0' $apbx.FullName
$null = Assert-That ($LASTEXITCODE -eq 0) 'the .apbx extracts with the AME password'
$null = Assert-That (Test-Path -LiteralPath (Join-Path $playbook 'playbook.conf')) 'playbook.conf is at the archive root'

# =======================================================================================
Write-Section 'AME CLI'
try {
    Add-MpPreference -ExclusionPath $WorkDirectory -ErrorAction Stop
}
catch {
    Write-Host ('   no Defender exclusion: {0}' -f (Format-LogLine $_.Exception.Message))
}

$cliZip = Join-Path $WorkDirectory 'CLI-Standalone.zip'
$cliUrl = 'https://github.com/Ameliorated-LLC/trusted-uninstaller-cli/releases/latest/download/CLI-Standalone.zip'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $cliUrl -OutFile $cliZip -UseBasicParsing

$cliRoot = Join-Path $WorkDirectory 'cli'
Expand-Archive -LiteralPath $cliZip -DestinationPath $cliRoot -Force
$cliExe = Get-ChildItem -LiteralPath $cliRoot -Recurse -Filter 'TrustedUninstaller.CLI.exe' | Select-Object -First 1
if (-not (Assert-That ($null -ne $cliExe) 'TrustedUninstaller.CLI.exe downloaded')) { throw 'AME CLI not found.' }
$cliDirectory = $cliExe.Directory.FullName
Write-Host ('   version {0}, SHA256 {1}' -f $cliExe.VersionInfo.FileVersion, (Get-FileHash -LiteralPath $cliZip -Algorithm SHA256).Hash)

# =======================================================================================
$toolboxSupport = Join-Path $playbook 'Executables\TGOS Toolbox\Support'
$snapshotScript = Join-Path $toolboxSupport 'Get-SystemSnapshot.ps1'
& $snapshotScript -Label before -OutputDirectory $artifacts 3>$null 6>$null | Out-Null

$installInfo = Join-Path $env:ProgramData 'TGOS\install-info.txt'
$extraOptions = @($Options -split '\s+' | Where-Object { $_ })
$optionList = (Get-PlaybookOptions -ConfPath (Join-Path $playbook 'playbook.conf') -Set $OptionSet -Extra $extraOptions) -join ' '
Write-Section ('Options ({0}): {1}' -f $OptionSet, $optionList)

# =======================================================================================
Write-Section ('Reject test (runner is {0} {1}; TGOS accepts only Professional AMD64)' -f $runnerEdition, $runnerArch)
if ($runnerEdition -eq 'Professional' -and $runnerArch -eq 'AMD64') {
    Write-Host '   runner is Windows Pro x64; the reject test does not apply'
}
else {
    $reject = Invoke-Playbook -CliDirectory $cliDirectory -PlaybookDirectory $playbook -OptionList $optionList -Name 'reject'
    $ok = Assert-That (-not $reject.TimedOut) 'reject: the engine did not hang'
    $ok = (Assert-That ($reject.Output -notmatch 'YAML Error') 'reject: the engine accepted the YAML') -and $ok
    $ok = (Assert-That ($reject.Output -notmatch 'Playbook completed successfully') 'reject: the engine did not report success') -and $ok
    $ok = (Assert-That (-not (Test-Path -LiteralPath $installInfo)) 'reject: install-info.txt was NOT written (halted before any module)') -and $ok
    $ok = (Assert-That (-not (Test-Path -LiteralPath (Join-Path ('{0}\' -f $env:SystemDrive) 'TGOS Toolbox'))) 'reject: the Toolbox was NOT installed') -and $ok
    if (-not $ok) { Show-EngineProblems $reject }
}

# =======================================================================================
Write-Section 'Pass test (runner edition allowed)'
$playbookPass = Join-Path $WorkDirectory 'playbook-pass'
Copy-Item -LiteralPath $playbook -Destination $playbookPass -Recurse -Force
$compatibility = Join-Path $playbookPass 'Executables\Scripts\Test-Compatibility.ps1'
$original = "`$AllowedEditions = @('Professional')"
$patched = "`$AllowedEditions = @('Professional', '{0}')" -f $runnerEdition
$originalArch = "if (`$Architecture -ne 'AMD64') {"
$patchedArch = "if (`$Architecture -ne 'AMD64' -and `$Architecture -ne '{0}') {{" -f $runnerArch
$content = Get-Content -LiteralPath $compatibility -Raw
$null = Assert-That ($content.Contains($original) -and $content.Contains($originalArch)) 'pass: the edition and architecture checks were found for patching'
Set-Content -LiteralPath $compatibility -Value $content.Replace($original, $patched).Replace($originalArch, $patchedArch) -Encoding ASCII

# Image runner sudah menonaktifkan sebagian tugas telemetri. Supaya penonaktifan oleh
# TGOS benar-benar teruji, tugas di daftar yang ada diaktifkan dulu.
$enabledTasks = @()
$taskList = Join-Path $playbook 'Executables\TGOS\scheduled-tasks.txt'
foreach ($entry in (Get-Content -LiteralPath $taskList | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })) {
    $separator = $entry.LastIndexOf('\')
    $task = Get-ScheduledTask -TaskPath $entry.Substring(0, $separator + 1) -TaskName $entry.Substring($separator + 1) -ErrorAction SilentlyContinue
    if ($task) {
        try {
            $task | Enable-ScheduledTask -ErrorAction Stop | Out-Null
            $enabledTasks += $task
        }
        catch {
            Write-Host ('   could not enable {0} for the test: {1}' -f $entry, (Format-LogLine $_.Exception.Message))
        }
    }
}
Write-Host ('   {0} listed task(s) enabled before the run' -f $enabledTasks.Count)

$pass = Invoke-Playbook -CliDirectory $cliDirectory -PlaybookDirectory $playbookPass -OptionList $optionList -Name 'pass'
$ok = Assert-That (-not $pass.TimedOut) 'pass: the engine did not hang'
$ok = (Assert-That ($pass.Output -notmatch 'YAML Error|Fatal Playbook Error') 'pass: no YAML or fatal error') -and $ok
$ok = (Assert-That ($pass.Output -match 'Playbook completed successfully') 'pass: the engine reported "Playbook completed successfully."') -and $ok
$ok = (Assert-That (Test-Path -LiteralPath $installInfo) 'pass: install-info.txt was written') -and $ok
if (-not $ok) { Show-EngineProblems $pass }

$summary = Get-EngineLogSummary $pass
Write-Host ('   engine log files: {0}' -f ($summary.Files -join '; '))
Write-Host ('   engine log: {0} error line(s), {1} warning line(s)' -f $summary.Errors, $summary.Warnings)
$summary.Samples | ForEach-Object { Write-Host ('   | ' + (Format-LogLine $_)) }

# Baris yang ditulis skrip TGOS sendiri: hasil tiap skrip, termasuk yang tidak fatal.
$engineOutput = Join-Path $pass.Logs 'Output.txt'
if (Test-Path -LiteralPath $engineOutput) {
    Write-Host '   TGOS script results in the engine log:'
    Get-Content -LiteralPath $engineOutput |
        Where-Object { $_ -match 'TGOS: (?!recorded option)|PASSED:|REJECTED:|SUMMARY:' -or $_ -match 'WARNING: ' } |
        ForEach-Object { ($_ -replace '^.*?(TGOS: |PASSED:|REJECTED:|SUMMARY:|WARNING: )', '$1') } |
        Select-Object -First 30 | ForEach-Object { Write-Host ('   | ' + (Format-LogLine $_)) }
}

Write-Host '   install-info.txt:'
Show-Excerpt -Path $installInfo -Limit 20

if ($enabledTasks.Count -gt 0) {
    $stillEnabled = @($enabledTasks | Where-Object {
            $task = Get-ScheduledTask -TaskPath $_.TaskPath -TaskName $_.TaskName -ErrorAction SilentlyContinue
            $task -and [string]$task.State -ne 'Disabled'
        })
    $null = Assert-That ($stillEnabled.Count -eq 0) ('pass: all {0} task(s) enabled before the run are now Disabled' -f $enabledTasks.Count)
    $stillEnabled | ForEach-Object { Write-Host ('   still enabled: {0}{1}' -f $_.TaskPath, $_.TaskName) }
}

# =======================================================================================
Write-Section 'Self-verification'
$installedSupport = Join-Path ('{0}\' -f $env:SystemDrive) 'TGOS Toolbox\Support'
$verifyScript = Join-Path $installedSupport 'Test-TgosResult.ps1'
$verifyReport = Join-Path $artifacts 'verify-report.txt'
if (Assert-That (Test-Path -LiteralPath $verifyScript) 'verify: Test-TgosResult.ps1 is installed with the Toolbox') {
    & $verifyScript -ReportPath $verifyReport | Out-Null
    $reportLines = @()
    if (Test-Path -LiteralPath $verifyReport) { $reportLines = @(Get-Content -LiteralPath $verifyReport) }
    $summaryLine = @($reportLines | Where-Object { $_ -match '^SUMMARY:' }) | Select-Object -Last 1
    Write-Host ('   {0}' -f $summaryLine)
    $failed = @($reportLines | Where-Object { $_ -match '^FAIL' })
    $null = Assert-That ($summaryLine -and $failed.Count -eq 0) 'verify: no FAIL in the verification report'
    $reportLines | Where-Object { $_ -match '^(FAIL|WARN)' } | Select-Object -First 25 |
        ForEach-Object { Write-Host ('   | ' + (Format-LogLine $_)) }
    # SKIP dihitung per alasan, supaya terlihat apa yang tidak teruji di runner ini.
    $reportLines | Where-Object { $_ -match '^SKIP' } |
        ForEach-Object { if ($_ -match '->\s+(.+?)\s+\[') { $Matches[1] -replace "'[^']*'", "'...'" -replace '\d{5}', 'N' } } |
        Group-Object | Sort-Object Count -Descending | Select-Object -First 8 |
        ForEach-Object { Write-Host ('   skip x{0}: {1}' -f $_.Count, (Format-LogLine $_.Name)) }
}

# =======================================================================================
Write-Section 'Toolbox round trips'
$featureScript = Join-Path $installedSupport 'Set-TgosFeature.ps1'
if (Assert-That (Test-Path -LiteralPath $featureScript) 'toolbox: Set-TgosFeature.ps1 is installed') {
    # Tiap fitur: nilai registry yang harus terlihat setelah Off, dan setelah On.
    # $null berarti nilainya harus tidak ada.
    $cases = @(
        @{ Feature = 'Vbs'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; Name = 'EnableVirtualizationBasedSecurity'; Off = 0; On = 1 },
        @{ Feature = 'Mitigations'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; Name = 'FeatureSettingsOverride'; Off = 3; On = $null },
        @{ Feature = 'AutoUpdate'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Name = 'NoAutoUpdate'; Off = 1; On = $null },
        @{ Feature = 'Indexing'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\WSearch'; Name = 'Start'; Off = 4; On = 2 },
        @{ Feature = 'Hibernation'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name = 'HiberbootEnabled'; Off = 0; On = 1 },
        @{ Feature = 'Defender'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableRealtimeMonitoring'; Off = 1; On = $null }
    )

    function Get-Value {
        param([string]$Path, [string]$Name)
        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
        if ($null -eq $item) { return $null }
        return $item.$Name
    }

    foreach ($case in $cases) {
        foreach ($state in @('Off', 'On')) {
            # Lewat cmd: di Windows PowerShell 5.1, stderr proses anak yang dialihkan
            # menjadi error yang menghentikan skrip ini.
            $command = 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Feature {1} -State {2} 2>&1' -f $featureScript, $case.Feature, $state
            $output = & cmd.exe /c $command | Out-String
            $exit = $LASTEXITCODE
            if ($exit -eq 3) {
                Write-Host ('  skip  toolbox: {0} {1} is not supported on this runner' -f $case.Feature, $state)
                continue
            }
            if ($case.Feature -eq 'Defender' -and $state -eq 'Off' -and $exit -eq 2) {
                # Perilaku yang dirancang di Windows 11: selama Tamper Protection aktif,
                # skrip menolak, menjelaskan caranya, dan tidak mengubah apa pun.
                $untouched = ($null -eq (Get-Value -Path $case.Path -Name $case.Name))
                $null = Assert-That ($untouched -and $output -match 'Tamper Protection') 'toolbox: Defender Off is refused while Tamper Protection is on, and changes nothing'
                continue
            }
            $actual = Get-Value -Path $case.Path -Name $case.Name
            $expected = $case[$state]
            if ($null -eq $expected) { $same = ($null -eq $actual) } else { $same = ($actual -eq $expected) }
            if ($null -eq $expected) { $expectedText = '(absent)' } else { $expectedText = [string]$expected }
            $label = 'toolbox: {0} {1} -> exit 0 and {2} = {3}' -f $case.Feature, $state, $case.Name, $expectedText
            if (-not (Assert-That ($exit -eq 0 -and $same) $label)) {
                if ($null -eq $actual) { $actualText = '(absent)' } else { $actualText = [string]$actual }
                Write-Host ('   exit {0}, actual value: {1}' -f $exit, $actualText)
                $output -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 4 | ForEach-Object { Write-Host ('   | ' + (Format-LogLine $_)) }
            }
        }
    }
}

# =======================================================================================
Write-Section 'Report collector'
$collectScript = Join-Path $installedSupport 'Collect-TgosReport.ps1'
if (Assert-That (Test-Path -LiteralPath $collectScript) 'collect: Collect-TgosReport.ps1 is installed') {
    $command = 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -OutputDirectory "{1}" -Label after 2>&1' -f $collectScript, $artifacts
    $collectOutput = & cmd.exe /c $command | Out-String
    $zip = Join-Path $artifacts 'TGOS-report.zip'
    if (Assert-That (Test-Path -LiteralPath $zip) 'collect: TGOS-report.zip was created') {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
        try { $entries = @($archive.Entries | ForEach-Object { $_.FullName }) } finally { $archive.Dispose() }
        $null = Assert-That ($entries -contains 'verify-report.txt') 'collect: the zip contains verify-report.txt'
        $null = Assert-That (@($entries | Where-Object { $_ -like 'TGOS-snapshot-*.json' }).Count -eq 1) 'collect: the zip contains the system snapshot'
        Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $artifacts 'report') -Force
    }
    else {
        $collectOutput -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 6 | ForEach-Object { Write-Host ('   | ' + (Format-LogLine $_)) }
    }
}

# =======================================================================================
$python = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$after = Get-ChildItem -LiteralPath (Join-Path $artifacts 'report') -Filter 'TGOS-snapshot-*.json' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($python -and $after) {
    Write-Section 'Before / after'
    $command = '"{0}" "{1}" "{2}" "{3}" 2>&1' -f $python.Source, (Join-Path $repoRoot 'tools\compare-snapshots.py'), (Join-Path $artifacts 'TGOS-snapshot-before.json'), $after.FullName
    $compare = & cmd.exe /c ('"{0}"' -f $command) | Out-String
    $compareExit = $LASTEXITCODE
    Set-Content -LiteralPath (Join-Path $artifacts 'compare.txt') -Value $compare -Encoding ASCII
    $compare -split "`r?`n" | Where-Object { $_ -match 'Proses|RAM terpakai|Layanan berjalan|Paket AppX:|^Layanan:|^Tugas terjadwal:|Defender|BAHAYA|^\s+!|Selesai' } |
        Select-Object -First 20 | ForEach-Object { Write-Host ('   | ' + (Format-LogLine $_)) }
    $null = Assert-That ($compareExit -eq 0) 'compare: nothing to investigate between the snapshots'
}

# =======================================================================================
Write-Section 'Result'
Write-Host ('CI SUMMARY: {0} passed, {1} failed' -f $script:passed, $script:failures.Count)
if ($script:failures.Count -gt 0) {
    $script:failures | ForEach-Object { Write-Host ('  - {0}' -f $_) }
    exit 1
}
exit 0
