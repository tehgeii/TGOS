<#
.SYNOPSIS
    Menghapus Microsoft Edge dengan uninstaller milik Edge sendiri. EKSPERIMENTAL.

.DESCRIPTION
    Uninstaller Edge (setup.exe) menolak bekerja di banyak instalasi Windows 11: di
    Windows 11 Pro 26H2 ia keluar dengan kode 93 tanpa menghapus apa pun. Skrip ini
    mencoba dua cara berurutan dan berhenti begitu Edge hilang:

    Cara 1 - penanda Edge lama.
        Membuat berkas kosong
        %SystemRoot%\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe\MicrosoftEdge.exe
        (lokasi Edge versi lama), menandai Edge boleh di-uninstall (AllowUninstall),
        menghapus label eksperimen EdgeUpdate, lalu menjalankan uninstaller.

    Cara 2 - variabel windir dikosongkan.
        Menjalankan uninstaller yang sama dengan variabel lingkungan "windir" dihapus
        HANYA untuk proses uninstaller itu. Variabel sistem tidak diubah.

    Berkas penanda dari cara 1 selalu dibersihkan lagi di akhir.

    Kedua cara berasal dari pengamatan komunitas, bukan dari dokumentasi Microsoft,
    jadi bisa berhenti bekerja kapan saja. Microsoft Edge WebView2 Runtime TIDAK
    dihapus: itu produk terpisah yang dipakai banyak launcher dan aplikasi. Update
    Windows bisa memasang Edge lagi.

    Skrip ini tidak fatal (kode keluar selalu 0); hasil sebenarnya diperiksa
    Test-TgosResult.ps1.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$EdgeClientState = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\ClientState\{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'
$UninstallArguments = '--uninstall --msedge --system-level --channel=stable --verbose-logging --force-uninstall'
$TimeoutMilliseconds = 300000

function Get-EdgeRoot {
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if ($base) {
            $root = Join-Path $base 'Microsoft\Edge\Application'
            if (Test-Path -LiteralPath $root) { return $root }
        }
    }
    return $null
}

function Test-EdgeInstalled {
    param([string]$Root)
    return (Test-Path -LiteralPath (Join-Path $Root 'msedge.exe'))
}

function Stop-EdgeProcesses {
    Get-Process -Name 'msedge' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

function Invoke-EdgeUninstaller {
    # Mengembalikan kode keluar uninstaller, atau $null bila tidak selesai tepat waktu.
    param(
        [string]$Setup,
        [switch]$WithoutWindir
    )

    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Setup
    $info.Arguments = $UninstallArguments
    $info.WorkingDirectory = Split-Path -Parent $Setup
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    if ($WithoutWindir) {
        # Hanya salinan lingkungan milik proses anak yang diubah.
        $info.EnvironmentVariables.Remove('windir')
    }

    $process = [System.Diagnostics.Process]::Start($info)
    if (-not $process.WaitForExit($TimeoutMilliseconds)) {
        try { $process.Kill() } catch { }
        return $null
    }
    return $process.ExitCode
}

$stubDirectory = Join-Path $env:SystemRoot 'SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe'
$stubFile = Join-Path $stubDirectory 'MicrosoftEdge.exe'
$createdStubDirectory = $false
$createdStubFile = $false

try {
    $edgeRoot = Get-EdgeRoot
    if (-not $edgeRoot -or -not (Test-EdgeInstalled -Root $edgeRoot)) {
        Write-Output 'TGOS: Microsoft Edge is not installed; nothing to remove'
        exit 0
    }

    $setup = Get-ChildItem -LiteralPath $edgeRoot -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'Installer\setup.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Sort-Object -Descending |
        Select-Object -First 1
    if (-not $setup) {
        Write-Output ("WARNING: no Edge setup.exe found under {0}" -f $edgeRoot)
        exit 0
    }

    # --- Persiapan bersama -----------------------------------------------------------
    $allowKey = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev'
    if (-not (Test-Path -LiteralPath $allowKey)) {
        New-Item -Path $allowKey -Force | Out-Null
    }
    Set-ItemProperty -LiteralPath $allowKey -Name 'AllowUninstall' -Value '' -Type String

    if (Test-Path -LiteralPath $EdgeClientState) {
        Remove-ItemProperty -LiteralPath $EdgeClientState -Name 'experiment_control_labels' -ErrorAction SilentlyContinue
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
        Write-Output ("WARNING: could not create the legacy Edge marker: {0}" -f (($_.Exception.Message -replace '\s+', ' ').Trim()))
    }

    # --- Cara 1 ----------------------------------------------------------------------
    Stop-EdgeProcesses
    Write-Output ("TGOS: Edge removal method 1 (legacy marker): {0} {1}" -f $setup, $UninstallArguments)
    $exitCode = Invoke-EdgeUninstaller -Setup $setup
    if ($null -eq $exitCode) {
        Write-Output 'WARNING: the Edge uninstaller did not finish within 5 minutes (method 1)'
    }
    else {
        Write-Output ("TGOS: Edge uninstaller exit code {0} (method 1)" -f $exitCode)
    }

    # --- Cara 2 ----------------------------------------------------------------------
    if ((Test-EdgeInstalled -Root $edgeRoot) -and (Test-Path -LiteralPath $setup)) {
        Stop-EdgeProcesses
        Write-Output 'TGOS: Edge removal method 2 (uninstaller without the windir variable)'
        $exitCode = Invoke-EdgeUninstaller -Setup $setup -WithoutWindir
        if ($null -eq $exitCode) {
            Write-Output 'WARNING: the Edge uninstaller did not finish within 5 minutes (method 2)'
        }
        else {
            Write-Output ("TGOS: Edge uninstaller exit code {0} (method 2)" -f $exitCode)
        }
    }

    if (Test-EdgeInstalled -Root $edgeRoot) {
        Write-Output 'WARNING: Microsoft Edge is still installed; Windows refused the uninstall'
    }
    else {
        Write-Output 'TGOS: Microsoft Edge removed (WebView2 Runtime kept)'
        foreach ($shortcut in @(
                (Join-Path $env:PUBLIC 'Desktop\Microsoft Edge.lnk'),
                (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk'))) {
            if (Test-Path -LiteralPath $shortcut) {
                Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
catch {
    Write-Output ("WARNING: could not remove Microsoft Edge: {0}" -f (($_.Exception.Message -replace '\s+', ' ').Trim()))
}
finally {
    # Hanya yang dibuat skrip ini yang dihapus.
    if ($createdStubFile -and (Test-Path -LiteralPath $stubFile)) {
        Remove-Item -LiteralPath $stubFile -Force -ErrorAction SilentlyContinue
    }
    if ($createdStubDirectory -and (Test-Path -LiteralPath $stubDirectory)) {
        Remove-Item -LiteralPath $stubDirectory -Force -ErrorAction SilentlyContinue
    }
}

exit 0
