<#
.SYNOPSIS
    Membersihkan folder sisa paket Widgets yang tidak bisa dihapus saat paketnya dicabut.

.DESCRIPTION
    Saat paket Widgets dihapus, sebagian filenya masih terkunci Windows (file hive
    "User.dat" di folder data paket), jadi folder berikut tertinggal:
        %ProgramData%\Packages\<paket>
        <profil>\AppData\Local\Packages\<paket>
        %ProgramFiles%\WindowsApps\<paket lengkap>

    Skrip ini mencoba menghapusnya. Yang masih terkunci didaftarkan ke Windows untuk
    dihapus saat restart berikutnya (MoveFileEx dengan MOVEFILE_DELAY_UNTIL_REBOOT),
    mekanisme resmi yang juga dipakai installer.

    Hanya folder yang namanya cocok dengan paket di -Families yang disentuh.
    Tidak fatal: kode keluar selalu 0.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string[]]$Families = @(
        'Microsoft.WidgetsPlatformRuntime_8wekyb3d8bbwe',
        'MicrosoftWindows.Client.WebExperience_cw5n1h2txyewy')
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

try {
    $targets = @()
    foreach ($family in $Families) {
        if ($family -notmatch '^(?<name>[A-Za-z0-9.]+)_(?<publisher>[a-z0-9]{13})$') {
            Write-Output ("WARNING: '{0}' is not a package family name; skipped" -f $family)
            continue
        }
        $name = $Matches['name']
        $publisher = $Matches['publisher']

        $targets += Join-Path $env:ProgramData ('Packages\{0}' -f $family)
        foreach ($profile in (Get-TgosUserProfiles)) {
            $targets += Join-Path $profile.Path ('AppData\Local\Packages\{0}' -f $family)
        }
        $windowsApps = Join-Path $env:ProgramFiles 'WindowsApps'
        if (Test-Path -LiteralPath $windowsApps) {
            Get-ChildItem -LiteralPath $windowsApps -Directory -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like ('{0}_*_{1}' -f $name, $publisher) } |
                ForEach-Object { $targets += $_.FullName }
        }
    }

    $present = @($targets | Where-Object { Test-Path -LiteralPath $_ })
    if ($present.Count -eq 0) {
        Write-Output 'TGOS: no leftover Widgets folders'
        exit 0
    }

    $removed = 0
    $scheduled = 0
    $native = $null
    foreach ($folder in $present) {
        Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $folder)) { $removed++; continue }

        if (-not $native) {
            $native = Add-Type -Namespace Tgos -Name NativeFile -PassThru -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);
'@
        }
        # File dulu, lalu folder dari yang paling dalam: Windows menghapusnya berurutan.
        $items = @(Get-ChildItem -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue)
        $ordered = @($items | Where-Object { -not $_.PSIsContainer }) +
            @($items | Where-Object { $_.PSIsContainer } | Sort-Object { $_.FullName.Length } -Descending)
        foreach ($item in $ordered) {
            [void]$native::MoveFileEx($item.FullName, $null, 4)
        }
        [void]$native::MoveFileEx($folder, $null, 4)
        $scheduled++
    }
    Write-Output ("TGOS: leftover Widgets folders - removed {0}, scheduled for removal at restart {1}" -f $removed, $scheduled)
}
catch {
    Write-Output ("WARNING: could not clean leftover Widgets folders: {0}" -f (Format-TgosError $_))
}

exit 0
