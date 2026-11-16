# Pengujian TGOS

TGOS diuji di tiga lapis. Tujuannya: kesalahan tertangkap sebelum sampai ke VM, supaya
uji di VM cukup sekali per rilis.

| Lapis | Di mana | Yang dibuktikan | Yang TIDAK dibuktikan |
|---|---|---|---|
| 1. Uji bentuk | Linux, `python tools/selftest.py` | YAML dan `playbook.conf` sesuai format AME; aturan pengaman TGOS dipatuhi; file turunan tidak usang | Apa pun yang terjadi di Windows |
| 2. Mesin AME | GitHub Actions: Windows Server 2025 (x64) dan Windows 11 Enterprise 25H2 (ARM64) | Mesin AME yang asli menjalankan playbook tanpa error; setiap tweak benar-benar ada di sistem; aplikasi bawaan terhapus; restore point terbuat; Toolbox bolak-balik | Edisi Pro, build 26300, x64 asli, tampilan, pasang ulang dari Store |
| 3. VM pemilik | VMware, Windows 11 Pro 26H2 | Hasil sebenarnya di sistem target | — |

## Lapis 1 — uji bentuk

```bash
python tools/selftest.py
```

- `tools/validate.py` harus lolos pada `src/`.
- Validator harus menangkap setiap kesalahan yang sengaja disisipkan (salah ketik
  properti, paket atau layanan yang dilindungi, opsi yang tidak dicatat, dan lainnya).
- `Test-Compatibility.ps1` harus memberi kode keluar yang benar untuk 13 kombinasi
  edisi/build/arsitektur.
- `docs/TWEAKS.md` dan `expected-state.json` harus sama dengan hasil generatornya.

## Lapis 2 — mesin AME di GitHub Actions

Workflow `.github/workflows/test.yml` jalan otomatis di setiap push. Job `engine`
menjalankan `tools/ci/Test-Engine.ps1` di tiga susunan: Windows Server dengan opsi
bawaan, Windows Server dengan semua opsi dicentang, dan Windows 11 dengan opsi bawaan:

1. `tools/build.ps1` dijalankan di Windows PowerShell 5.1, lalu `.apbx` hasilnya
   diekstrak. Yang diuji adalah arsip yang sama dengan yang dikirim ke pengguna.
2. **Uji tolak.** Playbook apa adanya dijalankan lewat runner command-line AME
   (`TrustedUninstaller.CLI.exe`). Karena runner bukan Windows Pro x64, playbook harus
   berhenti di langkah pertama tanpa mengubah apa pun.
3. **Uji lolos.** Salinan sementara playbook dengan edisi dan arsitektur runner
   diizinkan harus selesai dengan "Playbook completed successfully." Tugas terjadwal di
   daftar diaktifkan dulu, supaya penonaktifannya benar-benar teruji.
4. **Pemeriksaan diri.** `Test-TgosResult.ps1` tidak boleh melaporkan `FAIL`.
5. **Toolbox.** Tiap fitur dimatikan lalu dinyalakan lagi, dan nilai registrinya dicek.
   Di Windows 11, *Defender OFF* harus **ditolak** selama Tamper Protection aktif.
6. **Pengumpul laporan** harus menghasilkan `TGOS-report.zip` yang lengkap.

Yang dibuktikan runner Windows 11 dan tidak bisa dibuktikan Windows Server: aplikasi
bawaan benar-benar terhapus lewat aksi `!appx`, restore point bisa dibuat dari dalam
playbook, Defender tidak mengganggu dan tetap aktif sesudahnya, dan tidak ada nilai
registry yang ditolak Windows.

Batas lapis ini:

- Runner Windows 11 adalah edisi **Enterprise**, build **26200**, **ARM64**. Target TGOS
  adalah Pro, sampai build 26300, x64. Isi bawaan Pro bisa berbeda (mis. OneDrive).
- Pengukuran proses dan RAM di CI tidak berarti: diambil tanpa restart, saat skrip uji
  masih berjalan.
- Tidak ada yang melihat layar: Start, taskbar, wallpaper tidak dinilai.
- Pasang ulang aplikasi dari Store tidak dicoba.
- Mematikan Defender setelah Tamper Protection dimatikan manual tidak dicoba di Windows 11
  (di Windows Server, yang tanpa Tamper Protection, jalur itu lolos).

## Lapis 3 — uji di VM

**Jalankan hanya di VM.** TGOS mengubah Windows secara nyata.

### Sekali saja: potret sistem bersih

Dari snapshot VMware sesudah-update, tunggu 5 menit setelah boot, lalu di **PowerShell
sebagai Administrator**:

```powershell
powershell -ExecutionPolicy Bypass -File .\Get-SystemSnapshot.ps1 -Label before
```

File `TGOS-snapshot-before.json` muncul di Desktop. Skrip itu hanya membaca; tidak
mengubah apa pun. Kirim file itu: daftar layanan dan tugas terjadwal TGOS dicocokkan
dengan isinya sebelum rilis dibuat.

### Uji rilis

1. Kembalikan VM ke snapshot sesudah-update.
2. Ekstrak `TGOS-vX.Y.Z.7z` dengan password distribusi, buka AME Beta, seret
   `TGOS-vX.Y.Z.apbx`.
