#!/usr/bin/env python3
"""Uji diri untuk perkakas TGOS.

1. Menyisipkan satu kesalahan ke salinan src/ lalu memastikan tools/validate.py
   menangkapnya. Ini menjaga supaya validator tidak diam-diam berhenti memeriksa.
2. Menjalankan Test-Compatibility.ps1 dengan berbagai edisi/build/arsitektur dan
   memastikan kode keluarnya benar (dilewati bila PowerShell tidak terpasang).

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

# (nama, file, teks lama, teks baru, potongan pesan yang harus muncul)
MUTATIONS = [
    ("properti salah ketik", PREFLIGHT, "exeDir: true", "exedir: true",
     "properti 'exedir' tidak dikenal"),
    ("runas tidak valid", PREFLIGHT, "runas: trustedInstaller", "runas: admin",
     "runas: 'admin' tidak valid"),
    ("tag aksi salah ketik", MAIN, "!writeStatus: { status: 'Menyelesaikan' }",
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
     "bukan angka"),
    ("operasi scheduledTask tidak valid", FINALIZE, "actions:",
     "actions:\n  - !scheduledTask: { path: '\\Microsoft\\X', operation: remove }",
     "operation: 'remove' tidak valid"),
    ("tab di YAML", MAIN, "  - !writeStatus: { status: 'Menyelesaikan' }",
     "\t- !writeStatus: { status: 'Menyelesaikan' }", "karakter tab"),
    ("XML rusak", CONF, "</Version>", "</Versio>", "XML tidak valid"),
    ("UUID kosong", CONF, "26dd6cef-05e4-4674-a9d5-d0460896ba6a",
     "00000000-0000-0000-0000-000000000000", "UUID kosong"),
    ("build terlalu lama", CONF, "<string>22621</string>", "<string>19045</string>",
     "lebih lama dari batas TGOS"),
    ("requirement salah ketik", CONF, "<Requirement>PluggedIn", "<Requirement>Pluggedin",
     "tidak dikenal AME Wizard"),
    ("judul tidak memuat versi", CONF, "<Version>0.0.1</Version>", "<Version>0.0.2</Version>",
     "tidak memuat versi"),
    ("elemen conf salah ketik", CONF, "<Overhaul>false</Overhaul>", "<Overhall>false</Overhall>",
     "<Overhall> tidak dikenal"),
    ("non-ASCII di skrip", INFO_SCRIPT, "'Versi TGOS ", "'Versi TGOS – ",
     "karakter non-ASCII"),
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


def main() -> int:
    failures = test_validator() + test_compatibility()
    if failures:
        print(f"\nUji diri GAGAL: {failures} kegagalan")
        return 1
    print("\nUji diri lolos")
    return 0


if __name__ == "__main__":
    sys.exit(main())
