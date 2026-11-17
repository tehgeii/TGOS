<#
.SYNOPSIS
    Mengunduh dan memasang satu program pilihan pengguna dari sumber resminya.

.DESCRIPTION
    -Item
        brave     Brave Browser      (rilis resmi Brave di GitHub)
        chrome    Google Chrome      (MSI enterprise dari dl.google.com)
        firefox   Mozilla Firefox    (download.mozilla.org)
        7zip      7-Zip              (www.7-zip.org)
        vcredist  Visual C++ 2015-2022 Redistributable x64 dan x86 (aka.ms)
        directx   DirectX End-User Runtime, pustaka lama Juni 2010 (download.microsoft.com)

    Urutan kerja untuk tiap file:
      1. Diunduh lewat HTTPS ke folder sementara.
      2. Tanda tangan digitalnya diperiksa: harus sah dan penerbitnya harus cocok
         (Brave Software, Google, Mozilla, Microsoft). File yang tidak cocok TIDAK
         dijalankan. Pengecualian: 7-Zip tidak ditandatangani pembuatnya, jadi yang
         diperiksa info versi filenya (ProductName "7-Zip").
      3. Dijalankan tanpa tampilan (silent).
      4. Hasilnya diperiksa dari file program yang seharusnya ada.

    Hasil dicatat di <folder data TGOS>\software.txt, satu baris per program:
        brave: requested
        brave: installed
    Baris "requested" dipakai Remove-Edge.ps1: bila browser yang diminta tidak
    terpasang, Edge tidak dihapus.

    Bila unduhan gagal (mis. tanpa internet), skrip menulis WARNING dan selesai: playbook
    tetap lanjut. Pemasangan bisa diulang dari TGOS Toolbox.

    -Force mengunduh dan memasang walaupun programnya sudah ada (memasang ulang atau
    memperbarui). Dipakai tombol di TGOS Toolbox dan uji otomatis.

    -UrlOverride hanya untuk pengujian (mengganti alamat unduhan).

    Kode keluar: 0 terpasang atau sudah ada, 1 gagal. Playbook tidak berhenti pada 1.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('brave', 'chrome', 'firefox', '7zip', 'vcredist', 'directx')]
    [string]$Item,

    [string]$DataDirectory,
    [switch]$Force,
    [string]$UrlOverride
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

$UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) TGOS-Setup'
$DownloadTimeoutMilliseconds = 900000
$InstallTimeoutMilliseconds = 900000

