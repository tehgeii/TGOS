<#
.SYNOPSIS
    Memeriksa hal yang memengaruhi instalasi tetapi tidak menghentikannya: koneksi
    internet dan ruang disk kosong.

.DESCRIPTION
    Hanya menulis informasi ke log; tidak mengubah apa pun dan tidak fatal (kode keluar
    selalu 0). Syarat yang menghentikan playbook ada di Test-Compatibility.ps1.

      - Internet: dibutuhkan hanya bila pengguna memilih browser, 7-Zip, atau runtime
        game. Tanpa internet, pemasangan itu dilewati dan bisa diulang dari TGOS Toolbox.
      - Ruang disk: restore point dan unduhan butuh ruang.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param()

try {
    $online = $false
    foreach ($target in @('www.msftconnecttest.com', 'github.com')) {
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $pending = $client.BeginConnect($target, 443, $null, $null)
            if ($pending.AsyncWaitHandle.WaitOne(5000) -and $client.Connected) { $online = $true }
        }
        catch { }
        finally { $client.Close() }
        if ($online) { break }
    }
    if ($online) {
        Write-Output 'TGOS: internet connection available'
    }
    else {
        Write-Output 'WARNING: no internet connection: software downloads will be skipped (retry later from the TGOS Toolbox)'
    }

    $drive = New-Object System.IO.DriveInfo(($env:SystemDrive + '\'))
    $freeGb = [math]::Round($drive.AvailableFreeSpace / 1GB, 1)
    if ($freeGb -lt 8) {
        Write-Output ("WARNING: only {0} GB free on {1}; the restore point or downloads may fail" -f $freeGb, $env:SystemDrive)
    }
    else {
        Write-Output ("TGOS: {0} GB free on {1}" -f $freeGb, $env:SystemDrive)
    }
}
catch {
    Write-Output ("WARNING: prerequisite check failed: {0}" -f (($_.Exception.Message -replace '\s+', ' ').Trim()))
}

exit 0
