<#
.SYNOPSIS
    Mengatur daya untuk gaming: power plan Ultimate Performance, hibernasi mati,
    dan/atau core parking CPU mati.

.DESCRIPTION
    -UltimatePerformance
        Menyalin skema bawaan "Ultimate Performance" (bila belum pernah), mengaktifkannya,
        dan mematikan USB selective suspend di skema itu. Skema daya yang sudah ada tidak
        diubah atau dihapus, jadi bisa dipilih lagi di Control Panel > Power Options.
        GUID skema TGOS dan skema sebelumnya dicatat di folder data TGOS.

    -DisableHibernation
        Mematikan hibernasi (powercfg /hibernate off), yang juga menghapus hiberfil.sys.

    -DisableCoreParking
        Pada skema daya yang sedang aktif, jumlah core CPU minimum yang tidak boleh
        diparkir dijadikan 100% (CPMINCORES; CPMINCORES1 untuk CPU hibrida), untuk AC dan
        baterai. Nilai sebelumnya dicatat di <folder data TGOS>\core-parking-previous.txt
        supaya TGOS Toolbox bisa mengembalikannya.

    Tidak fatal: kode keluar selalu 0. Hasilnya diperiksa Test-TgosResult.ps1.

    File ini harus tetap ASCII murni dan kompatibel dengan Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [switch]$UltimatePerformance,
    [switch]$DisableHibernation,
    [switch]$DisableCoreParking,
    [string]$DataDirectory
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

# GUID bawaan Windows.
$UltimateTemplate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
$UsbSubgroup = '2a737441-1930-4402-8d77-b2bebba308a3'
$UsbSelectiveSuspend = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
$ProcessorSubgroup = '54533251-82be-4824-96c1-47b60b740d00'
# "Processor performance core parking min cores", kelas core 0 dan 1.
$CoreParkingSettings = @('0cc5b647-c1df-4637-891a-dec35c318583', '0cc5b647-c1df-4637-891a-dec35c318584')
$GuidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

function Invoke-PowerCfg {
    param([string[]]$Arguments)
    $output = & powercfg.exe @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw ('powercfg {0} failed ({1}): {2}' -f ($Arguments -join ' '), $LASTEXITCODE, $output.Trim())
    }
    return $output
}

if ($DisableHibernation) {
    try {
        Invoke-PowerCfg @('/hibernate', 'off') | Out-Null
        Write-Output 'TGOS: hibernation turned off'
    }
    catch {
        Write-Output ("WARNING: could not turn off hibernation: {0}" -f $_.Exception.Message)
    }
}

if ($UltimatePerformance) {
    try {
        $dataDir = Get-TgosDataDirectory -Path $DataDirectory
        $planFile = Join-Path $dataDir 'power-plan.txt'
        $previousFile = Join-Path $dataDir 'power-plan-previous.txt'

        $active = Invoke-PowerCfg @('/getactivescheme')
        if ($active -match $GuidPattern) {
            $activeGuid = $Matches[0].ToLower()
        }
        else {
            throw 'could not read the active power scheme'
        }

        $schemes = Invoke-PowerCfg @('/list')

        # Pakai ulang skema TGOS bila playbook pernah dijalankan, supaya tidak menumpuk.
        $planGuid = $null
        if (Test-Path -LiteralPath $planFile) {
            $recorded = (Get-Content -LiteralPath $planFile -TotalCount 1).Trim().ToLower()
            if ($recorded -match ('^' + $GuidPattern + '$') -and $schemes.ToLower().Contains($recorded)) {
                $planGuid = $recorded
            }
        }

        if (-not $planGuid) {
            $created = Invoke-PowerCfg @('-duplicatescheme', $UltimateTemplate)
            if ($created -match $GuidPattern) {
                $planGuid = $Matches[0].ToLower()
            }
            else {
                throw ('could not read the new scheme GUID from: {0}' -f $created.Trim())
            }
            Invoke-PowerCfg @('-changename', $planGuid, 'TGOS Ultimate Performance', 'Created by TGOS from the Ultimate Performance template.') | Out-Null
            if ($activeGuid -ne $planGuid) {
                Set-Content -LiteralPath $previousFile -Value $activeGuid -Encoding ASCII
            }
        }

        foreach ($index in @('/setacvalueindex', '/setdcvalueindex')) {
            Invoke-PowerCfg @($index, $planGuid, $UsbSubgroup, $UsbSelectiveSuspend, '0') | Out-Null
        }
        Invoke-PowerCfg @('/setactive', $planGuid) | Out-Null
        Set-Content -LiteralPath $planFile -Value $planGuid -Encoding ASCII

        Write-Output ("TGOS: power plan 'TGOS Ultimate Performance' active ({0})" -f $planGuid)
    }
    catch {
        Write-Output ("WARNING: could not apply the power plan: {0}" -f $_.Exception.Message)
    }
}

if ($DisableCoreParking) {
    try {
        $dataDir = Get-TgosDataDirectory -Path $DataDirectory
        $previousFile = Join-Path $dataDir 'core-parking-previous.txt'

        $active = Invoke-PowerCfg @('/getactivescheme')
        if ($active -match $GuidPattern) { $scheme = $Matches[0].ToLower() }
        else { throw 'could not read the active power scheme' }

        $records = @()
        $applied = 0
        foreach ($setting in $CoreParkingSettings) {
            try {
                # Dua angka heksadesimal terakhir di keluaran query adalah nilai AC dan
                # baterai saat ini; urutan itu sama di semua bahasa Windows.
                $query = Invoke-PowerCfg @('/query', $scheme, $ProcessorSubgroup, $setting)
                $values = @([regex]::Matches($query, '0x[0-9a-fA-F]{8}') | ForEach-Object { [Convert]::ToInt32($_.Value, 16) })
                if ($values.Count -ge 2) {
                    $records += ('{0};{1};{2};{3}' -f $scheme, $setting, $values[$values.Count - 2], $values[$values.Count - 1])
                }
                foreach ($index in @('/setacvalueindex', '/setdcvalueindex')) {
                    Invoke-PowerCfg @($index, $scheme, $ProcessorSubgroup, $setting, '100') | Out-Null
                }
                $applied++
            }
            catch {
                # Pengaturan kelas core 1 hanya ada di CPU hibrida; dilewati bila tidak ada.
            }
        }
        if ($applied -eq 0) { throw 'the core parking setting is not available on this PC' }
        Invoke-PowerCfg @('/setactive', $scheme) | Out-Null
        if ($records.Count -gt 0 -and -not (Test-Path -LiteralPath $previousFile)) {
            Set-Content -LiteralPath $previousFile -Value $records -Encoding ASCII
        }
        Write-Output ("TGOS: CPU core parking disabled on the active power plan ({0})" -f $scheme)
    }
    catch {
        Write-Output ("WARNING: could not disable CPU core parking: {0}" -f $_.Exception.Message)
    }
}

exit 0
