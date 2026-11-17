# Pengujian TGOS

TGOS diuji di tiga lapis. Tujuannya: kesalahan tertangkap sebelum sampai ke VM, supaya
uji di VM cukup sekali per rilis.

| Lapis | Di mana | Yang dibuktikan | Yang TIDAK dibuktikan |
|---|---|---|---|
| 1. Uji bentuk | Linux, `python tools/selftest.py` | YAML dan `playbook.conf` sesuai format AME; aturan pengaman TGOS dipatuhi; file turunan tidak usang | Apa pun yang terjadi di Windows |
| 2. Mesin AME | GitHub Actions: Windows Server 2025 (x64) dan Windows 11 Enterprise 25H2 (ARM64) | Mesin AME yang asli menjalankan playbook tanpa error; setiap tweak benar-benar ada di sistem; aplikasi bawaan terhapus; restore point terbuat; software diunduh, diperiksa tanda tangannya, dan terpasang; Toolbox bolak-balik | Edisi Pro, build 26300, x64 asli, tampilan (Wizard, taskbar, Start), program Copilot, pasang ulang dari Store |
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
- `Set-ShellLayout.ps1 -GenerateOnly` harus menghasilkan layout taskbar (XML) dan pin
  Start (JSON) yang sah untuk empat keadaan: ada browser, hanya Edge, Edge dan Chrome,
  tanpa browser dan tanpa Store.
- `docs/TWEAKS.md` dan `expected-state.json` harus sama dengan hasil generatornya.

## Lapis 2 — mesin AME di GitHub Actions

Workflow `.github/workflows/test.yml` jalan otomatis di setiap push. Job `engine`
menjalankan `tools/ci/Test-Engine.ps1` di empat susunan: Windows Server dan Windows 11,
masing-masing dengan opsi bawaan dan dengan semua opsi dicentang. Browser yang dipilih
berbeda di tiap job, supaya Brave, Chrome, dan Firefox semuanya terpasang lewat mesin AME:

1. `tools/build.ps1` dijalankan di Windows PowerShell 5.1, lalu `.apbx` hasilnya
   diekstrak. Yang diuji adalah arsip yang sama dengan yang dikirim ke pengguna.
2. **Uji tolak.** Playbook apa adanya dijalankan lewat runner command-line AME
   (`TrustedUninstaller.CLI.exe`). Karena runner bukan Windows Pro x64, playbook harus
   berhenti di langkah pertama tanpa mengubah apa pun.
3. **Pengaman pemasang.** Unduhan yang sengaja digagalkan harus dilaporkan dan dicatat
   tanpa menjalankan apa pun; dan `Remove-Edge.ps1` harus mempertahankan Edge bila
   browser yang diminta tidak terpasang.
4. **Uji lolos.** Salinan sementara playbook dengan edisi dan arsitektur runner
   diizinkan harus selesai dengan "Playbook completed successfully." Tugas terjadwal di
   daftar diaktifkan dulu, supaya penonaktifannya benar-benar teruji.
5. **Software.** Browser yang dipilih dan 7-Zip harus ada sesudahnya. Image runner
   sudah berisi Chrome, Firefox, dan 7-Zip, jadi program itu juga diunduh dan dipasang
   ulang lewat skrip di Toolbox (`-Force`), supaya unduhan dan pemeriksaan tanda
   tangannya benar-benar teruji.
6. **Pemeriksaan diri.** `Test-TgosResult.ps1` tidak boleh melaporkan `FAIL`.
7. **Toolbox.** Tiap fitur dimatikan lalu dinyalakan lagi, dan nilai registrinya dicek.
   Di Windows 11, *Defender OFF* harus **ditolak** selama Tamper Protection aktif.
8. **Pengumpul laporan** harus menghasilkan `TGOS-report.zip` yang lengkap.

Yang dibuktikan runner Windows 11 dan tidak bisa dibuktikan Windows Server: aplikasi
bawaan benar-benar terhapus lewat aksi `!appx`, restore point bisa dibuat dari dalam
playbook, Defender tidak mengganggu dan tetap aktif sesudahnya, dan tidak ada nilai
registry yang ditolak Windows.

Batas lapis ini:

- Runner Windows 11 adalah edisi **Enterprise**, build **26200**, **ARM64**. Target TGOS
  adalah Pro, sampai build 26300, x64. Isi bawaan Pro bisa berbeda (mis. OneDrive).
- Pengukuran proses dan RAM di CI tidak berarti: diambil tanpa restart, saat skrip uji
  masih berjalan.
- Tidak ada yang melihat layar: Wizard, Start, taskbar, wallpaper tidak dinilai.
- Runner tidak punya program Copilot versi 26H2, dan tidak punya daftar pin taskbar
  tersimpan (`Taskband`), jadi penghapusan Copilot dan reset pin taskbar tidak teruji.
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
3. Biarkan semua opsi pada bawaannya (atau centang semua, bila ingin menguji semuanya).
   VM harus tersambung internet. Jalankan sampai selesai, lalu restart.
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
- [ ] Wallpaper TGO terpasang dan mode gelap aktif (setelah restart). Gradasinya halus,
      tanpa garis-garis melingkar.
