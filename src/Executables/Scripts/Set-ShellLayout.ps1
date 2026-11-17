<#
.SYNOPSIS
    Menyusun ulang pin taskbar dan pin Start menu menjadi set TGOS.

.DESCRIPTION
    Dijalankan di akhir playbook, setelah browser terpasang dan aplikasi bawaan dihapus,
    supaya daftar pin sesuai dengan yang benar-benar ada di sistem.

    1. Taskbar. Menulis <folder data TGOS>\TaskbarLayout.xml: File Explorer, SATU
       browser, Microsoft Store (bila tidak dihapus). File itu ditunjuk policy
       "Start Layout" yang dipasang modul antarmuka.
       Browser yang dipin: yang dipilih di Wizard bila terpasang; bila tidak, browser
       pertama yang terpasang (Brave, Chrome, Firefox); bila tidak ada, Edge (bila masih
       ada). Pintasan Start-nya dicari menurut file exe yang ditunjuknya.
    2. Start. Menulis daftar pin lewat policy ConfigureStartPins: File Explorer,
       Settings, Microsoft Store, browser, Notepad, Calculator, Terminal.
    3. Reset paksa. Policy saja tidak mengganti pin yang sudah tersimpan di profil
       (terbukti di TGOS 0.9.1: pin Copilot yang mati tetap tampil sebagai kotak
       abu-abu). Jadi Explorer dan host Start dihentikan, lalu untuk setiap profil:
         - kunci registry "Taskband" (daftar pin taskbar) dihapus, dan
         - file start*.bin (daftar pin Start) dihapus,
       sehingga Windows menyusun keduanya lagi dari layout di atas.
       PIN YANG DIBUAT PENGGUNA IKUT HILANG. Itu keputusan pemilik proyek.

    Explorer dijalankan lagi oleh Start-Shell.ps1 (sebagai pengguna yang login), atau
    langsung oleh skrip ini bila -RestartExplorer diberikan (dipakai TGOS Toolbox).

    -GenerateOnly hanya menulis TaskbarLayout.xml dan StartPins.json ke -DataDirectory,
    tanpa menyentuh registry atau proses. Dipakai untuk pengujian, bersama
    -BrowserLinkNames: daftar pintasan browser yang dianggap terpasang, dipisah koma
    (lewat -File PowerShell tidak bisa menerima array), dalam urutan prioritas. Tiap
    entri boleh berbentuk "opsi=pintasan", mis. "browser-firefox=Firefox.lnk", supaya
    pilihan browser di install-info.txt ikut teruji.

    Tidak fatal: kode keluar selalu 0. Hasilnya diperiksa Test-TgosResult.ps1.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$DataDirectory,
    [string]$InstallInfoPath,
    [string[]]$BrowserLinkNames,
    [switch]$EdgeInstalled,
    [switch]$StoreRemoved,
    [switch]$GenerateOnly,
    [switch]$RestartExplorer
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

$StartMenuPrograms = '%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs'
$StoreAppId = 'Microsoft.WindowsStore_8wekyb3d8bbwe!App'
$StartPinsProvider = 'B5292708-1619-419B-9923-E5D9F3925E71'

