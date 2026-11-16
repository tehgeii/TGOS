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

function Format-TgosError {
    <# Pesan error satu baris, untuk ditulis ke log AME. #>
    param($ErrorRecord)
    return (('' + $ErrorRecord.Exception.Message) -replace '\s+', ' ').Trim()
}

function Split-TgosCommandLine {
    <#
    .SYNOPSIS
        Memisahkan baris perintah seperti UninstallString menjadi file dan argumennya.
        Mengembalikan @{ File; Arguments } atau $null bila tidak bisa dibaca.
    #>
    param([string]$CommandLine)

    $text = ('' + $CommandLine).Trim()
    if (-not $text) { return $null }
    if ($text.StartsWith('"')) {
        $end = $text.IndexOf('"', 1)
        if ($end -lt 0) { return $null }
        return @{ File = $text.Substring(1, $end - 1); Arguments = $text.Substring($end + 1).Trim() }
    }
    # Tanpa tanda kutip: jalur boleh berisi spasi, jadi dipotong setelah ".exe" pertama.
    if ($text -match '^(?<file>.+?\.exe)(?:\s+(?<args>.*))?$') {
        return @{ File = $Matches['file']; Arguments = ('' + $Matches['args']).Trim() }
    }
    return $null
}

function Invoke-TgosProcess {
    <#
    .SYNOPSIS
        Menjalankan program tanpa jendela dan menunggu sampai selesai.
        Mengembalikan kode keluarnya, atau $null bila melewati batas waktu.

    .PARAMETER WithoutWindir
        Menghapus variabel lingkungan "windir" HANYA untuk proses yang dijalankan.
    #>
    param(
        [string]$File,
        [string]$Arguments,
        [int]$TimeoutMilliseconds = 300000,
        [switch]$WithoutWindir
    )

    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $File
    $info.Arguments = $Arguments
    $info.WorkingDirectory = Split-Path -Parent $File
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    if ($WithoutWindir) {
        $info.EnvironmentVariables.Remove('windir')
    }

    $process = [System.Diagnostics.Process]::Start($info)
    if (-not $process.WaitForExit($TimeoutMilliseconds)) {
        try { $process.Kill() } catch { }
        return $null
    }
    return $process.ExitCode
}

