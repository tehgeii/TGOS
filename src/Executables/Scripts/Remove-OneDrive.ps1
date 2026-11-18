<#
.SYNOPSIS
    Menghapus OneDrive dengan uninstaller resminya, tanpa sisa yang memunculkan jendela.

.DESCRIPTION
    Dijalankan sebagai pengguna yang sedang login (token ter-elevasi), karena OneDrive
    terpasang per pengguna.

      1. Semua proses keluarga OneDrive di sesi ini dihentikan dulu: OneDrive.exe dan
         pembantunya (Microsoft.SharePoint.exe untuk sinkronisasi Microsoft Lists,
         FileCoAuth.exe, updater, launcher). Di uji VM revisi ketiga 1.0.0 hanya
         OneDrive.exe yang dihentikan; Microsoft.SharePoint.exe masih mengunci file di
         ListSync, jadi uninstaller tidak bisa menghapus foldernya dan meninggalkan
         perintah bersih-bersih "rd /s". Explorer menjalankan perintah itu saat dinyalakan
         ulang di akhir instalasi: beberapa jendela cmd muncul lalu hilang.
      2. "OneDriveSetup.exe /uninstall" tanpa jendela, ditunggu sampai selesai.
      3. Entri RunOnce (milik pengguna ini dan milik mesin) yang menyebut OneDrive dicatat
         isinya di log lalu dihapus, dan bersih-bersih itu dikerjakan di sini tanpa jendela:
         folder aplikasi %LOCALAPPDATA%\Microsoft\OneDrive dihapus; file yang masih
         terkunci dihapus Windows saat restart berikutnya.

    File pengguna di folder OneDrive (%USERPROFILE%\OneDrive) TIDAK disentuh.

    Tidak fatal: kode keluar selalu 0. Hasilnya diperiksa Test-TgosResult.ps1.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

# OneDriveSetup ikut dihentikan bila sudah berjalan sebelum skrip ini (mis. pemasangan
# OneDrive saat login pertama), supaya tidak bentrok dengan uninstaller.
$Family = @('OneDrive', 'OneDriveSetup', 'OneDriveStandaloneUpdater', 'OneDriveLauncher',
    'OneDriveFileLauncher', 'Microsoft.SharePoint', 'FileCoAuth', 'FileSyncConfig')
$Session = (Get-Process -Id $PID).SessionId

function Stop-OneDriveProcess {
    # Hanya proses di sesi pengguna ini; mengembalikan nama proses yang dihentikan.
    $found = @(Get-Process -Name $Family -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $Session })
    foreach ($process in $found) { try { $process.Kill() } catch { } }
    foreach ($process in $found) { try { [void]$process.WaitForExit(10000) } catch { } }
    return @($found | ForEach-Object { $_.ProcessName } | Sort-Object -Unique)
}

try {
    $stopped = @(Stop-OneDriveProcess)
    if ($stopped.Count -gt 0) { Write-Output ("TGOS: stopped {0}" -f ($stopped -join ', ')) }

    $candidates = @(
        (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'),
        (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe')
    )
    $setup = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

    if ($setup) {
        Write-Output ("TGOS: running {0} /uninstall" -f $setup)
        $process = Start-Process -FilePath $setup -ArgumentList '/uninstall' -PassThru -WindowStyle Hidden
        if (-not $process.WaitForExit(180000)) {
            Write-Output 'WARNING: the OneDrive uninstaller did not finish within 3 minutes'
            exit 0
        }
        # Uninstaller bisa menjalankan salinan dirinya; tunggu sampai semuanya selesai.
        for ($second = 0; $second -lt 60; $second++) {
            if (-not @(Get-Process -Name 'OneDriveSetup' -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $Session }).Count) { break }
            Start-Sleep -Seconds 1
        }
        Write-Output ("TGOS: the OneDrive uninstaller finished with exit code {0}" -f $process.ExitCode)
        $restarted = @(Stop-OneDriveProcess)
        if ($restarted.Count -gt 0) { Write-Output ("TGOS: stopped {0} after the uninstaller" -f ($restarted -join ', ')) }
    }
    else {
        Write-Output 'TGOS: OneDriveSetup.exe not found; nothing to uninstall'
    }

    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is not set for this account' }
    $appFolder = Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive'
    if (Test-Path -LiteralPath (Join-Path $appFolder 'OneDrive.exe')) {
        Write-Output ("WARNING: OneDrive is still present at {0}" -f (Join-Path $appFolder 'OneDrive.exe'))
        exit 0
    }
    if ($setup) { Write-Output 'TGOS: OneDrive uninstalled for the current user' }

    # Perintah bersih-bersih yang ditinggalkan uninstaller untuk dijalankan Explorer.
    $entries = 0
    foreach ($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce')) {
        $item = Get-Item -LiteralPath $key -ErrorAction SilentlyContinue
        if (-not $item) { continue }
        foreach ($valueName in @($item.GetValueNames() | Where-Object { $_ })) {
            $data = [string]$item.GetValue($valueName, '', 'DoNotExpandEnvironmentNames')
            if (($valueName + ' ' + $data) -notmatch '(?i)onedrive') { continue }
            Remove-ItemProperty -LiteralPath $key -Name $valueName -Force
            $shown = ($data -replace '\s+', ' ').Trim()
            if ($shown.Length -gt 200) { $shown = $shown.Substring(0, 200) + ' ...' }
            Write-Output ("TGOS: removed the OneDrive cleanup entry '{0}' from {1}: {2}" -f $valueName, ($key -replace ':', ''), $shown)
            $entries++
        }
    }
    if ($entries -eq 0) { Write-Output 'TGOS: no OneDrive cleanup entries in RunOnce' }

    # Bersih-bersih yang sama, tanpa jendela. Hanya folder aplikasi di AppData\Local.
    switch (Remove-TgosFolder -Path $appFolder) {
        'absent' { Write-Output 'TGOS: no OneDrive app folder left' }
        'removed' { Write-Output 'TGOS: removed the leftover OneDrive app folder' }
        'scheduled' { Write-Output 'TGOS: some leftover OneDrive app files are in use; Windows removes them at the next restart' }
    }
}
catch {
    Write-Output ("WARNING: could not uninstall OneDrive: {0}" -f (Format-TgosError $_))
}

exit 0
