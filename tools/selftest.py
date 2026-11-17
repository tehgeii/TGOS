#!/usr/bin/env python3
"""Uji diri untuk perkakas TGOS.

1. Menyisipkan satu kesalahan ke salinan src/ lalu memastikan tools/validate.py
   menangkapnya. Ini menjaga supaya validator tidak diam-diam berhenti memeriksa.
2. Menjalankan Test-Compatibility.ps1 dengan berbagai edisi/build/arsitektur dan
   memastikan kode keluarnya benar (dilewati bila PowerShell tidak terpasang).
3. Menjalankan Set-ShellLayout.ps1 -GenerateOnly dan memeriksa layout taskbar dan pin
   Start yang dihasilkannya.
4. Memastikan file yang dibuat dari YAML tidak usang.

Pemakaian:
    python tools/selftest.py
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

PREFLIGHT = "src/Configuration/Tasks/00-preflight.yml"
FINALIZE = "src/Configuration/Tasks/90-finalize.yml"
MAIN = "src/Configuration/main.yml"
CONF = "src/playbook.conf"
INFO_SCRIPT = "src/Executables/Scripts/Write-InstallInfo.ps1"
APPX = "src/Configuration/Tasks/10-debloat-appx.yml"
PRIVACY = "src/Configuration/Tasks/20-privacy.yml"
SERVICES = "src/Configuration/Tasks/30-services.yml"
SECURITY = "src/Configuration/Tasks/60-security-options.yml"
TASK_LIST = "src/Executables/TGOS/scheduled-tasks.txt"
EXPECTED_STATE = "src/Executables/TGOS Toolbox/Support/expected-state.json"
ICON = "src/playbook.png"
OPTION_IMAGE = "src/Images/firefox.png"

# PNG 1x1 yang valid: dipakai untuk menguji pemeriksaan ukuran ikon.
TINY_PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489"
    "0000000d49444154789c6360000002000001e221bc330000000049454e44ae426082")

# (nama, file, teks lama, teks baru, potongan pesan yang harus muncul)
MUTATIONS = [
    ("fitur Toolbox salah ketik", SECURITY, "-Feature UpdatePause -State Off", "-Feature UpdatePauze -State Off",
     "-Feature UpdatePauze tidak ada di ValidateSet"),
    ("properti salah ketik", PREFLIGHT, "exeDir: true", "exedir: true",
     "properti 'exedir' tidak dikenal"),
    ("runas tidak valid", PREFLIGHT, "runas: trustedInstaller", "runas: admin",
     "runas: 'admin' tidak valid"),
    ("tag aksi salah ketik", MAIN, "!writeStatus: { status: 'Finishing up' }",
     "!writeStatuss: { status: 'x' }", "aksi tidak dikenal"),
    ("file tugas hilang", MAIN, "90-finalize.yml", "91-finalize.yml",
     "tidak ditemukan"),
    ("skrip hilang", FINALIZE, "Write-InstallInfo.ps1", "Write-Info.ps1",
     "tidak ada di src/Executables"),
    ("kode keluar tanpa tanda kutip", PREFLIGHT, '{ "!0": halt }', "{ 1: halt }",
     "harus teks dalam tanda kutip"),
    ("tindakan kode keluar tidak valid", PREFLIGHT, "halt }", "stop }",
     "'stop' tidak valid"),
    ("kunci ganda", PREFLIGHT, "    wait: true", "    wait: true\n    wait: false",
     "ditulis lebih dari sekali"),
    ("opsi tidak ada", MAIN, "{ path: 'Tasks\\90-finalize.yml' }",
     "{ path: 'Tasks\\90-finalize.yml', option: '!no-such' }",
     "opsi 'no-such' tidak ada"),
    ("service tanpa operation", FINALIZE, "actions:",
     "actions:\n  - !service: { name: DiagTrack }",
     "'operation' wajib ditulis eksplisit"),
    ("service change tanpa startup", FINALIZE, "actions:",
     "actions:\n  - !service: { name: DiagTrack, operation: change }",
     "butuh 'startup'"),
    ("path registry tanpa hive", FINALIZE, "actions:",
     "actions:\n  - !registryValue: { path: 'SOFTWARE\\X', value: a, data: 1, type: REG_DWORD }",
     "harus diawali HKLM"),
    ("data DWORD bukan angka", FINALIZE, "actions:",
     "actions:\n  - !registryValue: { path: 'HKLM\\SOFTWARE\\X', value: a, data: zz, type: REG_DWORD }",
     "harus angka desimal"),
    ("operasi scheduledTask tidak valid", FINALIZE, "actions:",
     "actions:\n  - !scheduledTask: { path: '\\Microsoft\\X', operation: remove }",
     "operation: 'remove' tidak valid"),
    ("tab di YAML", MAIN, "  - !writeStatus: { status: 'Finishing up' }",
     "\t- !writeStatus: { status: 'Finishing up' }", "karakter tab"),
    ("XML rusak", CONF, "</Version>", "</Versio>", "XML tidak valid"),
    ("UUID kosong", CONF, "26dd6cef-05e4-4674-a9d5-d0460896ba6a",
     "00000000-0000-0000-0000-000000000000", "UUID kosong"),
    ("build terlalu lama", CONF, "<string>22621</string>", "<string>19045</string>",
     "lebih lama dari batas TGOS"),
    ("requirement salah ketik", CONF, "<Requirement>PluggedIn", "<Requirement>Pluggedin",
     "tidak dikenal AME Wizard"),
    ("judul tidak memuat versi", CONF, "</Version>", ".9</Version>",
     "tidak memuat versi"),
    ("elemen conf salah ketik", CONF, "<Overhaul>true</Overhaul>", "<Overhall>true</Overhall>",
     "<Overhall> tidak dikenal"),
    # --- Pengaman AppX ---
    ("appx menghapus Store", APPX, "actions:",
     "actions:\n  - !appx: { name: 'Microsoft.WindowsStore*', type: family }",
     "paket yang dilindungi 'Microsoft.WindowsStore'"),
    ("appx pola terlalu lebar", APPX, "actions:",
     "actions:\n  - !appx: { name: 'Microsoft.Xbox*', type: family }",
     "paket yang dilindungi 'Microsoft.XboxIdentityProvider'"),
    ("appx menghapus codec", APPX, "actions:",
     "actions:\n  - !appx: { name: 'Microsoft.HEVCVideoExtension*', type: family }",
     "paket yang dilindungi 'Microsoft.HEVCVideoExtension'"),
    ("appx diawali wildcard", APPX, "name: 'Microsoft.BingNews*'", "name: '*BingNews*'",
     "tidak boleh diawali wildcard"),
    ("appx nama terlalu pendek", APPX, "name: 'Microsoft.BingNews*'", "name: 'Micro*'",
     "terlalu pendek"),
    ("appx opsi tidak ada", APPX, "option: 'remove-xbox' }", "option: 'remove-xbx' }",
     "opsi 'remove-xbx' tidak ada"),
    # --- Registry ---
    ("DWORD notasi hex", PRIVACY, "value: 'AllowTelemetry', data: '0'",
     "value: 'AllowTelemetry', data: '0x0'", "harus angka desimal"),
    ("DWORD melebihi batas", PRIVACY, "value: 'AllowTelemetry', data: '0'",
     "value: 'AllowTelemetry', data: '4294967296'", "melebihi batas"),
    ("nilai registry kembar", PRIVACY, "actions:",
     "actions:\n  - !registryValue: { path: 'HKCU\\SOFTWARE\\Microsoft\\Siuf\\Rules', "
     "value: 'NumberOfSIUFInPeriod', data: '0', type: REG_DWORD }",
     "sudah ditulis di"),
    ("registry tanpa type", PRIVACY, "value: 'Enabled', data: '0', type: REG_DWORD }",
     "value: 'Enabled', data: '0' }", "'type' wajib"),
    ("filter build salah bentuk", PRIVACY, "builds: ['>=26100'] }", "builds: ['24H2'] }",
     "harus teks seperti"),
    # --- Layanan dan tugas terjadwal ---
    ("layanan yang dilindungi", SERVICES, "actions:",
     "actions:\n  - !service: { name: 'AudioSrv', operation: change, startup: 4 }",
     "layanan yang dilindungi"),
    ("layanan dilindungi, beda huruf besar", SERVICES, "actions:",
     "actions:\n  - !service: { name: 'wuauserv', operation: change, startup: 4 }",
     "layanan yang dilindungi"),
    ("layanan dihapus", SERVICES, "name: 'DiagTrack', operation: change, startup: 4",
     "name: 'DiagTrack', operation: delete", "hanya memakai 'operation: change'"),
    ("startup layanan di luar batas", SERVICES, "name: 'DiagTrack', operation: change, startup: 4",
     "name: 'DiagTrack', operation: change, startup: 0", "bernilai 2, 3, atau 4"),
    ("layanan dengan wildcard", SERVICES, "name: 'DiagTrack'", "name: 'Diag*'",
     "tidak boleh memakai wildcard"),
    ("aksi scheduledTask dipakai", SERVICES, "actions:",
     "actions:\n  - !scheduledTask: { path: '\\Microsoft\\X', operation: disable }",
     "tidak dipakai di TGOS"),
    ("jalur tugas salah bentuk", TASK_LIST, "\\Microsoft\\Windows\\Maps\\MapsUpdateTask",
     "Microsoft\\Windows\\Maps\\MapsUpdateTask", "bukan jalur tugas"),
    ("tugas ditulis dua kali", TASK_LIST, "\\Microsoft\\Windows\\Maps\\MapsUpdateTask",
     "\\Microsoft\\Windows\\Maps\\MapsToastTask", "ditulis lebih dari sekali"),
    # --- Catatan instalasi ---
    ("opsi tidak dicatat", FINALIZE, '-AppendOption "remove-edge"', '-AppendOption "remove-edg"',
     "opsi 'remove-edge' tidak dicatat"),
    ("modul tidak cocok dengan main.yml", FINALIZE, "preflight,software,debloat-appx,", "preflight,software,debloat,",
     "tidak sama dengan modul"),
    ("Store dihapus tanpa opsinya", APPX, "type: family, option: 'remove-store' }  # Microsoft Store",
     "type: family }  # Microsoft Store", "hanya boleh dengan option: 'remove-store'"),
    ("Spooler dimatikan tanpa opsinya", SERVICES, "name: 'Spooler', operation: change, startup: 4, option: 'trim-services'",
     "name: 'Spooler', operation: change, startup: 4", "hanya boleh disentuh dengan option: 'trim-services'"),
    ("gambar opsi tidak ada", CONF, "<FileName>brave</FileName>", "<FileName>opera</FileName>",
     "Images/opera.png tidak ditemukan"),
    ("warna gradasi salah format", CONF, "<FileName>brave</FileName>\n\t\t\t\t\t<GradientTopColor>#1B2232</GradientTopColor>",
     "<FileName>brave</FileName>\n\t\t\t\t\t<GradientTopColor>navy</GradientTopColor>", "warna gradasi harus berformat #RRGGBB"),
    ("warna gradasi sama", CONF, "<FileName>chrome</FileName>\n\t\t\t\t\t<GradientTopColor>#1B2232</GradientTopColor>",
     "<FileName>chrome</FileName>\n\t\t\t\t\t<GradientTopColor>#2C3650</GradientTopColor>", "dua warna gradasi tidak boleh sama"),
    ("opsi gambar tanpa FileName", CONF, "\t\t\t\t\t<FileName>chrome</FileName>\n", "",
     "opsi gambar 'browser-chrome' tanpa <FileName>"),
    ("opsi None di halaman wajib", CONF, '<RadioImagePage DefaultOption="browser-brave"',
     '<RadioImagePage IsRequired="true" DefaultOption="browser-brave"', "punya opsi None tetapi IsRequired"),
    ("kunci options dipakai", PRIVACY, "option: 'remove-ai-widgets' }",
     "options: ['remove-ai-widgets'] }", "options: tidak dipakai"),
    # --- Halaman opsi ---
    ("IsChecked bukan boolean", CONF, 'IsChecked="false"', 'IsChecked="no"',
     "IsChecked harus 'true' atau 'false'"),
    ("deskripsi singkat terlalu panjang", CONF, "<ShortDescription>Tech Gameplay Operating System<",
     "<ShortDescription>Tech Gameplay Operating System for Windows 11 Pro<",
     "<ShortDescription> butuh sekitar 3 baris"),
    ("deskripsi terlalu panjang", CONF, "Windows jadi lebih ringan untuk gaming.",
     "Windows jadi lebih ringan untuk gaming.\n\nWindows Defender stays on.\n\nSatu baris lagi.",
     "<Description> butuh sekitar 8 baris"),
    ("deskripsi halaman terlalu panjang", CONF, "Choose which built-in components to remove.",
     "Choose which built-in components TGOS removes from this Windows installation for you today.",
     "<CheckboxPage> Description butuh sekitar 3 baris"),
    ("teks opsi terlalu panjang", CONF, "<Text>Automatic Windows updates (default)</Text>",
     "<Text>Automatic Windows updates (the Windows default)</Text>",
     "teks opsi 'updates-default' 47 karakter"),
    ("status terlalu panjang", MAIN, "status: 'Removing components'",
     "status: 'Removing optional components'", "Wizard memotong status di atas 22"),
    ("atribut halaman salah ketik", CONF, "<CheckboxPage Description=", "<CheckboxPage Descripton=",
     "atribut 'Descripton' tidak dikenal"),
    ("jenis opsi salah", CONF, '<CheckboxOption IsChecked="false">', "<RadioOption>",
     "XML tidak valid"),
    ("nama opsi kembar", CONF, "<Name>remove-xbox</Name>", "<Name>remove-ai-widgets</Name>",
     "dipakai lebih dari sekali"),
    ("non-ASCII di skrip", INFO_SCRIPT, "'TGOS version ", "'TGOS version \u2013 ",
     "karakter non-ASCII"),
]

# (nama, file, isi baru dalam byte atau None untuk menghapus, potongan pesan)
BINARY_MUTATIONS = [
    ("ikon hilang", ICON, None, "ikon playbook tidak ditemukan"),
    ("ikon bukan PNG", ICON, b"GIF89a bukan png, cuma teks pengisi", "bukan file PNG"),
    ("ikon salah ukuran", ICON, TINY_PNG, "harus 256x256"),
    ("file pendukung hilang", EXPECTED_STATE, None, "file pendukung tidak ditemukan"),
    ("gambar opsi salah tinggi", OPTION_IMAGE, TINY_PNG, "tingginya 1 piksel"),
    ("gambar opsi bukan PNG", OPTION_IMAGE, b"bukan png, cuma teks pengisi yang cukup panjang", "bukan file PNG"),
]

# (edisi, build, arsitektur, kode keluar yang diharapkan)
COMPATIBILITY_CASES = [
    ("Professional", 26300, "AMD64", 0),
    ("Professional", 26200, "AMD64", 0),
    ("Professional", 26100, "AMD64", 0),
    ("Professional", 22631, "AMD64", 0),
    ("Professional", 22621, "AMD64", 0),
    ("Core", 26300, "AMD64", 10),
    ("ProfessionalN", 26300, "AMD64", 10),
    ("Enterprise", 26300, "AMD64", 10),
    ("Education", 26300, "AMD64", 10),
    ("Professional", 22000, "AMD64", 11),
    ("Professional", 19045, "AMD64", 11),
    ("Professional", 26300, "ARM64", 12),
    ("Professional", 26300, "x86", 12),
]


def run_validator(workdir: Path) -> tuple[int, str]:
    result = subprocess.run(
        [sys.executable, str(workdir / "tools" / "validate.py")],
        capture_output=True, text=True, encoding="utf-8", errors="replace")
    return result.returncode, result.stdout + result.stderr


def copy_sources(target: Path) -> None:
    shutil.copytree(ROOT / "src", target / "src")
    shutil.copytree(ROOT / "tools", target / "tools",
                    ignore=shutil.ignore_patterns("__pycache__"))


def test_validator() -> int:
    failures = 0

    code, output = run_validator(ROOT)
    if code != 0:
        print(f"GAGAL  src/ asli tidak lolos validasi:\n{output}")
        return 1
    print("lolos  src/ asli lolos validasi")

    for name, file, old, new, expected in MUTATIONS:
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp)
            copy_sources(work)
            target = work / file
            # newline="" supaya akhir baris file tidak diubah oleh Python.
            with open(target, encoding="utf-8", newline="") as handle:
                text = handle.read()
            old_text = old.replace("\n", "\r\n") if "\r\n" in text else old
            new_text = new.replace("\n", "\r\n") if "\r\n" in text else new
            if old_text not in text:
                print(f"GAGAL  {name}: teks yang mau diubah tidak ada di {file}")
                failures += 1
                continue
            with open(target, "w", encoding="utf-8", newline="") as handle:
                handle.write(text.replace(old_text, new_text, 1))
            code, output = run_validator(work)
        if code == 0:
            print(f"GAGAL  {name}: validator meloloskan kesalahan ini")
            failures += 1
        elif expected not in output:
            print(f"GAGAL  {name}: pesan '{expected}' tidak muncul:\n{output}")
            failures += 1
        else:
            print(f"lolos  {name}")

    for name, file, content, expected in BINARY_MUTATIONS:
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp)
            copy_sources(work)
            target = work / file
            if content is None:
                target.unlink()
            else:
                target.write_bytes(content)
            code, output = run_validator(work)
        if code == 0:
            print(f"GAGAL  {name}: validator meloloskan kesalahan ini")
            failures += 1
        elif expected not in output:
            print(f"GAGAL  {name}: pesan '{expected}' tidak muncul:\n{output}")
            failures += 1
        else:
            print(f"lolos  {name}")
    return failures


def find_powershell() -> str | None:
    for name in ("powershell", "pwsh"):
        path = shutil.which(name)
        if path:
            return path
    return None


def test_compatibility() -> int:
    shell = find_powershell()
    if not shell:
        print("lewat  Test-Compatibility.ps1: PowerShell tidak terpasang")
        return 0

    script = ROOT / "src" / "Executables" / "Scripts" / "Test-Compatibility.ps1"
    failures = 0
    for edition, build, arch, expected in COMPATIBILITY_CASES:
        result = subprocess.run(
            [shell, "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
             "-File", str(script), "-EditionId", edition, "-Build", str(build),
             "-Architecture", arch],
            capture_output=True, text=True, errors="replace")
        label = f"kompatibilitas {edition} / {build} / {arch} -> {expected}"
        if result.returncode != expected:
            print(f"GAGAL  {label}: kode keluar {result.returncode}\n{result.stdout}")
            failures += 1
        else:
            print(f"lolos  {label}")
    return failures


# (nama, argumen tambahan, jumlah pin taskbar, potongan yang harus ada, yang tidak boleh ada,
#  [isi install-info.txt])
SHELL_LAYOUT_CASES = [
    ("Brave terpasang", ["-BrowserLinkNames", "Brave.lnk"], 3, "Programs\\Brave.lnk", "MSEdge"),
    ("hanya Edge", ["-EdgeInstalled"], 3, "MSEdge", ".lnk"),
    ("Edge dan Chrome: Chrome yang dipin", ["-BrowserLinkNames", "Google Chrome.lnk", "-EdgeInstalled"],
     3, "Google Chrome.lnk", "MSEdge"),
    ("tanpa browser, Store dihapus", ["-StoreRemoved"], 1, "Microsoft.Windows.Explorer", "WindowsStore"),
    ("dua browser: hanya yang pertama dipin", ["-BrowserLinkNames", "Google Chrome.lnk,Firefox.lnk"],
     3, "Google Chrome.lnk", "Firefox.lnk"),
    ("dua browser: yang dipilih di Wizard dipin",
     ["-BrowserLinkNames", "browser-chrome=Google Chrome.lnk,browser-firefox=Firefox.lnk"],
     3, "Firefox.lnk", "Google Chrome.lnk", "Option selected : browser-firefox\n"),
]


def test_shell_layout() -> int:
    """Set-ShellLayout.ps1 -GenerateOnly: layout taskbar dan pin Start harus sah."""
    import json
    import xml.etree.ElementTree as ET

    shell = find_powershell()
    if not shell:
        print("lewat  Set-ShellLayout.ps1: PowerShell tidak terpasang")
        return 0

    script = ROOT / "src" / "Executables" / "Scripts" / "Set-ShellLayout.ps1"
    failures = 0
    for name, extra, pin_count, must_have, must_not_have, *rest in SHELL_LAYOUT_CASES:
        label = f"layout shell: {name}"
        with tempfile.TemporaryDirectory(prefix="tgos-layout-") as tmp:
            if rest:
                (Path(tmp) / "install-info.txt").write_text(rest[0], encoding="ascii")
            result = subprocess.run(
                [shell, "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                 "-File", str(script), "-GenerateOnly", "-DataDirectory", tmp, *extra],
                capture_output=True, text=True, errors="replace")
            problems = []
            try:
                xml_text = (Path(tmp) / "TaskbarLayout.xml").read_text(encoding="utf-8")
                json_text = (Path(tmp) / "StartPins.json").read_text(encoding="utf-8")
                root = ET.fromstring(xml_text.encode("utf-8"))
                pins = [node for node in root.iter() if node.tag.endswith("}DesktopApp") or node.tag.endswith("}UWA")]
                if len(pins) != pin_count:
                    problems.append(f"{len(pins)} pin taskbar, seharusnya {pin_count}")
                start = json.loads(json_text)["pinnedList"]
                if not start or any(len(item) != 1 for item in start):
                    problems.append("pinnedList kosong atau salah bentuk")
                for text in (xml_text, json_text.replace("\\\\", "\\")):
                    if must_have not in text:
                        problems.append(f"tidak memuat '{must_have}'")
                    if must_not_have in text:
                        problems.append(f"memuat '{must_not_have}'")
            except (OSError, ValueError, KeyError, ET.ParseError) as exc:
                problems.append(f"{type(exc).__name__}: {exc}")
            if "WARNING" in result.stdout or result.returncode != 0:
                problems.append(result.stdout.strip())
        if problems:
            print(f"GAGAL  {label}: {'; '.join(dict.fromkeys(problems))}")
            failures += 1
        else:
            print(f"lolos  {label}")
    return failures


# Pemindai PowerShell: variabel yang ditulis dengan nama parameter skrip tetapi beda huruf
# besar-kecil (mis. $state dan parameter $State). PowerShell menganggapnya variabel yang
# sama, jadi penulisan itu menimpa parameter. Bug ini pernah membuat tombol Toolbox
# "Extra Services" gagal.
PS_NAME_CHECK = r"""
param([string]$Paths)
$found = 0
$scanned = 0
foreach ($path in ($Paths -split ',')) {
    if (-not (Test-Path -LiteralPath $path)) { Write-Output ('missing file: {0}' -f $path); exit 100 }
    $scanned++
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if (-not $ast.ParamBlock) { continue }
    $params = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    $targets = @()
    $targets += $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true) |
        ForEach-Object { $_.Left } | Where-Object { $_ -is [System.Management.Automation.Language.VariableExpressionAst] }
    $targets += $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] }, $true) |
        ForEach-Object { $_.Variable }
    foreach ($target in $targets) {
        $name = $target.VariablePath.UserPath
        foreach ($param in $params) {
            if ($name -ieq $param -and $name -cne $param) {
                Write-Output ('{0}:{1}: ${2} overwrites the script parameter ${3}' -f $path, $target.Extent.StartLineNumber, $name, $param)
                $found++
            }
        }
    }
}
Write-Output ('scanned {0}' -f $scanned)
exit $found
"""


def run_ps_name_check(shell: str, paths: list[str]) -> subprocess.CompletedProcess:
    with tempfile.TemporaryDirectory(prefix="tgos-names-") as tmp:
        checker = Path(tmp) / "Check-Names.ps1"
        checker.write_text(PS_NAME_CHECK, encoding="ascii")
        return subprocess.run(
            [shell, "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
             "-File", str(checker), "-Paths", ",".join(paths)],
            capture_output=True, text=True, errors="replace")


def test_ps_variable_names() -> int:
    shell = find_powershell()
    if not shell:
        print("lewat  nama variabel PowerShell: PowerShell tidak terpasang")
        return 0
    failures = 0

    # Pemindai harus menangkap contoh yang sengaja salah.
    with tempfile.TemporaryDirectory(prefix="tgos-names-bad-") as tmp:
        bad = Path(tmp) / "Bad.ps1"
        bad.write_text("param([string]$State)\n$state = Get-Date\nforeach ($state in 1..2) { }\n",
                       encoding="ascii")
        result = run_ps_name_check(shell, [str(bad)])
        if result.returncode != 2 or "scanned 1" not in result.stdout:
            print(f"GAGAL  pemindai nama variabel tidak menangkap contoh salah: {result.stdout.strip()}")
            failures += 1
        else:
            print("lolos  pemindai nama variabel menangkap contoh salah")

    scripts = sorted(str(path) for path in (ROOT / "src").rglob("*.ps1"))
    scripts += sorted(str(path) for path in (ROOT / "tools").rglob("*.ps1"))
    # -Paths menerima satu teks dipisah koma; jalur di repo tidak berisi koma.
    assert not any("," in path for path in scripts)
    result = run_ps_name_check(shell, scripts)
    if result.returncode != 0 or f"scanned {len(scripts)}" not in result.stdout:
        print(f"GAGAL  nama variabel menimpa parameter:\n{result.stdout.strip()}")
        failures += 1
    else:
        print(f"lolos  tidak ada variabel yang menimpa parameter ({len(scripts)} skrip)")
    return failures


# Fungsi bersama di Common.ps1 yang menentukan apakah sebuah unduhan boleh dijalankan.
COMMON_CASES = r"""
. $args[0]
$manifest = Get-Content -LiteralPath $args[1] -Raw
$url = 'https://github.com/ip7z/7zip/releases/download/26.06/7z2606-x64.exe'
$checks = @(
    @('sha256 x64 exe', (Get-TgosManifestSha256 -Manifest $manifest -InstallerUrl $url), '9B697F65ECC2D9B0152F5EE96D72DDE522A7827690349D9307935DACF40F42EC'),
    @('sha256 x86 exe bukan x64', (Get-TgosManifestSha256 -Manifest $manifest -InstallerUrl 'https://github.com/ip7z/7zip/releases/download/26.06/7z2606.exe'), '5E38F80C3752DE43887E7A99AD10668C14BF64DCC929A636510B54616EA7DEC7'),
    @('sha256 url tidak ada', [string](Get-TgosManifestSha256 -Manifest $manifest -InstallerUrl 'https://example.invalid/7z.exe'), ''),
    @('sha256 manifest kosong', [string](Get-TgosManifestSha256 -Manifest '' -InstallerUrl $url), ''),
    @('versi 26.06 > 23.01', ((ConvertTo-TgosVersion '26.06') -gt (ConvertTo-TgosVersion '23.01')), $true),
    @('versi 160.0.1 > 160.0', ((ConvertTo-TgosVersion '160.0.1') -gt (ConvertTo-TgosVersion '160.0')), $true),
    @('versi satu angka', [string](ConvertTo-TgosVersion '160'), '160.0'),
    @('versi dengan teks', [string](ConvertTo-TgosVersion '26.06 beta'), '26.6'),
    @('versi tidak terbaca', ($null -eq (ConvertTo-TgosVersion 'unknown')), $true)
)
$bad = 0
foreach ($check in $checks) {
    if ($check[1] -ne $check[2]) { Write-Output ('GAGAL {0}: dapat "{1}", seharusnya "{2}"' -f $check[0], $check[1], $check[2]); $bad++ }
}
Write-Output ('checked {0}' -f $checks.Count)
exit $bad
"""


def test_common_functions() -> int:
    shell = find_powershell()
    if not shell:
        print("lewat  fungsi Common.ps1: PowerShell tidak terpasang")
        return 0
    with tempfile.TemporaryDirectory(prefix="tgos-common-") as tmp:
        runner = Path(tmp) / "Test-Common.ps1"
        runner.write_text(COMMON_CASES, encoding="ascii")
        result = subprocess.run(
            [shell, "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
             "-File", str(runner), str(ROOT / "src" / "Executables" / "Scripts" / "Common.ps1"),
             str(ROOT / "tools" / "fixtures" / "7zip.7zip.installer.yaml")],
            capture_output=True, text=True, errors="replace")
    if result.returncode != 0 or "checked 9" not in result.stdout:
        print(f"GAGAL  fungsi Common.ps1:\n{(result.stdout + result.stderr).strip()}")
        return 1
    print("lolos  fungsi Common.ps1: checksum manifest winget dan perbandingan versi (9 kasus)")
    return 0


def test_generated_files() -> int:
    """File yang dibuat dari YAML tidak boleh usang."""
    failures = 0
    for script in ("make-tweaks-doc.py", "make-expected-state.py", "make-toolbox.py"):
        result = subprocess.run(
            [sys.executable, str(ROOT / "tools" / script), "--check"],
            capture_output=True, text=True, encoding="utf-8", errors="replace")
        if result.returncode != 0:
            print(f"GAGAL  {script}: {(result.stdout + result.stderr).strip()}")
            failures += 1
        else:
            print(f"lolos  {result.stdout.strip()}")
    return failures


def main() -> int:
    failures = (test_validator() + test_compatibility() + test_shell_layout() + test_ps_variable_names()
                + test_common_functions() + test_generated_files())
    if failures:
        print(f"\nUji diri GAGAL: {failures} kegagalan")
        return 1
    print("\nUji diri lolos")
    return 0


if __name__ == "__main__":
    sys.exit(main())