3. Biarkan semua opsi pada bawaannya. Jalankan sampai selesai, lalu restart.
4. Di Desktop buka **TGOS Toolbox**, klik dua kali **Collect TGOS Report**.
5. Kirim `TGOS-report.zip` yang muncul di Desktop.

Isi zip: laporan pemeriksaan tiap tweak, potret sistem, catatan instalasi, dan log AME
yang ditemukan. Tidak memuat nama komputer, nama pengguna, alamat jaringan, atau file
pribadi.

### Yang hanya bisa dilihat mata

Laporan otomatis tidak bisa menilai hal berikut. Cukup jawab ya/tidak:

- [ ] Login normal, tidak ada pesan error.
- [ ] Start menu terbuka; tidak ada ubin kosong bekas aplikasi yang dihapus.
- [ ] Mengetik "notepad" di Start menemukan Notepad.
- [ ] Settings terbuka.
- [ ] Wallpaper TGO terpasang dan mode gelap aktif.
- [ ] Microsoft Store bisa memasang satu aplikasi.
- [ ] Microsoft Store bisa memasang ulang satu aplikasi yang dihapus (mis. Sticky Notes).
- [ ] Suara keluar dan internet jalan.
- [ ] Windows Security menunjukkan Defender masih aktif.
- [ ] Restore point "Before TGOS" ada (*Create a restore point* > *System Restore*).
- [ ] Bila bisa: satu launcher atau game terpasang dan jalan.

### Opsional: Toolbox dan opsi non-bawaan

Hanya bila ingin menguji lebih jauh. Buat snapshot VMware dulu.

- **Defender.** Klik dua kali *Windows Defender - Turn OFF*. Skrip seharusnya berhenti
  dan meminta Tamper Protection dimatikan. Matikan di Windows Security, jalankan lagi,
  restart, lalu cek Windows Security. Setelah itu *Turn ON* dan cek lagi.
- **Opsi yang defaultnya mati:** *Remove Xbox app and Game Bar* (perhatikan popup
  `ms-gamebar` saat menekan Win+G) dan *Remove Microsoft Edge (experimental)*.

## Catatan hasil

### Fase 0 — kerangka `0.0.2`: lolos

| Tanggal | Penguji | Windows | AME Wizard | Hasil |
|---|---|---|---|---|
| 14 Nov 2026 | tehgeii | Windows 11 Pro, VMware | AME Beta | Lolos |

AME memuat `.apbx`; nama, pembuat, versi, dan ikon tampil benar (walau "Unverified");
`install-info.txt` terbuat; AME tidak meminta mematikan Defender. Deskripsi di Wizard
terpotong setelah sekitar 5 baris, jadi sejak itu deskripsi dipendekkan.

### `0.9.0`

| Lapis | Tanggal | Hasil | Catatan |
|---|---|---|---|
| 1. Uji bentuk | 16 Nov 2026 | Lolos | 68 pemeriksaan di `tools/selftest.py` |
| 2. Mesin AME | 16 Nov 2026 | Lolos di kelima job | Rincian di bawah |
| 3. VM pemilik | | Belum | Menunggu uji di Windows 11 Pro 26H2 |

Lapis 2, runner command-line AME versi 0.8.4:

| Runner | Opsi | Mesin AME | Pemeriksaan diri | Pemeriksaan CI |
|---|---|---|---|---|
| Windows Server 2025, build 26100, x64 | bawaan | selesai tanpa error | 126 PASS, 0 FAIL, 1 WARN, 19 SKIP | 34 dari 34 |
| Windows Server 2025, build 26100, x64 | semua | selesai tanpa error | 135 PASS, 0 FAIL, 1 WARN, 11 SKIP | 34 dari 34 |
| Windows 11 Enterprise 25H2, build 26200, ARM64 | bawaan | selesai tanpa error | 131 PASS, 0 FAIL, 0 WARN, 15 SKIP | 34 dari 34 |
| Windows 11 Enterprise 25H2, build 26200, ARM64 | semua | selesai tanpa error | 140 PASS, 0 FAIL, 0 WARN, 7 SKIP | 34 dari 34 |

Satu-satunya `WARN` adalah restore point di Windows Server, yang memang tidak mendukungnya.
`SKIP` berasal dari opsi yang tidak dipilih, layanan atau tugas yang tidak ada di build
runner, dan aksi khusus build di bawah 26100.

Yang terlihat di log mesin AME pada Windows 11 dengan semua opsi:

- Uji tolak: playbook berhenti di langkah pertama (runner Enterprise ARM64, bukan Pro x64).
- Restore point "Before TGOS 0.9.0" terbuat.
- Paket AppX: 106 menjadi 83; tidak ada paket yang dilindungi ikut hilang kecuali Edge,
  yang memang dipilih.
- Tugas terjadwal: 11 dinonaktifkan, 2 tidak ada di build itu, 0 gagal.
- OneDrive terhapus lewat uninstaller resminya; Edge terhapus, WebView2 dipertahankan.
- Power plan "TGOS Ultimate Performance" aktif; hibernasi mati.
- Proteksi real-time Defender aktif sebelum dan sesudah.
- Toolbox: *Defender OFF* ditolak karena Tamper Protection aktif, tanpa mengubah apa pun.
