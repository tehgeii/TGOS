<#
.SYNOPSIS
    Mengunduh dan memasang satu program pilihan pengguna dari sumber resminya.

.DESCRIPTION
    -Item
        brave     Brave Browser      (rilis resmi Brave di GitHub; installer untuk semua
                                      pengguna, dengan updater Brave)
        chrome    Google Chrome      (MSI enterprise dari dl.google.com)
        firefox   Mozilla Firefox    (download.mozilla.org)
        7zip      7-Zip              (rilis resmi ip7z/7zip di GitHub)
        vcredist  Visual C++ 2015-2022 Redistributable x64 dan x86 (aka.ms)
        directx   DirectX End-User Runtime, pustaka lama Juni 2010, paket lengkap
                  (download.microsoft.com)

    Urutan kerja untuk tiap file:
      1. Diunduh lewat HTTPS ke folder sementara.
      2. Tanda tangan digitalnya diperiksa: harus sah dan penerbitnya harus cocok
         (Brave Software, Google, Mozilla, Microsoft). File yang tidak cocok TIDAK
         dijalankan. Pengecualian: 7-Zip tidak ditandatangani pembuatnya, jadi filenya
         dicocokkan dengan SHA256 yang tercantum di manifest winget Microsoft untuk versi
         itu (microsoft/winget-pkgs), ditambah nama produk dan versinya. Bila manifest
         versi itu belum terbit, hanya nama produk dan versi yang diperiksa (dicatat).
      3. Tidak pernah menurunkan versi: bila program yang terpasang lebih baru dari file
         unduhan, file itu tidak dijalankan. Hanya dibandingkan untuk 7-Zip, yang nomor
         versi installernya sama dengan nomor versi programnya. Installer Firefox membawa
         nomor versi installer-nya sendiri (mis. 18.5, bukan 160.0), jadi tidak bisa
         dibandingkan; browser memperbarui dirinya sendiri.
      4. Dijalankan tanpa tampilan (silent).
      5. Hasilnya diperiksa dari file program yang seharusnya ada.

    Catatan Brave: installer "BraveBrowserStandaloneSilentSetup.exe" memasang per
    pengguna; dijalankan oleh playbook (sebagai sistem), Brave masuk ke profil SYSTEM yang
    tidak terlihat. Yang dipakai di sini "BraveBrowserStandaloneSetup.exe /silent
    /install", sama dengan manifest winget untuk pemasangan semua pengguna.

    DirectX: dipakai paket lengkap resmi "directx_Jun2010_redist.exe", bukan installer
    web "dxwebsetup.exe". Installer web tetap menampilkan jendela "Installing Microsoft
    DirectX" walaupun diberi /Q, dan mengunduh komponennya satu per satu (di uji VM v1.0.0
    ia macet sampai batas 15 menit). Paket lengkap diekstrak tanpa tampilan, lalu
    DXSETUP.exe di dalamnya dijalankan dengan /silent, mode senyap yang didokumentasikan
    Microsoft untuk installer game. Paket itu self-extractor IExpress: /Q saja masih
    menampilkan jendela progres "DirectX June 2010 SDK" (tertangkap uji otomatis), jadi
    dipakai /Q:A (tanpa tampilan sama sekali), /C (hanya ekstrak), /T:<folder>.
    Pemeriksaannya berlapis: tanda tangan Microsoft pada paket, SHA256 paket harus sama
    dengan checksum yang dikunci di katalog (file ini tidak berubah sejak 2010; nilainya
    sama dengan checksum paket Chocolatey "directx"), dan tanda tangan Microsoft pada
    DXSETUP.exe hasil ekstraknya. Hanya dipakai di Windows x64 (target TGOS); di Windows
    ARM64 langkah ini dilewati.

    Tiap file yang lolos pemeriksaan dicatat SHA256-nya di log.

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
$ExtractTimeoutMilliseconds = 300000

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

