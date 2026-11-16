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

## Yang tidak pernah disentuh

Windows Firewall, UAC, Secure Boot, TPM, layanan audio, jaringan, Windows Update, Store,
Bluetooth, dan printer. Windows Defender tidak disentuh saat instalasi; hanya bisa diubah
pengguna lewat TGOS Toolbox sesudahnya.

## Cara mengembalikan

| Jenis | Cara |
|---|---|
| Aplikasi yang dihapus | Pasang lagi dari Microsoft Store (cari namanya), atau `winget install <nama>`. |
| Defender, VBS, mitigasi CPU, update otomatis, indexing, hibernasi | File *Turn ON* di **TGOS Toolbox** (pintasan di Desktop). |
| Layanan | `services.msc` > klik dua kali layanan > ubah *Startup type*. |
| Tugas terjadwal | Task Scheduler > cari tugasnya > *Enable*. |
| Power plan | Control Panel > Power Options > pilih skema lain. Skema lama tidak dihapus. |
| Nilai di `...\\Policies\\...` | Bawaan Windows: nilainya tidak ada. Hapus nilainya di Registry Editor, lalu restart. |
| Nilai `HKCU` selain Policies | Sebagian besar punya tombol di Settings. Atau hapus nilainya supaya Windows memakai bawaan. |
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


MODULE_TITLES = {
    "00-preflight.yml": "Persiapan",
    "10-debloat-appx.yml": "Aplikasi bawaan",
    "20-privacy.yml": "Privasi",
    "30-services.yml": "Layanan",
    "40-scheduled-tasks.yml": "Tugas terjadwal",
    "50-performance.yml": "Performa",
    "60-security-options.yml": "Opsi keamanan",
    "70-components.yml": "Komponen",
    "80-interface.yml": "Tampilan",
    "90-finalize.yml": "Penyelesaian",
}
STARTUP_NAMES = {2: "Automatic", 3: "Manual", 4: "Disabled"}
SCRIPT_RE = re.compile(r'-File\s+"\.\\([^"]+)"')
# Aksi pencatat (satu baris per opsi) tidak perlu didaftar sebagai tweak.
RECORD_RE = re.compile(r"-AppendOption")


def module_files(validator) -> list[Path]:
    """File tugas dalam urutan eksekusi main.yml."""
    main = yaml.load((ROOT / "src" / "Configuration" / "main.yml").read_text(encoding="utf-8"),
                     Loader=validator.PlaybookLoader)
    files = []
    for action in main.get("actions", []):
        if getattr(action, "tag", None) == "task":
            files.append(TASKS / Path(action.body["path"].replace("\\", "/")).name)
    return files


def read_task_list() -> list[tuple[str, list[tuple[str, str]]]]:
    """Mengembalikan [(judul kelompok, [(jalur tugas, keterangan), ...]), ...]."""
    path = ROOT / "src" / "Executables" / "TGOS" / "scheduled-tasks.txt"
    groups: list[tuple[str, list]] = []
    title, items, note = "Umum", [], ""
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        match = SECTION_RE.match(line)
        if match:
            if items:
                groups.append((title, items))
            title, items, note = match.group(1), [], ""
        elif line.startswith("#"):
            note = line.lstrip("#").strip()
        elif not line:
            note = ""
        elif groups or title != "Umum":
            items.append((line, note))
    if items:
        groups.append((title, items))
    return groups


def render_module(path: Path, validator, out: list[str]) -> None:
    sections = read_module(path, validator)
    out.append(f"\n\n## {MODULE_TITLES.get(path.name, path.stem)} (`{path.name}`)\n")

    for title, items in sections:
        removals = [i for i in items if i[0].tag == "appx"
                    and str(i[0].body.get("operation", "remove")).lower() == "remove"]
        caches = [i for i in items if i[0].tag == "appx"
                  and str(i[0].body.get("operation", "remove")).lower() == "clearcache"]
        values = [i for i in items if i[0].tag == "registryValue"]
        services = [i for i in items if i[0].tag == "service"]
        runs = [i for i in items if i[0].tag == "run"
                and not RECORD_RE.search(str(i[0].body.get("args", "")))]
        if not (removals or caches or values or services or runs):
            continue
        if len(sections) > 1 or title != "Umum":
            out.append(f"\n### {title}\n")

        if removals:
            out.append("| Aplikasi | Paket | Syarat | Keterangan |\n|---|---|---|---|")
            for action, note, label in removals:
                out.append(f"| {cell(label)} | `{cell(action.body['name'])}` "
                           f"| {condition(action.body)} | {cell(note)} |")
        if caches:
            names = ", ".join(f"`{cell(i[0].body['name'])}`" for i in caches)
            out.append(f"Bukan penghapusan: hanya mengosongkan cache {names}. {cell(caches[0][1])}")
        if values:
            if removals:
                out.append("")
            out.append("| Kunci | Nilai | Data | Syarat | Keterangan |\n|---|---|---|---|---|")
            for action, note, _ in values:
                body = action.body
                if str(body.get("operation", "")).lower() == "delete":
                    data = "*(dihapus)*"
                else:
                    data = f"`{cell(body.get('data', ''))}`"
                out.append(f"| `{cell(body['path'])}` | `{cell(body['value'])}` | {data} "
                           f"| {condition(body)} | {cell(note)} |")
        if services:
            out.append("| Layanan | Startup menjadi | Syarat | Keterangan |\n|---|---|---|---|")
            for action, note, _ in services:
                body = action.body
                startup = STARTUP_NAMES.get(body.get("startup"), body.get("startup"))
                out.append(f"| `{cell(body['name'])}` | {startup} | {condition(body)} | {cell(note)} |")
        if runs:
            if values or services:
                out.append("")
            out.append("| Skrip | Syarat | Keterangan |\n|---|---|---|")
            for action, note, _ in runs:
                match = SCRIPT_RE.search(str(action.body.get("args", "")))
                script = match.group(1) if match else str(action.body.get("exe", ""))
                extra = str(action.body.get("args", ""))[match.end():].strip() if match else ""
                name = f"`{cell(script)}`" + (f" `{cell(extra)}`" if extra else "")
                out.append(f"| {name} | {condition(action.body)} | {cell(note)} |")

    if path.name == "40-scheduled-tasks.yml":
        out.append("\nTugas yang dinonaktifkan (dari `src/Executables/TGOS/scheduled-tasks.txt`; "
                   "tugas yang tidak ada di build tertentu dilewati):\n")
        out.append("| Tugas | Kelompok | Keterangan |\n|---|---|---|")
        for title, items in read_task_list():
            for task, note in items:
                out.append(f"| `{cell(task)}` | {cell(title)} | {cell(note)} |")


def render(validator) -> str:
    report = validator.Report()
    _, version = validator.validate_conf(report)
    out = [HEADER.format(version=version)]
    for path in module_files(validator):
        render_module(path, validator, out)
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
