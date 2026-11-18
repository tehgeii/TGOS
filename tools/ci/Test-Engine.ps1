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

.PARAMETER ForceItems
    Program (dipisah spasi) yang diunduh dan dipasang ulang setelah playbook selesai,
    lewat skrip di TGOS Toolbox. Image runner sudah berisi Chrome, Firefox, dan 7-Zip,
    jadi tanpa ini jalur unduh dan pemeriksaan tanda tangan untuk program itu tidak
    teruji (skrip hanya berkata "already installed").
#>
[CmdletBinding()]
param(
    [ValidateSet('default', 'all')]
    [string]$OptionSet = 'default',
    [string]$Options = '',
    [string]$ForceItems = '',
    [string]$WorkDirectory,
    [int]$TimeoutMinutes = 60
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

# Meniru AME Wizard: Wizard adalah aplikasi GUI tanpa konsol, jadi proses yang dibuatnya
# tanpa CREATE_NO_WINDOW mendapat konsol BARU. CLI di sini dijalankan dengan
# DETACHED_PROCESS (tanpa konsol) dan keluarannya dialihkan ke file, supaya pemantau
# jendela melihat apa yang dilihat pengguna Wizard (uji VM revisi kedua 1.0.0: jendela
# terminal kosong di akhir instalasi, yang tidak pernah terlihat di CI).
Add-Type -Namespace TgosCi -Name Detached -MemberDefinition @'
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public struct StartupInfo {
    public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
    public int dwX; public int dwY; public int dwXSize; public int dwYSize; public int dwXCountChars; public int dwYCountChars;
    public int dwFillAttribute; public int dwFlags; public short wShowWindow; public short cbReserved2;
    public System.IntPtr lpReserved2; public System.IntPtr hStdInput; public System.IntPtr hStdOutput; public System.IntPtr hStdError;
}
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct ProcessInformation { public System.IntPtr hProcess; public System.IntPtr hThread; public int dwProcessId; public int dwThreadId; }
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
static extern bool CreateProcess(string app, System.Text.StringBuilder command, System.IntPtr pa, System.IntPtr ta, bool inherit, uint flags, System.IntPtr env, string cwd, ref StartupInfo si, out ProcessInformation pi);
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
static extern bool SetHandleInformation(System.IntPtr handle, uint mask, uint flags);
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
static extern uint WaitForSingleObject(System.IntPtr handle, uint milliseconds);
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
static extern bool GetExitCodeProcess(System.IntPtr handle, out uint code);
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
static extern bool CloseHandle(System.IntPtr handle);
// Mengembalikan kode keluar, atau -100000 bila melewati batas waktu (pemanggil menghentikan prosesnya).
public static long Run(string exe, string arguments, string cwd, string stdoutPath, string stderrPath, int timeoutMs, out int processId) {
    using (var output = new System.IO.FileStream(stdoutPath, System.IO.FileMode.Create, System.IO.FileAccess.Write, System.IO.FileShare.ReadWrite))
    using (var error = new System.IO.FileStream(stderrPath, System.IO.FileMode.Create, System.IO.FileAccess.Write, System.IO.FileShare.ReadWrite)) {
        System.IntPtr outHandle = output.SafeFileHandle.DangerousGetHandle();
        System.IntPtr errHandle = error.SafeFileHandle.DangerousGetHandle();
        SetHandleInformation(outHandle, 1, 1);
        SetHandleInformation(errHandle, 1, 1);
        var si = new StartupInfo();
        si.cb = System.Runtime.InteropServices.Marshal.SizeOf(typeof(StartupInfo));
        si.dwFlags = 0x100;
        si.hStdOutput = outHandle;
        si.hStdError = errHandle;
        ProcessInformation pi;
        var command = new System.Text.StringBuilder("\"" + exe + "\" " + arguments);
        // 0x8 = DETACHED_PROCESS
        if (!CreateProcess(null, command, System.IntPtr.Zero, System.IntPtr.Zero, true, 0x8, System.IntPtr.Zero, cwd, ref si, out pi)) {
            throw new System.ComponentModel.Win32Exception();
        }
        processId = pi.dwProcessId;
        uint wait = WaitForSingleObject(pi.hProcess, (uint)timeoutMs);
        long result = -100000;
        if (wait == 0) { uint code; GetExitCodeProcess(pi.hProcess, out code); result = unchecked((int)code); }
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        return result;
    }
}
'@

function Invoke-Playbook {
    param(
        [string]$CliDirectory,
        [string]$PlaybookDirectory,
        [string]$OptionList,
        [string]$Name,
        [switch]$Detached
    )

    $exe = Join-Path $CliDirectory 'TrustedUninstaller.CLI.exe'
    $stdout = Join-Path $artifacts ('{0}-stdout.txt' -f $Name)
    $stderr = Join-Path $artifacts ('{0}-stderr.txt' -f $Name)

    $argumentList = '"{0}" {1}' -f $PlaybookDirectory, $OptionList

    # Jendela tersembunyi sendiri, bukan konsol job: proses anak mesin AME menulis
    # langsung ke konsol, dan itu membanjiri log job.
    $started = Get-Date
    $timedOut = $false
    if ($Detached) {
        $processId = 0
        $exitCode = [TgosCi.Detached]::Run($exe, $argumentList, $CliDirectory, $stdout, $stderr, $TimeoutMinutes * 60 * 1000, [ref]$processId)
        if ($exitCode -eq -100000) {
            $timedOut = $true
            & taskkill.exe /PID $processId /T /F | Out-Null
            Start-Sleep -Seconds 5
        }
    }
    else {
        $process = Start-Process -FilePath $exe -ArgumentList $argumentList -WorkingDirectory $CliDirectory `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
        # Tanpa ini ExitCode kosong di Windows PowerShell 5.1 saat keluaran dialihkan.
        $null = $process.Handle
        if (-not $process.WaitForExit($TimeoutMinutes * 60 * 1000)) {
            $timedOut = $true
            & taskkill.exe /PID $process.Id /T /F | Out-Null
        }
        $process.WaitForExit()
        $exitCode = $process.ExitCode
    }
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

    Write-Host ('   engine exit code {0}, {1}s, timed out: {2}{3}' -f $exitCode, $seconds, $timedOut, $(if ($Detached) { ', started without a console like AME Wizard' } else { '' }))
    return [pscustomobject]@{
        ExitCode = $exitCode
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
    # Baris yang sama (selain jamnya) dikelompokkan, supaya satu pesan yang berulang
    # tidak menutupi pesan lain.
    $errors = 0
    $warnings = 0
    $groups = New-Object System.Collections.Specialized.OrderedDictionary
    $files = @()
    if (Test-Path -LiteralPath $Run.Logs) {
        foreach ($file in (Get-ChildItem -LiteralPath $Run.Logs -Recurse -File)) {
            $files += ('{0} ({1} bytes)' -f $file.Name, $file.Length)
            foreach ($line in (Get-Content -LiteralPath $file.FullName)) {
                if ($line -match '\[Error\]|\bERROR:|Exception') { $errors++ }
                elseif ($line -match '\[Warning\]|\bWARNING:') { $warnings++ }
                else { continue }
                $key = $line -replace '\d{2}:\d{2}:\d{2}', '..:..:..'
                if ($groups.Contains($key)) { $groups[$key] = $groups[$key] + 1 }
                else { $groups.Add($key, 1) }
            }
        }
    }
    $samples = @()
    foreach ($key in $groups.Keys) {
        if ($samples.Count -ge 10) { break }
        $samples += ('x{0}  {1}' -f $groups[$key], $key)
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
Write-Section 'Installer safety checks'
$playbookScripts = Join-Path $playbook 'Executables\Scripts'
$scratchData = Join-Path $WorkDirectory 'scratch-data'
New-Item -ItemType Directory -Path $scratchData -Force | Out-Null

# Unduhan yang gagal tidak boleh menghentikan apa pun: skrip melapor, mencatat, selesai.
$command = 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Item firefox -Force -UrlOverride "https://tgos-ci.invalid/setup.exe" -DataDirectory "{1}" 2>&1' -f (Join-Path $playbookScripts 'Install-Software.ps1'), $scratchData
$output = & cmd.exe /c $command | Out-String
$exit = $LASTEXITCODE
$record = @()
if (Test-Path -LiteralPath (Join-Path $scratchData 'software.txt')) { $record = @(Get-Content -LiteralPath (Join-Path $scratchData 'software.txt')) }
$ok = ($exit -eq 1) -and ($output -match 'WARNING: Mozilla Firefox was not installed') -and (@($record | Where-Object { $_ -match '^firefox: failed' }).Count -eq 1)
if (-not (Assert-That $ok 'software: a failed download is reported and recorded, and nothing is run')) {
    Write-Host ('   exit {0}' -f $exit)
    $output -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 4 | ForEach-Object { Write-Host ('   | ' + (Format-LogLine $_)) }
}

# Pengaman Edge: bila browser yang diminta tidak terpasang, Edge tidak dihapus.
$edgeExe = @(${env:ProgramFiles(x86)}, $env:ProgramFiles) | Where-Object { $_ } |
    ForEach-Object { Join-Path $_ 'Microsoft\Edge\Application\msedge.exe' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($edgeExe) {
    Set-Content -LiteralPath (Join-Path $scratchData 'software.txt') -Value 'brave: requested' -Encoding ASCII
    $command = 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -DataDirectory "{1}" -AssumeNoBrowser 2>&1' -f (Join-Path $playbookScripts 'Remove-Edge.ps1'), $scratchData
    $output = & cmd.exe /c $command | Out-String
    $ok = ($output -match 'Microsoft Edge was kept') -and (Test-Path -LiteralPath $edgeExe)
    if (-not (Assert-That $ok 'edge: kept when the requested browser is not installed')) {
        $output -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 4 | ForEach-Object { Write-Host ('   | ' + (Format-LogLine $_)) }
    }
}
else {
    Write-Host '  skip  edge: Microsoft Edge is not installed on this runner'
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

# Image runner sudah berisi Chrome, Firefox, dan 7-Zip. Supaya pemasangan oleh playbook
# (sebagai sistem, lewat mesin AME) benar-benar teruji, program yang dipilih job ini
# dicopot dulu. Fungsi bersama diambil dari Common.ps1 playbook.
. (Join-Path $playbook 'Executables\Scripts\Common.ps1')
$plannedOptions = @($optionList -split '\s+' | Where-Object { $_ })
$preinstalled = @(
    @{ Option = 'browser-chrome'; Name = 'Google Chrome'; Pattern = '^Google Chrome$'; Relative = 'Google\Chrome\Application\chrome.exe'; Silent = '--force-uninstall' },
    @{ Option = 'browser-firefox'; Name = 'Mozilla Firefox'; Pattern = '^Mozilla Firefox'; Relative = 'Mozilla Firefox\firefox.exe'; Silent = '/S' },
    @{ Option = 'install-7zip'; Name = '7-Zip'; Pattern = '^7-Zip'; Relative = '7-Zip\7z.exe'; Silent = '/S' })
foreach ($program in $preinstalled) {
    if ($plannedOptions -notcontains $program.Option) { continue }
    $exePath = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } |
        ForEach-Object { Join-Path $_ $program.Relative } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $exePath) {
        Write-Host ('   {0} is not on this runner; the playbook installs it from scratch' -f $program.Name)
        continue
    }
    # Entri MSI lebih dulu: uninstall MSI ikut menghapus program, dan pendaftaran MSI yang
    # tertinggal bisa membuat pemasangan MSI berikutnya tidak memasang apa-apa.
    $entries = @(Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match $program.Pattern -and $_.UninstallString } |
        Sort-Object { if ([string]$_.UninstallString -match '(?i)msiexec') { 0 } else { 1 } })
    foreach ($entry in $entries) {
        try {
            if ([string]$entry.UninstallString -match '(?i)msiexec') {
                $code = Invoke-TgosProcess -File (Join-Path $env:SystemRoot 'System32\msiexec.exe') -Arguments ('/x {0} /qn /norestart' -f $entry.PSChildName)
            }
            else {
                $command = Split-TgosCommandLine ([string]$entry.UninstallString)
                if (-not $command -or -not (Test-Path -LiteralPath $command.File)) {
                    Write-Host ('   skipped uninstall entry {0}: its uninstaller is already gone' -f $entry.DisplayName)
                    continue
                }
                $code = Invoke-TgosProcess -File $command.File -Arguments (($command.Arguments + ' ' + $program.Silent).Trim())
            }
            Write-Host ('   uninstalled {0} ({1}) before the run: exit {2}' -f $program.Name, $entry.DisplayName, $code)
        }
        catch {
            Write-Host ('   could not run the uninstaller of {0}: {1}' -f $entry.DisplayName, (Format-LogLine $_.Exception.Message))
        }
    }
    $gone = $false
    for ($attempt = 0; $attempt -lt 30 -and -not $gone; $attempt++) {
        $gone = -not (Test-Path -LiteralPath $exePath)
        if (-not $gone) { Start-Sleep -Seconds 2 }
    }
    $null = Assert-That $gone ('setup: preinstalled {0} removed, so the playbook must install it' -f $program.Name)
}

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

# DiagTrack harus berjalan sebelum playbook, supaya penghentiannya oleh TGOS teruji (uji
# VM v1.0.0: selama DiagTrack masih jalan, nilai perekam telemetri hilang setelah restart).
$diagTrack = Get-Service -Name 'DiagTrack' -ErrorAction SilentlyContinue
if ($diagTrack -and [string]$diagTrack.Status -ne 'Running') {
    try {
        Set-Service -Name 'DiagTrack' -StartupType Automatic
        Start-Service -Name 'DiagTrack'
    }
    catch {
        Write-Host ('   could not start DiagTrack for the test: {0}' -f (Format-LogLine $_.Exception.Message))
    }
}
if ($diagTrack) { Write-Host ('   DiagTrack before the run: {0}' -f (Get-Service -Name 'DiagTrack').Status) }
else { Write-Host '   DiagTrack is not on this runner' }

# Terminal bawaan seperti di PC pengguna Windows 11 (VM pemilik): Windows Terminal. Runner
# memakai Windows Console Host, sehingga jendela terminal kosong di VM pemilik tidak pernah
# terlihat di CI. Kontrol: konsol tersembunyi dengan Windows Terminal sebagai bawaan
# (diharapkan terlihat) dan dengan Console Host (diharapkan tidak).
$startupKey = 'HKCU:\Console\%%Startup'
$terminalGuids = @{ DelegationConsole = '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}'; DelegationTerminal = '{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}' }
$consoleHostGuid = '{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}'
function Set-TestTerminal {
    param([string]$Console, [string]$Terminal)
    if (-not (Test-Path -LiteralPath $startupKey)) { New-Item -Path $startupKey -Force | Out-Null }
    Set-ItemProperty -LiteralPath $startupKey -Name 'DelegationConsole' -Value $Console -Type String
    Set-ItemProperty -LiteralPath $startupKey -Name 'DelegationTerminal' -Value $Terminal -Type String
}
function Test-HiddenConsoleWindow {
    $before = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | ForEach-Object { $_.Id })
    $null = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList '/c ping -n 8 127.0.0.1 >nul' -WindowStyle Hidden -PassThru
    $seen = @{}
    for ($attempt = 0; $attempt -lt 14; $attempt++) {
        Start-Sleep -Milliseconds 500
        foreach ($process in @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $before -notcontains $_.Id -and $_.ProcessName -ne 'wsl' })) {
            $seen[$process.Id] = '{0} "{1}"' -f $process.ProcessName, $process.MainWindowTitle
        }
    }
    Get-Process -Name 'WindowsTerminal', 'OpenConsole' -ErrorAction SilentlyContinue | Where-Object { $before -notcontains $_.Id } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 4
    return @($seen.Values)
}
$terminalPackage = Get-AppxPackage -Name 'Microsoft.WindowsTerminal' -ErrorAction SilentlyContinue | Select-Object -First 1
$terminalEmulated = $false
if ($terminalPackage) {
    Write-Host ('   Windows Terminal {0} is installed for the test user' -f $terminalPackage.Version)
    Set-TestTerminal $terminalGuids.DelegationConsole $terminalGuids.DelegationTerminal
    $withTerminal = @(Test-HiddenConsoleWindow)
    Set-TestTerminal $consoleHostGuid $consoleHostGuid
    $withConsoleHost = @(Test-HiddenConsoleWindow)
    Write-Host ('   control: hidden console with Windows Terminal as default -> {0}' -f $(if ($withTerminal.Count) { 'VISIBLE: ' + ($withTerminal -join ', ') } else { 'no window' }))
    Write-Host ('   control: hidden console with Windows Console Host as default -> {0}' -f $(if ($withConsoleHost.Count) { 'VISIBLE: ' + ($withConsoleHost -join ', ') } else { 'no window' }))
    # Untuk playbook: seperti VM pemilik.
    Set-TestTerminal $terminalGuids.DelegationConsole $terminalGuids.DelegationTerminal
    $terminalEmulated = $true
}
else {
    Write-Host '   Windows Terminal is not installed on this runner; the default terminal is Windows Console Host'
}

# OneDrive berjalan seperti di PC pengguna baru. Uji VM revisi ketiga 1.0.0: sisa
# uninstaller OneDrive (file ListSync masih dikunci Microsoft.SharePoint.exe) memunculkan
# jendela cmd "rd /s" saat Explorer dinyalakan ulang di akhir instalasi. Di runner, OneDrive
# biasanya belum pernah dipasang untuk akun uji, jadi jalur itu tidak pernah teruji.
$oneDriveFamily = @('OneDrive', 'OneDriveStandaloneUpdater', 'Microsoft.SharePoint', 'FileCoAuth', 'OneDriveLauncher', 'OneDriveFileLauncher')
$oneDriveEmulated = $false
$runOnceKeys = @('HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce')
function Get-RunOnceEntry {
    foreach ($key in $runOnceKeys) {
        $item = Get-Item -LiteralPath $key -ErrorAction SilentlyContinue
        if (-not $item) { continue }
        foreach ($valueName in @($item.GetValueNames() | Where-Object { $_ })) {
            '{0} | {1} = {2}' -f ($key -replace ':', ''), $valueName, $item.GetValue($valueName, '', 'DoNotExpandEnvironmentNames')
        }
    }
}
@(Get-RunOnceEntry) | ForEach-Object { Write-Host ('   RunOnce before the playbook: {0}' -f (Format-LogLine $_)) }
if ($plannedOptions -contains 'remove-onedrive') {
    $oneDriveSetup = @((Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'), (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe')) |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    $oneDriveExe = Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'
    if (-not $oneDriveSetup) {
        Write-Host '   OneDriveSetup.exe is not on this runner; the OneDrive cleanup is not exercised here'
    }
    else {
        if (-not (Test-Path -LiteralPath $oneDriveExe)) {
            $started = Get-Date
            try {
                $setupProcess = Start-Process -FilePath $oneDriveSetup -ArgumentList '/silent' -PassThru -WindowStyle Hidden
                $null = $setupProcess.WaitForExit(300000)
            }
            catch { Write-Host ('   OneDriveSetup /silent failed: {0}' -f (Format-LogLine $_.Exception.Message)) }
            for ($second = 0; $second -lt 120 -and -not (Test-Path -LiteralPath $oneDriveExe); $second += 5) { Start-Sleep -Seconds 5 }
            Write-Host ('   OneDrive per-user install for the test user: {0} ({1}s)' -f $(if (Test-Path -LiteralPath $oneDriveExe) { 'installed' } else { 'not installed' }), [int]((Get-Date) - $started).TotalSeconds)
        }
        if (Test-Path -LiteralPath $oneDriveExe) {
            if (-not (Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue)) { $null = Start-Process -FilePath $oneDriveExe -ArgumentList '/background' -PassThru }
            Start-Sleep -Seconds 45
            $running = @(Get-Process -Name $oneDriveFamily -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName } | Sort-Object -Unique)
            Write-Host ('   OneDrive processes before the playbook: {0}' -f $(if ($running.Count) { $running -join ', ' } else { 'none' }))
            Write-Host ('   OneDrive ListSync folder present: {0}' -f (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\ListSync')))
            $oneDriveEmulated = $running -contains 'OneDrive'
        }
    }
}

# Jejak pembuatan proses selama playbook: setiap konsol baru (conhost.exe) dan setiap
# penyerahan ke Windows Terminal (OpenConsole.exe, WindowsTerminal.exe), dengan proses
# induknya, supaya terlihat program mana yang membuka konsol.
$traceLog = Join-Path $artifacts 'process-trace.txt'
Set-Content -LiteralPath $traceLog -Value @() -Encoding ASCII
$tracer = Start-Job -ArgumentList $traceLog -ScriptBlock {
    param($Path)
    foreach ($process in @(Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue)) {
        Add-Content -LiteralPath $Path -Value ('INIT|{0}|{1}|{2}' -f $process.ProcessId, $process.ParentProcessId, $process.Name) -Encoding ASCII
    }
    Register-CimIndicationEvent -Query 'SELECT * FROM Win32_ProcessStartTrace' -SourceIdentifier 'TgosTrace' -ErrorAction Stop
    Add-Content -LiteralPath $Path -Value 'READY' -Encoding ASCII
    while ($true) {
        foreach ($event in @(Get-Event -SourceIdentifier 'TgosTrace' -ErrorAction SilentlyContinue)) {
            $new = $event.SourceEventArgs.NewEvent
            $line = '{0:HH:mm:ss}|{1}|{2}|{3}' -f $event.TimeGenerated, $new.ProcessID, $new.ParentProcessID, $new.ProcessName
            if ($new.ProcessName -match '(?i)^cmd\.exe$') {
                # Baris perintah cmd.exe (bila prosesnya masih ada), untuk melihat siapa yang
                # menjalankan perintah apa.
                $commandLine = ''
                try { $commandLine = [string](Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId={0}' -f $new.ProcessID) -ErrorAction Stop).CommandLine } catch { }
                $line += '|' + (($commandLine -replace '\|', '/') -replace '\s+', ' ')
            }
            Add-Content -LiteralPath $Path -Value $line -Encoding ASCII
            Remove-Event -EventIdentifier $event.EventIdentifier
        }
        Start-Sleep -Milliseconds 200
    }
}
for ($attempt = 0; $attempt -lt 120; $attempt++) {
    if (@(Get-Content -LiteralPath $traceLog -ErrorAction SilentlyContinue) -contains 'READY') { break }
    Start-Sleep -Milliseconds 500
}
Write-Host ('   process trace: {0}' -f $(if (@(Get-Content -LiteralPath $traceLog -ErrorAction SilentlyContinue) -contains 'READY') { 'running' } else { 'did not start' }))

# Pemantau jendela selama seluruh playbook (permintaan pemilik: semua harus berjalan di
# latar, tanpa jendela). Proses terpisah mencatat setiap proses baru yang punya jendela
# terlihat. Kontrol dulu: jendela Notepad harus tercatat, kalau tidak hasilnya tidak
# berarti dan hanya dilaporkan.
$windowLog = Join-Path $artifacts 'visible-windows.txt'
Set-Content -LiteralPath $windowLog -Value @() -Encoding ASCII
$watcher = Start-Job -ArgumentList $windowLog -ScriptBlock {
    param($Path)
    # Ukuran jendela ikut dicatat: installer seperti WiX Burn (VC++ 2012/2013) dan updater
    # Brave membuat jendela pesan tanpa judul yang secara teknis "visible" tetapi tidak
    # tampil bagi pengguna.
    Add-Type -Namespace TgosCi -Name Win -MemberDefinition @'
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct Rect { public int Left; public int Top; public int Right; public int Bottom; }
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool GetWindowRect(System.IntPtr hWnd, out Rect rect);
'@
    $known = @{}
    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) { $known[$process.Id] = $true }
    }
    # Tanda siap: jendela kontrol baru dibuka sesudah daftar awal ini dibuat (job PowerShell
    # bisa butuh belasan detik untuk mulai di runner yang lambat).
    Add-Content -LiteralPath $Path -Value 'READY' -Encoding ASCII
    while ($true) {
        foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
            if ($process.MainWindowHandle -ne [IntPtr]::Zero -and -not $known.ContainsKey($process.Id)) {
                $known[$process.Id] = $true
                $rect = New-Object TgosCi.Win+Rect
                $null = [TgosCi.Win]::GetWindowRect($process.MainWindowHandle, [ref]$rect)
                # Jam dan proses induk, untuk mencocokkan jendela dengan langkah playbook.
                $parent = '?'
                $commandLine = ''
                try {
                    $info = Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId={0}' -f $process.Id) -ErrorAction Stop
                    $commandLine = [string]$info.CommandLine
                    if ($commandLine.Length -gt 160) { $commandLine = $commandLine.Substring(0, 160) }
                    $parent = (Get-Process -Id $info.ParentProcessId -ErrorAction Stop).ProcessName
                }
                catch { }
                Add-Content -LiteralPath $Path -Value ('{0} | {1} | {2}x{3} | {4:HH:mm:ss} parent {5} | {6}' -f $process.ProcessName, $process.MainWindowTitle, ($rect.Right - $rect.Left), ($rect.Bottom - $rect.Top), (Get-Date), $parent, $commandLine) -Encoding ASCII
            }
        }
        Start-Sleep -Milliseconds 300
    }
}
for ($attempt = 0; $attempt -lt 120; $attempt++) {
    if (@(Get-Content -LiteralPath $windowLog -ErrorAction SilentlyContinue) -contains 'READY') { break }
    Start-Sleep -Milliseconds 500
}
$null = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\notepad.exe') -PassThru
$watcherWorks = $false
for ($attempt = 0; $attempt -lt 40 -and -not $watcherWorks; $attempt++) {
    Start-Sleep -Milliseconds 500
    $watcherWorks = [bool](@(Get-Content -LiteralPath $windowLog -ErrorAction SilentlyContinue) -match '^notepad \|').Count
}
Get-Process -Name 'notepad' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
# Jendela yang sudah muncul sebelum playbook dijalankan (milik runner, bukan TGOS).
@(Get-Content -LiteralPath $windowLog -ErrorAction SilentlyContinue | Where-Object { $_ -and $_ -ne 'READY' -and $_ -notmatch '^notepad \|' }) |
    ForEach-Object { Write-Host ('   window before the playbook: {0}' -f (Format-LogLine $_)) }
$wslTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { @($_.Actions | Where-Object { [string]$_.Execute -match '(?i)wsl' }).Count } |
        ForEach-Object { '{0}{1}' -f $_.TaskPath, $_.TaskName })
Write-Host ('   runner scheduled tasks that start wsl.exe: {0}' -f $(if ($wslTasks.Count) { $wslTasks -join ', ' } else { 'none' }))
Write-Host ('   wsl.exe processes before the playbook: {0}' -f @(Get-Process -Name 'wsl' -ErrorAction SilentlyContinue).Count)
Set-Content -LiteralPath $windowLog -Value @() -Encoding ASCII

$pass = Invoke-Playbook -CliDirectory $cliDirectory -PlaybookDirectory $playbookPass -OptionList $optionList -Name 'pass' -Detached
if ($pass.ExitCode -ne 0 -and -not $pass.TimedOut -and $pass.Output -notmatch 'Playbook completed') {
    # Bila CLI tidak bisa berjalan tanpa konsol, hasil uji lain tetap diperlukan: jalankan
    # dengan cara biasa dan catat bahwa peniruan Wizard tidak berhasil.
    Write-Host '   INFO: the engine did not run without a console; running it the usual way'
    Show-Excerpt -Path (Join-Path $artifacts 'pass-stderr.txt') -Limit 8
    $pass = Invoke-Playbook -CliDirectory $cliDirectory -PlaybookDirectory $playbookPass -OptionList $optionList -Name 'pass'
}

Stop-Job -Job $watcher -ErrorAction SilentlyContinue
Remove-Job -Job $watcher -Force -ErrorAction SilentlyContinue
Stop-Job -Job $tracer -ErrorAction SilentlyContinue
Receive-Job -Job $tracer -ErrorAction SilentlyContinue | Select-Object -First 3 | ForEach-Object { Write-Host ('   trace job: {0}' -f (Format-LogLine ([string]$_))) }
Remove-Job -Job $tracer -Force -ErrorAction SilentlyContinue

# Siapa yang membuka konsol selama playbook.
$names = @{}
$parents = @{}
$consoleStarts = @()
$cmdStarts = @()
foreach ($line in @(Get-Content -LiteralPath $traceLog -ErrorAction SilentlyContinue)) {
    $parts = $line -split '\|'
    if ($parts.Count -lt 4) { continue }
    $names[$parts[1]] = $parts[3]
    $parents[$parts[1]] = $parts[2]
    if ($parts[0] -ne 'INIT' -and $parts[3] -match '(?i)^(conhost|OpenConsole|WindowsTerminal)\.exe$') { $consoleStarts += , $parts }
    if ($parts[0] -ne 'INIT' -and $parts[3] -match '(?i)^cmd\.exe$') { $cmdStarts += , $parts }
}
function Get-TraceName { param([string]$Id) if ($names.ContainsKey($Id)) { return $names[$Id] } return '?' }
$groups = @{}
foreach ($parts in $consoleStarts) {
    $client = $parts[2]
    $grand = ''
    if ($parents.ContainsKey($client)) { $grand = Get-TraceName $parents[$client] }
    $key = '{0} for {1} (parent {2})' -f $parts[3], (Get-TraceName $client), $grand
    if (-not $groups.ContainsKey($key)) { $groups[$key] = @() }
    $groups[$key] += $parts[0]
}
Write-Host ('   console hosts started during the playbook: {0}' -f $consoleStarts.Count)
$groups.GetEnumerator() | Sort-Object { $_.Value.Count } -Descending | Select-Object -First 20 |
    ForEach-Object { Write-Host ('     {0} x{1} (first {2}, last {3})' -f $_.Key, $_.Value.Count, $_.Value[0], $_.Value[-1]) }

# cmd.exe yang dijalankan Explorer = perintah RunOnce/startup yang tampil sebagai jendela
# (pop up di uji VM revisi ketiga 1.0.0).
$cmdByExplorer = @($cmdStarts | Where-Object { (Get-TraceName $_[2]) -match '(?i)^explorer\.exe$' })
Write-Host ('   cmd.exe started during the playbook: {0} (by Explorer: {1})' -f $cmdStarts.Count, $cmdByExplorer.Count)
$cmdStarts | Group-Object { Get-TraceName $_[2] } | Sort-Object Count -Descending | Select-Object -First 10 |
    ForEach-Object { Write-Host ('     cmd.exe from {0} x{1}' -f $_.Name, $_.Count) }
$cmdByExplorer | Select-Object -First 10 | ForEach-Object { Write-Host ('     by Explorer at {0}: {1}' -f $_[0], $(if ($_.Count -ge 5) { Format-LogLine $_[4] } else { '' })) }
$null = Assert-That ($cmdByExplorer.Count -eq 0) ('pass: Explorer started no cmd.exe during the playbook (OneDrive was running before it: {0})' -f $oneDriveEmulated)
if ($terminalEmulated) {
    # TGOS tidak lagi mengubah terminal bawaan (revisi keempat 1.0.0).
    $after = Get-ItemProperty -LiteralPath $startupKey -ErrorAction SilentlyContinue
    $null = Assert-That ($after.DelegationConsole -eq $terminalGuids.DelegationConsole -and $after.DelegationTerminal -eq $terminalGuids.DelegationTerminal) ('terminal: the default terminal is unchanged by the playbook ({0})' -f $after.DelegationConsole)
}
# Bagian shell Windows yang memang muncul lagi saat TGOS menjalankan ulang Explorer.
$shellProcesses = '^(explorer|ShellExperienceHost|StartMenuExperienceHost|SearchHost|SearchApp|TextInputHost|ApplicationFrameHost|LockApp|ShellHost) \|'
$newWindows = @(Get-Content -LiteralPath $windowLog -ErrorAction SilentlyContinue | Where-Object { $_ })
# Image runner Windows 11 membuka "wsl.exe --update --confirm --prompt-before-exit" tiap
# 90 detik sepanjang job (juga saat uji Game Bar, sesudah playbook selesai). TGOS tidak
# pernah menjalankan WSL: validate.py menolak "wsl" di seluruh src/.
$runnerNoise = '^wsl \|.*\| (?i:C:\\Windows\\system32\\wsl\.exe) --update --confirm --prompt-before-exit\s*$'
$noise = @($newWindows | Where-Object { $_ -match $runnerNoise })
$newWindows = @($newWindows | Where-Object { $_ -notmatch $runnerNoise })
if ($noise.Count) { Write-Host ('   ignored {0} runner window(s): wsl.exe --update (WSL updater of the runner image)' -f $noise.Count) }
if ($oneDriveEmulated) {
    # OneDrive yang dijalankan uji ini sebelum playbook (bukan oleh TGOS) bisa membuka jendela
    # masuk akun sebelum playbook menghentikannya.
    $emulation = @($newWindows | Where-Object { $_ -match '^(OneDrive|Microsoft\.SharePoint|FileCoAuth) \|' })
    $newWindows = @($newWindows | Where-Object { $_ -notmatch '^(OneDrive|Microsoft\.SharePoint|FileCoAuth) \|' })
    $emulation | ForEach-Object { Write-Host ('   ignored (OneDrive started by this test): {0}' -f (Format-LogLine $_)) }
}
# Pelanggaran: jendela berjudul, atau jendela tanpa judul yang ukurannya nyata (bukan
# jendela pesan kosong), dari proses selain shell Windows.
$unexpected = @($newWindows | Where-Object {
        $parts = $_ -split ' \| '
        $titled = $parts.Count -ge 2 -and $parts[1].Trim()
        $large = $false
        if ($parts.Count -ge 3 -and $parts[2] -match '^(-?\d+)x(-?\d+)$') { $large = ([int]$Matches[1] -ge 50 -and [int]$Matches[2] -ge 50) }
        ($_ -notmatch $shellProcesses) -and ($titled -or $large)
    })
if ($watcherWorks) {
    $null = Assert-That ($unexpected.Count -eq 0) ('pass: no visible window appeared during the playbook ({0} window(s) seen; shell windows and empty message windows are not counted)' -f $newWindows.Count)
    $unexpected | ForEach-Object { Write-Host ('   VISIBLE: {0}' -f (Format-LogLine $_)) }
}
else {
    Write-Host '   INFO: the window watcher could not see the Notepad control window; the no-window check is inconclusive'
}
$newWindows | Select-Object -First 15 | ForEach-Object { Write-Host ('   window: {0}' -f (Format-LogLine $_)) }

# Diagnosa: paket framework yang dijaga compare-snapshots.py, tepat setelah playbook. Bila
# nanti hilang sebelum potret "after", log AppX Windows menunjukkan siapa yang mencabutnya.
$frameworks = @(Get-AppxPackage -AllUsers -Name 'Microsoft.NET.Native.*' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name } | Select-Object -Unique)
Write-Host ('   .NET Native frameworks right after the playbook: {0}' -f $(if ($frameworks.Count) { $frameworks -join ', ' } else { 'none' }))
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
# Baris per-tugas terjadwal dilewati (ringkasannya tetap tampil), supaya hasil skrip
# sesudahnya (OneDrive, Edge, Toolbox) tidak terdorong keluar dari batas baris.
$engineOutput = Join-Path $pass.Logs 'Output.txt'
if (Test-Path -LiteralPath $engineOutput) {
    Write-Host '   TGOS script results in the engine log:'
    Get-Content -LiteralPath $engineOutput |
        Where-Object { $_ -match 'TGOS: (?!recorded option|task disabled:|task not present)|PASSED:|REJECTED:|SUMMARY:' -or $_ -match 'WARNING: ' } |
        ForEach-Object {
            # Jam dari log mesin AME ikut ditampilkan, supaya langkah yang lama terlihat.
            $time = ''
            if ($_ -match '\| (\d{2}:\d{2}:\d{2})\]') { $time = $Matches[1] + ' ' }
            $time + ($_ -replace '^.*?(TGOS: |PASSED:|REJECTED:|SUMMARY:|WARNING: )', '$1')
        } |
        Select-Object -First 120 | ForEach-Object { Write-Host ('   | ' + (Format-LogLine $_)) }
}

Write-Host '   install-info.txt:'
Show-Excerpt -Path $installInfo -Limit 20

if ($diagTrack) {
    $status = [string](Get-Service -Name 'DiagTrack').Status
    $null = Assert-That ($status -eq 'Stopped') ('pass: DiagTrack was stopped by the playbook (status {0})' -f $status)
}
foreach ($logger in @('AutoLogger-Diagtrack-Listener', 'SQMLogger')) {
    $value = (Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\{0}' -f $logger) -Name 'Start' -ErrorAction SilentlyContinue).Start
    $null = Assert-That ($value -eq 0) ('pass: autologger {0} Start = 0 after DiagTrack stopped (found {1})' -f $logger, $value)
}

if ($enabledTasks.Count -gt 0) {
    $stillEnabled = @($enabledTasks | Where-Object {
            $task = Get-ScheduledTask -TaskPath $_.TaskPath -TaskName $_.TaskName -ErrorAction SilentlyContinue
            $task -and [string]$task.State -ne 'Disabled'
        })
    $null = Assert-That ($stillEnabled.Count -eq 0) ('pass: all {0} task(s) enabled before the run are now Disabled' -f $enabledTasks.Count)
    $stillEnabled | ForEach-Object { Write-Host ('   still enabled: {0}{1}' -f $_.TaskPath, $_.TaskName) }
}

# =======================================================================================
Write-Section 'OneDrive leftovers and RunOnce'
if ($plannedOptions -contains 'remove-onedrive') {
    $left = @(Get-RunOnceEntry | Where-Object { $_ -match '(?i)onedrive' })
    $null = Assert-That ($left.Count -eq 0) ('onedrive: no OneDrive cleanup command is left in RunOnce ({0} found)' -f $left.Count)
    $left | ForEach-Object { Write-Host ('   left: {0}' -f (Format-LogLine $_)) }
    $stillRunning = @(Get-Process -Name $oneDriveFamily -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName } | Sort-Object -Unique)
    $null = Assert-That ($stillRunning.Count -eq 0) ('onedrive: no OneDrive process is left running ({0})' -f ($stillRunning -join ', '))
    Write-Host ('   OneDrive app folder still present: {0}' -f (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive')))
    if (-not $oneDriveEmulated) { Write-Host '   INFO: OneDrive was not running before the playbook on this runner; the cleanup path was not exercised' }
}
@(Get-RunOnceEntry) | ForEach-Object { Write-Host ('   RunOnce after the playbook: {0}' -f (Format-LogLine $_)) }
# Kontrol untuk penyebab pop up di VM: perintah RunOnce dijalankan Explorer saat
# dinyalakan ulang, dalam jendela cmd yang terlihat. Hanya informasi.
if (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue) {
    $runOnceKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    if (-not (Test-Path -LiteralPath $runOnceKey)) { New-Item -Path $runOnceKey -Force | Out-Null }
    Set-ItemProperty -LiteralPath $runOnceKey -Name 'TgosCiControl' -Value ('"{0}" /c ping -n 9 127.0.0.1 >nul' -f (Join-Path $env:SystemRoot 'System32\cmd.exe'))
    Get-Process -Name 'explorer' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    if (-not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) { Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') }
    $control = $null
    for ($attempt = 0; $attempt -lt 40 -and -not $control; $attempt++) {
        Start-Sleep -Milliseconds 500
        $control = Get-CimInstance -ClassName Win32_Process -Filter "Name='cmd.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match 'ping -n 9 127\.0\.0\.1' } | Select-Object -First 1
    }
    $visible = $false
    $parent = '?'
    if ($control) {
        for ($attempt = 0; $attempt -lt 6 -and -not $visible; $attempt++) {
            $process = Get-Process -Id $control.ProcessId -ErrorAction SilentlyContinue
            $visible = $process -and $process.MainWindowHandle -ne [IntPtr]::Zero
            if (-not $visible) { Start-Sleep -Milliseconds 500 }
        }
        $parentProcess = Get-Process -Id $control.ParentProcessId -ErrorAction SilentlyContinue
        if ($parentProcess) { $parent = $parentProcess.ProcessName }
        Stop-Process -Id $control.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Remove-ItemProperty -LiteralPath $runOnceKey -Name 'TgosCiControl' -ErrorAction SilentlyContinue
    Write-Host ('   control: a RunOnce command ran when Explorer restarted: {0}; parent {1}; window visible: {2}' -f [bool]$control, $parent, $visible)
    Start-Sleep -Seconds 5
}
else {
    Write-Host '   Explorer is not running on this runner; the RunOnce control was skipped'
}

# =======================================================================================
Write-Section 'Software'
$selectedOptions = @($optionList -split '\s+' | Where-Object { $_ })
$softwareChecks = @(
    @{ Option = 'browser-brave'; Name = 'Brave'; Relative = 'BraveSoftware\Brave-Browser\Application\brave.exe' },
    @{ Option = 'browser-chrome'; Name = 'Chrome'; Relative = 'Google\Chrome\Application\chrome.exe' },
    @{ Option = 'browser-firefox'; Name = 'Firefox'; Relative = 'Mozilla Firefox\firefox.exe' },
    @{ Option = 'install-7zip'; Name = '7-Zip'; Relative = '7-Zip\7z.exe' },
    @{ Option = 'install-steam'; Name = 'Steam'; Relative = 'Steam\steam.exe'; X64Only = $true },
    @{ Option = 'install-epic'; Name = 'Epic Games Launcher'; Relative = 'Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe'; X64Only = $true },
    @{ Option = 'install-ea'; Name = 'EA app'; Relative = 'Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe'; X64Only = $true },
    @{ Option = 'install-ubisoft'; Name = 'Ubisoft Connect'; Relative = 'Ubisoft\Ubisoft Game Launcher\UbisoftConnect.exe'; X64Only = $true },
    @{ Option = 'install-discord'; Name = 'Discord'; UserRelative = 'Discord\Update.exe'; X64Only = $true },
    @{ Option = 'install-spotify'; Name = 'Spotify'; UserRelative = 'Spotify\Spotify.exe'; Roaming = $true; X64Only = $true })
foreach ($check in $softwareChecks) {
    if ($selectedOptions -notcontains $check.Option) { continue }
    if ($check.X64Only -and $runnerArch -ne 'AMD64') {
        Write-Host ('   {0}: skipped on {1} (TGOS installs it on x64 only)' -f $check.Name, $runnerArch)
        continue
    }
    if ($check.UserRelative) {
        # Per pengguna: dipasang ke profil akun yang menjalankan uji ini.
        $base = $env:LOCALAPPDATA
        if ($check.Roaming) { $base = $env:APPDATA }
        $found = @(Join-Path $base $check.UserRelative) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }
    else {
        $found = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } |
            ForEach-Object { Join-Path $_ $check.Relative } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }
    if (-not $found -and $check.Option -eq 'install-epic') {
        $found = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } |
            ForEach-Object { Join-Path $_ 'Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }
    if (-not $found -and $check.Option -eq 'install-ubisoft') {
        $found = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } |
            ForEach-Object { Join-Path $_ 'Ubisoft\Ubisoft Game Launcher\upc.exe' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }
    $null = Assert-That ([bool]$found) ('software: {0} is installed after the run' -f $check.Name)
    if ($found) { Write-Host ('   {0} {1}' -f $found, (Get-Item -LiteralPath $found).VersionInfo.ProductVersion) }
    elseif ($check.Option -eq 'browser-brave') {
        # Gejala installer per pengguna yang dijalankan sebagai sistem.
        $systemCopy = Join-Path $env:SystemRoot 'System32\config\systemprofile\AppData\Local\BraveSoftware\Brave-Browser\Application\brave.exe'
        Write-Host ('   Brave in the SYSTEM profile instead: {0}' -f (Test-Path -LiteralPath $systemCopy))
    }
}

# Unduh, periksa tanda tangan, dan pasang ulang lewat skrip yang terpasang di Toolbox.
$toolboxInstaller = Join-Path ('{0}\' -f $env:SystemDrive) 'TGOS Toolbox\Support\Install-Software.ps1'
# Program yang versinya bisa dibaca: versi tidak boleh turun karena pemasangan ulang.
$versionedExe = @{ '7zip' = '7-Zip\7z.exe'; firefox = 'Mozilla Firefox\firefox.exe'; chrome = 'Google\Chrome\Application\chrome.exe' }
function Get-InstalledVersion {
    param([string]$Relative)
    $exe = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } |
        ForEach-Object { Join-Path $_ $Relative } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $exe) { return $null }
    return (ConvertTo-TgosVersion (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion)
}
# Jendela yang terlihat, dicari dari nama proses atau judul jendelanya.
function Get-VisibleWindow {
    param([string]$Pattern)
    @(Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and ($_.ProcessName -match $Pattern -or $_.MainWindowTitle -match $Pattern) } |
        ForEach-Object { '{0} "{1}"' -f $_.ProcessName, $_.MainWindowTitle })
}
# Kontrol pemantau jendela: jendela Notepad harus terdeteksi. Bila tidak, runner ini tidak
# memperlihatkan jendela dan uji "tidak ada jendela" tidak berarti.
function Test-WindowControl {
    $null = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\notepad.exe') -PassThru
    $seen = $false
    for ($attempt = 0; $attempt -lt 30 -and -not $seen; $attempt++) {
        Start-Sleep -Milliseconds 500
        $seen = (Get-VisibleWindow '(?i)^notepad$').Count -gt 0
    }
    Get-Process -Name 'notepad' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    return $seen
}
foreach ($item in @($ForceItems -split '\s+' | Where-Object { $_ })) {
    $before = $null
    if ($versionedExe.ContainsKey($item)) { $before = Get-InstalledVersion $versionedExe[$item] }
    $command = 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Item {1} -Force 2>&1' -f $toolboxInstaller, $item
    if ($item -eq 'directx') {
        # Uji VM v1.0.0: installer web DirectX menampilkan jendela "Installing Microsoft
        # DirectX". Selama pemasangan, jendela installer DirectX yang terlihat dicari.
        # Kontrol dulu: jendela Notepad harus terdeteksi oleh cara yang sama; bila tidak,
        # runner ini tidak bisa melihat jendela dan hasilnya hanya dicatat.
        $controlSeen = Test-WindowControl
        $outFile = Join-Path $artifacts 'force-directx.txt'
        $process = Start-Process -FilePath 'cmd.exe' -ArgumentList ('/c ' + $command) -RedirectStandardOutput $outFile -NoNewWindow -PassThru
        $null = $process.Handle
        $windows = @()
        while (-not $process.HasExited) {
            $windows += Get-VisibleWindow '(?i)directx|dxsetup|dxwebsetup'
            Start-Sleep -Milliseconds 500
        }
        $process.WaitForExit()
        $exit = $process.ExitCode
        $output = ''
        if (Test-Path -LiteralPath $outFile) { $output = Get-Content -LiteralPath $outFile -Raw }
        if ($controlSeen) {
            $null = Assert-That ($windows.Count -eq 0) 'software: no DirectX installer window was visible (control: the Notepad window was detected)'
            @($windows | Select-Object -Unique -First 5) | ForEach-Object { Write-Host ('   visible: {0}' -f $_) }
        }
        else {
            Write-Host '   INFO: this runner does not expose windows (the Notepad control was not detected); the visible-window check is inconclusive'
        }
    }
    else {
        $output = & cmd.exe /c $command | Out-String
        $exit = $LASTEXITCODE
    }
    $ok = ($exit -eq 0) -and ($output -match 'verified:') -and ($output -match 'TGOS: .+ installed')
    # Hanya 7-Zip yang boleh dilewati karena versi terpasang lebih baru.
    $ok = $ok -and ($item -eq '7zip' -or $output -notmatch 'nothing changed')
    $null = Assert-That $ok ('software: forced download of {0} is verified and installed' -f $item)
    if ($null -ne $before) {
        $after = Get-InstalledVersion $versionedExe[$item]
        $null = Assert-That ($null -ne $after -and $after -ge $before) ('software: {0} version did not go down ({1} -> {2})' -f $item, $before, $after)
    }
    $output -split "`r?`n" | Where-Object { $_ -match 'TGOS: |WARNING: ' } | Select-Object -First 8 | ForEach-Object { Write-Host ('   | ' + (Format-LogLine $_)) }
    if (-not $ok) { Write-Host ('   exit {0}' -f $exit) }
}

# =======================================================================================
Write-Section 'Game Bar and Windows Update'
if ($plannedOptions -contains 'remove-xbox') {
    # Tanpa aplikasi Game Bar, protokol ms-gamebar memunculkan jendela "You'll need a new
    # app to open this ms-gamebar link". TGOS memberi penangan pengganti (systray.exe).
    $systray = Join-Path $env:SystemRoot 'System32\systray.exe'
    $null = Assert-That (Test-Path -LiteralPath $systray) 'gamebar: systray.exe (the replacement handler) exists'
    # Diagnosa: penangan tiap protokol untuk pengguna uji, dan pilihan aplikasi tersimpan.
    foreach ($protocol in @('ms-gamebar', 'ms-gamingoverlay')) {
        foreach ($root in @('HKCU:\Software\Classes', 'HKLM:\SOFTWARE\Classes')) {
            $command = Join-Path (Join-Path $root $protocol) 'shell\open\command'
            $value = '(missing)'
            if (Test-Path -LiteralPath $command) { $value = [string](Get-Item -LiteralPath $command).GetValue('', '', 'DoNotExpandEnvironmentNames') }
            Write-Host ('   {0}\{1}\shell\open\command = {2}' -f ($root -replace ':', ''), $protocol, $value)
        }
        $choice = 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\{0}\UserChoice' -f $protocol
        $progId = (Get-ItemProperty -LiteralPath $choice -ErrorAction SilentlyContinue).ProgId
        if (-not $progId) { $progId = '(none)' }
        Write-Host ('   UserChoice for {0}: {1}' -f $protocol, $progId)
    }
    $overlay = @(Get-AppxPackage -AllUsers -Name '*XboxGamingOverlay*' -ErrorAction SilentlyContinue | ForEach-Object { $_.PackageFullName })
    Write-Host ('   Game Bar packages left: {0}' -f $(if ($overlay.Count) { $overlay -join ', ' } else { 'none' }))
    # Informasi: cache AppX Windows (StateRepository) yang masih mengaitkan ms-gamebar dengan
    # Game Bar yang sudah dihapus. TGOS tidak mengubah cache ini; Win+G diblokir.
    $stateCache = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\Cache\Protocol\Index\Name\ms-gamebar'
    Write-Host ('   StateRepository cache entry for ms-gamebar: {0}' -f $(if (Test-Path -LiteralPath $stateCache) { 'present' } else { 'absent' }))
    $advanced = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $hotkeys = [string](Get-ItemProperty -LiteralPath $advanced -ErrorAction SilentlyContinue).DisabledHotkeys
    $null = Assert-That ($hotkeys.Contains('G')) ('gamebar: Win+G is blocked for the test user (DisabledHotkeys = {0})' -f $hotkeys)
    if (Test-WindowControl) {
        # Win+G sungguhan lewat keybd_event. Jendela dicari dengan EnumWindows (semua jendela
        # teratas yang terlihat dan berjudul, termasuk dialog milik Explorer).
        Add-Type -Namespace TgosCi -Name Top -MemberDefinition @'
public delegate bool EnumProc(System.IntPtr hWnd, System.IntPtr lParam);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool EnumWindows(EnumProc callback, System.IntPtr lParam);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool IsWindowVisible(System.IntPtr hWnd);
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int GetWindowText(System.IntPtr hWnd, System.Text.StringBuilder text, int count);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern uint GetWindowThreadProcessId(System.IntPtr hWnd, out uint processId);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool PostMessage(System.IntPtr hWnd, uint msg, System.IntPtr wParam, System.IntPtr lParam);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern void keybd_event(byte vk, byte scan, uint flags, System.UIntPtr extra);
public static System.Collections.Generic.List<System.IntPtr> Visible() {
    var list = new System.Collections.Generic.List<System.IntPtr>();
    EnumWindows((h, l) => { if (IsWindowVisible(h)) { list.Add(h); } return true; }, System.IntPtr.Zero);
    return list;
}
'@
        function Get-TitledWindow {
            $names = @{}
            Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $names[[uint32]$_.Id] = $_.ProcessName }
            $result = @{}
            foreach ($handle in [TgosCi.Top]::Visible()) {
                $text = New-Object System.Text.StringBuilder 256
                $null = [TgosCi.Top]::GetWindowText($handle, $text, 256)
                $title = $text.ToString().Trim()
                if (-not $title) { continue }
                $processId = [uint32]0
                $null = [TgosCi.Top]::GetWindowThreadProcessId($handle, [ref]$processId)
                $name = '?'
                if ($names.ContainsKey($processId)) { $name = $names[$processId] }
                $result[[long]$handle] = '{0} "{1}"' -f $name, $title
            }
            return $result
        }
        function Test-WinGPopup {
            $before = Get-TitledWindow
            [TgosCi.Top]::keybd_event(0x5B, 0, 0, [UIntPtr]::Zero)
            [TgosCi.Top]::keybd_event(0x47, 0, 0, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 100
            [TgosCi.Top]::keybd_event(0x47, 0, 2, [UIntPtr]::Zero)
            [TgosCi.Top]::keybd_event(0x5B, 0, 2, [UIntPtr]::Zero)
            $seen = @{}
            for ($attempt = 0; $attempt -lt 16; $attempt++) {
                Start-Sleep -Milliseconds 500
                $now = Get-TitledWindow
                foreach ($handle in @($now.Keys)) {
                    if (-not $before.ContainsKey($handle) -and -not $seen.ContainsKey($handle)) { $seen[$handle] = $now[$handle] }
                }
            }
            foreach ($handle in @($seen.Keys)) { $null = [TgosCi.Top]::PostMessage([IntPtr]$handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) }
            Get-Process -Name 'OpenWith' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 800
            # wsl.exe: updater WSL milik image runner (lihat pemantau jendela di atas).
            return @($seen.Values | Where-Object { $_ -notmatch '^wsl ' })
        }
        function Restart-TestExplorer {
            Get-Process -Name 'explorer' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            if (-not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) { Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') }
            Start-Sleep -Seconds 10
        }
        # Kontrol: tanpa blok TGOS, Win+G HARUS memunculkan jendela di runner ini (Game Bar
        # sudah dihapus). Bila tidak, runner ini tidak meneruskan Win+G dan hasilnya tidak
        # dihitung.
        $withoutG = $hotkeys.Replace('G', '')
        if ($withoutG) { Set-ItemProperty -LiteralPath $advanced -Name 'DisabledHotkeys' -Value $withoutG }
        else { Remove-ItemProperty -LiteralPath $advanced -Name 'DisabledHotkeys' -ErrorAction SilentlyContinue }
        Restart-TestExplorer
        $control = @(Test-WinGPopup)
        $control | ForEach-Object { Write-Host ('   control (block removed), Win+G showed: {0}' -f (Format-LogLine $_)) }
        Set-ItemProperty -LiteralPath $advanced -Name 'DisabledHotkeys' -Value $hotkeys
        Restart-TestExplorer
        $blocked = @(Test-WinGPopup)
        $blocked | ForEach-Object { Write-Host ('   with the TGOS block, Win+G showed: {0}' -f (Format-LogLine $_)) }
        if ($control.Count) {
            $null = Assert-That ($blocked.Count -eq 0) 'gamebar: Win+G shows no window (control: without the TGOS block it showed one)'
        }
        else {
            Write-Host '   INFO: Win+G showed no window even without the block, so this runner cannot show the effect; result not counted'
        }
    }
    else {
        Write-Host '   INFO: this runner does not expose windows; the Win+G check is inconclusive'
    }
}
if ($plannedOptions -contains 'updates-pause') {
    # Informasi: nilai pause yang ditulis TGOS, dan bagaimana layanan Windows Update
    # membacanya (kunci UpdatePolicy diisi layanan itu sendiri, tidak oleh TGOS).
    foreach ($key in @('HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings', 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\Settings')) {
        $item = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if ($null -eq $item) { Write-Host ('   {0}: (missing)' -f $key); continue }
        $item.PSObject.Properties | Where-Object { $_.Name -match '(?i)pause' } |
            ForEach-Object { Write-Host ('   {0}\{1} = {2}' -f ($key -replace '^.*\\', ''), $_.Name, $_.Value) }
    }
    # Definisi Defender tetap bisa diperbarui saat Windows Update di-pause? (informasi)
    $mpCmd = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
    if (Test-Path -LiteralPath $mpCmd) {
        $mpOutput = & cmd.exe /c ('"{0}" -SignatureUpdate 2>&1' -f $mpCmd) | Out-String
        Write-Host ('   Defender signature update while paused: exit {0}' -f $LASTEXITCODE)
        $mpOutput -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 3 | ForEach-Object { Write-Host ('   | ' + (Format-LogLine $_)) }
    }
}

# =======================================================================================
Write-Section 'Deep clean'
if ($plannedOptions -contains 'deep-clean' -or $plannedOptions -contains 'deep-clean-plus') {
    $cleanRecord = Join-Path $env:ProgramData 'TGOS\deep-clean.txt'
    if (Assert-That (Test-Path -LiteralPath $cleanRecord) 'deep clean: deep-clean.txt was written') {
        $cleanLines = @(Get-Content -LiteralPath $cleanRecord)
        $cleanLines | ForEach-Object { Write-Host ('   | ' + (Format-LogLine $_)) }
        $null = Assert-That ([bool](@($cleanLines -match 'completed:').Count)) 'deep clean: finished (completed line present)'
        if ($plannedOptions -contains 'deep-clean-plus') {
            $null = Assert-That ([bool](@($cleanLines -match 'ResetBase').Count)) 'deep clean: Deep clean+ ran the ResetBase step'
        }
    }
    # Folder playbook yang sedang berjalan tidak boleh tersentuh (langkah sesudahnya masih
    # memakai skripnya).
    $null = Assert-That (Test-Path -LiteralPath (Join-Path $playbookPass 'Executables\Scripts\Set-ShellLayout.ps1')) 'deep clean: the running playbook folder was left alone'
}
else {
    Write-Host '   deep clean not selected in this job'
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
        @{ Feature = 'Telemetry'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\CompatTelRunner.exe'; Name = 'Debugger'; Off = '%windir%\System32\taskkill.exe'; On = $null },
        @{ Feature = 'ExtraServices'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Spooler'; Name = 'Start'; Off = 4; On = 2 },
        # Tanpa nilai registry: yang diperiksa kode keluarnya (0, atau 3 bila tidak didukung).
        @{ Feature = 'CoreParking'; Path = $null; Name = 'exit code'; Off = $null; On = $null },
        @{ Feature = 'Defender'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Name = 'DisableRealtimeMonitoring'; Off = 1; On = $null },
        # '*' = nilainya harus ada (isinya tanggal yang dihitung saat itu).
        @{ Feature = 'UpdatePause'; Path = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'; Name = 'PauseUpdatesExpiryTime'; Off = '*'; On = $null },
        @{ Feature = 'DriverUpdates'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name = 'ExcludeWUDriversInQualityUpdate'; Off = 1; On = $null },
        @{ Feature = 'BackgroundApps'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'; Name = 'LetAppsRunInBackground'; Off = 2; On = $null },
        @{ Feature = 'LockScreen'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'; Name = 'NoLockScreen'; Off = 1; On = $null },
        @{ Feature = 'GameBar'; Path = 'HKLM:\SOFTWARE\Classes\ms-gamebar'; Name = 'NoOpenWith'; Off = ''; On = $null },
        @{ Feature = 'LoginTheme'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'; Name = 'LockScreenImageStatus'; Off = $null; On = 1 },
        # DISM; diperiksa lewat kode keluarnya (3 = tidak didukung di runner ini).
        @{ Feature = 'ReservedStorage'; Path = $null; Name = 'exit code'; Off = $null; On = $null }
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
            if ($case.Feature -eq 'ReservedStorage' -and $exit -eq 4) {
                Write-Host ('  skip  toolbox: ReservedStorage {0}: Windows is using reserved storage on this runner' -f $state)
                continue
            }
            if ($case.Feature -eq 'Defender' -and $state -eq 'Off' -and $exit -eq 2) {
                # Perilaku yang dirancang di Windows 11: selama Tamper Protection aktif,
                # skrip menolak, menjelaskan caranya, dan tidak mengubah apa pun.
                $untouched = ($null -eq (Get-Value -Path $case.Path -Name $case.Name))
                $null = Assert-That ($untouched -and $output -match 'Tamper Protection') 'toolbox: Defender Off is refused while Tamper Protection is on, and changes nothing'
                continue
            }
            if ($null -eq $case.Path) {
                if (-not (Assert-That ($exit -eq 0) ('toolbox: {0} {1} -> exit 0' -f $case.Feature, $state))) {
                    Write-Host ('   exit {0}' -f $exit)
                    $output -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 4 | ForEach-Object { Write-Host ('   | ' + (Format-LogLine $_)) }
                }
                continue
            }
            $actual = Get-Value -Path $case.Path -Name $case.Name
            $expected = $case[$state]
            if ($null -eq $expected) { $same = ($null -eq $actual) }
            elseif ($expected -is [string] -and $expected -eq '*') { $same = ($null -ne $actual -and [string]$actual -ne '') }
            else { $same = ($null -ne $actual -and $actual -eq $expected) }
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
Write-Section 'Toolbox buttons'
# Tombol .cmd yang sebenarnya diklik pengguna, dengan input disuapkan (Enter untuk
# "pause"). Membuktikan jalur ..\Support dari subfolder dan menu Install Software.
$toolboxRoot = Join-Path ('{0}\' -f $env:SystemDrive) 'TGOS Toolbox'
function Invoke-ToolboxButton {
    param([string]$Relative, [string[]]$InputLines, [string]$Path)
    $inputFile = Join-Path $artifacts 'button-input.txt'
    $stem = [IO.Path]::GetFileNameWithoutExtension($Relative) -replace '[^A-Za-z0-9-]', ''
    $outputFile = Join-Path $artifacts ('button-{0}.txt' -f $stem)
    $errorFile = Join-Path $artifacts ('button-{0}-stderr.txt' -f $stem)
    Set-Content -LiteralPath $inputFile -Value $InputLines -Encoding ASCII
    if (-not $Path) { $Path = Join-Path $toolboxRoot $Relative }
    $process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', ('"{0}"' -f $Path)) -RedirectStandardInput $inputFile -RedirectStandardOutput $outputFile -RedirectStandardError $errorFile -NoNewWindow -PassThru
    $null = $process.Handle
    if (-not $process.WaitForExit(600000)) { try { $process.Kill() } catch { } }
    # Get-Content -Raw pada file kosong tidak mengembalikan apa pun (bukan string kosong).
    $text = ''
    if (Test-Path -LiteralPath $outputFile) { $text = Get-Content -LiteralPath $outputFile -Raw }
    if ($null -eq $text) { $text = '' }
    $errors = ''
    if (Test-Path -LiteralPath $errorFile) { $errors = Get-Content -LiteralPath $errorFile -Raw }
    if ($null -eq $errors) { $errors = '' }
    return @{ Exit = $process.ExitCode; Output = [string]$text; Errors = [string]$errors }
}
$lockKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
$result = Invoke-ToolboxButton -Relative 'Turn ON or OFF\Lock Screen - Turn OFF.cmd' -InputLines @('')
$value = (Get-ItemProperty -LiteralPath $lockKey -ErrorAction SilentlyContinue).NoLockScreen
$null = Assert-That ($value -eq 1 -and $result.Output -match 'lock screen is now skipped') 'toolbox button: "Turn ON or OFF\Lock Screen - Turn OFF.cmd" works'
$result = Invoke-ToolboxButton -Relative 'Turn ON or OFF\Lock Screen - Turn ON.cmd' -InputLines @('')
$value = (Get-ItemProperty -LiteralPath $lockKey -ErrorAction SilentlyContinue).NoLockScreen
$null = Assert-That ($null -eq $value -and $result.Output -match 'lock screen is back') 'toolbox button: "Turn ON or OFF\Lock Screen - Turn ON.cmd" works'
# Menu: 4 = 7-Zip, lalu "x" untuk "pause", lalu 0 = keluar. Dengan input dari file,
# "pause" hanya memakan SATU karakter (di konsol sungguhan: satu tombol), jadi baris kedua
# "x0" = tombol untuk pause, lalu "0" untuk menu.
$result = Invoke-ToolboxButton -Relative 'Install Software.cmd' -InputLines @('4', 'x0')
$ok = Assert-That ($result.Output -match 'TGOS: 7-Zip installed' -and $result.Output -match 'verified:' -and $result.Output -notmatch 'Unknown number') 'toolbox button: "Install Software.cmd" menu installs 7-Zip and exits on 0'
if (-not $ok) { $result.Output -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 8 | ForEach-Object { Write-Host ('   | ' + (Format-LogLine $_)) } }
$null = Assert-That (-not $result.Errors.Trim()) 'toolbox button: "Install Software.cmd" printed no cmd error'
if ($result.Errors.Trim()) {
    Write-Host ('   stderr: {0}' -f (Format-LogLine $result.Errors))
    # Jalankan salinan dengan "echo on" supaya baris yang memicu error terlihat.
    $debugCopy = Join-Path $toolboxRoot 'menu-debug.cmd'
    (Get-Content -LiteralPath (Join-Path $toolboxRoot 'Install Software.cmd') -Raw).Replace('@echo off', '@echo on') |
        Set-Content -LiteralPath $debugCopy -Encoding ASCII -NoNewline
    $debug = Invoke-ToolboxButton -Relative 'menu-debug.cmd' -Path $debugCopy -InputLines @('4', 'x0')
    $debug.Output -split "`r?`n" | Where-Object { $_.Trim() -and $_ -notmatch '^\s*(\| |TGOS:)' } | Select-Object -Last 30 | ForEach-Object { Write-Host ('   debug | ' + (Format-LogLine $_)) }
    Write-Host ('   debug stderr: {0}' -f (Format-LogLine $debug.Errors))
    Remove-Item -LiteralPath $debugCopy -Force -ErrorAction SilentlyContinue
}
# Ketikan yang bukan nomor (tanda kutip dan &) tidak boleh merusak menu.
$result = Invoke-ToolboxButton -Relative 'Install Software.cmd' -InputLines @('"&x')
$null = Assert-That ($result.Output -match 'Unknown number' -and -not $result.Errors.Trim()) 'toolbox button: "Install Software.cmd" handles a bad entry without a cmd error'
if ($result.Errors.Trim()) { Write-Host ('   stderr: {0}' -f (Format-LogLine $result.Errors)) }

# =======================================================================================
Write-Section 'Retries after restart'
# Langkah yang gagal karena Windows sibuk dijadwalkan lewat Add-TgosAfterRestartItem
# (Common.ps1) dan dikerjakan tugas tersembunyi \TGOS\Finish after restart, yang menjalankan
# Complete-AfterRestart.ps1 sebagai SYSTEM. Di sini tugas itu dijalankan sungguhan lewat
# Task Scheduler (bukan restart): reserved storage di semua job, dan di job Windows 11
# bawaan juga .NET Framework 3.5 dengan payload dibuang dulu, saat update di-pause.
$commonScript = Join-Path $installedSupport 'Common.ps1'
$isClient = (Get-CimInstance -ClassName Win32_OperatingSystem).ProductType -eq 1
$withNetFx3 = $OptionSet -eq 'default' -and $isClient -and $plannedOptions -contains 'install-dotnet' -and $plannedOptions -contains 'updates-pause'
if ((Assert-That (Test-Path -LiteralPath $commonScript) 'retry: Common.ps1 is installed with the Toolbox') -and
    (Assert-That (Test-Path -LiteralPath (Join-Path $installedSupport 'Complete-AfterRestart.ps1')) 'retry: Complete-AfterRestart.ps1 is installed with the Toolbox')) {
    . $commonScript
    $leftover = Get-ScheduledTask -TaskPath '\TGOS\' -TaskName 'Finish after restart' -ErrorAction SilentlyContinue
    Write-Host ('   after-restart task before this test: {0}; list: {1}' -f $(if ($leftover) { 'registered' } else { 'none' }),
        $(if (Test-Path -LiteralPath (Join-Path $env:ProgramData 'TGOS\after-restart.txt')) { (Get-Content -LiteralPath (Join-Path $env:ProgramData 'TGOS\after-restart.txt')) -join ', ' } else { 'none' }))
    if ($withNetFx3) {
        $dism = Join-Path $env:SystemRoot 'System32\dism.exe'
        $started = Get-Date
        & cmd.exe /c ('"{0}" /Online /Disable-Feature /FeatureName:NetFx3 /Remove /NoRestart /Quiet' -f $dism) | Out-Null
        $state = (Get-WindowsOptionalFeature -Online -FeatureName NetFx3 -ErrorAction SilentlyContinue).State
        Write-Host ('   NetFx3 after /Disable-Feature /Remove: {0} ({1}s)' -f $state, [int]((Get-Date) - $started).TotalSeconds)
    }
    $registered = $false
    try {
        $registered = [bool](Add-TgosAfterRestartItem -Step 'reserved-storage')
        if ($withNetFx3) { $registered = [bool](Add-TgosAfterRestartItem -Step 'netfx3') -and $registered }
    }
    catch { Write-Host ('   could not schedule: {0}' -f (Format-LogLine $_.Exception.Message)) }
    $task = Get-ScheduledTask -TaskPath '\TGOS\' -TaskName 'Finish after restart' -ErrorAction SilentlyContinue
    $boot = @($task.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskBootTrigger' })
    $null = Assert-That ($registered -and $task -and $boot.Count -eq 1 -and $task.Principal.UserId -match '(?i)SYSTEM|S-1-5-18' -and $task.Settings.Hidden) ('retry: the after-restart task is registered (SYSTEM, at startup + {0}, hidden)' -f $(if ($boot.Count) { $boot[0].Delay } else { '?' }))
    if ($task) { Write-Host ('   task action: {0} {1}' -f $task.Actions[0].Execute, (Format-LogLine $task.Actions[0].Arguments)) }
    $list = @(Get-Content -LiteralPath (Join-Path $env:ProgramData 'TGOS\after-restart.txt') -ErrorAction SilentlyContinue)
    Write-Host ('   steps waiting: {0}' -f ($list -join ', '))
    if ($task) {
        $logBefore = @(Get-Content -LiteralPath (Join-Path $env:ProgramData 'TGOS\toolbox.log') -ErrorAction SilentlyContinue).Count
        $started = Get-Date
        Start-ScheduledTask -TaskPath '\TGOS\' -TaskName 'Finish after restart'
        # Sampai tugasnya selesai dan menghapus dirinya (atau 40 menit).
        for ($second = 0; $second -lt 2400; $second += 10) {
            Start-Sleep -Seconds 10
            $current = Get-ScheduledTask -TaskPath '\TGOS\' -TaskName 'Finish after restart' -ErrorAction SilentlyContinue
            if (-not $current -or ($second -ge 30 -and [string]$current.State -ne 'Running')) { break }
        }
        $current = Get-ScheduledTask -TaskPath '\TGOS\' -TaskName 'Finish after restart' -ErrorAction SilentlyContinue
        $seconds = [int]((Get-Date) - $started).TotalSeconds
        @(Get-Content -LiteralPath (Join-Path $env:ProgramData 'TGOS\toolbox.log') -ErrorAction SilentlyContinue) | Select-Object -Skip $logBefore |
            ForEach-Object { Write-Host ('   toolbox.log | {0}' -f (Format-LogLine $_)) }
        if ($current) {
            $info = $current | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
            Write-Host ('   task still registered: state {0}, last result 0x{1:X8}' -f $current.State, [int64]$info.LastTaskResult)
        }
        $null = Assert-That (-not $current -and -not (Test-Path -LiteralPath (Join-Path $env:ProgramData 'TGOS\after-restart.txt'))) ('retry: the after-restart task finished every step and removed itself ({0}s)' -f $seconds)
        if ($withNetFx3) {
            $state = (Get-WindowsOptionalFeature -Online -FeatureName NetFx3 -ErrorAction SilentlyContinue).State
            $null = Assert-That ([string]$state -eq 'Enabled') ('retry: .NET Framework 3.5 was installed by the after-restart task as SYSTEM while updates are paused ({0})' -f $state)
        }
        $folder = $null
        try { $scheduler = New-Object -ComObject 'Schedule.Service'; $scheduler.Connect(); $folder = $scheduler.GetFolder('\TGOS') } catch { }
        $null = Assert-That ($null -eq $folder) 'retry: the empty \TGOS task folder was removed too'
    }
}
# Pembeda "sedang dipakai" vs "tidak didukung" untuk Reserved Storage diuji di
# tools/selftest.py dengan contoh teks DISM.

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
$frameworks = @(Get-AppxPackage -AllUsers -Name 'Microsoft.NET.Native.*' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name } | Select-Object -Unique)
Write-Host ('   .NET Native frameworks now: {0}' -f $(if ($frameworks.Count) { $frameworks -join ', ' } else { 'none' }))
try {
    Get-WinEvent -LogName 'Microsoft-Windows-AppXDeploymentServer/Operational' -MaxEvents 4000 -ErrorAction Stop |
        Where-Object { $_.Message -match 'NET\.Native' -and $_.Message -match '(?i)remov|deprovision|uninstall' } |
        Select-Object -First 6 |
        ForEach-Object { Write-Host ('   appx event {0:HH:mm:ss} id {1}: {2}' -f $_.TimeCreated, $_.Id, (Format-LogLine $_.Message)) }
}
catch {
    Write-Host ('   appx events not readable: {0}' -f (Format-LogLine $_.Exception.Message))
}
    $command = '"{0}" "{1}" "{2}" "{3}" 2>&1' -f $python.Source, (Join-Path $repoRoot 'tools\compare-snapshots.py'), (Join-Path $artifacts 'TGOS-snapshot-before.json'), $after.FullName
    $compare = & cmd.exe /c ('"{0}"' -f $command) | Out-String
    $compareExit = $LASTEXITCODE
    Set-Content -LiteralPath (Join-Path $artifacts 'compare.txt') -Value $compare -Encoding ASCII
    $compare -split "`r?`n" | Where-Object { $_ -match 'Proses|RAM terpakai|Layanan berjalan|Paket AppX:|^Layanan:|^Tugas terjadwal:|Defender|BAHAYA|^\s+!|Selesai' } |
        Select-Object -First 20 | ForEach-Object { Write-Host ('   | ' + (Format-LogLine $_)) }
    $null = Assert-That ($compareExit -eq 0) 'compare: nothing to investigate between the snapshots'
}

# =======================================================================================
# Pasang ulang Microsoft Store setelah dihapus playbook. Paling akhir, karena Store yang
# kembali akan membuat pemeriksaan "Store dihapus" di atas gagal. Hanya informasi:
# unduhannya asinkron dan bergantung pada layanan Microsoft.
if ($plannedOptions -contains 'remove-store' -and $runnerEdition -notlike 'Server*') {
    Write-Section 'Reinstall Microsoft Store (information only)'
    if (Get-AppxPackage -AllUsers -Name 'Microsoft.WindowsStore' -ErrorAction SilentlyContinue) {
        Write-Host '   the Microsoft Store is present, so there is nothing to reinstall'
    }
    else {
        $code = Invoke-TgosProcess -File (Join-Path $env:SystemRoot 'System32\wsreset.exe') -Arguments '-i' -TimeoutMilliseconds 120000
        Write-Host ('   wsreset -i exit code: {0}' -f $code)
        $back = $false
        for ($second = 0; $second -lt 300 -and -not $back; $second += 10) {
            $back = [bool](Get-AppxPackage -AllUsers -Name 'Microsoft.WindowsStore' -ErrorAction SilentlyContinue)
            if (-not $back) { Start-Sleep -Seconds 10 }
        }
        if ($back) { Write-Host ('   info  the Microsoft Store is back after about {0} s' -f $second) }
        else { Write-Host '   info  the Microsoft Store did not come back within 5 minutes' }
    }
}

Write-Section 'Result'
Write-Host ('CI SUMMARY: {0} passed, {1} failed' -f $script:passed, $script:failures.Count)
if ($script:failures.Count -gt 0) {
    $script:failures | ForEach-Object { Write-Host ('  - {0}' -f $_) }
    exit 1
}
exit 0
