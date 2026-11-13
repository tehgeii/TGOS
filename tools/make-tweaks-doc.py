#!/usr/bin/env python3
"""Membuat docs/TWEAKS.md dari file tugas playbook.

Daftar tweak di dokumen selalu diambil dari YAML yang benar-benar dijalankan, jadi
dokumen tidak bisa berbeda dari playbook. Keterangan tiap tweak diambil dari komentar
di atas aksinya; judul kelompok dari baris komentar berbentuk "# --- Judul ---".

Pemakaian:
    python tools/make-tweaks-doc.py           # tulis ulang docs/TWEAKS.md
    python tools/make-tweaks-doc.py --check   # kode keluar 1 bila dokumen usang
"""
from __future__ import annotations

import argparse
import importlib.util
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
TASKS = ROOT / "src" / "Configuration" / "Tasks"
OUTPUT = ROOT / "docs" / "TWEAKS.md"

SECTION_RE = re.compile(r"^#\s*-{3}\s*(.+?)\s*-{3,}\s*$")
TRAILING_RE = re.compile(r"\}\s+#\s*(.+?)\s*$")

HEADER = """# Daftar tweak TGOS

> File ini dibuat otomatis oleh `tools/make-tweaks-doc.py` dari file di
> `src/Configuration/Tasks/`. Jangan diedit langsung: ubah YAML-nya (termasuk komentar
> di atas tiap aksi), lalu jalankan skrip itu lagi.

Versi playbook: `{version}`

Kolom **Syarat** kosong berarti tweak selalu diterapkan. `opsi: nama` berarti hanya bila
opsi itu dicentang di AME Wizard; `build: ...` berarti hanya di build Windows tersebut.

## Yang tidak disentuh versi ini

Layanan Windows, tugas terjadwal, Windows Defender, Windows Update, Microsoft Edge,
OneDrive, pengaturan performa, dan tampilan. Semua itu dijadwalkan di versi berikutnya
(lihat [PLAN.md](../PLAN.md#12-roadmap)).

## Cara mengembalikan

| Jenis | Cara |
|---|---|
| Aplikasi yang dihapus | Pasang lagi dari Microsoft Store (cari namanya), atau `winget install <nama>`. |
| Nilai di `...\\Policies\\...` | Bawaan Windows: nilainya tidak ada. Hapus nilainya di Registry Editor, lalu restart. |
| Nilai `HKCU` selain Policies | Sebagian besar punya tombol di Settings (Privacy & security, Personalization > Start, System > Notifications). Atau hapus nilainya supaya Windows memakai bawaan. |
| Semua perubahan registry sekaligus | Pulihkan restore point "Before TGOS <versi>" lewat *Create a restore point* > *System Restore*. Restore point **tidak** mengembalikan aplikasi yang dihapus. |

Catatan: apakah aplikasi yang dihapus bisa dipasang lagi dari Store, dan apakah restore
point berhasil dibuat dari dalam playbook, masih harus dibuktikan di uji VM
(lihat [TESTING.md](TESTING.md)).
"""


