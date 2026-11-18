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

function Get-TgosAfterRestartList {
    <#
    .SYNOPSIS
        Langkah yang menunggu restart, dari %ProgramData%\TGOS\after-restart.txt.
        Mengembalikan hashtable @{ Name; Attempts } per langkah (bisa kosong).
    #>
    $file = Join-Path $env:ProgramData 'TGOS\after-restart.txt'
    $items = @()
    if (Test-Path -LiteralPath $file) {
        foreach ($line in @(Get-Content -LiteralPath $file -ErrorAction SilentlyContinue)) {
            if ($line -match '^(?<step>[a-z0-9-]+)\|(?<attempts>\d+)$') {
                $items += , @{ Name = $Matches['step']; Attempts = [int]$Matches['attempts'] }
            }
        }
    }
    return $items
}

function Set-TgosAfterRestartList {
    <# Menulis daftar langkah yang menunggu restart; daftar kosong = file dihapus. #>
    param([object[]]$Items)
    $file = Join-Path (Get-TgosDataDirectory) 'after-restart.txt'
    $lines = @($Items | Where-Object { $_ } | ForEach-Object { '{0}|{1}' -f $_.Name, $_.Attempts })
    if ($lines.Count -gt 0) { Set-Content -LiteralPath $file -Value $lines -Encoding ASCII }
    else { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
}

function Register-TgosAfterRestartTask {
    <#
    .SYNOPSIS
        Mendaftarkan tugas terjadwal tersembunyi \TGOS\Finish after restart, bila belum ada.
        Mengembalikan $true bila tugas itu ada, $false bila TGOS Toolbox belum terpasang
        (Install-Toolbox.ps1 mendaftarkannya nanti).

    .DESCRIPTION
        Tugas itu berjalan sebagai SYSTEM (sesi 0, jadi tanpa jendela), 3 menit setelah
        startup, dan menjalankan Complete-AfterRestart.ps1 dari TGOS Toolbox. Skrip itu
        menghapus tugas ini begitu daftar langkahnya kosong. Tugas yang sudah ada tidak
        didaftarkan ulang (bisa sedang berjalan).
    #>
    if (Get-ScheduledTask -TaskPath '\TGOS\' -TaskName 'Finish after restart' -ErrorAction SilentlyContinue) { return $true }
    $script = Join-Path ('{0}\' -f $env:SystemDrive) 'TGOS Toolbox\Support\Complete-AfterRestart.ps1'
    if (-not (Test-Path -LiteralPath $script)) { return $false }
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argument = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $script
    $action = New-ScheduledTaskAction -Execute $powershell -Argument $argument
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $trigger.Delay = 'PT3M'
    $principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden `
        -ExecutionTimeLimit (New-TimeSpan -Hours 2)
    Register-ScheduledTask -TaskPath '\TGOS\' -TaskName 'Finish after restart' -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force `
        -Description 'TGOS: finishes steps that had to wait for a restart, then removes itself.' | Out-Null
    return $true
}

function Unregister-TgosAfterRestartTask {
    <# Menghapus tugas \TGOS\Finish after restart, dan folder \TGOS bila sudah kosong. #>
    Unregister-ScheduledTask -TaskPath '\TGOS\' -TaskName 'Finish after restart' -Confirm:$false -ErrorAction SilentlyContinue
    try {
        $scheduler = New-Object -ComObject 'Schedule.Service'
        $scheduler.Connect()
        $folder = $scheduler.GetFolder('\TGOS')
        if ($folder.GetTasks(1).Count -eq 0 -and $folder.GetFolders(0).Count -eq 0) { $scheduler.GetFolder('\').DeleteFolder('TGOS', 0) }
    }
    catch { }
}

function Add-TgosAfterRestartItem {
    <#
    .SYNOPSIS
        Menjadwalkan satu langkah untuk dicoba lagi otomatis setelah restart berikutnya.

    .DESCRIPTION
        Dipakai bila Windows sedang sibuk saat instalasi: reserved storage sedang dipakai
        update (DISM 0x800F0975, Invoke-DeepClean.ps1) atau .NET Framework 3.5 tidak bisa
        diunduh karena Windows Update sibuk (Install-Software.ps1). Mengembalikan $true bila
        tugas startup sudah terdaftar (lihat Register-TgosAfterRestartTask).
    #>
    param(
        [ValidateSet('reserved-storage', 'netfx3')]
        [string]$Step
    )
    $items = @(Get-TgosAfterRestartList)
    if (@($items | Where-Object { $_.Name -eq $Step }).Count -eq 0) {
        $items += , @{ Name = $Step; Attempts = 0 }
        Set-TgosAfterRestartList -Items $items
    }
    return (Register-TgosAfterRestartTask)
}

function Remove-TgosFolder {
    <#
    .SYNOPSIS
        Menghapus satu folder beserta isinya, tanpa jendela.
        Mengembalikan 'absent', 'removed', atau 'scheduled'.

    .DESCRIPTION
        File yang masih terkunci didaftarkan ke Windows untuk dihapus saat restart
        berikutnya (MoveFileEx dengan MOVEFILE_DELAY_UNTIL_REBOOT, mekanisme resmi yang juga
        dipakai installer; butuh hak admin). Folder yang berisi link (junction atau symlink)
        tidak disentuh, supaya isi di luar folder itu tidak ikut terhapus.
    #>
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 'absent' }
    $root = Get-Item -LiteralPath $Path -Force
    $items = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue)
    if (($root.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        @($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) {
        throw ('{0} contains a link; it was left as is' -f $Path)
    }
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $Path)) { return 'removed' }

    if (-not ('Tgos.NativeFile' -as [type])) {
        Add-Type -Namespace Tgos -Name NativeFile -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);
'@
    }
    # File dulu, lalu folder dari yang paling dalam: Windows menghapusnya berurutan.
    $items = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue)
    $ordered = @($items | Where-Object { -not $_.PSIsContainer }) +
        @($items | Where-Object { $_.PSIsContainer } | Sort-Object { $_.FullName.Length } -Descending)
    foreach ($item in $ordered) {
        [void][Tgos.NativeFile]::MoveFileEx($item.FullName, $null, 4)
    }
    [void][Tgos.NativeFile]::MoveFileEx($Path, $null, 4)
    return 'scheduled'
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
        Browser selain Edge yang terpasang untuk semua pengguna, dalam urutan tetap
        (Brave, Chrome, Firefox). Mengembalikan daftar @{ Name; Option; Exe; LinkName }.
        Option = nama opsi Wizard untuk browser itu. LinkName = nama pintasan yang biasa
        dibuat installer-nya di "%ProgramData%\Microsoft\Windows\Start Menu\Programs";
        hanya dipakai bila pintasan tidak bisa ditemukan menurut targetnya.
    #>
    $known = @(
        @{ Name = 'Brave'; Option = 'browser-brave'; Relative = 'BraveSoftware\Brave-Browser\Application\brave.exe'; LinkName = 'Brave.lnk' },
        @{ Name = 'Chrome'; Option = 'browser-chrome'; Relative = 'Google\Chrome\Application\chrome.exe'; LinkName = 'Google Chrome.lnk' },
        @{ Name = 'Firefox'; Option = 'browser-firefox'; Relative = 'Mozilla Firefox\firefox.exe'; LinkName = 'Firefox.lnk' })
    $found = @()
    foreach ($browser in $known) {
        foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if (-not $base) { continue }
            $exe = Join-Path $base $browser.Relative
            if (Test-Path -LiteralPath $exe) {
                $found += @{ Name = $browser.Name; Option = $browser.Option; Exe = $exe; LinkName = $browser.LinkName }
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

function Get-TgosNativeArchitecture {
    <#
    .SYNOPSIS
        Arsitektur asli Windows (AMD64, ARM64, x86), juga bila PowerShell berjalan lewat
        emulasi. Dibaca dari variabel lingkungan sistem di registry.
    #>
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    $value = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).PROCESSOR_ARCHITECTURE
    if ($value) { return [string]$value }
    if ($env:PROCESSOR_ARCHITEW6432) { return $env:PROCESSOR_ARCHITEW6432 }
    return $env:PROCESSOR_ARCHITECTURE
}

function ConvertTo-TgosVersion {
    <#
    .SYNOPSIS
        Mengubah teks versi seperti "26.06", "160.0.1", atau "1.2.3.4 beta" menjadi
        [version]. Mengembalikan $null bila tidak ada angka versi di awal teks.
    #>
    param([string]$Text)
    if (('' + $Text).Trim() -notmatch '^(?<v>\d+(?:\.\d+){0,3})') { return $null }
    $parts = $Matches['v'] -split '\.'
    while ($parts.Count -lt 2) { $parts += '0' }
    try { return [version]($parts -join '.') } catch { return $null }
}

function Get-TgosManifestSha256 {
    <#
    .SYNOPSIS
        SHA256 untuk satu InstallerUrl dari teks manifest installer winget
        (microsoft/winget-pkgs). Mengembalikan teks heksadesimal huruf besar, atau $null.
    #>
    param([string]$Manifest, [string]$InstallerUrl)
    $lines = ('' + $Manifest).Replace("`r", '') -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '^\s*(?:-\s+)?InstallerUrl:\s*(?<url>\S+)\s*$') { continue }
        if ($Matches['url'] -ne $InstallerUrl) { continue }
        # SHA256 ada beberapa baris di bawah, di blok installer yang sama.
        for ($j = $i + 1; $j -lt $lines.Count -and $j -le $i + 6; $j++) {
            if ($lines[$j] -match '^\s*-\s') { break }
            if ($lines[$j] -match '^\s*InstallerSha256:\s*(?<sha>[0-9A-Fa-f]{64})\s*$') {
                return $Matches['sha'].ToUpperInvariant()
            }
        }
        return $null
    }
    return $null
}
