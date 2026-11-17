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
    ("warna gradasi salah format", CONF, "<GradientTopColor>#FB542B</GradientTopColor>",
     "<GradientTopColor>orange</GradientTopColor>", "warna gradasi harus berformat #RRGGBB"),
    ("warna gradasi sama", CONF, "<GradientBottomColor>#A3300F</GradientBottomColor>",
     "<GradientBottomColor>#FB542B</GradientBottomColor>", "dua warna gradasi tidak boleh sama"),
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


# (nama, argumen tambahan, jumlah pin taskbar, potongan yang harus ada, yang tidak boleh ada)
SHELL_LAYOUT_CASES = [
    ("Brave terpasang", ["-BrowserLinkNames", "Brave.lnk"], 3, "Programs\\Brave.lnk", "MSEdge"),
    ("hanya Edge", ["-EdgeInstalled"], 3, "MSEdge", ".lnk"),
    ("Edge dan Chrome: Chrome yang dipin", ["-BrowserLinkNames", "Google Chrome.lnk", "-EdgeInstalled"],
     3, "Google Chrome.lnk", "MSEdge"),
    ("tanpa browser, Store dihapus", ["-StoreRemoved"], 1, "Microsoft.Windows.Explorer", "WindowsStore"),
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
    for name, extra, pin_count, must_have, must_not_have in SHELL_LAYOUT_CASES:
        label = f"layout shell: {name}"
        with tempfile.TemporaryDirectory(prefix="tgos-layout-") as tmp:
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


def test_generated_files() -> int:
    """File yang dibuat dari YAML tidak boleh usang."""
    failures = 0
    for script in ("make-tweaks-doc.py", "make-expected-state.py"):
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
    failures = test_validator() + test_compatibility() + test_shell_layout() + test_generated_files()
    if failures:
        print(f"\nUji diri GAGAL: {failures} kegagalan")
        return 1
    print("\nUji diri lolos")
    return 0


if __name__ == "__main__":
    sys.exit(main())
