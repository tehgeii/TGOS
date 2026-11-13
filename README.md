# TGOS — Tech Gameplay Operating System

Playbook AME Wizard yang mengubah Windows 11 Pro menjadi OS gaming yang sangat ringan,
dengan prioritas performa.

> **Status: `0.1.0`, tahap uji.** Versi ini menghapus aplikasi bawaan dan menerapkan
> pengaturan privasi. Belum diuji di AME Wizard. Pakai hanya di mesin virtual, jangan di
> komputer utama.

## Target

- Windows 11 **Pro** x64 — 22H2, 23H2, 24H2, 25H2, 26H2
- Dipasang lewat AME Wizard dengan file `.apbx`

## Dokumen

- [PLAN.md](PLAN.md) — rencana lengkap: format playbook, daftar tweak, roadmap.
- [docs/TWEAKS.md](docs/TWEAKS.md) — semua tweak yang diterapkan dan cara mengembalikannya.
- [docs/TESTING.md](docs/TESTING.md) — langkah uji di VMware dan catatan hasil.
- [CHANGELOG.md](CHANGELOG.md) — riwayat versi.

## Struktur

| Folder | Isi |
|---|---|
| `src/` | Sumber playbook: `playbook.conf`, `Configuration/`, `Executables/` |
| `assets/branding/` | Logo TGO, ikon TGOS, wallpaper |
| `tools/` | Validasi, skrip build, potret sistem, pembuat ikon dan dokumen |
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

Memastikan validator masih menangkap kesalahan, pemeriksaan kompatibilitas memberi kode
keluar yang benar, dan `docs/TWEAKS.md` sesuai dengan playbook.

## Mengukur hasil

Di Windows, PowerShell sebagai Administrator, sebelum dan sesudah menerapkan TGOS:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Get-SystemSnapshot.ps1 -Label before
```

Lalu bandingkan dua file hasilnya:

```bash
python tools/compare-snapshots.py TGOS-snapshot-before.json TGOS-snapshot-after.json
```

## Peringatan

TGOS mengurangi fitur keamanan Windows demi performa bila opsinya dipilih. Uji dulu di
mesin virtual dan buat cadangan sebelum memakainya di hardware asli.
