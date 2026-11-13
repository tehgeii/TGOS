#!/usr/bin/env python3
"""Membuat ikon TGOS dari logo TGO asli.

Logo TGO (assets/branding/tgo-logo.png) tidak diubah: skrip ini menyalinnya lalu
menambahkan garis merah dan label "OS" di area hitam di bawah tulisan, supaya ikon
TGOS tetap satu keluarga dengan web dan aplikasi TGO tetapi bisa dibedakan.

Keluaran:
    assets/branding/tgos-icon.png   1024x1024, sumber ikon TGOS
    src/playbook.png                256x256, ikon playbook untuk AME Wizard

Pemakaian:
    python tools/make-icon.py
    python tools/make-icon.py --font "C:\\Windows\\Fonts\\verdanab.ttf"

Butuh: Pillow (pip install pillow) dan font sans tebal. Kedua keluaran sudah di-commit,
jadi skrip ini hanya perlu dijalankan lagi bila logo atau desain labelnya berubah.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # pragma: no cover
    sys.exit("Pillow belum terpasang. Jalankan: pip install pillow")

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "branding" / "tgo-logo.png"
ICON = ROOT / "assets" / "branding" / "tgos-icon.png"
PLAYBOOK_ICON = ROOT / "src" / "playbook.png"

# Geometri tulisan "TGO" pada logo asli 1024x1024 (hasil pengukuran piksel).
WORDMARK_LEFT = 82
WORDMARK_RIGHT = 932
WORDMARK_BOTTOM = 665

RED = (235, 18, 28)      # merah logo asli
WHITE = (255, 255, 255)

LABEL = "OS"
LABEL_CAP_HEIGHT = 96    # tinggi huruf kapital label, piksel
LABEL_GAP = 70           # jarak dari bawah tulisan TGO ke atas label
RULE_THICKNESS = 22      # tebal garis merah
RULE_GAP = 38            # jarak garis merah ke label

PLAYBOOK_ICON_SIZE = 256

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "C:\\Windows\\Fonts\\verdanab.ttf",
    "/Library/Fonts/Verdana Bold.ttf",
    "/System/Library/Fonts/Supplemental/Verdana Bold.ttf",
]


def find_font(explicit: str | None) -> Path:
    candidates = [explicit] if explicit else FONT_CANDIDATES
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return Path(candidate)
    sys.exit("Font tidak ditemukan. Beri jalur font sans tebal dengan --font.")


def fit_font(font_path: Path, cap_height: int) -> ImageFont.FreeTypeFont:
    """Mencari ukuran font yang tinggi huruf kapitalnya tepat cap_height piksel."""
    size = cap_height
    while True:
        font = ImageFont.truetype(str(font_path), size)
        top, bottom = font.getbbox("O")[1], font.getbbox("O")[3]
        if bottom - top >= cap_height:
            return font
        size += 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Membuat ikon TGOS dari logo TGO.")
    parser.add_argument("--font", help="jalur font sans tebal (.ttf/.otf)")
    args = parser.parse_args()

    if not SOURCE.is_file():
        sys.exit(f"Logo sumber tidak ditemukan: {SOURCE}")

    logo = Image.open(SOURCE).convert("RGB")
    if logo.size != (1024, 1024):
        sys.exit(f"Logo sumber harus 1024x1024, bukan {logo.size[0]}x{logo.size[1]}")

    font = fit_font(find_font(args.font), LABEL_CAP_HEIGHT)
    draw = ImageDraw.Draw(logo)

    # Label rata kanan dengan tepi kanan tulisan TGO.
    left, top, right, bottom = font.getbbox(LABEL)
    label_width = right - left
    label_top = WORDMARK_BOTTOM + LABEL_GAP
    label_x = WORDMARK_RIGHT - label_width
    draw.text((label_x - left, label_top - top), LABEL, font=font, fill=WHITE)

    # Garis merah dari tepi kiri tulisan sampai sebelum label, di tengah tinggi label.
    rule_center = label_top + (bottom - top) // 2
    draw.rectangle(
        [WORDMARK_LEFT, rule_center - RULE_THICKNESS // 2,
         label_x - RULE_GAP, rule_center + RULE_THICKNESS // 2 - 1],
        fill=RED)

    ICON.parent.mkdir(parents=True, exist_ok=True)
    logo.save(ICON, format="PNG", optimize=True)

    small = logo.resize((PLAYBOOK_ICON_SIZE, PLAYBOOK_ICON_SIZE), Image.LANCZOS)
    small.save(PLAYBOOK_ICON, format="PNG", optimize=True)

    print(f"Dibuat: {ICON.relative_to(ROOT).as_posix()} (1024x1024)")
    print(f"Dibuat: {PLAYBOOK_ICON.relative_to(ROOT).as_posix()} "
          f"({PLAYBOOK_ICON_SIZE}x{PLAYBOOK_ICON_SIZE})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
