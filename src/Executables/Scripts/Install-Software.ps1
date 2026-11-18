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
        vcredist-legacy
                  Visual C++ 2005, 2008, 2010, 2012, 2013 x86 dan x64, versi terakhir
                  masing-masing (download.microsoft.com, aka.ms). Banyak game lama
                  membutuhkan runtime ini, bukan hanya 2015-2022.
        xna       XNA Framework 4.0 Redistributable (download.microsoft.com)
        directx   DirectX End-User Runtime, pustaka lama Juni 2010, paket lengkap
                  (download.microsoft.com)
        dotnet    .NET Desktop Runtime LTS terbaru (10.0) x64 dan x86 (aka.ms/dotnet)
        netfx3    .NET Framework 3.5 (fitur Windows; diunduh Windows sendiri lewat DISM)
        steam     Steam               (cdn.akamai.steamstatic.com, Valve)
        epic      Epic Games Launcher (MSI resmi Epic Games)
        ea        EA app              (installer resmi Electronic Arts)
        ubisoft   Ubisoft Connect     (installer resmi Ubisoft)
        discord   Discord             (discord.com) - PER PENGGUNA
        spotify   Spotify             (installer lengkap, download.scdn.co) - PER PENGGUNA

    Program PER PENGGUNA dipasang ke profil akun yang menjalankan skrip ini (playbook
    menjalankannya sebagai pengguna yang login). Installer Spotify menolak hak
    Administrator; bila skrip berjalan sebagai admin, installer dijalankan dengan token
    pengguna biasa (runas /trustlevel:0x20000). Program yang langsung dibuka installer-nya
    sesudah pasang (Discord, Spotify, launcher) ditutup otomatis, supaya tidak ada jendela
    di tengah instalasi TGOS.

    Semua yang diunduh selalu versi terbaru dari alamat resmi "latest" pembuatnya, kecuali
    runtime lama yang memang sudah final. Selain 7-Zip dan .NET Framework 3.5, semua hanya
    dipasang di Windows x64 (target TGOS); di Windows ARM64 dilewati.

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
    [ValidateSet('brave', 'chrome', 'firefox', '7zip', 'vcredist', 'vcredist-legacy', 'xna', 'directx',
        'dotnet', 'netfx3', 'steam', 'epic', 'ea', 'ubisoft', 'discord', 'spotify')]
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

function Test-UninstallEntry {
    # Ada program terpasang yang DisplayName-nya cocok dengan pola ini (64 dan 32-bit).
    param([string]$Pattern)
    $roots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
    $names = @(Get-ItemProperty -Path $roots -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.DisplayName })
    return [bool](@($names | Where-Object { $_ -match $Pattern }).Count)
}

function Test-DesktopRuntime {
    # .NET Desktop Runtime dengan versi utama ini, di Program Files 64 dan 32-bit.
    param([string]$Major)
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        $folder = Join-Path $base 'dotnet\shared\Microsoft.WindowsDesktop.App'
        if (-not (Test-Path -LiteralPath $folder)) { return $false }
        if (-not @(Get-ChildItem -LiteralPath $folder -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like ('{0}.*' -f $Major) }).Count) {
            return $false
        }
    }
    return $true
}