def load_validator():
    spec = importlib.util.spec_from_file_location("tgos_validate", ROOT / "tools" / "validate.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["tgos_validate"] = module
    spec.loader.exec_module(module)
    return module


def cell(text: object) -> str:
    return str(text).replace("|", "\\|").replace("\n", " ")


def condition(body: dict) -> str:
    parts = []
    if body.get("option"):
        parts.append(f"opsi: `{body['option']}`")
    if body.get("options"):
        parts.append("opsi: " + " / ".join(f"`{item}`" for item in body["options"]))
    if body.get("builds"):
        parts.append("build: " + ", ".join(f"`{item}`" for item in body["builds"]))
    return "; ".join(parts)


def read_module(path: Path, validator) -> list[tuple[str, list[tuple[object, str, str]]]]:
    """Mengembalikan [(judul kelompok, [(aksi, keterangan, nama tampilan), ...]), ...]."""
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    document = yaml.load(text, Loader=validator.PlaybookLoader)

    sections: list[tuple[str, list]] = []
    by_line = {action.line: action for action in document.get("actions", [])
               if getattr(action, "tag", None)}

    current_title = "Umum"
    current_items: list = []
    comment: list[str] = []
    note = ""

    def flush() -> None:
        nonlocal current_items
        if current_items:
            sections.append((current_title, current_items))
        current_items = []

    for number, raw in enumerate(lines, start=1):
        stripped = raw.strip()
        if stripped.startswith("#"):
            match = SECTION_RE.match(stripped)
            if match:
                flush()
                current_title = match.group(1)
                comment, note = [], ""
            else:
                comment.append(stripped.lstrip("#").strip())
            continue
        if not stripped:
            comment, note = [], ""
            continue
        action = by_line.get(number)
        if action is None:
            continue
        if comment:
            # Komentar berlaku untuk aksi ini dan aksi berikutnya sampai baris kosong
            # atau komentar baru.
            note = " ".join(part for part in comment if part)
            comment = []
        # Komentar di ujung baris adalah nama tampilan aksi itu saja.
        trailing = TRAILING_RE.search(raw)
        label = trailing.group(1) if trailing else ""
        current_items.append((action, note, label))
    flush()
    return sections


def render(validator) -> str:
    report = validator.Report()
    _, version = validator.validate_conf(report)
    out = [HEADER.format(version=version)]

    appx_path = TASKS / "10-debloat-appx.yml"
    if appx_path.is_file():
        out.append("\n## Aplikasi bawaan (`10-debloat-appx.yml`)\n")
        out.append("Nama paket memakai awalan + `*`. Paket yang tidak ada di sistem dilewati.\n")
        for title, items in read_module(appx_path, validator):
            removals = [item for item in items if item[0].tag == "appx"
                        and str(item[0].body.get("operation", "remove")).lower() == "remove"]
            caches = [item for item in items if item[0].tag == "appx"
                      and str(item[0].body.get("operation", "remove")).lower() == "clearcache"]
            if removals:
                out.append(f"\n### {title}\n")
                out.append("| Aplikasi | Paket | Syarat | Keterangan |\n|---|---|---|---|")
                for action, note, label in removals:
                    out.append(f"| {cell(label)} | `{cell(action.body['name'])}` "
                               f"| {condition(action.body)} | {cell(note)} |")
            if caches:
                out.append(f"\n### {title}\n")
                names = ", ".join(f"`{cell(item[0].body['name'])}`" for item in caches)
                out.append(f"Bukan penghapusan: hanya mengosongkan cache {names}. {cell(caches[0][1])}")

    privacy_path = TASKS / "20-privacy.yml"
    if privacy_path.is_file():
        out.append("\n\n## Privasi (`20-privacy.yml`)\n")
        out.append("Semua berupa nilai registry `REG_DWORD`. Nilai `HKCU` diterapkan ke semua pengguna.\n")
        for title, items in read_module(privacy_path, validator):
            values = [(item[0], item[1]) for item in items if item[0].tag == "registryValue"]
            if not values:
                continue
            out.append(f"\n### {title}\n")
            out.append("| Kunci | Nilai | Data | Syarat | Keterangan |\n|---|---|---|---|---|")
            for action, note in values:
                body = action.body
                out.append(f"| `{cell(body['path'])}` | `{cell(body['value'])}` | `{cell(body.get('data', ''))}` "
                           f"| {condition(body)} | {cell(note)} |")

    return "\n".join(out).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Membuat docs/TWEAKS.md dari YAML playbook.")
    parser.add_argument("--check", action="store_true",
                        help="hanya periksa apakah docs/TWEAKS.md masih sesuai")
    args = parser.parse_args()

    content = render(load_validator())

    if args.check:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.is_file() else ""
        if current.replace("\r\n", "\n") != content:
            print("docs/TWEAKS.md usang. Jalankan: python tools/make-tweaks-doc.py")
            return 1
        print("docs/TWEAKS.md sesuai dengan playbook")
        return 0

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(content, encoding="utf-8", newline="\n")
    print(f"Dibuat: {OUTPUT.relative_to(ROOT).as_posix()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