- [ ] Di Wizard tidak ada teks yang terpotong dengan "...": deskripsi playbook, teks
      kecil di kiri, deskripsi tiap halaman opsi, dan status saat instalasi.
- [ ] Selama instalasi tidak muncul jendela "Yes/No" (UAC) untuk Microsoft OneDrive.
- [ ] Halaman browser di Wizard tampil benar: tiga kotak bergambar (B, C, F) dan None.
- [ ] Taskbar: tidak ada kotak abu-abu; pencarian berupa ikon; tombol Task View tidak
      ada; yang tersisa Start, Search, File Explorer, browser pilihan, Store.
- [ ] Start menu: pin berisi File Explorer, Settings, Store, browser, Notepad,
      Calculator, Terminal; tidak ada WhatsApp/Adobe Express/LinkedIn; tidak ada bagian
      Recent.
- [ ] Settings > Apps > Installed apps: tidak ada "Copilot".
- [ ] Browser pilihan terbuka dan bisa membuka satu situs.
- [ ] Setelah instalasi selesai (sebelum restart) desktop dan taskbar tetap ada.
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
  `ms-gamebar` saat menekan Win+G), *Remove Microsoft Edge*, *Remove Microsoft Store*
  (lalu coba *Reinstall Microsoft Store* di Toolbox), *Trim extra services*, dan
  *Taskbar icons on the left*.

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
| 3. VM pemilik | 16 Nov 2026 | 139 PASS, 1 FAIL, 7 SKIP | Windows 11 Pro 26H2; rincian di bawah |

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

Lapis 3, uji pemilik: Windows 11 Pro 26H2 build 26300.9974 di VMware, AME Beta 0.8.4,
**semua opsi dicentang**. Angka dari `TGOS-snapshot-before.json` dan `TGOS-report.zip`:

| | Sebelum | Sesudah | Target `PLAN.md` |
|---|---|---|---|
| Proses | 149 | 122 (−18%) | −35%, belum tercapai |
| RAM terpakai | 3.345 MB | 2.352 MB (−30%) | −30%, tercapai |
| Layanan berjalan | 97 | 82 (−15%) | −30%, belum tercapai |
| Disk terpakai | 30,0 GB | 24,7 GB | tanpa target |
| Paket AppX | 108 | 84 | |

Potret "sesudah" diambil sekitar 2,5 menit setelah boot, bukan 5 menit, jadi angka
proses dan RAM-nya indikatif.

- Restore point terbuat; Defender tetap aktif dan terlindung Tamper Protection.
- 11 tugas terjadwal dinonaktifkan, 2 tidak ada di build itu.
- **Satu FAIL: Edge masih terpasang.** Uninstaller Edge keluar dengan kode 93.
- OneDrive terhapus, tetapi uninstaller-nya menampilkan prompt UAC dan menunggu jawaban.
- 57 baris error di log AME: file Widgets masih terkunci saat paketnya dihapus.
- Yang terlihat mata: beberapa teks Wizard terpotong; taskbar menyisakan kotak abu-abu
  (pin Copilot yang aplikasinya sudah dihapus); wallpaper bergaris; wallpaper dan mode
  gelap baru tampil setelah restart (memang begitu cara kerjanya).

Semua temuan itu ditangani di `0.9.1`.

### `0.9.1`

| Lapis | Tanggal | Hasil | Catatan |
|---|---|---|---|
| 1. Uji bentuk | 16 Nov 2026 | Lolos | 75 pemeriksaan di `tools/selftest.py` |
| 2. Mesin AME | 16 Nov 2026 | Lolos di kelima job | Rincian di bawah |
| 3. VM pemilik | | Belum | Menunggu uji ulang di Windows 11 Pro 26H2 |

Lapis 2, runner command-line AME versi 0.8.4:

| Runner | Opsi | Mesin AME | Pemeriksaan diri | Pemeriksaan CI |
|---|---|---|---|---|
| Windows Server 2025, build 26100, x64 | bawaan | selesai tanpa error | 142 PASS, 0 FAIL, 1 WARN, 26 SKIP | 34 dari 34 |
| Windows Server 2025, build 26100, x64 | semua | selesai tanpa error | 151 PASS, 0 FAIL, 1 WARN, 18 SKIP | 34 dari 34 |
| Windows 11 Enterprise 25H2, build 26200, ARM64 | bawaan | selesai tanpa error | 153 PASS, 0 FAIL, 0 WARN, 16 SKIP | 34 dari 34 |
| Windows 11 Enterprise 25H2, build 26200, ARM64 | semua | selesai tanpa error | 162 PASS, 0 FAIL, 0 WARN, 8 SKIP | 34 dari 34 |

