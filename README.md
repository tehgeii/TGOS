# TGOS — Tech Gameplay Operating System

Playbook AME Wizard yang mengubah Windows 11 Pro menjadi OS gaming yang sangat ringan,
dengan prioritas performa.

> **Status: `0.0.2`, kerangka uji.** Versi ini hanya memeriksa kompatibilitas sistem dan
> belum menerapkan tweak apa pun. Belum diuji di AME Wizard. Jangan dipakai di komputer
> utama.

## Target

- Windows 11 **Pro** x64 — 22H2, 23H2, 24H2, 25H2, 26H2
- Dipasang lewat AME Wizard dengan file `.apbx`

## Dokumen

- [PLAN.md](PLAN.md) — rencana lengkap: format playbook, daftar tweak, roadmap.
- [docs/TESTING.md](docs/TESTING.md) — langkah uji di VMware dan catatan hasil.
- [CHANGELOG.md](CHANGELOG.md) — riwayat versi.

## Struktur

| Folder | Isi |
|---|---|
| `src/` | Sumber playbook: `playbook.conf`, `Configuration/`, `Executables/` |
| `assets/branding/` | Logo TGO, ikon TGOS, wallpaper |
| `tools/` | Validasi, skrip build, pembuat ikon |
| `docs/` | Dokumen pengujian |
| `release/` | Hasil build (tidak di-commit) |

## Build

Butuh [7-Zip](https://www.7-zip.org), Python 3, dan PyYAML (`pip install pyyaml`).

Windows (PowerShell):

```powershell
.\tools\build.ps1
```

Linux:

```bash
tools/build.sh
```

Skrip build menjalankan `tools/validate.py` dulu dan berhenti bila ada kesalahan.
Hasilnya `release/TGOS-v<versi>.apbx`. Untuk sekaligus membuat pembungkus distribusi
berpassword (`release/TGOS-v<versi>.7z`), isi variabel lingkungan `TGOS_DIST_PASSWORD`
sebelum menjalankan skrip. Password itu tidak pernah ditulis di repo.

Catatan: file `.apbx` sendiri selalu memakai password `malte`. Itu ketentuan AME Wizard
dan tidak bisa diganti; penjelasannya ada di [PLAN.md bagian 3](PLAN.md#3-soal-password-apbx).

## Uji perkakas

```bash
python tools/selftest.py
```

Memastikan validator masih menangkap kesalahan dan pemeriksaan kompatibilitas memberi
kode keluar yang benar.

## Peringatan

TGOS mengurangi fitur keamanan Windows demi performa bila opsinya dipilih. Uji dulu di
mesin virtual dan buat cadangan sebelum memakainya di hardware asli.
