#!/usr/bin/env bash
# Mengemas src/ menjadi release/TGOS-v<versi>.apbx (Linux / macOS / CI).
#
# Pemakaian:
#   tools/build.sh
#   TGOS_DIST_PASSWORD='...' tools/build.sh    # sekaligus membuat pembungkus .7z
#
# Butuh: 7-Zip (7z, 7zz, atau 7za), Python 3, PyYAML.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/src"
OUT="$ROOT/release"

# Password .apbx ditentukan AME Wizard dan tidak bisa diganti: Wizard hanya membuka
# playbook yang dienkripsi dengan password ini. Ini bukan rahasia.
APBX_PASSWORD='malte'

SEVENZIP="$(command -v 7z || command -v 7zz || command -v 7za || true)"
if [[ -z "$SEVENZIP" ]]; then
    echo "7-Zip tidak ditemukan. Pasang paket 7zip atau p7zip-full." >&2
    exit 1
fi

python3 "$ROOT/tools/validate.py"
VERSION="$(python3 "$ROOT/tools/validate.py" --print-version)"

APBX="$OUT/TGOS-v$VERSION.apbx"
WRAPPER="$OUT/TGOS-v$VERSION.7z"

mkdir -p "$OUT"
rm -f "$APBX" "$WRAPPER"

# Yang diarsipkan adalah ISI src/, bukan foldernya: playbook.conf harus di akar arsip.
ITEMS=(playbook.conf Configuration Executables)
if [[ -f "$SRC/playbook.png" ]]; then
    ITEMS+=(playbook.png)
fi
(cd "$SRC" && "$SEVENZIP" a -t7z -mx=9 "-p$APBX_PASSWORD" -bso0 -bsp0 "$APBX" "${ITEMS[@]}")
"$SEVENZIP" t "-p$APBX_PASSWORD" -bso0 -bsp0 "$APBX"
echo "Dibuat: ${APBX#"$ROOT"/}"

if [[ -n "${TGOS_DIST_PASSWORD:-}" ]]; then
    # Pembungkus distribusi: nama file ikut dienkripsi (-mhe=on) dan tanpa kompresi
    # (-mx=0) karena .apbx di dalamnya sudah terkompresi.
    (cd "$OUT" && "$SEVENZIP" a -t7z -mx=0 -mhe=on "-p$TGOS_DIST_PASSWORD" -bso0 -bsp0 \
        "$WRAPPER" "$(basename "$APBX")")
    "$SEVENZIP" t "-p$TGOS_DIST_PASSWORD" -bso0 -bsp0 "$WRAPPER"
    echo "Dibuat: ${WRAPPER#"$ROOT"/}"
else
    echo "TGOS_DIST_PASSWORD tidak diisi: pembungkus distribusi .7z dilewati."
fi
