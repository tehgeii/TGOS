<#
.SYNOPSIS
    Menyetel terminal bawaan ke Windows Console Host selama instalasi TGOS, lalu
    mengembalikannya seperti semula.

.DESCRIPTION
    Di Windows 11 terminal bawaan biasanya Windows Terminal. Program lain (installer,
    Explorer yang dijalankan ulang) kadang membuka konsol yang seharusnya tersembunyi;
    Windows bisa menyerahkan konsol itu ke Windows Terminal, yang lalu tampil sebagai
    jendela kosong sebentar (uji VM revisi kedua 1.0.0). Windows Console Host menghormati
    permintaan "tersembunyi".

    -Action Save    : nilai lama DelegationConsole dan DelegationTerminal tiap pengguna
                      yang sedang login (dan akun SYSTEM) dicatat ke
                      <folder data TGOS>\terminal-previous.txt, lalu keduanya disetel ke
                      Windows Console Host. Bila catatan itu sudah ada (instalasi
                      sebelumnya berhenti di tengah), catatan lama TIDAK ditimpa, supaya
                      nilai asli pengguna tidak hilang.
    -Action Restore : nilai lama dikembalikan persis (dihapus bila dulu tidak ada), lalu
                      catatannya dihapus.

    Kunci: HKEY_USERS\<SID>\Console\%%Startup (pengaturan "Terminal" di Settings > System >
    For developers). Tidak fatal: kode keluar selalu 0.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Save', 'Restore')]
    [string]$Action,

    [string]$DataDirectory
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

# Windows Console Host untuk kedua nilai.
$consoleHost = '{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}'
$names = @('DelegationConsole', 'DelegationTerminal')

function Get-StartupKey {
    param([string]$Sid)
    return ('Registry::HKEY_USERS\{0}\Console\%%Startup' -f $Sid)
}

try {
    $DataDirectory = Get-TgosDataDirectory -Path $DataDirectory
    $record = Join-Path $DataDirectory 'terminal-previous.txt'

    if ($Action -eq 'Save') {
        $sids = @(Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
                Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' -or $_.PSChildName -eq 'S-1-5-18' } |
                ForEach-Object { $_.PSChildName })
        if (Test-Path -LiteralPath $record) {
            Write-Output 'TGOS: the earlier default terminal record is kept (a previous run did not finish)'
        }
        else {
            $lines = @()
            foreach ($sid in $sids) {
                $key = Get-Item -LiteralPath (Get-StartupKey $sid) -ErrorAction SilentlyContinue
                $parts = @($sid)
                foreach ($name in $names) {
                    $value = $null
                    if ($key) { $value = $key.GetValue($name, $null) }
                    if ($null -eq $value) { $parts += ('{0}=' -f $name) } else { $parts += ('{0}={1}' -f $name, $value) }
                }
                $lines += ($parts -join '|')
            }
            Set-Content -LiteralPath $record -Value $lines -Encoding ASCII
        }
        foreach ($sid in $sids) {
            $path = Get-StartupKey $sid
            if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
            foreach ($name in $names) {
                Set-ItemProperty -LiteralPath $path -Name $name -Value $consoleHost -Type String
            }
        }
        Write-Output ('TGOS: default terminal set to Windows Console Host for the install ({0} account(s))' -f $sids.Count)
    }
    else {
        if (-not (Test-Path -LiteralPath $record)) {
            Write-Output 'TGOS: no default terminal record; nothing to restore'
            exit 0
        }
        $restored = 0
        $skipped = 0
        foreach ($line in @(Get-Content -LiteralPath $record | Where-Object { $_ -match '\|' })) {
            $parts = $line -split '\|'
            $path = Get-StartupKey $parts[0]
            if (-not (Test-Path -LiteralPath ('Registry::HKEY_USERS\{0}' -f $parts[0]))) {
                # Pengguna itu sudah logout: hive-nya tidak termuat.
                $skipped++
                continue
            }
            foreach ($part in $parts[1..($parts.Count - 1)]) {
                $name, $value = $part -split '=', 2
                if ($names -notcontains $name) { continue }
                if ($value) {
                    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
                    Set-ItemProperty -LiteralPath $path -Name $name -Value $value -Type String
                }
                elseif (Test-Path -LiteralPath $path) {
                    Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue
                }
            }
            $restored++
        }
        Remove-Item -LiteralPath $record -Force
        Write-Output ('TGOS: default terminal restored for {0} account(s){1}' -f $restored, $(if ($skipped) { ', {0} not signed in' -f $skipped } else { '' }))
    }
}
catch {
    Write-Output ('WARNING: default terminal {0} failed: {1}' -f $Action.ToLower(), (Format-TgosError $_))
}

exit 0
