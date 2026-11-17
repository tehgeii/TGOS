#!/usr/bin/env python3
"""Membuat tombol .cmd TGOS Toolbox dari satu tabel.

Keluaran (di src/Executables/TGOS Toolbox/):
    Turn ON or OFF/<Fitur> - Turn ON.cmd / - Turn OFF.cmd   (lewat Support/Set-TgosFeature.ps1)
    Install Software.cmd                                    (menu, lewat Support/Install-Software.ps1)

Tiap nama fitur dan program dicocokkan dengan ValidateSet di skrip PowerShell-nya, jadi
tombol yang memanggil fitur yang tidak ada tertangkap sebelum rilis.

Pemakaian:
    python tools/make-toolbox.py           # tulis ulang file
    python tools/make-toolbox.py --check   # kode keluar 1 bila file usang atau tidak cocok

File .cmd ditulis ASCII dengan akhir baris CRLF (cmd.exe membaca file per baris CRLF).
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOLBOX = ROOT / "src" / "Executables" / "TGOS Toolbox"
FEATURE_DIR = TOOLBOX / "Turn ON or OFF"
FEATURE_SCRIPT = TOOLBOX / "Support" / "Set-TgosFeature.ps1"
INSTALL_SCRIPT = ROOT / "src" / "Executables" / "Scripts" / "Install-Software.ps1"
MENU = TOOLBOX / "Install Software.cmd"

# (label tombol, nama fitur di Set-TgosFeature.ps1, teks untuk -State Off, teks untuk -State On)
FEATURES = [
    ("Windows Defender", "Defender", "Turn OFF", "Turn ON"),
    ("Core Isolation VBS", "Vbs", "Turn OFF", "Turn ON"),
    ("CPU Mitigations", "Mitigations", "Turn OFF", "Turn ON"),
    ("Automatic Updates", "AutoUpdate", "Turn OFF", "Turn ON"),
    ("Windows Updates", "UpdatePause", "Pause", "Resume"),
    ("Driver Updates", "DriverUpdates", "Turn OFF", "Turn ON"),
    ("Search Indexing", "Indexing", "Turn OFF", "Turn ON"),
    ("Hibernation", "Hibernation", "Turn OFF", "Turn ON"),
    ("CPU Core Parking", "CoreParking", "Turn OFF", "Turn ON"),
    ("Extra Services", "ExtraServices", "Turn OFF", "Turn ON"),
    ("Telemetry Collectors", "Telemetry", "Turn OFF", "Turn ON"),
    ("Background Apps", "BackgroundApps", "Turn OFF", "Turn ON"),
    ("Lock Screen", "LockScreen", "Turn OFF", "Turn ON"),
    ("Xbox Game Bar", "GameBar", "Turn OFF", "Turn ON"),
    ("TGO Login Screen", "LoginTheme", "Turn OFF", "Turn ON"),
    ("Reserved Storage", "ReservedStorage", "Turn OFF", "Turn ON"),
]

# Tombol di folder utama Toolbox yang menjalankan satu skrip Support (nama file, rem, skrip,
# argumen, baris echo sebelum skrip jalan).
SCRIPT_BUTTONS = [
    ("Deep Clean.cmd", "clean temporary files, update caches, error reports and old components",
     "Invoke-DeepClean.ps1", "",
     ["Deep clean: removes temporary files, Windows Update caches, error reports, crash",
      "dumps and replaced Windows components, and turns reserved storage off. It takes",
      "a few minutes. Your files, games and the Recycle Bin are not touched.",
      "Membersihkan file sementara dan sampah Windows. File pribadi tidak disentuh."]),
]

# (teks menu, item Install-Software.ps1 yang dipasang berurutan)
SOFTWARE = [
    ("Brave", ["brave"]),
    ("Google Chrome", ["chrome"]),
    ("Mozilla Firefox", ["firefox"]),
    ("7-Zip", ["7zip"]),
    ("Game runtimes (Visual C++ 2005-2022, DirectX, XNA)", ["vcredist", "vcredist-legacy", "xna", "directx"]),
    (".NET (Framework 3.5 and Desktop Runtime)", ["netfx3", "dotnet"]),
    ("Steam", ["steam"]),
    ("Epic Games Launcher", ["epic"]),
    ("EA app", ["ea"]),
    ("Ubisoft Connect", ["ubisoft"]),
    ("Discord (for this account)", ["discord"]),
    ("Spotify (for this account)", ["spotify"]),
]

ELEVATE = [
    "setlocal",
    "fltmc >nul 2>&1",
    "if not errorlevel 1 goto run",
    "powershell -NoProfile -Command \"Start-Process -FilePath '%~f0' -Verb RunAs\"",
    "exit /b",
    ":run",
]


def feature_file(label: str, feature: str, verb: str, state: str) -> tuple[Path, str]:
    lines = ["@echo off", f"rem TGOS Toolbox - {label}: {verb.lower()}"] + ELEVATE + [
        "powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "
        f"\"%~dp0..\\Support\\Set-TgosFeature.ps1\" -Feature {feature} -State {state}",
        "echo.",
        "pause",
    ]
    return FEATURE_DIR / f"{label} - {verb}.cmd", "\r\n".join(lines) + "\r\n"


def script_button(rem: str, script: str, arguments: str, notes: list[str]) -> str:
    lines = ["@echo off", f"rem TGOS Toolbox - {rem}"] + ELEVATE + [f"echo {note}" for note in notes] + [
        "echo.",
        "powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "
        f"\"%~dp0Support\\{script}\"" + (f" {arguments}" if arguments else ""),
        "echo.",
        "pause",
    ]
    return "\r\n".join(lines) + "\r\n"


def menu_file() -> str:
    # "set /p" (ketik nomor lalu Enter), bukan "choice": choice membaca keyboard langsung,
    # jadi menu tidak bisa diuji otomatis dengan input yang disuapkan. Enter tanpa nomor
    # (atau input habis) = keluar, supaya menu tidak berputar tanpa akhir.
    lines = ["@echo off", "rem TGOS Toolbox - download and install software from official sites"] + ELEVATE + [
        "set \"INSTALLER=%~dp0Support\\Install-Software.ps1\"",
        ":menu",
        "cls",
        "echo TGOS Toolbox - Install Software",
        "echo.",
        "echo Each program is downloaded from its official site, and its digital signature",
        "echo is checked before it runs. Needs internet. A program that is already",
        "echo installed is installed again (repaired or updated).",
        "echo Diunduh dari situs resminya dan tanda tangannya diperiksa. Butuh internet.",
        "echo.",
    ]
    for number, (text, _) in enumerate(SOFTWARE, start=1):
        lines.append(f"echo   {number:>2}  {text}")
    lines += [
        "echo    0  Exit / Keluar",
        "echo.",
        "set \"PICK=\"",
        "set /p \"PICK=Type a number, then Enter / Ketik nomor lalu Enter: \"",
        "if not defined PICK exit /b 0",
        "if \"%PICK%\"==\"0\" exit /b 0",
    ]
    for number, (_, items) in enumerate(SOFTWARE, start=1):
        for item in items:
            lines.append(f"if \"%PICK%\"==\"{number}\" call :install {item}")
    lines += [
        "echo.",
        "pause",
        "goto menu",
        ":install",
        "powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File \"%INSTALLER%\" -Item %1 -Force",
        "exit /b",
    ]
    return "\r\n".join(lines) + "\r\n"


def validate_set(script: Path, parameter: str) -> set[str]:
    text = script.read_text(encoding="ascii")
    match = re.search(r"\[ValidateSet\(([^)]*)\)\]\s*\[string\]\$" + parameter + r"\b", text)
    if not match:
        raise SystemExit(f"ValidateSet untuk -{parameter} tidak ditemukan di {script.relative_to(ROOT)}")
    return set(re.findall(r"'([^']+)'", match.group(1)))


def expected_files() -> dict[Path, str]:
    problems = []
    features = validate_set(FEATURE_SCRIPT, "Feature")
    items = validate_set(INSTALL_SCRIPT, "Item")
    files: dict[Path, str] = {}
    for label, feature, off, on in FEATURES:
        if feature not in features:
            problems.append(f"fitur '{feature}' tidak ada di ValidateSet Set-TgosFeature.ps1")
        for verb, state in ((off, "Off"), (on, "On")):
            path, content = feature_file(label, feature, verb, state)
            files[path] = content
    for text, names in SOFTWARE:
        for name in names:
            if name not in items:
                problems.append(f"program '{name}' ({text}) tidak ada di ValidateSet Install-Software.ps1")
    files[MENU] = menu_file()
    for name, rem, script, arguments, notes in SCRIPT_BUTTONS:
        source = ROOT / "src" / "Executables" / "Scripts" / script
        if not source.is_file():
            problems.append(f"skrip '{script}' untuk tombol '{name}' tidak ada di src/Executables/Scripts")
        files[TOOLBOX / name] = script_button(rem, script, arguments, notes)
    if problems:
        raise SystemExit("\n".join(problems))
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description="Membuat tombol TGOS Toolbox.")
    parser.add_argument("--check", action="store_true", help="hanya periksa apakah file masih sesuai")
    args = parser.parse_args()

    files = expected_files()
    stale = sorted(path for path in FEATURE_DIR.glob("*.cmd") if path not in files) if FEATURE_DIR.is_dir() else []
    if args.check:
        bad = [path for path, content in files.items()
               if not path.is_file() or path.read_bytes() != content.encode("ascii")]
        if bad or stale:
            for path in bad + stale:
                print(f"usang: {path.relative_to(ROOT).as_posix()}")
            print("Tombol TGOS Toolbox usang. Jalankan: python tools/make-toolbox.py")
            return 1
        print(f"tombol TGOS Toolbox sesuai ({len(files)} file)")
        return 0

    FEATURE_DIR.mkdir(parents=True, exist_ok=True)
    for path in stale:
        path.unlink()
        print(f"Dihapus: {path.relative_to(ROOT).as_posix()}")
    for path, content in files.items():
        path.write_bytes(content.encode("ascii"))
    print(f"Dibuat: {len(files)} file tombol TGOS Toolbox")
    return 0


if __name__ == "__main__":
    sys.exit(main())
