#!/usr/bin/env python3
"""Membuat ikon untuk halaman pilihan browser di AME Wizard.

Halaman `RadioImagePage` menampilkan satu gambar PNG per opsi, di atas gradasi warna
yang ditentukan di playbook.conf. Dokumentasi AME menyarankan tinggi gambar 128 piksel.

Ikon di sini SENGAJA bukan logo resmi browser: logo itu merek dagang pemiliknya. Yang
digambar adalah inisial nama browser di dalam lingkaran, putih di atas latar transparan.
Untuk memakai gambar lain, cukup ganti file PNG di src/Images/ (tinggi 128 piksel, nama
file sama dengan <FileName> di playbook.conf).

Keluaran:
    src/Images/brave.png, chrome.png, firefox.png

Pemakaian:
    python tools/make-option-images.py

Butuh: Pillow. Keluarannya sudah di-commit, jadi skrip ini hanya perlu dijalankan lagi
bila desainnya berubah.
"""
from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # pragma: no cover
    sys.exit("Butuh Pillow. Jalankan: pip install pillow")

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "src" / "Images"

SIZE = 128
SCALE = 4  # digambar 4x lalu diperkecil supaya tepinya halus
ICONS = {"brave": "B", "chrome": "C", "firefox": "F"}

FONT_CANDIDATES = [
    "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf",
    "/usr/share/fonts/opentype/inter/Inter-Bold.otf",
    "C:\\Windows\\Fonts\\segoeuib.ttf",
]


def find_font() -> Path:
    for candidate in FONT_CANDIDATES:
        if Path(candidate).is_file():
            return Path(candidate)
    sys.exit("Font tidak ditemukan. Tambahkan jalur font tebal ke FONT_CANDIDATES.")


def draw_icon(letter: str, font_path: Path) -> Image.Image:
    big = SIZE * SCALE
    image = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    margin = 6 * SCALE
    ring = 7 * SCALE
    draw.ellipse((margin, margin, big - margin, big - margin), outline=(255, 255, 255, 255), width=ring)

    font = ImageFont.truetype(str(font_path), 66 * SCALE)
    left, top, right, bottom = font.getbbox(letter)
    x = (big - (right - left)) / 2 - left
    y = (big - (bottom - top)) / 2 - top
    draw.text((x, y), letter, font=font, fill=(255, 255, 255, 255))

    return image.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> int:
    font_path = find_font()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, letter in ICONS.items():
        target = OUTPUT / f"{name}.png"
        draw_icon(letter, font_path).save(target, format="PNG", optimize=True)
        print(f"Dibuat: {target.relative_to(ROOT).as_posix()} ({SIZE}x{SIZE})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