function Get-SevenZipRelease {
    <#
    Rilis 7-Zip terbaru dari repo resmi ip7z/7zip (alamat "releases/latest" GitHub tidak
    pernah menunjuk pre-release). Mengembalikan @{ Version; Url; Sha256 }; Sha256 berisi
    $null bila manifest winget untuk versi itu belum terbit.

    Sebelumnya versi dibaca dari tautan pertama di halaman 7-zip.org; di uji otomatis itu
    menghasilkan 7-Zip 23.01 yang lama. Jangan kembali ke cara itu.
    #>
    $request = [System.Net.HttpWebRequest]::Create('https://github.com/ip7z/7zip/releases/latest')
    $request.AllowAutoRedirect = $false
    $request.UserAgent = $UserAgent
    $request.Timeout = 30000
    $response = $request.GetResponse()
    try { $location = [string]$response.Headers['Location'] }
    finally { $response.Close() }
    if ($location -notmatch '/releases/tag/(?<tag>\d{2}\.\d{2})$') {
        throw ("unexpected 7-Zip latest release address: '{0}'" -f $location)
    }
    $tag = $Matches['tag']
    $release = @{
        Version = $tag
        Url     = ('https://github.com/ip7z/7zip/releases/download/{0}/7z{1}-x64.exe' -f $tag, $tag.Replace('.', ''))
        Sha256  = $null
    }

    $manifestUrl = 'https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests/7/7zip/7zip/{0}/7zip.7zip.installer.yaml' -f $tag
    $client = New-Object System.Net.WebClient
    try {
        $client.Headers['User-Agent'] = $UserAgent
        $release.Sha256 = Get-TgosManifestSha256 -Manifest $client.DownloadString($manifestUrl) -InstallerUrl $release.Url
    }
    catch {
        # Manifest versi baru biasanya terbit satu-dua hari setelah rilis.
        $release.Sha256 = $null
    }
    finally { $client.Dispose() }
    return $release
}

