#!/usr/bin/env python3
"""Membuat gambar untuk halaman pilihan browser di AME Wizard.

Halaman `RadioImagePage` menampilkan satu gambar PNG per opsi di atas gradasi warna yang
ditentukan di playbook.conf. Dokumentasi AME menyarankan tinggi gambar 128 piksel.

Sumbernya logo resmi tiap browser di assets/branding/browser-logos/ (lihat README di
sana; logo itu milik pemiliknya masing-masing). Tiap logo dipotong ke bagian yang
berisi, lalu diperkecil supaya sisi terpanjangnya sama untuk ketiga browser dan
diletakkan di tengah kanvas transparan 128x128. Dengan begitu ketiga logo tampak sama
besar walaupun file sumbernya punya ruang tepi yang berbeda.

Keluaran:
    src/Images/brave.png, chrome.png, firefox.png

Pemakaian:
    python tools/make-option-images.py

Butuh: Pillow. Keluarannya sudah di-commit, jadi skrip ini hanya perlu dijalankan lagi
bila logonya diganti.
"""
from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    sys.exit("Butuh Pillow. Jalankan: pip install pillow")

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "branding" / "browser-logos"
OUTPUT = ROOT / "src" / "Images"

SIZE = 128
LOGO_SIZE = 104  # sisi terpanjang logo di dalam kanvas; sisanya ruang tepi
BROWSERS = ("brave", "chrome", "firefox")


def make_image(source: Path) -> Image.Image:
    logo = Image.open(source).convert("RGBA")
    box = logo.getbbox()
    if box is None:
        sys.exit(f"{source} kosong")
    logo = logo.crop(box)
    scale = LOGO_SIZE / max(logo.size)
    logo = logo.resize((max(1, round(logo.width * scale)), max(1, round(logo.height * scale))), Image.LANCZOS)

    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    canvas.paste(logo, ((SIZE - logo.width) // 2, (SIZE - logo.height) // 2), logo)
    return canvas


def main() -> int:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name in BROWSERS:
        source = SOURCE / f"{name}.png"
        if not source.is_file():
            sys.exit(f"Logo sumber tidak ditemukan: {source.relative_to(ROOT).as_posix()}")
        target = OUTPUT / f"{name}.png"
        make_image(source).save(target, format="PNG", optimize=True)
        print(f"Dibuat: {target.relative_to(ROOT).as_posix()} ({SIZE}x{SIZE}) dari {source.relative_to(ROOT).as_posix()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