function Get-ProgramPath {
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

function Test-VcRuntime {
    param([string]$Architecture)
    $paths = @(
        ('HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\{0}' -f $Architecture),
        ('HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\{0}' -f $Architecture))
    foreach ($path in $paths) {
        $installed = (Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue).Installed
        if ($installed -eq 1) { return $true }
    }
    return $false
}

function Get-SevenZipUrl {
    # Halaman unduhan resmi memuat tautan seperti "a/7z2409-x64.exe"; yang pertama
    # adalah versi stabil terbaru.
    $client = New-Object System.Net.WebClient
    try {
        $client.Headers['User-Agent'] = $UserAgent
        $page = $client.DownloadString('https://www.7-zip.org/download.html')
    }
    finally { $client.Dispose() }
    if ($page -match 'href="(?<path>a/7z\d+-x64\.exe)"') {
        return ('https://www.7-zip.org/{0}' -f $Matches['path'])
    }
    throw 'no 64-bit installer link found on www.7-zip.org'
}

# Katalog. Signer = teks yang harus ada di subjek sertifikat penanda tangan.
$Catalog = @{
    brave    = @{
        Name  = 'Brave'
        Files = @(@{ Url = 'https://github.com/brave/brave-browser/releases/latest/download/BraveBrowserStandaloneSilentSetup.exe'
                File = 'BraveBrowserStandaloneSilentSetup.exe'; Arguments = ''; Signer = 'Brave Software' })
        Test  = { [bool](Get-ProgramPath 'BraveSoftware\Brave-Browser\Application\brave.exe') }
    }
    chrome   = @{
        Name  = 'Google Chrome'
        Files = @(@{ Url = 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi'
                File = 'GoogleChromeStandaloneEnterprise64.msi'; Msi = $true; Signer = 'Google LLC' })
        Test  = { [bool](Get-ProgramPath 'Google\Chrome\Application\chrome.exe') }
    }
    firefox  = @{
        Name  = 'Mozilla Firefox'
        Files = @(@{ Url = 'https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US'
                File = 'FirefoxSetup.exe'; Arguments = '/S'; Signer = 'Mozilla Corporation' })
        Test  = { [bool](Get-ProgramPath 'Mozilla Firefox\firefox.exe') }
    }
    '7zip'   = @{
        Name  = '7-Zip'
        Files = @(@{ UrlResolver = { Get-SevenZipUrl }; File = '7z-x64.exe'; Arguments = '/S'; ProductName = '7-Zip' })
        Test  = { [bool](Get-ProgramPath '7-Zip\7z.exe') }
    }
    vcredist = @{
        Name  = 'Visual C++ Redistributable'
        Files = @(
            @{ Url = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'; File = 'vc_redist.x64.exe'
                Arguments = '/install /quiet /norestart'; Signer = 'Microsoft Corporation'; SuccessCodes = @(0, 3010, 1638) },
            @{ Url = 'https://aka.ms/vs/17/release/vc_redist.x86.exe'; File = 'vc_redist.x86.exe'
                Arguments = '/install /quiet /norestart'; Signer = 'Microsoft Corporation'; SuccessCodes = @(0, 3010, 1638) })
        Test  = { (Test-VcRuntime 'x64') -and (Test-VcRuntime 'x86') }
    }
    directx  = @{
        Name  = 'DirectX End-User Runtime'
        Files = @(@{ Url = 'https://download.microsoft.com/download/1/7/1/1718CCC4-6315-4D8E-9543-8E28A4E18C4C/dxwebsetup.exe'
                File = 'dxwebsetup.exe'; Arguments = '/Q'; Signer = 'Microsoft Corporation' })
        Test  = { Test-Path -LiteralPath (Join-Path $env:SystemRoot 'System32\d3dx9_43.dll') }
    }
}

function Write-SoftwareRecord {
    param([string]$State)
    try {
        $file = Join-Path $DataDirectory 'software.txt'
        $kept = @()
        if (Test-Path -LiteralPath $file) {
            $kept = @(Get-Content -LiteralPath $file | Where-Object { $_ -and $_ -notmatch ('^{0}:\s*{1}\b' -f [regex]::Escape($Item), [regex]::Escape($State)) })
            if ($State -ne 'requested') {
                # Hasil lama untuk program yang sama diganti.
                $kept = @($kept | Where-Object { $_ -notmatch ('^{0}:\s*(installed|failed)\b' -f [regex]::Escape($Item)) })
            }
        }
        Set-Content -LiteralPath $file -Value (@($kept) + ('{0}: {1}' -f $Item, $State)) -Encoding ASCII
    }
    catch {
        Write-Output ("WARNING: could not update software.txt: {0}" -f (Format-TgosError $_))
    }
}

function Save-Download {
    param([string]$Url, [string]$Path)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $client = New-Object System.Net.WebClient
    try {
        $client.Headers['User-Agent'] = $UserAgent
        $task = $client.DownloadFileTaskAsync($Url, $Path)
        if (-not $task.Wait($DownloadTimeoutMilliseconds)) {
            $client.CancelAsync()
            throw 'the download did not finish within 15 minutes'
        }
    }
    catch {
        $inner = $_.Exception
        while ($inner.InnerException) { $inner = $inner.InnerException }
        throw ('download failed: {0}' -f (('' + $inner.Message) -replace '\s+', ' ').Trim())
    }
    finally { $client.Dispose() }
    if (-not (Test-Path -LiteralPath $Path) -or (Get-Item -LiteralPath $Path).Length -lt 100000) {
        throw 'download failed: the file is missing or too small'
    }
}

function Assert-TrustedFile {
    param($Spec, [string]$Path)
    if ($Spec.Signer) {
        $signature = Get-AuthenticodeSignature -LiteralPath $Path
        $subject = ''
        if ($signature.SignerCertificate) { $subject = [string]$signature.SignerCertificate.Subject }
        if ([string]$signature.Status -ne 'Valid') {
            throw ("signature is not valid ({0}); the file was not run" -f $signature.Status)
        }
        if ($subject -notmatch [regex]::Escape($Spec.Signer)) {
            throw ("unexpected publisher '{0}'; the file was not run" -f $subject)
        }
        return ('signed by {0}' -f $Spec.Signer)
    }
    if ($Spec.ProductName) {
        $product = [string](Get-Item -LiteralPath $Path).VersionInfo.ProductName
        if ($product -ne $Spec.ProductName) {
            throw ("unexpected product name '{0}'; the file was not run" -f $product)
        }
        return ('product {0} {1} (the author does not sign this file)' -f $product, (Get-Item -LiteralPath $Path).VersionInfo.ProductVersion)
    }
    throw 'no trust rule for this file; it was not run'
}

$exitCode = 1
$workDirectory = $null
try {
    $DataDirectory = Get-TgosDataDirectory -Path $DataDirectory
    $entry = $Catalog[$Item]
    Write-SoftwareRecord -State 'requested'

    if (-not $Force -and (& $entry.Test)) {
        Write-Output ("TGOS: {0} is already installed" -f $entry.Name)
        Write-SoftwareRecord -State 'installed'
        exit 0
    }

    $workDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('tgos-setup-{0}' -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null

    foreach ($spec in $entry.Files) {
        $url = $spec.Url
        if ($UrlOverride) { $url = $UrlOverride }
        elseif ($spec.UrlResolver) { $url = & $spec.UrlResolver }
        $path = Join-Path $workDirectory $spec.File

        Write-Output ("TGOS: downloading {0} from {1}" -f $spec.File, ([uri]$url).Host)
        Save-Download -Url $url -Path $path
        $trust = Assert-TrustedFile -Spec $spec -Path $path
        Write-Output ("TGOS: {0} verified: {1}, {2:N1} MB" -f $spec.File, $trust, ((Get-Item -LiteralPath $path).Length / 1MB))

        if ($spec.Msi) {
            $file = Join-Path $env:SystemRoot 'System32\msiexec.exe'
            $arguments = '/i "{0}" /qn /norestart' -f $path
        }
        else {
            $file = $path
            $arguments = [string]$spec.Arguments
        }
        $code = Invoke-TgosProcess -File $file -Arguments $arguments -TimeoutMilliseconds $InstallTimeoutMilliseconds
        if ($null -eq $code) { throw ("the installer {0} did not finish within 15 minutes" -f $spec.File) }
        $accepted = @(0, 3010)
        if ($spec.SuccessCodes) { $accepted = @($spec.SuccessCodes) }
        if ($accepted -notcontains $code) {
            Write-Output ("WARNING: the installer {0} returned exit code {1}" -f $spec.File, $code)
        }
        else {
            Write-Output ("TGOS: installer {0} finished with exit code {1}" -f $spec.File, $code)
        }
    }

    # Sebagian installer selesai sebelum semua filenya tertulis.
    $installed = $false
    for ($attempt = 0; $attempt -lt 30 -and -not $installed; $attempt++) {
        $installed = [bool](& $entry.Test)
        if (-not $installed) { Start-Sleep -Seconds 2 }
    }
    if ($installed) {
        Write-Output ("TGOS: {0} installed" -f $entry.Name)
        Write-SoftwareRecord -State 'installed'
        $exitCode = 0
    }
    else {
        throw 'the installer ran but the program was not found afterwards'
    }
}
catch {
    Write-Output ("WARNING: {0} was not installed: {1}" -f $Catalog[$Item].Name, (Format-TgosError $_))
    Write-SoftwareRecord -State 'failed'
}
finally {
    if ($workDirectory -and (Test-Path -LiteralPath $workDirectory)) {
        Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit $exitCode