function Find-StartMenuLink {
    # Pintasan di Start Menu semua pengguna yang menunjuk file exe ini. Mengembalikan
    # jalurnya relatif terhadap folder Programs (mis. "Brave.lnk"), atau $null.
    param([string]$Exe, [string]$PreferredName)
    $programs = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
    if (-not (Test-Path -LiteralPath $programs)) { return $null }
    $shell = New-Object -ComObject WScript.Shell
    $matching = @()
    foreach ($link in (Get-ChildItem -LiteralPath $programs -Filter '*.lnk' -Recurse -File -ErrorAction SilentlyContinue)) {
        try { $target = [string]$shell.CreateShortcut($link.FullName).TargetPath } catch { continue }
        if ($target -and [string]::Equals($target, $Exe, [System.StringComparison]::OrdinalIgnoreCase)) {
            $matching += $link.FullName.Substring($programs.Length).TrimStart('\')
        }
    }
    if ($matching.Count -eq 0) {
        if ($PreferredName -and (Test-Path -LiteralPath (Join-Path $programs $PreferredName))) { return $PreferredName }
        return $null
    }
    $exact = @($matching | Where-Object { $_ -eq $PreferredName })
    if ($exact.Count -gt 0) { return $exact[0] }
    return ($matching | Sort-Object { $_.Length } | Select-Object -First 1)
}

function Get-LayoutFacts {
    # Keadaan sistem yang menentukan isi layout. Parameter uji menggantikan deteksi.
    $selected = @()
    if ($InstallInfoPath -and (Test-Path -LiteralPath $InstallInfoPath)) {
        $selected = @(Get-Content -LiteralPath $InstallInfoPath |
                Where-Object { $_ -match '^Option selected\s*:' } |
                ForEach-Object { ($_ -replace '^Option selected\s*:\s*', '').Trim() })
    }

    # Kandidat: @{ Option; Link }, dalam urutan Brave, Chrome, Firefox.
    $candidates = @()
    if ($BrowserLinkNames) {
        foreach ($entry in @($BrowserLinkNames | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
            if ($entry -match '^(?<option>[a-z0-9-]+)=(?<link>.+)$') {
                $candidates += @{ Option = $Matches['option']; Link = $Matches['link'] }
            }
            else {
                $candidates += @{ Option = ''; Link = $entry }
            }
        }
    }
    elseif (-not $GenerateOnly) {
        foreach ($browser in (Get-TgosInstalledBrowsers)) {
            $link = Find-StartMenuLink -Exe $browser.Exe -PreferredName $browser.LinkName
            if ($link) {
                $candidates += @{ Option = $browser.Option; Link = $link }
            }
            else {
                Write-Output ("WARNING: {0} is installed but no Start Menu shortcut points to {1}; not pinned" -f $browser.Name, $browser.Exe)
            }
        }
    }

    # Satu browser: yang dipilih di Wizard bila ada, kalau tidak yang pertama.
    $links = @()
    if ($candidates.Count -gt 0) {
        $chosen = @($candidates | Where-Object { $_.Option -and ($selected -contains $_.Option) }) | Select-Object -First 1
        if (-not $chosen) { $chosen = $candidates[0] }
        $links = @($chosen.Link)
    }

    $edge = [bool]$EdgeInstalled
    if (-not $GenerateOnly -and -not $EdgeInstalled) {
        foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
            if ($base -and (Test-Path -LiteralPath (Join-Path $base 'Microsoft\Edge\Application\msedge.exe'))) {
                $edge = $true
            }
        }
    }

    $noStore = [bool]$StoreRemoved
    if (-not $noStore -and $InstallInfoPath -and (Test-Path -LiteralPath $InstallInfoPath)) {
        $noStore = [bool](Get-Content -LiteralPath $InstallInfoPath |
                Where-Object { $_ -match '^Option selected\s*:\s*remove-store\s*$' })
    }

    return @{ BrowserLinks = $links; UseEdge = ($links.Count -eq 0 -and $edge); StoreRemoved = $noStore }
}

function New-TaskbarLayoutXml {
    param($Facts)
    $pins = @('        <taskbar:DesktopApp DesktopApplicationID="Microsoft.Windows.Explorer" />')
    foreach ($link in $Facts.BrowserLinks) {
        $path = [System.Security.SecurityElement]::Escape(('{0}\{1}' -f $StartMenuPrograms, $link))
        $pins += ('        <taskbar:DesktopApp DesktopApplicationLinkPath="{0}" />' -f $path)
    }
    if ($Facts.UseEdge) {
        $pins += '        <taskbar:DesktopApp DesktopApplicationID="MSEdge" />'
    }
    if (-not $Facts.StoreRemoved) {
        $pins += ('        <taskbar:UWA AppUserModelID="{0}" />' -f $StoreAppId)
    }

    $lines = @(
        '<?xml version="1.0" encoding="utf-8"?>',
        '<!-- Pin taskbar TGOS. Dibuat Set-ShellLayout.ps1; jangan diedit tangan. -->',
        '<LayoutModificationTemplate',
        '    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"',
        '    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"',
        '    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"',
        '    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"',
        '    Version="1">',
        '  <CustomTaskbarLayoutCollection PinListPlacement="Replace">',
        '    <defaultlayout:TaskbarLayout>',
        '      <taskbar:TaskbarPinList>') + $pins + @(
        '      </taskbar:TaskbarPinList>',
        '    </defaultlayout:TaskbarLayout>',
        '  </CustomTaskbarLayoutCollection>',
        '</LayoutModificationTemplate>')
    return ($lines -join "`r`n") + "`r`n"
}

function New-StartPinsJson {
    param($Facts)
    $pins = @(
        @{ desktopAppId = 'Microsoft.Windows.Explorer' },
        @{ packagedAppId = 'windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel' })
    if (-not $Facts.StoreRemoved) {
        $pins += @{ packagedAppId = $StoreAppId }
    }
    foreach ($link in $Facts.BrowserLinks) {
        $pins += @{ desktopAppLink = ('{0}\{1}' -f $StartMenuPrograms, $link) }
    }
    if ($Facts.UseEdge) {
        $pins += @{ desktopAppId = 'MSEdge' }
    }
    $pins += @{ packagedAppId = 'Microsoft.WindowsNotepad_8wekyb3d8bbwe!App' }
    $pins += @{ packagedAppId = 'Microsoft.WindowsCalculator_8wekyb3d8bbwe!App' }
    $pins += @{ packagedAppId = 'Microsoft.WindowsTerminal_8wekyb3d8bbwe!App' }
    return (@{ pinnedList = $pins } | ConvertTo-Json -Depth 4 -Compress)
}

function Set-StartPinsPolicy {
    param([string]$Json)
    $targets = @(
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'; Values = @{ ConfigureStartPins = $Json } },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start'
            Values = @{ ConfigureStartPins = $Json; ConfigureStartPins_ProviderSet = 1; ConfigureStartPins_WinningProvider = $StartPinsProvider } },
        @{ Path = ('HKLM:\SOFTWARE\Microsoft\PolicyManager\providers\{0}\default\Device\Start' -f $StartPinsProvider)
            Values = @{ ConfigureStartPins = $Json; ConfigureStartPins_LastWrite = 1 } })
    foreach ($target in $targets) {
        if (-not (Test-Path -LiteralPath $target.Path)) {
            New-Item -Path $target.Path -Force | Out-Null
        }
        foreach ($name in $target.Values.Keys) {
            $value = $target.Values[$name]
            if ($value -is [int]) {
                Set-ItemProperty -LiteralPath $target.Path -Name $name -Value $value -Type DWord
            }
            else {
                Set-ItemProperty -LiteralPath $target.Path -Name $name -Value ([string]$value) -Type String
            }
        }
    }
}

