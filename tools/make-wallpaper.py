#!/usr/bin/env python3
"""Membuat wallpaper TGOS 3840x2160 dengan gradasi halus.

Wallpaper asli (assets/branding/tgo-wallpaper.webp) hanya 2000x1125 dan terkompresi
berat, sehingga gradasinya tampak bergaris. Skrip ini menggambar ulang desain yang sama:
latar gelap dengan gradasi radial dan tulisan "PROJECT TGO" berjarak lebar di tengah.
Warna, posisi, dan ukuran tulisan diukur dari file asli.

Garis pada gradasi dicegah dengan dithering teratur (matriks Bayer 8x8): setiap piksel
dibulatkan ke atas atau ke bawah menurut pola tetap, sehingga peralihan antar-tingkat
warna tersebar halus dan file PNG-nya tetap kecil.

Keluaran:
    assets/branding/tgos-wallpaper.png    3840x2160, sumber wallpaper TGOS
    src/Executables/TGOS/TGOS.png         salinan yang dipasang playbook

Pemakaian:
    python tools/make-wallpaper.py
    python tools/make-wallpaper.py --font /jalur/ke/font-tipis.otf

Butuh: Pillow dan NumPy. Kedua keluaran sudah di-commit, jadi skrip ini hanya perlu
dijalankan lagi bila desainnya berubah.
"""
from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

try:
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError:  # pragma: no cover
    sys.exit("Butuh Pillow dan NumPy. Jalankan: pip install pillow numpy")

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "assets" / "branding" / "tgos-wallpaper.png"
PLAYBOOK_COPY = ROOT / "src" / "Executables" / "TGOS" / "TGOS.png"

WIDTH, HEIGHT = 3840, 2160

# Diukur dari wallpaper asli.
CENTER_COLOR = (18.0, 19.0, 26.0)   # tengah gambar
EDGE_COLOR = (9.0, 11.0, 12.0)      # pada jarak setengah lebar dari tengah, dan seterusnya
FALLOFF = 1.7                        # bentuk kurva dari tengah ke tepi
TEXT = "PROJECT TGO"
TEXT_COLOR = (86, 88, 93)
SHADOW_COLOR = (4, 5, 7)
TEXT_WIDTH_RATIO = 0.3655            # lebar tulisan / lebar gambar
CAP_HEIGHT_RATIO = 0.049             # tinggi huruf kapital / tinggi gambar
WORD_GAP = 1.9                       # jarak antar-kata, dalam kelipatan jarak antar-huruf

FONT_CANDIDATES = [
    "/usr/share/fonts/opentype/inter/Inter-Light.otf",
    "/usr/share/fonts/opentype/inter/InterDisplay-Light.otf",
    "C:\\Windows\\Fonts\\segoeuil.ttf",
]

BAYER_8 = np.array([
    [0, 32, 8, 40, 2, 34, 10, 42],
    [48, 16, 56, 24, 50, 18, 58, 26],
    [12, 44, 4, 36, 14, 46, 6, 38],
    [60, 28, 52, 20, 62, 30, 54, 22],
    [3, 35, 11, 43, 1, 33, 9, 41],
    [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37],
    [63, 31, 55, 23, 61, 29, 53, 21],
], dtype=np.float32)


def find_font(explicit: str | None) -> Path:
    for candidate in ([explicit] if explicit else FONT_CANDIDATES):
        if candidate and Path(candidate).is_file():
            return Path(candidate)
    sys.exit("Font tidak ditemukan. Beri jalur font sans tipis dengan --font.")


def background() -> Image.Image:
    """Gradasi radial dengan dithering Bayer supaya tidak bergaris."""
    ys, xs = np.mgrid[0:HEIGHT, 0:WIDTH].astype(np.float32)
    distance = np.hypot(xs - (WIDTH - 1) / 2, ys - (HEIGHT - 1) / 2) / (WIDTH / 2)
    amount = np.clip(distance, 0.0, 1.0) ** FALLOFF

    # Ambang per piksel di [0, 1): bagian pecahan warna di atas ambang dibulatkan ke atas.
    threshold = (np.tile(BAYER_8, (HEIGHT // 8 + 1, WIDTH // 8 + 1))[:HEIGHT, :WIDTH] + 0.5) / 64.0

    channels = []
    for center, edge in zip(CENTER_COLOR, EDGE_COLOR):
        value = center + (edge - center) * amount
        floor = np.floor(value)
        channels.append((floor + ((value - floor) > threshold)).astype(np.uint8))
    return Image.fromarray(np.dstack(channels), "RGB")


def fit_font(path: Path, cap_height: int) -> ImageFont.FreeTypeFont:
    size = cap_height
    while True:
        font = ImageFont.truetype(str(path), size)
        box = font.getbbox("O")
        if box[3] - box[1] >= cap_height:
            return font
        size += 1


def draw_text(image: Image.Image, font: ImageFont.FreeTypeFont) -> None:
    """Menggambar tulisan huruf demi huruf supaya jarak antar-huruf bisa diatur."""
    target_width = WIDTH * TEXT_WIDTH_RATIO
    letters = list(TEXT)
    widths = [font.getlength(letter) if letter != " " else 0.0 for letter in letters]

    # Jarak antar-huruf dicari supaya lebar total sama dengan wallpaper asli.
    gaps = sum(WORD_GAP if " " in (a, b) else 1.0 for a, b in zip(letters, letters[1:]))
    tracking = (target_width - sum(widths)) / gaps

    top, bottom = font.getbbox("O")[1], font.getbbox("O")[3]
    y = (HEIGHT - (bottom - top)) / 2 - top

    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw_layer, draw_shadow = ImageDraw.Draw(layer), ImageDraw.Draw(shadow)

    x = (WIDTH - target_width) / 2
    for index, letter in enumerate(letters):
        if letter != " ":
            draw_shadow.text((x, y + 4), letter, font=font, fill=SHADOW_COLOR + (255,))
            draw_layer.text((x, y), letter, font=font, fill=TEXT_COLOR + (255,))
        if index + 1 < len(letters):
            step = WORD_GAP if " " in (letter, letters[index + 1]) else 1.0
            x += widths[index] + tracking * step

    image.paste(shadow.filter(ImageFilter.GaussianBlur(3)), (0, 0), shadow.filter(ImageFilter.GaussianBlur(3)))
    image.paste(layer, (0, 0), layer)


def main() -> int:
    parser = argparse.ArgumentParser(description="Membuat wallpaper TGOS 3840x2160.")
    parser.add_argument("--font", help="jalur font sans tipis (.ttf/.otf)")
    args = parser.parse_args()

    image = background()
    draw_text(image, fit_font(find_font(args.font), round(HEIGHT * CAP_HEIGHT_RATIO)))

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT, format="PNG", optimize=True)
    PLAYBOOK_COPY.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(OUTPUT, PLAYBOOK_COPY)

    size_kb = OUTPUT.stat().st_size / 1024
    print(f"Dibuat: {OUTPUT.relative_to(ROOT).as_posix()} ({WIDTH}x{HEIGHT}, {size_kb:.0f} KB)")
    print(f"Disalin: {PLAYBOOK_COPY.relative_to(ROOT).as_posix()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