Yang terlihat di log mesin AME pada Windows 11 dengan semua opsi:

- Tugas terjadwal: 22 dinonaktifkan, 3 tidak ada di build itu, 0 gagal.
- OneDrive terhapus dengan `runas: currentUserElevated`.
- Edge terhapus pada cara 1 (kode keluar 0); cara 2 tidak sampai dijalankan.
- `TaskbarLayout.xml` tersalin ke `C:\ProgramData\TGOS`; policy layout dan dua nilai
  taskbar (`SearchboxTaskbarMode`, `ShowTaskViewButton`) terbaca benar sesudahnya.
- Satu peringatan `UnauthorizedAccessException` dari mesin AME: Windows menolak satu
  penulisan registry langsung, lalu mesin AME mengulanginya dengan cara cadangannya
  sendiri. Nilai akhirnya benar (0 FAIL). Paling mungkin itu salah satu dari dua nilai
  taskbar, yang dilindungi Windows; log tidak menyebut nilainya.
- Empat pasang baris `Could not get app executable file location data` dari mesin AME
  saat menghapus paket AppX. Sudah ada sejak `0.9.0` dan tidak memengaruhi hasil.
- Paket AppX: 106 menjadi 83. Proteksi real-time Defender aktif sebelum dan sesudah.

Angka proses dan RAM di runner uji naik, bukan turun: potret "sesudah" diambil saat
runner masih sibuk tepat setelah instalasi, tanpa restart. Angka itu tidak dipakai untuk
menilai performa; yang dipakai adalah ukuran di VM.

Yang **tidak** bisa dibuktikan uji otomatis, jadi baru terlihat di uji ulang VM:

- Teks Wizard tidak terpotong. Batas panjang di validator adalah perkiraan dari
  screenshot `0.9.0`; runner uji tidak menampilkan Wizard.
- Prompt OneDrive tidak muncul. Runner uji berjalan tanpa UAC interaktif.
- Tampilan taskbar. Uji otomatis hanya membuktikan policy dan nilainya tertulis.
- Edge di edisi Pro. Di runner (Enterprise) Edge terhapus pada cara pertama, jadi cara
  kedua dan penolakan kode 93 tidak pernah terjadi di sana.
- Wallpaper tampil halus di layar.

Lapis 3, uji pemilik `0.9.1`: Windows 11 Pro 26H2 build 26300.9974 di VMware, AME Beta
0.8.4, semua opsi dicentang. Pemeriksaan diri **163 PASS, 0 FAIL, 7 SKIP**.

| | Sebelum | Sesudah | Target `PLAN.md` |
|---|---|---|---|
| Proses | 149 | 120 (−19%) | −35%, tidak tercapai |
| RAM terpakai | 3.345 MB | 2.285 MB (−32%) | −30%, tercapai |
| Layanan berjalan | 97 | 84 (−13%) | −30%, tidak tercapai |
| Disk terpakai | 30,0 GB | 24,5 GB | tanpa target |
| Paket AppX | 108 | 83 | |

Yang terbukti beres: Edge terhapus di edisi Pro (cara 1, kode keluar 19); OneDrive
terhapus dalam 10 detik tanpa prompt; teks Wizard tidak terpotong; wallpaper halus;
23 tugas terjadwal dinonaktifkan.

Yang masih salah, dan penyebabnya (dari log dan `TGOS-diag.txt`):

- **"Copilot" masih ada di Installed apps (1,72 GB).** Paket Store `Microsoft.Copilot`
  tidak pernah ada di Windows itu; Copilot adalah program biasa dengan uninstaller
  sendiri. TGOS hanya menghapus paket `Microsoft.MicrosoftOfficeHub`, yang ternyata
  identitas aplikasinya.
- **Kotak abu-abu di taskbar tetap ada.** Itu pin Copilot yang identitasnya terhapus.
  Policy layout taskbar tidak membuang pin yang sudah tersimpan di profil.
- **Start menu masih berisi ubin promosi** (WhatsApp, Adobe Express, LinkedIn).
- 33 baris error di log AME: folder data Widgets terkunci saat paketnya dihapus.

Semuanya ditangani di `1.0.0`.

### `1.0.0`

| Lapis | Tanggal | Hasil | Catatan |
|---|---|---|---|
| 1. Uji bentuk | 17 Nov 2026 | Lolos | 86 pemeriksaan di `tools/selftest.py` |
| 2. Mesin AME | 17 Nov 2026 | @@LAPIS2@@ | Rincian di bawah |
| 3. VM pemilik | | Belum | Menunggu uji ulang di Windows 11 Pro 26H2 |
| Hardware asli | | Belum | Benchmark dan anti-cheat belum diuji |

@@HASIL@@