function Reset-ShellPins {
    # Explorer otomatis dijalankan lagi oleh Windows bila mati mendadak. Itu dimatikan
    # sebentar supaya Explorer lama tidak sempat menulis ulang daftar pin-nya.
    $winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $previous = (Get-ItemProperty -LiteralPath $winlogon -ErrorAction SilentlyContinue).AutoRestartShell
    $taskbar = 0
    $start = 0
    $pinLinks = 0
    try {
        Set-ItemProperty -LiteralPath $winlogon -Name 'AutoRestartShell' -Value 0 -Type DWord
        foreach ($name in @('explorer', 'StartMenuExperienceHost')) {
            Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2

        foreach ($profile in (Get-TgosUserProfiles)) {
            $taskband = 'Registry::HKEY_USERS\{0}\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband' -f $profile.Sid
            if (Test-Path -LiteralPath $taskband) {
                Remove-Item -LiteralPath $taskband -Recurse -Force -ErrorAction SilentlyContinue
                if (-not (Test-Path -LiteralPath $taskband)) { $taskbar++ }
            }
            # Pintasan pin lama juga dihapus. Bila dibiarkan, Windows membuat salinan baru
            # di sebelahnya saat menerapkan layout (uji VM v1.0.0: "File Explorer (2).lnk").
            # Hanya file .lnk langsung di folder ini; subfolder ImplicitAppShortcuts tidak
            # disentuh.
            $pinned = Join-Path $profile.Path 'AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
            if (Test-Path -LiteralPath $pinned) {
                foreach ($link in @(Get-ChildItem -LiteralPath $pinned -Filter '*.lnk' -File -Force -ErrorAction SilentlyContinue)) {
                    Remove-Item -LiteralPath $link.FullName -Force -ErrorAction SilentlyContinue
                    if (-not (Test-Path -LiteralPath $link.FullName)) { $pinLinks++ }
                }
            }
            $state = Join-Path $profile.Path 'AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState'
            if (Test-Path -LiteralPath $state) {
                $files = @(Get-ChildItem -LiteralPath $state -Filter 'start*.bin' -Force -ErrorAction SilentlyContinue)
                foreach ($file in $files) {
                    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
                }
                if ($files.Count -gt 0) { $start++ }
            }
        }
    }
    finally {
        if ($null -eq $previous) { $previous = 1 }
        Set-ItemProperty -LiteralPath $winlogon -Name 'AutoRestartShell' -Value ([int]$previous) -Type DWord
    }
    Write-Output ("TGOS: pins reset - taskbar for {0} profile(s), Start for {1} profile(s), {2} old pin shortcut(s) removed" -f $taskbar, $start, $pinLinks)
}

try {
    if (-not $GenerateOnly -or -not $DataDirectory) {
        $DataDirectory = Get-TgosDataDirectory -Path $DataDirectory
    }
    elseif (-not (Test-Path -LiteralPath $DataDirectory)) {
        New-Item -ItemType Directory -Path $DataDirectory -Force | Out-Null
    }
    if (-not $InstallInfoPath) {
        $InstallInfoPath = Join-Path $DataDirectory 'install-info.txt'
    }

    $facts = Get-LayoutFacts
    $xml = New-TaskbarLayoutXml -Facts $facts
    $json = New-StartPinsJson -Facts $facts

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $DataDirectory 'TaskbarLayout.xml'), $xml, $encoding)
    [System.IO.File]::WriteAllText((Join-Path $DataDirectory 'StartPins.json'), $json, $encoding)

    $browserText = 'none'
    if ($facts.BrowserLinks.Count -gt 0) { $browserText = ($facts.BrowserLinks -join ', ') }
    elseif ($facts.UseEdge) { $browserText = 'Microsoft Edge' }
    $storeText = 'pinned'
    if ($facts.StoreRemoved) { $storeText = 'not pinned (removed)' }
    Write-Output ("TGOS: shell layout written - browser: {0}; Store: {1}" -f $browserText, $storeText)

    if (-not $GenerateOnly) {
        Set-StartPinsPolicy -Json $json
        Write-Output 'TGOS: Start pin policy written'
        Reset-ShellPins
        if ($RestartExplorer -and -not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) {
            Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe')
        }
    }
}
catch {
    Write-Output ("WARNING: could not set the shell layout: {0}" -f (Format-TgosError $_))
}

exit 0
