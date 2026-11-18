<#
.SYNOPSIS
    Menyelesaikan langkah TGOS yang harus menunggu restart.

.DESCRIPTION
    Dijalankan tugas terjadwal tersembunyi \TGOS\Finish after restart (SYSTEM, sesi 0 jadi
    tanpa jendela, 3 menit setelah startup). Tugas itu didaftarkan Common.ps1
    (Add-TgosAfterRestartItem) bila sebuah langkah gagal karena Windows sedang sibuk saat
    instalasi:

      reserved-storage  Reserved Storage dimatikan. Saat instalasi Windows sedang memakainya
                        untuk update yang disiapkan (DISM 0x800F0975).
      <program>         Program per mesin yang gagal dipasang saat instalasi, dengan nama
                        -Item Install-Software.ps1 (netfx3, steam, epic, ea, ubisoft, browser,
                        runtime). Contoh: .NET Framework 3.5 saat Windows Update sibuk (uji VM
                        revisi kedua sampai keempat 1.0.0), EA app saat Windows Installer
                        masih memasang program lain (uji VM revisi keempat).

    Daftarnya di %ProgramData%\TGOS\after-restart.txt, satu baris "langkah|percobaan".
    Langkah yang ternyata sudah beres (mis. sudah dikerjakan dari Toolbox) langsung selesai,
    karena kedua skrip yang dipanggil tidak mengubah apa pun bila keadaannya sudah benar.
    Tiap langkah dicoba paling banyak 3 kali (3 kali startup). Hasilnya dicatat di
    %ProgramData%\TGOS\toolbox.log. Begitu daftarnya kosong, tugas terjadwal itu dihapus.

    Kode keluar selalu 0.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

$MaxAttempts = 3
$Software = @('netfx3', 'brave', 'chrome', 'firefox', '7zip', 'vcredist', 'vcredist-legacy', 'xna', 'directx',
    'dotnet', 'steam', 'epic', 'ea', 'ubisoft')

function Write-Log {
    param([string]$Message)
    try {
        $line = '{0}  After restart: {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath (Join-Path (Get-TgosDataDirectory) 'toolbox.log') -Value $line -Encoding ASCII
    }
    catch {
        # Log hanya catatan.
    }
}

function Invoke-SupportScript {
    # Menjalankan skrip Toolbox lain tanpa jendela; mengembalikan @{ Exit; Output }.
    param([string]$Script, [string]$Arguments)
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $info.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" {1}' -f (Join-Path $PSScriptRoot $Script), $Arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($info)
    $errors = $process.StandardError.ReadToEndAsync()
    $output = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()
    return @{ Exit = $process.ExitCode; Output = ($output + $errors.Result) }
}

function Get-LastLine {
    param([string]$Text, [string]$Pattern = '.')
    $line = @($Text -split "`r?`n" | Where-Object { $_.Trim() -and $_ -match $Pattern }) | Select-Object -Last 1
    $line = (('' + $line) -replace '\s+', ' ').Trim()
    if ($line.Length -gt 300) { $line = $line.Substring(0, 300) + ' ...' }
    return $line
}

try {
    $items = @(Get-TgosAfterRestartList)
    $kept = @()
    foreach ($item in $items) {
        $done = $false
        $detail = ''
        switch ($item.Name) {
            'reserved-storage' {
                $result = Invoke-SupportScript -Script 'Set-TgosFeature.ps1' -Arguments '-Feature ReservedStorage -State Off'
                if ($result.Exit -eq 0) { $done = $true; $detail = 'reserved storage is off' }
                elseif ($result.Exit -eq 3) { $done = $true; $detail = 'reserved storage is not supported on this PC' }
                elseif ($result.Exit -eq 4) { $detail = 'Windows is still using it for an update' }
                else { $detail = Get-LastLine $result.Output }
            }
            default {
                if ($Software -contains $item.Name) {
                    # Program yang sudah terpasang (mis. dari Toolbox) langsung selesai.
                    $result = Invoke-SupportScript -Script 'Install-Software.ps1' -Arguments ('-Item {0}' -f $item.Name)
                    if ($result.Exit -eq 0) { $done = $true; $detail = Get-LastLine $result.Output 'TGOS: .*(installed|skipped)' }
                    else { $detail = Get-LastLine $result.Output 'WARNING|TGOS:' }
                }
                else {
                    $done = $true
                    $detail = 'unknown step; dropped'
                }
            }
        }
        $attempt = $item.Attempts + 1
        if ($done) {
            Write-Log ('{0}: done ({1})' -f $item.Name, $detail)
        }
        elseif ($attempt -ge $MaxAttempts) {
            Write-Log ('{0}: gave up after {1} attempts ({2}); use the TGOS Toolbox to try again' -f $item.Name, $attempt, $detail)
        }
        else {
            Write-Log ('{0}: attempt {1} of {2} did not finish ({3}); trying again after the next restart' -f $item.Name, $attempt, $MaxAttempts, $detail)
            $kept += , @{ Name = $item.Name; Attempts = $attempt }
        }
    }
    Set-TgosAfterRestartList -Items $kept
    if ($kept.Count -eq 0) {
        Unregister-TgosAfterRestartTask
        Write-Log 'nothing left to do; the startup task was removed'
    }
}
catch {
    Write-Log ('FAILED: {0}' -f (Format-TgosError $_))
}

exit 0
