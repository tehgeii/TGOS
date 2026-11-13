# Pengujian TGOS

Dokumen ini berisi langkah uji per versi dan tempat mencatat hasilnya. Rencana uji
lengkap (spesifikasi VM, urutan snapshot) ada di
[PLAN.md bagian 11](../PLAN.md#11-rencana-pengujian-di-vmware).

## Yang sudah diuji tanpa Windows

Bisa diulang kapan saja dengan `python tools/selftest.py` dan skrip build. Ini membuktikan
file-nya benar secara bentuk, **bukan** bahwa playbook berjalan benar di Windows.

| Pemeriksaan | Hasil `0.1.0` |
|---|---|
| `tools/validate.py` pada `src/` | Lolos, 0 error, 0 peringatan |
| `tools/selftest.py`: validator menangkap 40 jenis kesalahan yang sengaja disisipkan | 40 dari 40 tertangkap |
| `tools/selftest.py`: `Test-Compatibility.ps1` untuk 13 kombinasi edisi/build/arsitektur | Kode keluar sesuai (0, 10, 11, 12) |
| `tools/selftest.py`: `docs/TWEAKS.md` sesuai dengan YAML | Lolos |
| Sintaks semua `.ps1` (parser PowerShell), tanpa operator khusus PowerShell 7 | Lolos |
| `New-RestorePoint.ps1` saat restore point tidak bisa dibuat | Keluar 0, kegagalan tercatat |
| `Get-SystemSnapshot.ps1` saat sebagian data tidak bisa dibaca | Tetap menulis JSON, galat tercatat |
| `compare-snapshots.py` dengan data buatan (normal, aplikasi tersisa, paket dilindungi hilang) | Hasil sesuai |
| `tools/build.sh` dan `tools/build.ps1` | Keduanya menghasilkan `.apbx` dan `.7z` |
| `.apbx` terbuka dengan password `malte`, ditolak dengan password lain | Lolos |
| Ekstrak pembungkus → ekstrak `.apbx` → bandingkan dengan `src/` | Identik |

Yang **belum** diuji dan hanya bisa diuji di Windows: semua efek nyata v0.1.0 (penghapusan
aplikasi, nilai registry, restore point), dan skrip PowerShell di Windows PowerShell 5.1
(baru dijalankan di PowerShell 7 di Linux).

---

## Fase 0 — kerangka `0.0.2`: LOLOS

| Tanggal | Penguji | Windows | AME Wizard | Uji 1 (Pro) | Uji 2 (bukan Pro) |
|---|---|---|---|---|---|
| 14 Nov 2026 | tehgeii | Windows 11 Pro, VMware | AME Beta | Lolos | Belum diuji |

Yang terbukti:

- AME memuat `.apbx`; nama **TGOS**, pembuat **tehgeii**, dan versi tampil benar.
- Ikon TGOS tampil walau playbook berstatus "Unverified".
- Status akhir "This Playbook is currently applied".
- `C:\ProgramData\TGOS\install-info.txt` terbuat dengan isi benar, jadi aksi `!run`
  dan skrip PowerShell berjalan.
- AME tidak meminta mematikan Defender.

Yang ditemukan:

- Deskripsi di Wizard terpotong setelah sekitar 5 baris. Sejak `0.1.0` deskripsi
  dipendekkan supaya intinya muat.

Yang masih terutang: **Uji 2** (playbook harus berhenti di edisi bukan Pro). Butuh VM
Windows 11 Home. Logikanya sudah diuji di luar Windows untuk 13 kombinasi, tapi belum
pernah dibuktikan lewat AME.

---

## Fase 1a — `0.1.0`: aplikasi bawaan + privasi

**Ini versi pertama yang benar-benar mengubah Windows.** Jalankan hanya di VM, dan selalu
mulai dari snapshot bersih.

### Persiapan (sekali)

1. Kembalikan VM ke snapshot bersih yang sudah di-update (`S1-updated` atau `S2`).
   Jangan menerapkan `0.1.0` di atas hasil `0.0.2`; kalau terpaksa, tidak masalah, tapi
   angka pembandingnya jadi kurang bersih.
2. Salin ke VM: `TGOS-v0.1.0.7z`, `Get-SystemSnapshot.ps1`, dan AME Beta.
3. Ekstrak `.7z` dengan password distribusi.

### Uji A — opsi bawaan

1. Restart VM, tunggu 5 menit, lalu buka **PowerShell sebagai Administrator** di folder
   tempat skrip berada dan jalankan:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Get-SystemSnapshot.ps1 -Label before
   ```

2. Buat snapshot VMware di titik ini (supaya Uji B bisa mulai dari sini).
3. Buka AME Beta, seret `TGOS-v0.1.0.apbx`. Di halaman opsi biarkan bawaan:
   "Remove Copilot and Widgets" tercentang, "Remove Xbox app and Game Bar" tidak.
4. Jalankan sampai selesai, lalu restart.
5. Tunggu 5 menit, jalankan lagi dengan label lain:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Get-SystemSnapshot.ps1 -Label after-A
   ```

6. Kerjakan checklist di bawah.

### Uji B — semua opsi dicentang

Kembali ke snapshot dari langkah 2, terapkan lagi dengan **kedua** opsi dicentang,
restart, lalu jalankan `Get-SystemSnapshot.ps1 -Label after-B`.

### Checklist

Selama proses:

- [ ] Halaman opsi tampil dengan dua kotak centang dan bawaannya benar.
- [ ] AME tidak meminta mematikan Defender.
- [ ] Proses selesai tanpa pesan error. Bila ada, catat teksnya.

Setelah restart:

- [ ] Login normal, tidak ada pesan error.
- [ ] Start menu terbuka; aplikasi yang dihapus tidak tersisa sebagai ubin kosong.
- [ ] Mengetik di Start menemukan aplikasi (mis. "notepad") dan tidak menampilkan
      hasil web.
- [ ] Settings terbuka dan halaman-halamannya bisa dibuka.
- [ ] Masih ada: Microsoft Store, Notepad, Paint, Photos, Calculator, Snipping Tool,
      Terminal, Media Player.
- [ ] Sudah hilang: News, Weather, Solitaire, Teams, Outlook, Clipchamp, Feedback Hub,
      Copilot. Tombol Widgets di taskbar hilang.
- [ ] Microsoft Store bisa memasang satu aplikasi baru.
- [ ] Microsoft Store bisa memasang ulang satu aplikasi yang dihapus (mis. Sticky Notes).
- [ ] `winget --version` jalan di Terminal.
- [ ] Windows Update bisa memeriksa update.
- [ ] Defender masih aktif (Windows Security > Virus & threat protection).
- [ ] `C:\ProgramData\TGOS\install-info.txt` memuat baris `Restore point`, `Modules run`,
      dan `Option selected` sesuai pilihan.
- [ ] Restore point "Before TGOS 0.1.0" ada (*Create a restore point* > *System Restore*).
- [ ] Uji B saja: Xbox app dan Game Bar hilang, dan **tidak muncul** popup
      "You'll need a new app to open this ms-gamebar link" saat menekan Win+G atau
      membuka aplikasi/game.
- [ ] `sfc /verifyonly` (PowerShell Administrator) tidak menemukan pelanggaran.

### Yang dikirim setelah uji

1. File `TGOS-snapshot-before.json`, `TGOS-snapshot-after-A.json`, dan bila ada
   `TGOS-snapshot-after-B.json` dari Desktop.
2. Hasil checklist (mana yang gagal).
3. Bila ada error: tangkapan layar dan folder log AME.

File snapshot tidak memuat nama komputer, nama pengguna, atau alamat jaringan. Isinya
daftar proses (hanya jumlahnya), layanan, paket aplikasi, dan tugas terjadwal.

### Yang sengaja diamati di uji ini

Empat hal ini belum pasti dan dijawab oleh hasil uji:

| Pertanyaan | Bila jawabannya buruk |
|---|---|
| Aplikasi yang dihapus bisa dipasang lagi dari Store? | Cara penghapusan diganti ke `Remove-AppxPackage` biasa. |
| Restore point berhasil dibuat dari dalam playbook? | Dicoba dengan hak akses lain, atau dijadikan langkah manual sebelum instalasi. |
| Menghapus Game Bar memunculkan popup `ms-gamebar`? | Opsi Xbox ditambah perbaikan penangan protokolnya, atau Game Bar dikeluarkan dari opsi. |
| Defender mengganggu saat playbook mengubah sistem? | Requirement `DefenderToggled` terpaksa dipakai selama instalasi. |

### Hasil

| Tanggal | Penguji | Windows (versi, build) | AME Wizard | Uji A | Uji B | Catatan |
|---|---|---|---|---|---|---|
| | | | | | | |
