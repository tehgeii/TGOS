# Changelog

Semua perubahan penting pada TGOS dicatat di sini. Nomor versi mengikuti roadmap di
[PLAN.md](PLAN.md#12-roadmap).

## 0.0.2 — branding dan teks bahasa Inggris (belum diuji di AME Wizard)

Masih kerangka Fase 0, tanpa tweak.

- Ikon playbook `playbook.png`: logo TGO ditambah label `OS`, dibuat `tools/make-icon.py`.
- Aset branding di `assets/branding/`: logo TGO asli, ikon TGOS, wallpaper.
- Teks yang dilihat pengguna (deskripsi Wizard, status progres, pesan skrip,
  `install-info.txt`) kini bahasa Inggris; deskripsi Wizard punya ringkasan Indonesia.
- `tools/validate.py` memeriksa ikon (PNG, 256x256); `tools/selftest.py` mengujinya.
- `PLAN.md`: keputusan edisi, visibilitas repo, branding, dan bahasa; acuan dari website
  TGO dan dokumentasi AME.

## 0.0.1 — kerangka Fase 0 (belum diuji di AME Wizard)

Kerangka untuk membuktikan rantai build → AME Wizard → eksekusi. Tidak ada tweak.

- `playbook.conf` dengan metadata TGOS dan build Windows 11 22H2 sampai 26H2.
- Pemeriksaan kompatibilitas: playbook berhenti bila edisi bukan Pro, build lebih lama
  dari 22621, atau arsitektur bukan x64.
- Pencatat info instalasi ke `%ProgramData%\TGOS\install-info.txt`.
- `tools/validate.py`: validasi `playbook.conf`, YAML, dan skrip terhadap format AME.
- `tools/build.sh` dan `tools/build.ps1`: membuat `.apbx` dan pembungkus distribusi `.7z`.
- Rencana pengembangan (`PLAN.md`) dan panduan uji (`docs/TESTING.md`).
