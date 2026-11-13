# Changelog

Semua perubahan penting pada TGOS dicatat di sini. Nomor versi mengikuti roadmap di
[PLAN.md](PLAN.md#12-roadmap).

## 0.1.0 — tweak pertama: aplikasi bawaan dan privasi (belum diuji di AME Wizard)

Versi pertama yang mengubah Windows. Layanan, tugas terjadwal, Defender, dan Windows
Update belum disentuh.

- Menghapus 26 aplikasi bawaan (berita, cuaca, Office hub, Teams, Clipchamp, dan lainnya).
  Store, winget, codec, Notepad, Paint, Photos, Calculator, Snipping Tool, Terminal,
  Camera, dan Media Player dipertahankan.
- Opsi di Wizard: hapus Copilot dan Widgets (default aktif); hapus Xbox app dan Game Bar
  (default mati).
- 40 pengaturan privasi lewat registry: telemetri, Advertising ID, saran dan iklan di
  Start/Settings/lock screen, Activity History, pencarian web di Start, Recall.
- Restore point "Before TGOS <versi>" dibuat sebelum perubahan (tidak fatal bila gagal).
- `install-info.txt` kini mencatat hasil restore point, modul, dan opsi yang dipilih.
- `tools/Get-SystemSnapshot.ps1` dan `tools/compare-snapshots.py`: potret sistem sebelum
  dan sesudah, lalu perbandingannya.
- `tools/validate.py`: daftar paket yang dilindungi (validasi gagal bila ada aksi yang
  akan menghapusnya), aturan nama paket, data DWORD desimal, nilai registry kembar,
  aturan halaman opsi.
- `docs/TWEAKS.md` dibuat otomatis dari YAML oleh `tools/make-tweaks-doc.py`.
- Hasil uji Fase 0 dicatat di `docs/TESTING.md`: lolos di AME Beta.

## 0.0.2 — branding dan teks bahasa Inggris (lolos uji di AME Beta)

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
