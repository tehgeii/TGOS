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
      5. Potret sistem sebelum dan sesudah, lalu dibandingkan.

    Semua yang penting dicetak ke log job, karena log itulah yang dibaca saat memeriksa
    hasil. Kode keluar bukan 0 berarti ada pemeriksaan yang gagal.

    JANGAN jalankan skrip ini di komputer sendiri: skrip ini benar-benar menerapkan
    playbook ke sistem tempat ia dijalankan.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.

.PARAMETER Options
    Opsi playbook dipisah spasi. Kosong = opsi bawaan (yang IsChecked di playbook.conf).
#>
[CmdletBinding()]
param(
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

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host ('=' * 78)
    Write-Host ('== {0}' -f $Title)
    Write-Host ('=' * 78)
}

function Add-Failure {
    param([string]$Message)
    $script:failures += $Message
    Write-Host ('::error::{0}' -f $Message)
}

function Assert-That {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host ('  ok    {0}' -f $Message)
    }
    else {
        Add-Failure $Message
    }
}

function Show-File {
    param([string]$Path, [int]$Tail = 200)
    if (Test-Path -LiteralPath $Path) {
        Write-Host ('--- {0} (last {1} lines)' -f $Path, $Tail)
        Get-Content -LiteralPath $Path -Tail $Tail | ForEach-Object { Write-Host $_ }
    }
    else {
        Write-Host ('--- {0}: not found' -f $Path)
    }
}

