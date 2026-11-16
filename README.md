# TGOS — Tech Gameplay Operating System

Playbook AME Wizard yang mengubah Windows 11 Pro menjadi OS gaming yang sangat ringan,
dengan prioritas performa.

> **Status: `0.9.1`, tahap uji.** Semua modul sudah ada dan lolos uji otomatis lewat
> mesin AME di Windows Server 2025 dan Windows 11 Enterprise 25H2. Versi `0.9.0` sudah
> diuji sekali di Windows 11 Pro 26H2 (VMware, AME Beta); `0.9.1` berisi perbaikan dari
> uji itu dan menunggu uji ulang. Pakai hanya di mesin virtual, jangan di komputer utama.

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
| `tools/` | Validasi, skrip build, pembanding potret, pembuat ikon dan dokumen |
| `.github/workflows/` | Uji otomatis lewat mesin AME di Windows |
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
keluar yang benar, dan file turunan (`docs/TWEAKS.md`, `expected-state.json`) sesuai
dengan playbook. Setelah mengubah YAML, buat ulang file turunan itu:

```bash
python tools/make-tweaks-doc.py
```

```bash
python tools/make-expected-state.py
```

## Mengukur hasil

Di Windows, PowerShell sebagai Administrator, sebelum dan sesudah menerapkan TGOS:

```powershell
powershell -ExecutionPolicy Bypass -File ".\src\Executables\TGOS Toolbox\Support\Get-SystemSnapshot.ps1" -Label before
```

Lalu bandingkan dua file hasilnya:

```bash
python tools/compare-snapshots.py TGOS-snapshot-before.json TGOS-snapshot-after.json
```

## Peringatan

TGOS mengurangi fitur keamanan Windows demi performa bila opsinya dipilih. Uji dulu di
mesin virtual dan buat cadangan sebelum memakainya di hardware asli.