function Remove-TgosChromiumProduct {
    <#
    .SYNOPSIS
        Menjalankan uninstaller produk Microsoft berbasis Chromium (Edge, Copilot) yang
        sering menolak bekerja, dengan dua cara berurutan. Berhenti begitu produknya
        hilang. Hasil akhirnya diperiksa pemanggil lewat $TestInstalled.

    .DESCRIPTION
        Cara 1 - penanda Edge lama: berkas kosong
            %SystemRoot%\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe\MicrosoftEdge.exe,
            nilai AllowUninstall, dan label eksperimen EdgeUpdate dihapus.
        Cara 2 - uninstaller dijalankan tanpa variabel "windir" (hanya proses itu).

        Berkas penanda selalu dibersihkan lagi. Kedua cara berasal dari pengamatan
        komunitas, bukan dokumentasi Microsoft, jadi bisa berhenti bekerja.
    #>
    param(
        [string]$Label,
        [string]$Setup,
        [string]$Arguments,
        [scriptblock]$TestInstalled,
        [scriptblock]$StopProcesses,
        [string]$ClientStateGuid
    )

    $stubDirectory = Join-Path $env:SystemRoot 'SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe'
    $stubFile = Join-Path $stubDirectory 'MicrosoftEdge.exe'
    $createdStubDirectory = $false
    $createdStubFile = $false

    try {
        $allowKey = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev'
        if (-not (Test-Path -LiteralPath $allowKey)) {
            New-Item -Path $allowKey -Force | Out-Null
        }
        Set-ItemProperty -LiteralPath $allowKey -Name 'AllowUninstall' -Value '' -Type String

        if ($ClientStateGuid) {
            $clientState = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\ClientState\{0}' -f $ClientStateGuid
            if (Test-Path -LiteralPath $clientState) {
                Remove-ItemProperty -LiteralPath $clientState -Name 'experiment_control_labels' -ErrorAction SilentlyContinue
            }
        }

        try {
            if (-not (Test-Path -LiteralPath $stubDirectory)) {
                New-Item -ItemType Directory -Path $stubDirectory -Force | Out-Null
                $createdStubDirectory = $true
            }
            if (-not (Test-Path -LiteralPath $stubFile)) {
                New-Item -ItemType File -Path $stubFile -Force | Out-Null
                $createdStubFile = $true
            }
        }
        catch {
            Write-Output ("WARNING: could not create the legacy Edge marker: {0}" -f (Format-TgosError $_))
        }

        if ($StopProcesses) { & $StopProcesses }
        Write-Output ("TGOS: {0} removal method 1 (legacy marker): {1} {2}" -f $Label, $Setup, $Arguments)
        $exitCode = Invoke-TgosProcess -File $Setup -Arguments $Arguments
        if ($null -eq $exitCode) {
            Write-Output ("WARNING: the {0} uninstaller did not finish within 5 minutes (method 1)" -f $Label)
        }
        else {
            Write-Output ("TGOS: {0} uninstaller exit code {1} (method 1)" -f $Label, $exitCode)
        }

        if ((& $TestInstalled) -and (Test-Path -LiteralPath $Setup)) {
            if ($StopProcesses) { & $StopProcesses }
            Write-Output ("TGOS: {0} removal method 2 (uninstaller without the windir variable)" -f $Label)
            $exitCode = Invoke-TgosProcess -File $Setup -Arguments $Arguments -WithoutWindir
            if ($null -eq $exitCode) {
                Write-Output ("WARNING: the {0} uninstaller did not finish within 5 minutes (method 2)" -f $Label)
            }
            else {
                Write-Output ("TGOS: {0} uninstaller exit code {1} (method 2)" -f $Label, $exitCode)
            }
        }
    }
    finally {
        # Hanya yang dibuat fungsi ini yang dihapus.
        if ($createdStubFile -and (Test-Path -LiteralPath $stubFile)) {
            Remove-Item -LiteralPath $stubFile -Force -ErrorAction SilentlyContinue
        }
        if ($createdStubDirectory -and (Test-Path -LiteralPath $stubDirectory)) {
            Remove-Item -LiteralPath $stubDirectory -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-TgosInstalledBrowsers {
    <#
    .SYNOPSIS
        Browser selain Edge yang terpasang untuk semua pengguna.
        Mengembalikan daftar @{ Name; Exe; LinkName }. LinkName adalah nama pintasan di
        "%ProgramData%\Microsoft\Windows\Start Menu\Programs" yang dibuat installer-nya.
    #>
    $known = @(
        @{ Name = 'Brave'; Relative = 'BraveSoftware\Brave-Browser\Application\brave.exe'; LinkName = 'Brave.lnk' },
        @{ Name = 'Chrome'; Relative = 'Google\Chrome\Application\chrome.exe'; LinkName = 'Google Chrome.lnk' },
        @{ Name = 'Firefox'; Relative = 'Mozilla Firefox\firefox.exe'; LinkName = 'Firefox.lnk' })
    $found = @()
    foreach ($browser in $known) {
        foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if (-not $base) { continue }
            $exe = Join-Path $base $browser.Relative
            if (Test-Path -LiteralPath $exe) {
                $found += @{ Name = $browser.Name; Exe = $exe; LinkName = $browser.LinkName }
                break
            }
        }
    }
    return $found
}

function Get-TgosUserProfiles {
    <#
    .SYNOPSIS
        Profil pengguna biasa di mesin ini: daftar @{ Sid; Path }.
    #>
    $list = @()
    $root = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    foreach ($key in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
        if ($key.PSChildName -notmatch '^S-1-5-21-[\d-]+$') { continue }
        $path = (Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
        if ($path -and (Test-Path -LiteralPath $path)) {
            $list += @{ Sid = $key.PSChildName; Path = [string]$path }
        }
    }
    return $list
}