# Katalog. Signer = teks yang harus ada di subjek sertifikat penanda tangan.
$Catalog = @{
    brave    = @{
        Name  = 'Brave'
        # -2147219416 = sudah terpasang (dari manifest winget Brave.Brave).
        Files = @(@{ Url = 'https://github.com/brave/brave-browser/releases/latest/download/BraveBrowserStandaloneSetup.exe'
                File = 'BraveBrowserStandaloneSetup.exe'; Arguments = '/silent /install'; Signer = 'Brave Software'
                SuccessCodes = @(0, -2147219416) })
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
        Files = @(@{ Resolver = { Get-SevenZipRelease }; File = '7z-x64.exe'; Arguments = '/S'; ProductName = '7-Zip'
                CompareWith = '7-Zip\7z.exe' })
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
        # Paket lengkap: diekstrak dulu (Extract), lalu Setup di dalamnya dijalankan.
        # Sha256 = checksum yang dikunci untuk file unduhan (bukan untuk Setup).
        Files = @(@{ Url = 'https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe'
                File = 'directx_Jun2010_redist.exe'; Signer = 'Microsoft Corporation'
                Sha256 = '053F76DCBB28802E23341B6A787E3B0791C0FA5C8D4D011B1044172DBF89C73B'
                Extract = '/Q:A /C /T:"{0}"'; Setup = 'DXSETUP.exe'; Arguments = '/silent' })
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

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-TrustedFile {
    param($Spec, [string]$Path, $Release)
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
        $info = (Get-Item -LiteralPath $Path).VersionInfo
        $product = [string]$info.ProductName
        if ($product -ne $Spec.ProductName) {
            throw ("unexpected product name '{0}'; the file was not run" -f $product)
        }
        if ($Release -and $Release.Version -and -not ([string]$info.ProductVersion).StartsWith($Release.Version)) {
            throw ("version {0} does not match the release {1}; the file was not run" -f $info.ProductVersion, $Release.Version)
        }
        if ($Release -and $Release.Sha256) {
            $hash = Get-Sha256 $Path
            if ($hash -ne $Release.Sha256) {
                throw ("SHA256 {0} does not match the published checksum {1}; the file was not run" -f $hash, $Release.Sha256)
            }
            return ('product {0} {1}, SHA256 matches the winget manifest' -f $product, $info.ProductVersion)
        }
        return ('product {0} {1}; no published checksum for this version yet (the author does not sign this file)' -f $product, $info.ProductVersion)
    }
    throw 'no trust rule for this file; it was not run'
}

$exitCode = 1
$workDirectory = $null
try {
    # Windows PowerShell 5.1 tidak memakai TLS 1.2 secara bawaan; GitHub dan situs unduhan
    # lain mewajibkannya. Dipasang sebelum permintaan jaringan pertama.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $DataDirectory = Get-TgosDataDirectory -Path $DataDirectory
    $entry = $Catalog[$Item]
    Write-SoftwareRecord -State 'requested'

    if ($Item -eq 'directx' -and (Get-TgosNativeArchitecture) -ne 'AMD64') {
        Write-Output ("TGOS: DirectX End-User Runtime skipped: TGOS installs it on x64 Windows only (this PC is {0})" -f (Get-TgosNativeArchitecture))
        Write-SoftwareRecord -State 'skipped'
        exit 0
    }

    if (-not $Force -and (& $entry.Test)) {
        Write-Output ("TGOS: {0} is already installed" -f $entry.Name)
        Write-SoftwareRecord -State 'installed'
        exit 0
    }

    $workDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('tgos-setup-{0}' -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null

    foreach ($spec in $entry.Files) {
        $url = $spec.Url
        $release = $null
        if ($UrlOverride) { $url = $UrlOverride }
        elseif ($spec.Resolver) {
            $release = & $spec.Resolver
            $url = $release.Url
        }
        $path = Join-Path $workDirectory $spec.File

        Write-Output ("TGOS: downloading {0} from {1}" -f $spec.File, ([uri]$url).Host)
        Save-Download -Url $url -Path $path
        $trust = Assert-TrustedFile -Spec $spec -Path $path -Release $release
        if ($spec.Sha256) {
            $hash = Get-Sha256 $path
            if ($hash -ne $spec.Sha256) {
                throw ("SHA256 {0} does not match the pinned checksum {1}; the file was not run" -f $hash, $spec.Sha256)
            }
            $trust = '{0}, SHA256 matches the pinned checksum' -f $trust
        }
        Write-Output ("TGOS: {0} verified: {1}, {2:N1} MB, SHA256 {3}" -f $spec.File, $trust, ((Get-Item -LiteralPath $path).Length / 1MB), (Get-Sha256 $path))

        # Jangan pernah menurunkan versi program yang sudah terpasang.
        if ($spec.CompareWith) {
            $installedExe = Get-ProgramPath $spec.CompareWith
            if ($installedExe) {
                $installedVersion = ConvertTo-TgosVersion (Get-Item -LiteralPath $installedExe).VersionInfo.ProductVersion
                $downloadVersion = ConvertTo-TgosVersion (Get-Item -LiteralPath $path).VersionInfo.ProductVersion
                if ($installedVersion -and $downloadVersion -and $installedVersion -gt $downloadVersion) {
                    Write-Output ("TGOS: {0} {1} is already installed, newer than the download ({2}); nothing changed" -f $entry.Name, $installedVersion, $downloadVersion)
                    continue
                }
                if (-not $installedVersion -or -not $downloadVersion) {
                    Write-Output ("TGOS: the versions of {0} could not be compared; installing the download" -f $entry.Name)
                }
            }
        }

        $label = $spec.File
        if ($spec.Msi) {
            $file = Join-Path $env:SystemRoot 'System32\msiexec.exe'
            $arguments = '/i "{0}" /qn /norestart' -f $path
        }
        elseif ($spec.Extract) {
            # Paket diekstrak tanpa tampilan, lalu installer di dalamnya diperiksa lagi
            # tanda tangannya sebelum dijalankan.
            $extractDirectory = Join-Path $workDirectory 'extracted'
            New-Item -ItemType Directory -Path $extractDirectory -Force | Out-Null
            $code = Invoke-TgosProcess -File $path -Arguments ($spec.Extract -f $extractDirectory) -TimeoutMilliseconds $ExtractTimeoutMilliseconds
            if ($null -eq $code) { throw ("extracting {0} did not finish within 5 minutes" -f $spec.File) }
            $file = Join-Path $extractDirectory $spec.Setup
            if ($code -ne 0 -or -not (Test-Path -LiteralPath $file)) {
                throw ("extracting {0} failed (exit code {1}); {2} was not found" -f $spec.File, $code, $spec.Setup)
            }
            $setupTrust = Assert-TrustedFile -Spec $spec -Path $file -Release $null
            Write-Output ("TGOS: extracted {0}; {1} verified: {2}" -f $spec.File, $spec.Setup, $setupTrust)
            $arguments = [string]$spec.Arguments
            $label = $spec.Setup
        }
        else {
            $file = $path
            $arguments = [string]$spec.Arguments
        }
        $code = Invoke-TgosProcess -File $file -Arguments $arguments -TimeoutMilliseconds $InstallTimeoutMilliseconds
        if ($null -eq $code) { throw ("the installer {0} did not finish within 15 minutes" -f $label) }
        $accepted = @(0, 3010)
        if ($spec.SuccessCodes) { $accepted = @($spec.SuccessCodes) }
        if ($accepted -notcontains $code) {
            Write-Output ("WARNING: the installer {0} returned exit code {1}" -f $label, $code)
        }
        else {
            Write-Output ("TGOS: installer {0} finished with exit code {1}" -f $label, $code)
        }
    }

    # Sebagian installer selesai sebelum semua filenya tertulis.
    $installed = $false
    for ($attempt = 0; $attempt -lt 60 -and -not $installed; $attempt++) {
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