function Test-IsAdministrator {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Stop-NewProcess {
    # Menutup proses bernama $Names yang tidak ada di $Before (dibuka installer).
    param([string[]]$Names, [int[]]$Before)
    $closed = @()
    foreach ($process in @(Get-Process -Name $Names -ErrorAction SilentlyContinue)) {
        if ($Before -notcontains $process.Id) {
            try { $process.Kill(); $closed += $process.ProcessName } catch { }
        }
    }
    return $closed
}

function Invoke-Installer {
    <#
    Menjalankan installer tanpa jendela dan menunggu. Selama menunggu dan 30 detik
    sesudahnya, program bernama $CloseAfter yang dibuka installer langsung ditutup.
    $DropAdmin: bila proses ini admin, installer dijalankan dengan token pengguna biasa.
    $Msi: installer msiexec. Bila melewati batas waktu, prosesnya TIDAK dihentikan (Windows
    Installer tetap memasang walaupun kliennya dihentikan); pemanggil menunggunya.
    Mengembalikan @{ Code; Closed; Process } (Code $null = melewati batas waktu).

    Batas waktu diukur dengan Stopwatch, bukan jam Windows: di uji VM revisi keempat 1.0.0
    jam VM melompat dua hari di tengah instalasi (sinkronisasi waktu setelah snapshot
    dipulihkan), sehingga installer Epic langsung dianggap lewat batas waktu.
    #>
    param([string]$File, [string]$Arguments, [int]$TimeoutMilliseconds, [string[]]$CloseAfter, [switch]$DropAdmin, [switch]$Msi)
    $before = @()
    if ($CloseAfter) { $before = @(Get-Process -Name $CloseAfter -ErrorAction SilentlyContinue | ForEach-Object { $_.Id }) }
    $closed = @()

    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WorkingDirectory = Split-Path -Parent $File
    $waitName = $null
    if ($DropAdmin -and (Test-IsAdministrator)) {
        # runas /trustlevel langsung selesai; yang ditunggu proses installer-nya.
        $info.FileName = Join-Path $env:SystemRoot 'System32\runas.exe'
        $info.Arguments = '/trustlevel:0x20000 "\"{0}\" {1}"' -f $File, $Arguments
        $waitName = [IO.Path]::GetFileNameWithoutExtension($File)
        Write-Output ("TGOS: {0} refuses administrator rights; running it as a standard user" -f (Split-Path -Leaf $File))
    }
    else {
        $info.FileName = $File
        $info.Arguments = $Arguments
    }
    $process = [System.Diagnostics.Process]::Start($info)
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $code = $null
    $installerSeen = $false
    while ($clock.ElapsedMilliseconds -lt $TimeoutMilliseconds) {
        if ($CloseAfter) { $closed += Stop-NewProcess -Names $CloseAfter -Before $before }
        if ($process.HasExited) {
            if (-not $waitName) { $code = $process.ExitCode; break }
            # Lewat runas: tunggu installer-nya muncul dulu (paling lama 60 detik), lalu
            # tunggu sampai selesai. Kode keluarnya tidak terbaca; hasilnya diperiksa dari
            # file program.
            $running = [bool](Get-Process -Name $waitName -ErrorAction SilentlyContinue)
            if ($running) { $installerSeen = $true }
            elseif ($installerSeen -or $clock.Elapsed.TotalSeconds -gt 60) {
                if ($process.ExitCode -ne 0) { $code = $process.ExitCode } else { $code = 0 }
                break
            }
        }
        Start-Sleep -Milliseconds 250
    }
    if ($null -eq $code -and -not $Msi) {
        try { $process.Kill() } catch { }
        if ($waitName) { Get-Process -Name $waitName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
    }
    if ($CloseAfter) {
        for ($attempt = 0; $attempt -lt 120; $attempt++) {
            $closed += Stop-NewProcess -Names $CloseAfter -Before $before
            Start-Sleep -Milliseconds 250
        }
    }
    return @{ Code = $code; Closed = @($closed | Select-Object -Unique); Process = $process }
}

function Test-InstallerBusy {
    # Windows Installer sedang memasang sesuatu: mutex Global\_MSIExecute ada selama itu.
    # Di uji VM revisi keempat 1.0.0 installer EA app gagal (kode 1) karena dijalankan saat
    # Windows Installer masih memasang Epic Games Launcher.
    $mutex = $null
    try {
        if ([System.Threading.Mutex]::TryOpenExisting('Global\_MSIExecute', [ref]$mutex)) {
            $mutex.Dispose()
            return $true
        }
        return $false
    }
    catch [System.UnauthorizedAccessException] {
        # Mutex ada, hanya tidak boleh dibuka akun ini: tetap berarti sedang sibuk.
        return $true
    }
    catch {
        return $false
    }
}

function Wait-InstallerIdle {
    # Menunggu Windows Installer selesai (paling lama $Minutes). Mengembalikan jumlah detik
    # menunggu, atau -1 bila masih sibuk sampai batas itu.
    param([int]$Minutes = 30)
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while (Test-InstallerBusy) {
        if ($clock.Elapsed.TotalMinutes -ge $Minutes) { return -1 }
        Start-Sleep -Seconds 3
    }
    return [int]$clock.Elapsed.TotalSeconds
}

function Get-ShortcutPlace {
    <#
    Folder Start Menu dan Desktop yang dilihat pengguna. Program per mesin: milik mesin dan
    semua profil pengguna biasa. Program per pengguna ($PerUser): milik mesin dan akun ini
    saja (pintasan ke profil disimpan dengan %LOCALAPPDATA% dsb., jadi pintasan milik akun
    lain akan terbaca seolah menunjuk ke profil akun ini).
    Mengembalikan @{ Path; Kind } (Kind: Start atau Desktop) untuk folder yang ada.
    #>
    param([switch]$PerUser)
    $places = @(
        @{ Path = [Environment]::GetFolderPath('CommonPrograms'); Kind = 'Start' },
        @{ Path = [Environment]::GetFolderPath('CommonDesktopDirectory'); Kind = 'Desktop' })
    if ($PerUser) {
        $places += @{ Path = [Environment]::GetFolderPath('Programs'); Kind = 'Start' }
        $places += @{ Path = [Environment]::GetFolderPath('Desktop'); Kind = 'Desktop' }
    }
    else {
        foreach ($userProfile in @(Get-TgosUserProfiles)) {
            $places += @{ Path = Join-Path $userProfile.Path 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs'; Kind = 'Start' }
            $places += @{ Path = Join-Path $userProfile.Path 'Desktop'; Kind = 'Desktop' }
        }
    }
    $seen = @{}
    $result = @()
    foreach ($place in $places) {
        if (-not $place.Path) { continue }
        $key = $place.Path.TrimEnd('\').ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        if (Test-Path -LiteralPath $place.Path -ErrorAction SilentlyContinue) { $result += , $place }
    }
    return $result
}

function Find-ProgramShortcut {
    # Pintasan .lnk di $Places yang target-nya ada di dalam folder $Root. Start Menu
    # diperiksa beserta subfoldernya, Desktop hanya tingkat teratas.
    param([string]$Root, [object[]]$Places)
    $shell = New-Object -ComObject WScript.Shell
    $prefix = $Root.TrimEnd('\') + '\'
    $found = @()
    foreach ($place in $Places) {
        $links = @(Get-ChildItem -LiteralPath $place.Path -Filter '*.lnk' -Force -Recurse:($place.Kind -eq 'Start') -ErrorAction SilentlyContinue)
        foreach ($link in $links) {
            $target = ''
            try { $target = [string]$shell.CreateShortcut($link.FullName).TargetPath } catch { continue }
            if ($target -and $target.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $found += , @{ Path = $link.FullName; Kind = $place.Kind }
            }
        }
    }
    return $found
}

function Confirm-ProgramShortcut {
    <#
    .SYNOPSIS
        Memastikan program yang terpasang punya pintasan di Start dan di Desktop.

    .DESCRIPTION
        Sebagian installer tidak membuatnya saat dipasang senyap. Di uji VM revisi keempat
        1.0.0 Discord dan Ubisoft Connect terpasang, tetapi tidak ada di Start maupun
        Desktop. Pintasan yang sudah ada (yang target-nya di folder program itu) tidak
        digandakan. Yang dibuat: program per mesin di Start Menu dan Desktop milik semua
        pengguna; program per pengguna di milik akun ini.
        Mengembalikan @{ Added; Hidden } (Hidden: pintasan yang ditaruh installer di profil
        SYSTEM, yang tidak terlihat pengguna; hanya dicatat).
    #>
    param($Spec, [switch]$PerUser)
    $result = @{ Added = @(); Hidden = 0 }
    $root = & $Spec.Root
    $target = & $Spec.Target
    if (-not $root -or -not $target -or -not (Test-Path -LiteralPath $target)) { return $result }
    $existing = @(Find-ProgramShortcut -Root $root -Places @(Get-ShortcutPlace -PerUser:$PerUser))
    if (-not $PerUser) {
        $system = Join-Path $env:SystemRoot 'System32\config\systemprofile'
        $hidden = @(@{ Path = Join-Path $system 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs'; Kind = 'Start' },
            @{ Path = Join-Path $system 'Desktop'; Kind = 'Desktop' }) | Where-Object { Test-Path -LiteralPath $_.Path -ErrorAction SilentlyContinue }
        if (@($hidden).Count) { $result.Hidden = @(Find-ProgramShortcut -Root $root -Places @($hidden)).Count }
    }
    $kinds = @($existing | ForEach-Object { $_.Kind })
    $shell = New-Object -ComObject WScript.Shell
    foreach ($kind in @('Start', 'Desktop')) {
        if ($kinds -contains $kind) { continue }
        if ($kind -eq 'Start') {
            if ($PerUser) { $folder = [Environment]::GetFolderPath('Programs') } else { $folder = [Environment]::GetFolderPath('CommonPrograms') }
            if ($Spec.Folder) { $folder = Join-Path $folder $Spec.Folder }
        }
        elseif ($PerUser) { $folder = [Environment]::GetFolderPath('Desktop') }
        else { $folder = [Environment]::GetFolderPath('CommonDesktopDirectory') }
        if (-not $folder) { continue }
        if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
        $path = Join-Path $folder ('{0}.lnk' -f $Spec.Name)
        # Pintasan lain dengan nama yang sama tidak ditimpa.
        if (Test-Path -LiteralPath $path) { continue }
        $link = $shell.CreateShortcut($path)
        $link.TargetPath = $target
        $link.WorkingDirectory = Split-Path -Parent $target
        if ($Spec.Arguments) { $link.Arguments = $Spec.Arguments }
        if ($Spec.Icon) {
            $icon = & $Spec.Icon
            if ($icon -and (Test-Path -LiteralPath $icon)) { $link.IconLocation = $icon }
        }
        $link.Description = $Spec.Name
        $link.Save()
        $result.Added += $kind
    }
    return $result
}

function Write-ProgramShortcut {
    # Memanggil Confirm-ProgramShortcut untuk program pilihan ini dan mencatat hasilnya.
    if (-not $entry.Shortcut) { return }
    try {
        $shortcut = Confirm-ProgramShortcut -Spec $entry.Shortcut -PerUser:([bool]$entry.PerUser)
        if ($shortcut.Hidden -gt 0) {
            Write-Output ("TGOS: the {0} installer put {1} shortcut(s) in the SYSTEM profile, where no user sees them" -f $entry.Name, $shortcut.Hidden)
        }
        if ($shortcut.Added.Count -gt 0) {
            $names = @($shortcut.Added | ForEach-Object { if ($_ -eq 'Start') { 'Start menu' } else { 'desktop' } })
            Write-Output ("TGOS: added the missing {0} shortcut for {1}" -f ($names -join ' and '), $entry.Name)
        }
        else {
            Write-Output ("TGOS: {0} has its Start menu and desktop shortcuts" -f $entry.Name)
        }
    }
    catch {
        Write-Output ("WARNING: could not check the shortcuts of {0}: {1}" -f $entry.Name, (Format-TgosError $_))
    }
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
        X64Only = $true
    }
    'vcredist-legacy' = @{
        Name  = 'Visual C++ 2005-2013 Redistributables'
        # Argumen senyap dari dokumentasi Microsoft untuk tiap generasi installer.
        # 2005: paket IExpress; /q:a tanpa tampilan, /c: menjalankan MSI di dalamnya senyap.
        Files = @(
            @{ Url = 'https://download.microsoft.com/download/8/B/4/8B42259F-5D70-43F4-AC2E-4B208FD8D66A/vcredist_x86.EXE'; File = 'vcredist2005_x86.exe'
                Arguments = '/q:a /c:"msiexec /i vcredist.msi /qn"'; Signer = 'Microsoft Corporation'; SuccessCodes = @(0, 3010, 1638) },
            @{ Url = 'https://download.microsoft.com/download/8/B/4/8B42259F-5D70-43F4-AC2E-4B208FD8D66A/vcredist_x64.EXE'; File = 'vcredist2005_x64.exe'
                Arguments = '/q:a /c:"msiexec /i vcredist.msi /qn"'; Signer = 'Microsoft Corporation'; SuccessCodes = @(0, 3010, 1638) },
            @{ Url = 'https://download.microsoft.com/download/5/D/8/5D8C65CB-C849-4025-8E95-C3966CAFD8AE/vcredist_x86.exe'; File = 'vcredist2008_x86.exe'
                Arguments = '/q'; Signer = 'Microsoft Corporation'; SuccessCodes = @(0, 3010, 1638) },
            @{ Url = 'https://download.microsoft.com/download/5/D/8/5D8C65CB-C849-4025-8E95-C3966CAFD8AE/vcredist_x64.exe'; File = 'vcredist2008_x64.exe'
                Arguments = '/q'; Signer = 'Microsoft Corporation'; SuccessCodes = @(0, 3010, 1638) },
            @{ Url = 'https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x86.exe'; File = 'vcredist2010_x86.exe'
                Arguments = '/q /norestart'; Signer = 'Microsoft Corporation'; SuccessCodes = @(0, 3010, 1638, 5100) },
            @{ Url = 'https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x64.exe'; File = 'vcredist2010_x64.exe'
                Arguments = '/q /norestart'; Signer = 'Microsoft Corporation'; SuccessCodes = @(0, 3010, 1638, 5100) },
            @{ Url = 'https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x86.exe'; File = 'vcredist2012_x86.exe'
                Arguments = '/install /quiet /norestart'; Signer = 'Microsoft Corporation'; SuccessCodes = @(0, 3010, 1638) },
            @{ Url = 'https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x64.exe'; File = 'vcredist2012_x64.exe'
                Arguments = '/install /quiet /norestart'; Signer = 'Microsoft Corporation'; SuccessCodes = @(0, 3010, 1638) },
            @{ Url = 'https://aka.ms/highdpimfc2013x86enu'; File = 'vcredist2013_x86.exe'
                Arguments = '/install /quiet /norestart'; Signer = 'Microsoft Corporation'; SuccessCodes = @(0, 3010, 1638) },
            @{ Url = 'https://aka.ms/highdpimfc2013x64enu'; File = 'vcredist2013_x64.exe'
                Arguments = '/install /quiet /norestart'; Signer = 'Microsoft Corporation'; SuccessCodes = @(0, 3010, 1638) })
        Test  = {
            $patterns = @('2005 Redistributable$', '2005 Redistributable \(x64\)', '2008 Redistributable - x86', '2008 Redistributable - x64',
                '2010\s+x86 Redistributable', '2010\s+x64 Redistributable', '2012 Redistributable \(x86\)', '2012 Redistributable \(x64\)',
                '2013 Redistributable \(x86\)', '2013 Redistributable \(x64\)')
            @($patterns | Where-Object { -not (Test-UninstallEntry ('Visual C\+\+ ' + $_)) }).Count -eq 0
        }
        X64Only = $true
    }
    xna      = @{
        Name  = 'XNA Framework 4.0'
        Files = @(@{ Url = 'https://download.microsoft.com/download/A/C/2/AC2C903B-E6E8-42C2-9FD7-BEBAC362A930/xnafx40_redist.msi'
                File = 'xnafx40_redist.msi'; Msi = $true; Signer = 'Microsoft Corporation' })
        Test  = { Test-UninstallEntry '^Microsoft XNA Framework Redistributable 4\.0' }
        X64Only = $true
    }
    dotnet   = @{
        Name  = '.NET Desktop Runtime 10'
        Files = @(
            @{ Url = 'https://aka.ms/dotnet/10.0/windowsdesktop-runtime-win-x64.exe'; File = 'windowsdesktop-runtime-win-x64.exe'
                Arguments = '/install /quiet /norestart'; Signer = 'Microsoft Corporation'; SuccessCodes = @(0, 3010, 1638) },
            @{ Url = 'https://aka.ms/dotnet/10.0/windowsdesktop-runtime-win-x86.exe'; File = 'windowsdesktop-runtime-win-x86.exe'
                Arguments = '/install /quiet /norestart'; Signer = 'Microsoft Corporation'; SuccessCodes = @(0, 3010, 1638) })
        Test  = { Test-DesktopRuntime '10' }
        X64Only = $true
    }
    netfx3   = @{
        Name  = '.NET Framework 3.5'
        # Fitur Windows, bukan unduhan TGOS: DISM mengambil filenya dari Windows Update.
        Dism  = 'NetFx3'
        Test  = { (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5' -ErrorAction SilentlyContinue).Install -eq 1 }
    }
    steam    = @{
        Name  = 'Steam'
        Files = @(@{ Url = 'https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe'
                File = 'SteamSetup.exe'; Arguments = '/S'; Signer = 'Valve' })
        Test  = { [bool](Get-ProgramPath 'Steam\steam.exe') }
        Shortcut = @{ Name = 'Steam'; Folder = 'Steam'; Root = { Get-ProgramPath 'Steam' }; Target = { Get-ProgramPath 'Steam\steam.exe' } }
        CloseAfter = @('steam', 'steamwebhelper')
        X64Only = $true
    }
    epic     = @{
        Name  = 'Epic Games Launcher'
        Files = @(@{ Url = 'https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi'
                File = 'EpicGamesLauncherInstaller.msi'; Msi = $true; Signer = 'Epic Games' })
        Test  = { [bool]((Get-ProgramPath 'Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe') -or (Get-ProgramPath 'Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe')) }
        Shortcut = @{ Name = 'Epic Games Launcher'; Root = { Get-ProgramPath 'Epic Games\Launcher' }
            Target = { @((Get-ProgramPath 'Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe'), (Get-ProgramPath 'Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe')) | Where-Object { $_ } | Select-Object -First 1 } }
        CloseAfter = @('EpicGamesLauncher', 'EpicWebHelper')
        X64Only = $true
    }
    ea       = @{
        Name  = 'EA app'
        Files = @(@{ Url = 'https://origin-a.akamaihd.net/EA-Desktop-Client-Download/installer-releases/EAappInstaller.exe'
                File = 'EAappInstaller.exe'; Arguments = '/quiet /norestart'; Signer = 'Electronic Arts' })
        Test  = { [bool](Get-ProgramPath 'Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe') }
        Shortcut = @{ Name = 'EA'; Root = { Get-ProgramPath 'Electronic Arts\EA Desktop' }
            Target = { @((Get-ProgramPath 'Electronic Arts\EA Desktop\EA Desktop\EALauncher.exe'), (Get-ProgramPath 'Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe')) | Where-Object { $_ } | Select-Object -First 1 } }
        CloseAfter = @('EADesktop', 'EABackgroundService', 'EALauncher')
        X64Only = $true
    }
    ubisoft  = @{
        Name  = 'Ubisoft Connect'
        Files = @(@{ Url = 'https://static3.cdn.ubi.com/orbit/launcher_installer/UbisoftConnectInstaller.exe'
                File = 'UbisoftConnectInstaller.exe'; Arguments = '/S'; Signer = 'Ubisoft' })
        Test  = { [bool]((Get-ProgramPath 'Ubisoft\Ubisoft Game Launcher\UbisoftConnect.exe') -or (Get-ProgramPath 'Ubisoft\Ubisoft Game Launcher\upc.exe')) }
        Shortcut = @{ Name = 'Ubisoft Connect'; Folder = 'Ubisoft'; Root = { Get-ProgramPath 'Ubisoft\Ubisoft Game Launcher' }
            Target = { @((Get-ProgramPath 'Ubisoft\Ubisoft Game Launcher\UbisoftConnect.exe'), (Get-ProgramPath 'Ubisoft\Ubisoft Game Launcher\upc.exe')) | Where-Object { $_ } | Select-Object -First 1 } }
        CloseAfter = @('UbisoftConnect', 'upc')
        X64Only = $true
    }
    discord  = @{
        Name  = 'Discord'
        Files = @(@{ Url = 'https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=win&arch=x64'
                File = 'DiscordSetup.exe'; Arguments = '-s'; Signer = 'Discord' })
        Test  = { Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Discord\Update.exe') }
        # Sama dengan pintasan yang dibuat installer Discord (Squirrel).
        Shortcut = @{ Name = 'Discord'; Folder = 'Discord Inc'; Root = { Join-Path $env:LOCALAPPDATA 'Discord' }
            Target = { Join-Path $env:LOCALAPPDATA 'Discord\Update.exe' }; Arguments = '--processStart Discord.exe'
            Icon = { Join-Path $env:LOCALAPPDATA 'Discord\app.ico' } }
        CloseAfter = @('Discord')
        PerUser = $true
        X64Only = $true
    }
    spotify  = @{
        Name  = 'Spotify'
        # Installer lengkap: installer web (SpotifySetup.exe) menampilkan jendela unduhan
        # walaupun diberi /silent, dan di uji otomatis menggantung sampai batas waktu.
        Files = @(@{ Url = 'https://download.scdn.co/SpotifyFullSetup.exe'
                File = 'SpotifyFullSetup.exe'; Arguments = '/silent'; Signer = 'Spotify'; DropAdmin = $true })
        TimeoutMinutes = 5
        Test  = { Test-Path -LiteralPath (Join-Path $env:APPDATA 'Spotify\Spotify.exe') }
        Shortcut = @{ Name = 'Spotify'; Root = { Join-Path $env:APPDATA 'Spotify' }; Target = { Join-Path $env:APPDATA 'Spotify\Spotify.exe' } }
        CloseAfter = @('Spotify')
        PerUser = $true
        X64Only = $true
    }
}

function Write-SoftwareRecord {
    param([string]$State)
    # Program per pengguna dipasang dari akun biasa, yang tidak boleh menulis file data
    # TGOS. Pemeriksa hasil memeriksa program itu langsung di profil pengguna.
    if (-not (Test-IsAdministrator)) { return }
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
    # Unduhan yang terputus dicoba lagi (paling banyak 3 kali, jeda 10 detik). Di uji
    # otomatis revisi kelima 1.0.0, unduhan VC++ dari aka.ms sekali terputus ("The
    # connection was closed"). Unduhan yang melewati batas waktu tidak diulang.
    param([string]$Url, [string]$Path)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Save-DownloadOnce -Url $Url -Path $Path
            return
        }
        catch {
            $message = Format-TgosError $_
            if ($attempt -ge 3 -or $message -match 'did not finish within') { throw }
            Write-Output ("TGOS: {0}; trying the download again ({1} of 3)" -f $message, ($attempt + 1))
            Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 10
        }
    }
}

function Save-DownloadOnce {
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

    if ($entry.X64Only -and (Get-TgosNativeArchitecture) -ne 'AMD64') {
        Write-Output ("TGOS: {0} skipped: TGOS installs it on x64 Windows only (this PC is {1})" -f $entry.Name, (Get-TgosNativeArchitecture))
        Write-SoftwareRecord -State 'skipped'
        exit 0
    }

    if (-not $Force -and (& $entry.Test)) {
        Write-Output ("TGOS: {0} is already installed" -f $entry.Name)
        Write-SoftwareRecord -State 'installed'
        Write-ProgramShortcut
        exit 0
    }

    if ($entry.Dism) {
        # Fitur Windows: DISM mengunduh dan memasangnya sendiri lewat layanan Windows Update
        # (butuh internet). Di uji VM revisi kedua 1.0.0, DISM gagal dengan 0x8024001E
        # (layanan Windows Update sedang berhenti), jadi layanan itu dipastikan berjalan,
        # dan bila gagal dicoba sekali lagi sesudah layanannya dijalankan ulang.
        $dismArguments = '/Online /Enable-Feature /FeatureName:{0} /All /NoRestart /Quiet' -f $entry.Dism
        $updateService = Get-Service -Name 'wuauserv' -ErrorAction SilentlyContinue
        if ($updateService -and $updateService.StartType -eq 'Disabled') {
            throw ('the Windows Update service is disabled; {0} is downloaded through it' -f $entry.Name)
        }
        $code = $null
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            if ($attempt -gt 1) {
                Write-Output ('TGOS: DISM returned 0x{0:X8}; restarting the Windows Update service and trying once more' -f $code)
                Restart-Service -Name 'wuauserv' -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 30
            }
            if ($updateService) { Start-Service -Name 'wuauserv' -ErrorAction SilentlyContinue }
            Write-Output ("TGOS: enabling the Windows feature {0} (Windows downloads it)" -f $entry.Dism)
            $code = Invoke-TgosProcess -File (Join-Path $env:SystemRoot 'System32\dism.exe') -Arguments $dismArguments -TimeoutMilliseconds 1800000
            if ($null -eq $code) { throw 'DISM did not finish within 30 minutes' }
            if (@(0, 3010) -contains $code) { break }
        }
        if (@(0, 3010) -notcontains $code) {
            # Baris error terakhir dari log DISM, supaya penyebabnya terlihat di laporan.
            $detail = ''
            $dismLog = Join-Path $env:SystemRoot 'Logs\DISM\dism.log'
            if (Test-Path -LiteralPath $dismLog) {
                $lastError = @(Get-Content -LiteralPath $dismLog -Tail 400 -ErrorAction SilentlyContinue | Where-Object { $_ -match ', Error\s' }) | Select-Object -Last 1
                if ($lastError) { $detail = ' (dism.log: {0})' -f (($lastError -replace '\s+', ' ').Trim()) }
            }
            if ($detail.Length -gt 300) { $detail = $detail.Substring(0, 300) + ' ...)' }
            # Di uji VM revisi ketiga 1.0.0 kedua percobaan gagal (0x8024001E) walau layanan
            # Windows Update sudah dijalankan ulang: Windows yang baru dipasang sedang sibuk
            # dengan update. Dicoba lagi otomatis setelah restart (lihat catch di bawah).
            $services = @(foreach ($name in @('wuauserv', 'UsoSvc', 'TrustedInstaller')) {
                    $service = Get-Service -Name $name -ErrorAction SilentlyContinue
                    if ($service) { '{0} {1}' -f $name, $service.Status }
                }) -join ', '
            throw ('DISM returned exit code {0} (0x{0:X8}) twice{1} [{2}]' -f $code, $detail, $services)
        }
        Write-Output ("TGOS: DISM finished with exit code {0}" -f $code)
    }

    $workDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('tgos-setup-{0}' -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null

    foreach ($spec in @($entry.Files | Where-Object { $_ })) {
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
        $timeout = $InstallTimeoutMilliseconds
        if ($entry.TimeoutMinutes) { $timeout = [int]$entry.TimeoutMinutes * 60000 }
        # Installer berikutnya baru dijalankan setelah Windows Installer selesai dengan
        # pemasangan lain (installer sebelumnya, atau servicing Windows).
        if (Test-InstallerBusy) {
            Write-Output 'TGOS: waiting for another installation (Windows Installer) to finish'
            $waited = Wait-InstallerIdle -Minutes 30
            if ($waited -lt 0) { Write-Output 'WARNING: Windows Installer is still busy after 30 minutes; running the installer anyway' }
            else { Write-Output ("TGOS: Windows Installer is free after {0} s" -f $waited) }
        }
        $run = Invoke-Installer -File $file -Arguments $arguments -TimeoutMilliseconds $timeout -CloseAfter $entry.CloseAfter -DropAdmin:([bool]$spec.DropAdmin) -Msi:([bool]$spec.Msi)
        $code = $run.Code
        if ($null -eq $code -and $spec.Msi) {
            # msiexec tidak dihentikan: Windows Installer tetap memasang. Ditunggu sampai
            # 30 menit lagi, lalu hasilnya diperiksa seperti biasa.
            Write-Output ("TGOS: {0} is still running after {1} minutes; waiting for it to finish" -f $label, ($timeout / 60000))
            if ($run.Process.WaitForExit(1800000)) { $code = $run.Process.ExitCode }
            else { try { $run.Process.Kill() } catch { } }
        }
        if ($run.Closed.Count -gt 0) {
            Write-Output ("TGOS: closed the window the installer opened: {0}" -f ($run.Closed -join ', '))
        }
        if ($null -eq $code) { throw ("the installer {0} did not finish within {1} minutes" -f $label, ($timeout / 60000)) }
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
        Write-ProgramShortcut
        $exitCode = 0
    }
    else {
        throw 'the installer ran but the program was not found afterwards'
    }
}
catch {
    $reason = Format-TgosError $_
    # Program per mesin dicoba lagi otomatis beberapa menit setelah restart berikutnya
    # (Complete-AfterRestart.ps1, sebagai SYSTEM, paling banyak 3 kali). Program per
    # pengguna (Discord, Spotify) diulang dari TGOS Toolbox. Tidak saat diuji (-UrlOverride).
    $later = ''
    if (-not $Catalog[$Item].PerUser -and -not $UrlOverride -and (Test-IsAdministrator)) {
        try {
            if (Add-TgosAfterRestartItem -Step $Item) { $later = '; it is tried again automatically after the next restart' }
            else { $later = '; it is tried again automatically after the next restart (once the TGOS Toolbox is installed)' }
        }
        catch {
            $later = ('; the retry after restart could not be scheduled: {0}' -f (Format-TgosError $_))
        }
    }
    Write-Output ("WARNING: {0} was not installed: {1}{2}" -f $Catalog[$Item].Name, $reason, $later)
    Write-SoftwareRecord -State 'failed'
}
finally {
    if ($workDirectory -and (Test-Path -LiteralPath $workDirectory)) {
        Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit $exitCode