function Invoke-Playbook {
    <#
    Menjalankan runner AME terhadap satu folder playbook. Mengembalikan objek berisi
    kode keluar, keluaran, dan tanda waktu habis.
    #>
    param(
        [string]$CliDirectory,
        [string]$PlaybookDirectory,
        [string]$OptionList,
        [string]$Name
    )

    $exe = Join-Path $CliDirectory 'TrustedUninstaller.CLI.exe'
    $stdout = Join-Path $artifacts ('{0}-stdout.txt' -f $Name)
    $stderr = Join-Path $artifacts ('{0}-stderr.txt' -f $Name)

    $argumentList = '"{0}"' -f $PlaybookDirectory
    if ($OptionList) {
        $argumentList = '{0} {1}' -f $argumentList, $OptionList
    }
    Write-Host ('Running: TrustedUninstaller.CLI.exe {0}' -f $argumentList)

    $process = Start-Process -FilePath $exe -ArgumentList $argumentList -WorkingDirectory $CliDirectory `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -NoNewWindow -PassThru
    # Tanpa ini ExitCode kosong di Windows PowerShell 5.1 saat keluaran dialihkan.
    $null = $process.Handle

    $timedOut = $false
    if (-not $process.WaitForExit($TimeoutMinutes * 60 * 1000)) {
        $timedOut = $true
        Write-Host ('Timed out after {0} minutes; killing the process tree.' -f $TimeoutMinutes)
        & taskkill.exe /PID $process.Id /T /F | Out-Null
    }
    $process.WaitForExit()

    $output = ''
    if (Test-Path -LiteralPath $stdout) { $output = Get-Content -LiteralPath $stdout -Raw }
    if ($null -eq $output) { $output = '' }

    Show-File -Path $stdout -Tail 120
    Show-File -Path $stderr -Tail 60

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output   = $output
        TimedOut = $timedOut
    }
}

function Save-EngineLogs {
    param([string]$CliDirectory, [string]$Name)
    $logs = Join-Path $CliDirectory 'Logs'
    if (Test-Path -LiteralPath $logs) {
        $target = Join-Path $artifacts ('{0}-logs' -f $Name)
        Copy-Item -LiteralPath $logs -Destination $target -Recurse -Force
        Get-ChildItem -LiteralPath $target -Recurse -File | ForEach-Object {
            Show-File -Path $_.FullName -Tail 250
        }
        # Log dikosongkan supaya uji berikutnya tidak tercampur.
        Remove-Item -LiteralPath $logs -Recurse -Force
    }
    else {
        Write-Host ('No Logs folder in {0}' -f $CliDirectory)
    }
}

# ---------------------------------------------------------------------------------
Write-Section 'System'
$cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$runnerEdition = [string]$cv.EditionID
Write-Host ('Edition : {0}' -f $runnerEdition)
Write-Host ('Version : {0}' -f $cv.DisplayVersion)
Write-Host ('Build   : {0}.{1}' -f $cv.CurrentBuildNumber, $cv.UBR)
Write-Host ('PowerShell {0}' -f $PSVersionTable.PSVersion)
Write-Host ('Options : "{0}"' -f $Options)

# ---------------------------------------------------------------------------------
Write-Section 'Build .apbx'
& (Join-Path $repoRoot 'tools\build.ps1')
$apbx = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'release') -Filter '*.apbx' | Select-Object -First 1
Assert-That ($null -ne $apbx) 'build.ps1 produced an .apbx'
if ($null -eq $apbx) { throw 'No .apbx to test.' }

$sevenZip = Get-Command 7z -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($sevenZip) { $sevenZip = $sevenZip.Source } else { $sevenZip = Join-Path $env:ProgramFiles '7-Zip\7z.exe' }

$playbook = Join-Path $WorkDirectory 'playbook'
& $sevenZip x ('-o' + $playbook) '-pmalte' '-y' '-bso0' '-bsp0' $apbx.FullName
Assert-That ($LASTEXITCODE -eq 0) 'the .apbx extracts with the AME password'
Assert-That (Test-Path -LiteralPath (Join-Path $playbook 'playbook.conf')) 'playbook.conf is at the archive root'

# ---------------------------------------------------------------------------------
Write-Section 'Download AME CLI'
try {
    Add-MpPreference -ExclusionPath $WorkDirectory -ErrorAction Stop
    Write-Host ('Defender exclusion added for {0}' -f $WorkDirectory)
}
catch {
    Write-Host ('Could not add a Defender exclusion: {0}' -f $_.Exception.Message)
}

$cliZip = Join-Path $WorkDirectory 'CLI-Standalone.zip'
$cliUrl = 'https://github.com/Ameliorated-LLC/trusted-uninstaller-cli/releases/latest/download/CLI-Standalone.zip'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $cliUrl -OutFile $cliZip -UseBasicParsing
Write-Host ('Downloaded {0} bytes, SHA256 {1}' -f (Get-Item -LiteralPath $cliZip).Length, (Get-FileHash -LiteralPath $cliZip -Algorithm SHA256).Hash)

$cliRoot = Join-Path $WorkDirectory 'cli'
Expand-Archive -LiteralPath $cliZip -DestinationPath $cliRoot -Force
$cliExe = Get-ChildItem -LiteralPath $cliRoot -Recurse -Filter 'TrustedUninstaller.CLI.exe' | Select-Object -First 1
Assert-That ($null -ne $cliExe) 'TrustedUninstaller.CLI.exe is in the download'
if ($null -eq $cliExe) { throw 'AME CLI not found in the downloaded archive.' }
$cliDirectory = $cliExe.Directory.FullName
Write-Host ('CLI directory: {0}' -f $cliDirectory)
Get-ChildItem -LiteralPath $cliDirectory | ForEach-Object { Write-Host ('  {0,12}  {1}' -f $_.Length, $_.Name) }
Write-Host ('CLI file version: {0}' -f $cliExe.VersionInfo.FileVersion)

# ---------------------------------------------------------------------------------
Write-Section 'Snapshot before'
& (Join-Path $repoRoot 'tools\Get-SystemSnapshot.ps1') -Label before -OutputDirectory $artifacts

$installInfo = Join-Path $env:ProgramData 'TGOS\install-info.txt'

# ---------------------------------------------------------------------------------
Write-Section ('Reject test: unmodified playbook on edition {0}' -f $runnerEdition)
if ($runnerEdition -eq 'Professional') {
    Write-Host 'Runner is Windows Pro; the reject test does not apply.'
}
else {
    $reject = Invoke-Playbook -CliDirectory $cliDirectory -PlaybookDirectory $playbook -OptionList $Options -Name 'reject'
    Save-EngineLogs -CliDirectory $cliDirectory -Name 'reject'
    Assert-That (-not $reject.TimedOut) 'reject test: the engine did not hang'
    Assert-That (-not (Test-Path -LiteralPath $installInfo)) 'reject test: install-info.txt was NOT written (playbook halted before finalize)'
    Assert-That ($reject.Output -notmatch 'Playbook completed successfully') 'reject test: the engine did not report success'
}

# ---------------------------------------------------------------------------------
Write-Section 'Pass test: playbook with the runner edition allowed'
$playbookPass = Join-Path $WorkDirectory 'playbook-pass'
Copy-Item -LiteralPath $playbook -Destination $playbookPass -Recurse -Force
$compatibility = Join-Path $playbookPass 'Executables\Scripts\Test-Compatibility.ps1'
$original = "`$AllowedEditions = @('Professional')"
$patched = "`$AllowedEditions = @('Professional', '{0}')" -f $runnerEdition
$content = Get-Content -LiteralPath $compatibility -Raw
Assert-That ($content.Contains($original)) 'pass test: the edition list was found for patching'
Set-Content -LiteralPath $compatibility -Value $content.Replace($original, $patched) -Encoding ASCII

$pass = Invoke-Playbook -CliDirectory $cliDirectory -PlaybookDirectory $playbookPass -OptionList $Options -Name 'pass'
Save-EngineLogs -CliDirectory $cliDirectory -Name 'pass'
Assert-That (-not $pass.TimedOut) 'pass test: the engine did not hang'
Assert-That ($pass.Output -match 'Playbook completed successfully') 'pass test: the engine reported "Playbook completed successfully."'
Assert-That ($pass.Output -notmatch 'YAML Error|Fatal Playbook Error') 'pass test: no YAML or fatal error'
Assert-That (Test-Path -LiteralPath $installInfo) 'pass test: install-info.txt was written'
Show-File -Path $installInfo -Tail 40
Show-File -Path (Join-Path $env:ProgramData 'TGOS\restore-point.txt') -Tail 5

# ---------------------------------------------------------------------------------
Write-Section 'Snapshot after'
& (Join-Path $repoRoot 'tools\Get-SystemSnapshot.ps1') -Label after -OutputDirectory $artifacts

$python = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($python) {
    Write-Section 'Compare snapshots'
    & $python.Source (Join-Path $repoRoot 'tools\compare-snapshots.py') `
        (Join-Path $artifacts 'TGOS-snapshot-before.json') (Join-Path $artifacts 'TGOS-snapshot-after.json')
    Assert-That ($LASTEXITCODE -eq 0) 'compare-snapshots.py found nothing to investigate'
}

# ---------------------------------------------------------------------------------
Write-Section 'Result'
if ($script:failures.Count -gt 0) {
    Write-Host ('{0} check(s) failed:' -f $script:failures.Count)
    $script:failures | ForEach-Object { Write-Host ('  - {0}' -f $_) }
    exit 1
}
Write-Host 'All checks passed.'
exit 0
