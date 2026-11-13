# Pengujian TGOS

Dokumen ini berisi langkah uji per fase dan tempat mencatat hasilnya. Rencana uji
lengkap (spesifikasi VM, urutan snapshot, matriks opsi) ada di
[PLAN.md bagian 11](../PLAN.md#11-rencana-pengujian-di-vmware).

## Yang sudah diuji tanpa Windows

Bisa diulang kapan saja dengan `python tools/selftest.py` dan skrip build. Ini membuktikan
file-nya benar secara bentuk, **bukan** bahwa playbook berjalan di AME Wizard.

| Pemeriksaan | Hasil `0.0.2` |
|---|---|
| `tools/validate.py` pada `src/` | Lolos, 0 error, 0 peringatan |
| `tools/selftest.py`: validator menangkap 25 jenis kesalahan yang sengaja disisipkan | 25 dari 25 tertangkap |
| Sintaks semua `.ps1` (parser PowerShell), tanpa operator khusus PowerShell 7 | Lolos |
| `tools/selftest.py`: `Test-Compatibility.ps1` untuk 13 kombinasi edisi/build/arsitektur | Kode keluar sesuai (0, 10, 11, 12) |
| `Test-Compatibility.ps1` saat registry tidak bisa dibaca | Menolak (kode 1), tidak meloloskan |
| `tools/build.sh` dan `tools/build.ps1` | Keduanya menghasilkan `.apbx` dan `.7z` |
| `.apbx` terbuka dengan password `malte`, ditolak dengan password lain | Lolos |
| Pembungkus `.7z`: daftar file tersembunyi tanpa password | Lolos |
| Ekstrak pembungkus → ekstrak `.apbx` → bandingkan dengan `src/` | Identik |
| `playbook.png` ada di akar arsip, PNG 256x256 | Lolos |

Yang **belum** diuji dan hanya bisa diuji di Windows: apakah AME Wizard memuat `.apbx`
ini, apakah aksi `!run` berjalan seperti yang diharapkan, dan apakah `build.ps1` berjalan
di Windows PowerShell 5.1 (baru dijalankan di PowerShell 7 di Linux).

---

## Fase 0 — kerangka `0.0.2`

**Tujuan:** membuktikan rantai build → AME Wizard → eksekusi bekerja, sebelum ada tweak.
Versi ini hanya memeriksa kompatibilitas dan menulis satu file teks.

### Persiapan

1. Siapkan VM sesuai [PLAN.md 11.1](../PLAN.md#111-persiapan-vm) sampai snapshot
   `S2-baseline-measured`.
2. Unduh AME Wizard dari situs resminya ke dalam VM. Catat versinya di tabel hasil.
3. Salin `TGOS-v0.0.2.7z` ke VM, ekstrak dengan 7-Zip memakai password distribusi.
   Hasilnya `TGOS-v0.0.2.apbx`.

### Uji 1 — jalur lolos (Windows 11 Pro)

1. Buka AME Wizard, seret `TGOS-v0.0.2.apbx` ke jendelanya.
2. Biarkan Defender aktif. Ikuti langkah Wizard sampai selesai.
3. Periksa:

- [ ] Wizard menerima file dan menampilkan nama **TGOS**, pembuat **tehgeii**, versi **0.0.2**.
- [ ] Deskripsi tampil utuh (dua paragraf Inggris + ringkasan Indonesia), tidak ada
      karakter rusak.
- [ ] Wizard tidak mengeluh soal build yang tidak didukung.
- [ ] Proses selesai tanpa pesan error.
- [ ] File `C:\ProgramData\TGOS\install-info.txt` ada dan isinya benar
      (`TGOS version : 0.0.2`, `Windows edition : Professional`, versi dan build sesuai).
- [ ] Log AME memuat baris `PASSED: this system is compatible with TGOS.`
- [ ] Defender masih aktif setelah selesai.
- [ ] Tidak ada perubahan lain: jumlah proses, layanan, dan aplikasi sama dengan baseline.

### Uji 2 — jalur tolak (edisi bukan Pro)

Butuh VM kedua dengan Windows 11 **Home** pada build yang didukung.

- [ ] Wizard memuat playbook (build cocok), lalu playbook **berhenti** di langkah pertama.
- [ ] Log AME memuat `REJECTED: TGOS only supports Windows 11 Pro.`
- [ ] `C:\ProgramData\TGOS\install-info.txt` **tidak** dibuat.

Kalau belum ada VM Home, uji ini boleh ditunda, tapi harus lolos sebelum `0.1.0`
dirilis karena mulai versi itu playbook mengubah sistem.

### Yang perlu dicatat walau semuanya lolos

- Apakah Wizard meminta mematikan Defender atau Tamper Protection meski playbook tidak
  memintanya? (Menentukan nasib requirement `DefenderToggled`, lihat PLAN.md 7.2.)
- Apakah ikon TGOS (logo TGO + label OS) tampil di Wizard? Ikon bisa saja hanya
  ditampilkan untuk playbook yang diverifikasi AME.
- Apakah Wizard meminta restart di akhir?
- Lokasi persis file log AME di versi Wizard yang dipakai.
- Apakah Wizard membuat perubahan sendiri di luar playbook (akun, pengaturan, layanan)?

### Hasil

| Tanggal | Penguji | Windows (versi, build) | AME Wizard | Uji 1 | Uji 2 | Catatan |
|---|---|---|---|---|---|---|
| | | | | | | |

### Kalau gagal

Simpan dan kirim tiga hal ini supaya penyebabnya bisa dicari:

1. Tangkapan layar pesan error di Wizard.
2. Folder log AME Wizard.
3. Hasil perintah berikut di PowerShell:

```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' |
    Select-Object EditionID, DisplayVersion, CurrentBuildNumber, UBR
```
