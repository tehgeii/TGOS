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
   daftar diaktifkan dulu, supaya penonaktifannya benar-benar teruji. Image runner sudah
   berisi Chrome, Firefox, dan 7-Zip; browser yang dipilih job itu dan 7-Zip **dicopot
   dulu**, supaya pemasangannya oleh playbook (sebagai sistem) benar-benar teruji.
5. **Software.** Browser yang dipilih dan 7-Zip harus terpasang di Program Files
   sesudahnya. Lalu beberapa program dipasang ulang lewat skrip di Toolbox (`-Force`):
   unduhan, tanda tangan atau checksum, dan installer-nya harus benar-benar jalan, dan
   versi program tidak boleh turun.
6. **Pemeriksaan diri.** `Test-TgosResult.ps1` tidak boleh melaporkan `FAIL`.
7. **Toolbox.** Tiap fitur dimatikan lalu dinyalakan lagi, dan nilai registrinya dicek.
   Di Windows 11, *Defender OFF* harus **ditolak** selama Tamper Protection aktif.
8. **Pengumpul laporan** harus menghasilkan `TGOS-report.zip` yang lengkap.
9. **Pasang ulang Microsoft Store** (job Windows 11 semua opsi, hanya informasi):
   `wsreset -i` dijalankan, lalu ditunggu sampai 5 menit apakah Store kembali.

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
- [ ] Selama instalasi tidak muncul jendela installer apa pun (mis. "Installing
      Microsoft DirectX"); semua berjalan di latar belakang.
- [ ] Halaman browser di Wizard tampil benar: logo asli Brave, Chrome, Firefox di atas
      kotak gelap, dan None.
- [ ] Ikon TGOS Toolbox di Desktop berada di deretan ikon kiri, bukan di tengah.
- [ ] Settings > Windows Update menampilkan "Updates paused until ..." (pilihan Pause),
      dan masih begitu setelah restart. Tombol "Resume updates" ada.
- [ ] Windows Security > Virus & threat protection > Protection updates > "Check for
      updates" tetap bisa memperbarui definisi saat update Windows di-pause.
- [ ] Settings > Gaming > Game Bar: kedua toggle (controller dan View + Menu) Off; Win+G
      tidak memunculkan jendela apa pun, juga setelah restart (opsi Xbox). Satu game
      dijalankan: tidak ada jendela "Pick an app" / "ms-gamingoverlay".
- [ ] Gambar layar kunci dan latar layar login bertema TGO.
- [ ] Bila "Skip the lock screen" dicentang: setelah restart langsung ke kotak
      password/PIN.
- [ ] Klik kanan aplikasi di taskbar: ada "End task".
- [ ] Launcher dan aplikasi yang dicentang terpasang dan terbuka normal; tidak ada
      jendelanya yang muncul selama instalasi.
- [ ] `%ProgramData%\TGOS\deep-clean.txt` berisi ruang yang dibebaskan.
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
- **Opsi yang defaultnya mati:** *Remove Xbox app and turn Game Bar off* (Win+G tidak
  memunculkan apa pun; *Xbox Game Bar - Turn ON* di Toolbox mengembalikan Win+G setelah
  sign out/in), *Remove Microsoft Edge*, *Remove Microsoft Store*
  (lalu coba *Reinstall Microsoft Store* di Toolbox; tidak dijamin berhasil, jadi buat
  snapshot VMware dulu), *Trim extra services*, dan
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
| 1. Uji bentuk | 17 Nov 2026 | Lolos | 91 pemeriksaan di `tools/selftest.py`; revisi kedua 97, revisi keempat 100, revisi kelima 101 |
| 2. Mesin AME | 17 Nov 2026 | Lolos di kelima job | Rincian di bawah |
| 2. Mesin AME, revisi kedua | 17 Nov 2026 | Lolos di kelima job | Rincian di akhir bagian ini |
| 3. VM pemilik, build pertama | 17 Nov 2026 | 225 PASS, 1 FAIL; setelah restart 224 PASS, 2 FAIL | Rincian di bawah; dua FAIL itu diperbaiki di revisi |
| 3. VM pemilik, revisi pertama | 17 Nov 2026 | Setelah restart 226 PASS, 0 FAIL, 0 WARN | Rincian di bawah |
| 3. VM pemilik, revisi kedua | 16-18 Nov 2026 | Setelah restart 283 PASS, 1 FAIL, 2 WARN | Rincian di akhir bagian ini; FAIL dan WARN diperbaiki di revisi ketiga |
| 2. Mesin AME, revisi ketiga | 18 Nov 2026 | Lolos di kelima job | Rincian di akhir bagian ini |
| 3. VM pemilik, revisi ketiga | 16-18 Nov 2026 | Setelah restart 277 PASS, 1 FAIL, 2 WARN | Rincian di akhir bagian ini; jendela cmd, FAIL, dan WARN diperbaiki di revisi keempat |
| 2. Mesin AME, revisi keempat | 18 Nov 2026 | Lolos di kelima job | Rincian di akhir bagian ini |
| 3. VM pemilik, revisi keempat | 18 Nov 2026 | Setelah restart 284 PASS, 1 FAIL, 2 WARN | Rincian di akhir bagian ini; FAIL dan pintasan yang hilang diperbaiki di revisi kelima |
| 2. Mesin AME, revisi kelima | 18 Nov 2026 | Lolos di kelima job | Rincian di akhir bagian ini |
| 3. VM pemilik, revisi kelima | | Belum | Pemilik akan menguji di PC asli |
| Hardware asli | | Belum | Benchmark dan anti-cheat belum diuji |

Lapis 2, runner command-line AME versi 0.8.4 (run terakhir sebelum rilis):

| Runner | Opsi, browser | Pemeriksaan diri | Pemeriksaan CI |
|---|---|---|---|
| Windows Server 2025, build 26100, x64 | bawaan, Brave | 188 PASS, 0 FAIL, 1 WARN, 43 SKIP | 51 dari 51 |
| Windows Server 2025, build 26100, x64 | semua, Chrome | 214 PASS, 0 FAIL, 1 WARN, 18 SKIP | 53 dari 53 |
| Windows 11 Enterprise 25H2, build 26200, ARM64 | bawaan, Brave | 198 PASS, 0 FAIL, 0 WARN, 34 SKIP | 50 dari 50 |
| Windows 11 Enterprise 25H2, build 26200, ARM64 | semua, Firefox | 224 PASS, 0 FAIL, 0 WARN, 9 SKIP | 49 dari 49 |

`WARN` di Server adalah restore point, yang memang tidak didukung Windows Server.

Yang terlihat di log:

- **Revisi setelah uji VM.** DirectX dipasang playbook sendiri (lewat mesin AME) dari
  paket lengkap di kedua job Server: SHA256 cocok dengan checksum yang dikunci,
  `DXSETUP.exe` bertanda tangan Microsoft dan keluar dengan kode 0. Selama pemasangan
  DirectX, pemantau jendela **tidak melihat jendela DirectX apa pun**, dan kontrolnya
  (jendela Notepad) terdeteksi, jadi pemantaunya terbukti bekerja. Satu run sebelumnya,
  saat masih memakai `/Q` saja, pemantau yang sama menangkap jendela progres
  pengekstrak "DirectX June 2010 SDK"; itu sebabnya sekarang `/Q:A`.
- DiagTrack berjalan sebelum playbook dan dihentikan playbook di keempat job; nilai
  `Start` kedua perekam telemetri tetap 0 sesudahnya.
- Reset pin menghapus 1-2 pintasan pin lama di job Server; Explorer hidup lagi sebelum
  pintasan TGOS Toolbox dibuat.
- **Software dipasang oleh playbook sendiri** (sebagai sistem, lewat mesin AME): Brave
  157.1.99.57 di `C:\Program Files\BraveSoftware` (dua job), Chrome 157.0.8103.79 dan
  Firefox 160.0 setelah versi bawaan runner dicopot, 7-Zip 26.06 di keempat job
  (checksum cocok dengan manifest winget), DirectX di Server x64. Di ARM64 DirectX
  dilewati dengan pesan jelas.
- Pemasangan ulang lewat Toolbox (VC++, 7-Zip, Chrome, Firefox, DirectX) berhasil, dan
  versi tidak pernah turun.
- Pin taskbar: satu browser, yaitu yang dipilih (`Brave.lnk`, `Google Chrome.lnk`,
  `Firefox.lnk`), ditemukan dari target pintasannya. Explorer dijalankan lagi.
- Store terhapus pada opsi *Remove Microsoft Store*; Edge terhapus pada opsi Edge karena
  browser pilihan sudah terpasang.
- Toolbox: semua tombol ON/OFF lolos bolak-balik, termasuk core parking, layanan ekstra,
  dan pengumpul telemetri. *Defender OFF* ditolak di Windows 11 selama Tamper
  Protection aktif.
- **Pasang ulang Microsoft Store tidak berhasil di runner:** `wsreset -i` keluar dengan
  kode 0, tetapi Store tidak kembali dalam 5 menit. Karena itu opsinya diberi label
  *hard to undo* di Wizard, dan Toolbox menyebut bahwa itu tidak dijamin.

Masalah yang ditemukan uji ini sebelum rilis, dan sudah diperbaiki: Brave terpasang ke
profil SYSTEM (installer per pengguna), 7-Zip turun ke versi 23.01 (tautan pertama di
7-zip.org), tombol *Extra Services* gagal (nama variabel bentrok dengan parameter, lalu
kunci registry layanan yang ditolak untuk Administrator), nilai core parking tidak
terbaca (pengaturan tersembunyi), aturan versi salah untuk installer Firefox, dan
DirectX di ARM64.

Lapis 3, uji pemilik build pertama `1.0.0`: Windows 11 Pro 26H2 build 26300.9974 di
VMware, AME Beta 0.8.4, semua opsi dicentang, browser Chrome.

| | Sebelum | Sesudah | Target `PLAN.md` |
|---|---|---|---|
| Proses | 149 | 113 (−24%) | −35%, tidak tercapai |
| Thread | 1.931 | 1.172 (−39%) | tanpa target |
| RAM terpakai | 3.345 MB | 2.165 MB (−35%) | −30%, tercapai |
| Layanan berjalan | 97 | 77 (−21%) | −30%, tidak tercapai |
| Disk terpakai | 30,0 GB | 24,2 GB | tanpa target |
| Paket AppX | 108 | 80 | |

Yang terbukti beres di VM: program Copilot terhapus (uninstaller-nya keluar 20, tidak
ada lagi di Installed apps); kotak abu-abu di taskbar hilang; Start berisi File Explorer,
Settings, Google Chrome, Notepad, Calculator, Terminal, tanpa ubin promosi dan tanpa
Recent; Edge terhapus (kode keluar 19) karena Chrome terpasang; Chrome dipasang playbook;
Defender tetap aktif dengan Tamper Protection.

Yang masih salah, dan penyebabnya (dari log dan screenshot):

- **Jendela "Installing Microsoft DirectX" muncul** di tengah instalasi, lalu macet;
  TGOS menghentikannya setelah 15 menit dan DirectX tidak terpasang (FAIL). Installer web
  `dxwebsetup.exe` tetap menampilkan jendelanya walaupun diberi `/Q`. Instalasi jadi
  makan sekitar 30 menit.
- **Nilai `Start` perekam `AutoLogger-Diagtrack-Listener` hilang setelah restart**
  (FAIL kedua; saat instalasi masih PASS). DiagTrack masih berjalan selama instalasi dan
  menulis ulang konfigurasi perekamnya saat dimatikan ketika shutdown.
- Ikon TGOS Toolbox muncul di tengah Desktop: pintasannya dibuat sebelum Explorer
  dihentikan untuk reset pin.
- Ada `File Explorer (2).lnk` ganda di folder pin taskbar (tidak terlihat di taskbar).
- Ikon halaman browser berupa huruf; pemilik meminta logo asli.

Catatan: entri "Microsoft Windows Application Compatibility Fix Database" di Installed
apps bukan dari TGOS.

Semuanya ditangani di revisi `1.0.0` (lihat CHANGELOG).

Yang **tidak** bisa dibuktikan uji otomatis, jadi baru terlihat di uji ulang VM:

- Logo browser tampil benar di Wizard.
- Tidak ada jendela installer yang muncul selama instalasi di Windows 11 Pro.
- Nilai perekam telemetri bertahan setelah restart (uji otomatis tidak bisa restart).
- Ikon TGOS Toolbox tidak di tengah Desktop, dan tidak ada pintasan pin ganda.

Lapis 3, uji pemilik revisi pertama `1.0.0`: Windows 11 Pro 26H2 build 26300.9974 di
VMware, AME Beta 0.8.4, semua opsi, browser Brave. Instalasi sekitar 10 menit (build
pertama sekitar 30 menit). Setelah restart: **226 PASS, 0 FAIL, 0 WARN, 7 SKIP**.

| | Sebelum | Sesudah |
|---|---|---|
| Proses | 149 | 111 (−25%) |
| Thread | 1.931 | 1.225 (−37%) |
| RAM terpakai | 3.345 MB | 2.181 MB (−35%) |
| Layanan berjalan | 97 | 76 (−22%) |
| Disk terpakai | 30,0 GB | 24,9 GB |
| Paket AppX | 108 | 80 |

Terbukti beres di VM: DirectX terpasang tanpa jendela (checksum terkunci cocok); nilai
perekam telemetri bertahan setelah restart; ikon TGOS Toolbox di deretan kiri; satu
pintasan pin lama terhapus; Copilot dan Edge terhapus; restore point dibuat; Defender
aktif dengan Tamper Protection.

Masukan pemilik untuk revisi kedua: opsi Pause Windows update; Game Bar masih aktif di
Settings > Gaming (toggle controller dan View + Menu) walaupun aplikasinya dihapus; ide
tambahan. Sisa kecil yang dicatat apa adanya: "Click to Do" dan "Get Started" masih di All
apps (komponen sistem); baris error Widgets di log AME adalah upaya mesin AME sendiri pada
file terkunci, dan skrip TGOS sesudahnya tidak menemukan sisa folder.

Lapis 2, revisi kedua (runner command-line AME versi 0.8.4, run terakhir sebelum rilis):

| Runner | Opsi, browser | Pemeriksaan diri | Pemeriksaan CI |
|---|---|---|---|
| Windows Server 2025, build 26100, x64 | bawaan, Brave | 212 PASS, 0 FAIL, 1 WARN, 73 SKIP | 74 dari 74 |
| Windows Server 2025, build 26100, x64 | semua, Chrome | 273 PASS, 0 FAIL, 1 WARN, 19 SKIP | 85 dari 85 |
| Windows 11 Enterprise 25H2, build 26200, ARM64 | bawaan, Brave | 209 PASS, 0 FAIL, 0 WARN, 77 SKIP | 73 dari 73 |
| Windows 11 Enterprise 25H2, build 26200, ARM64 | semua, Firefox | 263 PASS, 0 FAIL, 0 WARN, 30 SKIP | 75 dari 75 |

`WARN` di Server tetap restore point (tidak didukung Windows Server). Yang terbukti:

- **Pause update**: nilai pause tertulis (sampai 2036) dan Windows 11 sendiri mencatat
  `PausedFeatureStatus = 1` dan `PausedQualityStatus = 1`. Definisi Defender tetap bisa
  diperbarui saat pause (`MpCmdRun -SignatureUpdate` keluar 0).
- **Launcher dan aplikasi** (Server x64): Steam, Epic Games Launcher, EA app, Ubisoft
  Connect terpasang untuk semua pengguna; Discord dan Spotify terpasang di profil pengguna
  yang login. Semua bertanda tangan penerbitnya. Di runner ARM64 dilewati (TGOS x64 saja).
- **Runtime**: Visual C++ 2005-2013 dan XNA 4.0 (x64), DirectX dari paket lengkap,
  .NET Framework 3.5 lewat DISM (juga di ARM64; sekitar 6 menit), .NET Desktop Runtime 10.
- **Tanpa jendela**: pemantau jendela tidak menangkap satu pun jendela dari TGOS selama
  seluruh playbook di keempat job (kontrol Notepad terdeteksi). Satu-satunya jendela di
  runner Windows 11 adalah updater WSL milik image runner (`wsl.exe --update`, sudah
  berjalan sebelum playbook); TGOS sendiri tidak pernah menjalankan WSL (dijaga validator).
- **Deep clean**: sekitar 6 GB dibebaskan di Windows 11, hampir semuanya dari Reserved
  Storage; Deep clean+ menjalankan ResetBase; folder playbook yang sedang berjalan tidak
  tersentuh.
- **Toolbox**: semua fitur baru bolak-balik ON/OFF; tombol `.cmd` di subfolder bekerja;
  menu *Install Software* memasang 7-Zip, keluar dengan 0, dan menolak ketikan aneh
  (tanda kutip, `&`) tanpa error.
- **Game Bar**: blok Win+G tertulis (`DisabledHotkeys` berisi `G`) dan diperiksa
  pemeriksaan diri. Efeknya **tidak bisa dibuktikan di runner**: bahkan tanpa blok, Win+G
  yang dikirim uji tidak memunculkan jendela apa pun di runner, jadi hasil itu tidak
  dihitung. Bukti akhirnya di VM (checklist di atas).
- **.NET Native di Server dengan *Remove Microsoft Store***: Windows kadang langsung
  membuang .NET Native 2.2 karena Store adalah pemakai terakhirnya. Perbandingan potret
  sekarang membedakan ini (framework tanpa pemakai) dari framework yang hilang padahal
  masih dipakai.

Lapis 3, uji pemilik revisi kedua: Windows 11 Pro 26H2 build 26300.9974 di VMware, AME
Beta 0.8.4, semua opsi, Firefox, semua launcher dan aplikasi. Instalasi 78 menit, hampir
seluruhnya unduhan (sekitar 1 GB pada 0,5-1 MB/s) ditambah installer EA sekitar 10 menit.
Setelah restart **283 PASS, 1 FAIL, 2 WARN, 8 SKIP**.

| | Sesudah restart | Revisi pertama |
|---|---|---|
| Proses | 118 | 111 |
| Thread | 1.250 | 1.225 |
| RAM terpakai | 2.252 MB | 2.181 MB |
| Layanan berjalan | 82 | 76 |
| Disk terpakai | 27,0 GB | 24,9 GB |

Terbukti di VM: "Updates paused until 11/13/2036" dengan tombol Resume; kedua toggle Game
Bar Off dan Win+G diblokir; layar kunci terlewati langsung ke sign-in; Steam, Epic, EA app,
Ubisoft Connect, Discord, Spotify, VC++ 2005-2022, XNA, DirectX, dan .NET Desktop Runtime 10
terpasang; layanan launcher semuanya Manual.

Masalah, dengan penyebabnya:

- **FAIL .NET Framework 3.5**: DISM `0x8024001E` (layanan Windows Update sedang berhenti),
  tanpa percobaan ulang.
- **WARN Reserved Storage**: DISM `0x800F0975` (cadangan sedang dipakai operasi servicing),
  sehingga Deep clean+ hanya membebaskan 1,26 GB.
- **Jendela terminal kosong di akhir instalasi** (screenshot pukul 13:45: empat jendela
  bertumpuk, Windows Terminal aktif di taskbar, status AME "Reticulating splines...").
  Bukan dari langkah TGOS menurut uji otomatis revisi ketiga (lihat di bawah); penyebab pasti
  di VM belum diketahui.

Lapis 2, revisi ketiga (runner command-line AME versi 0.8.4, run terakhir sebelum rilis):

| Runner | Opsi, browser | Pemeriksaan diri | Pemeriksaan CI |
|---|---|---|---|
| Windows Server 2025, build 26100, x64 | bawaan, Brave | 213 PASS, 0 FAIL, 1 WARN, 73 SKIP | 79 dari 79 |
| Windows Server 2025, build 26100, x64 | semua, Chrome | 274 PASS, 0 FAIL, 1 WARN, 19 SKIP | 90 dari 90 |
| Windows 11 Enterprise 25H2, build 26200, ARM64 | bawaan, Brave | 210 PASS, 0 FAIL, 0 WARN, 77 SKIP | 79 dari 79 |
| Windows 11 Enterprise 25H2, build 26200, ARM64 | semua, Firefox | 264 PASS, 0 FAIL, 0 WARN, 30 SKIP | 80 dari 80 |

`WARN` di Server tetap restore point. Yang terbukti:

- **Seperti AME Wizard**: mesin AME dijalankan tanpa konsol (`DETACHED_PROCESS`), dengan
  Windows Terminal 1.24 sebagai terminal bawaan di runner Windows 11. Pemantau jendela tidak
  melihat satu pun jendela dari TGOS. Jejak proses mencatat sekitar 110 konsol selama
  playbook, semuanya tanpa jendela: PowerShell tiap langkah TGOS (44), `ame-assassin.exe`
  milik AME (31), ngen/DISM/servicing Windows, dan updater WSL milik runner. Kontrol: konsol
  tersembunyi dengan Windows Terminal maupun Console Host sebagai bawaan tetap tersembunyi,
  jadi jendela kosong di VM pemilik **tidak bisa dibuat ulang** di runner.
- **Terminal bawaan** disetel ke Console Host selama playbook dan kembali persis ke Windows
  Terminal sesudahnya; catatannya terhapus; pemeriksaan diri memeriksanya.
- **.NET Framework 3.5**: dicopot sampai payload-nya hilang
  (`DisabledWithPayloadRemoved`), lalu dipasang lagi lewat Toolbox saat update di-pause:
  berhasil dalam 188-221 detik. Jalur percobaan ulang (DISM gagal sekali) tidak terjadi di
  runner, jadi belum teruji langsung.
- **Reserved Storage**: tugas `\TGOS\Reserved Storage Off` terdaftar (SYSTEM, saat
  startup, tersembunyi) dan menghapus dirinya sendiri setelah berhasil, di keempat job.
  Kondisi "sedang dipakai" seperti di VM tidak bisa dibuat di runner.

Lapis 3, uji pemilik revisi ketiga: Windows 11 Pro 26H2 build 26300.9974 di VMware, AME
Beta 0.8.4, hampir semua opsi (tanpa browser dengan Edge dihapus, tanpa launcher dan
aplikasi, Deep clean+, Pause). Setelah restart **277 PASS, 1 FAIL, 2 WARN, 8 SKIP**.

| | Sesudah restart | Revisi kedua |
|---|---|---|
| Proses | 117 | 118 |
| Thread | 1.386 | 1.250 |
| RAM terpakai | 2.219 MB | 2.252 MB |
| Layanan berjalan | 82 | 82 |
| Disk terpakai | 23,3 GB | 27,0 GB |

Terbukti di VM: terminal bawaan kembali ke "Let Windows decide" sesudah instalasi; Start
berisi set TGOS; Installed apps hanya program yang dipilih (7-Zip, VC++, XNA, .NET Desktop
Runtime) ditambah aplikasi sistem.

Masalah, dengan penyebabnya:

- **Jendela cmd muncul lalu hilang di akhir instalasi** (screenshot 13:00 waktu VM = 06:00
  UTC): `rd /s` pada `AppData\Local\Microsoft\OneDrive\ListSync\...` gagal karena file
  masih dipakai. Waktunya tepat saat TGOS menyalakan ulang Explorer (06:00:08 dan 06:00:13);
  uninstaller OneDrive berjalan 05:49:48-05:50:00. Penyebab: TGOS hanya menghentikan
  `OneDrive.exe`, sementara `Microsoft.SharePoint.exe` masih mengunci file ListSync, dan
  uninstaller meninggalkan perintah bersih-bersih yang dijalankan Explorer. Pengaturan
  terminal sementara revisi ketiga bukan penyebabnya (jendela kini tampil sebagai Console
  Host biasa).
- **FAIL .NET Framework 3.5**: DISM `0x8024001E` dua kali, juga sesudah layanan Windows
  Update dijalankan ulang (`dism.log`: "DISM Package Manager processed the command line but
  failed. HRESULT=8024001E").
- **WARN Reserved Storage**: saat instalasi sedang dipakai (`0x800F0975`). Tugas startup
  berjalan setelah restart, tetapi TGOS keliru membaca pesan "not supported when reserved
  storage is in use" sebagai "tidak didukung" dan menghapus tugasnya (`toolbox.log`:
  "ReservedStorage Off: not supported").
- Permintaan pemilik: teks pilihan di Wizard tanpa titik koma.

Lapis 2, revisi keempat (runner command-line AME versi 0.8.4, run terakhir sebelum rilis):

| Runner | Opsi, browser | Pemeriksaan diri | Pemeriksaan CI |
|---|---|---|---|
| Windows Server 2025, build 26100, x64 | bawaan, Brave | 213 PASS, 0 FAIL, 1 WARN, 73 SKIP | 85 dari 85 |
| Windows Server 2025, build 26100, x64 | semua, Chrome | 274 PASS, 0 FAIL, 1 WARN, 19 SKIP | 96 dari 96 |
| Windows 11 Enterprise 25H2, build 26200, ARM64 | bawaan, Brave | 210 PASS, 0 FAIL, 0 WARN, 77 SKIP | 85 dari 85 |
| Windows 11 Enterprise 25H2, build 26200, ARM64 | semua, Firefox | 264 PASS, 0 FAIL, 0 WARN, 30 SKIP | 86 dari 86 |

`WARN` di Server tetap restore point. Yang terbukti:

- **Penyebab jendela cmd terbukti**: di runner Windows 11, OneDrive dipasang dan dijalankan
  dulu untuk akun uji (seperti PC baru; folder ListSync ada). `Remove-OneDrive.ps1`
  menghentikan OneDrive, uninstaller keluar 0, lalu menemukan dan menghapus **tiga perintah
  sisa uninstaller di RunOnce** pengguna: `Delete Cached Update Binary`, `Delete Cached
  Standalone Update Binary` (`cmd.exe /q /c del /q ...`), dan `Uninstall 26.212.1029.0006`
  (`cmd.exe /q /c rmdir /s /q "...\AppData\Local\Microsoft\OneDrive..."`), persis isi
  jendela di screenshot pemilik. Sebagian file aplikasi OneDrive masih terkunci dan
  dijadwalkan dihapus Windows saat restart. Selama playbook, Explorer tidak menjalankan satu
  pun `cmd.exe` (29-30 cmd.exe, semuanya dari PowerShell langkah TGOS), RunOnce bersih, tidak
  ada proses OneDrive tersisa, dan pemantau jendela tidak melihat jendela.
- Kontrol: di Server, entri RunOnce buatan memang dijalankan Explorer saat dinyalakan ulang
  (mekanisme yang sama dengan pop up di VM). Di runner Windows 11 kontrol itu tidak memicu
  apa pun, jadi buktinya di sana adalah entri yang sudah dihapus sebelum Explorer dinyalakan
  ulang. Di Server tidak ada `OneDriveSetup.exe`.
- **Langkah setelah restart**: tugas `\TGOS\Finish after restart` terdaftar (SYSTEM, startup
  + 3 menit, tersembunyi), dijalankan lewat Task Scheduler, mengerjakan Reserved Storage di
  keempat job, lalu menghapus dirinya dan folder `\TGOS`. Di job Windows 11 bawaan, .NET
  Framework 3.5 dicopot sampai payload-nya hilang lalu dipasang oleh tugas itu sebagai SYSTEM
  saat update di-pause (214-236 detik).
- **Laporan**: `servicing.txt` ada; isi zip dipindai, tidak ada nama akun runner, nama
  komputer, atau SID akun (14-15 file teks).
- Terminal bawaan tidak lagi diubah TGOS (tetap Windows Terminal di runner Windows 11).
- Percobaan pertama job semua-opsi Server gagal di satu pemeriksaan: installer EA app (dari
  server EA) keluar 0 tanpa memasang aplikasinya. Bagian itu tidak diubah di revisi ini;
  dijalankan ulang, lolos.

Lapis 3, uji pemilik revisi keempat: Windows 11 Pro 26H2 build 26300.9974 di VMware, AME Beta
0.8.4, semua opsi, Chrome, dan keenam aplikasi (Steam, Epic, EA app, Ubisoft Connect, Discord,
Spotify). Setelah restart **284 PASS, 1 FAIL, 2 WARN, 8 SKIP**; 116 proses, RAM 2.932 MB,
disk terpakai 27,5 GB.

Terbukti di VM:

- **Tidak ada lagi jendela cmd**: `Remove-OneDrive.ps1` menghapus 10 perintah bersih-bersih
  OneDrive dari RunOnce (`cmd.exe /q /c rmdir /s /q ...\OneDrive\ListSync...` dan
  sejenisnya), yang dulu masing-masing tampil sebagai jendela saat Explorer dinyalakan ulang.
- **.NET Framework 3.5** gagal saat instalasi (`0x8024001E`, `wuauserv` berhenti), lalu
  dipasang otomatis oleh `\TGOS\Finish after restart` setelah restart (PASS).
- **Reserved Storage** masih dipakai Windows pada restart pertama; tugasnya tetap terdaftar
  untuk restart berikutnya (percobaan 1 dari 3), laporan memberi WARN yang menjelaskannya.
- Laporan disamarkan (`C:\Users\<user>`).

Masalah, dengan penyebabnya:

- **FAIL EA app**: jam VM melompat dua hari di tengah instalasi (snapshot dipulihkan dengan
  jam lama, lalu disinkronkan; log melompat dari 05:39 ke 11:35). Batas waktu installer diukur
  dengan jam Windows, jadi installer Epic (MSI) langsung dianggap lewat 15 menit, padahal
  Windows Installer tetap memasangnya (Epic akhirnya PASS). EA app dijalankan saat Windows
  Installer masih sibuk dan keluar dengan kode 1.
- **Discord dan Ubisoft Connect tidak ada di Start dan Desktop** walau terpasang (PASS di
  laporan, tetapi tidak terlihat pengguna): daftar Start di potret tidak memuat keduanya.

Lapis 2, revisi kelima (runner command-line AME versi 0.8.4, run terakhir sebelum rilis):

| Runner | Opsi, browser | Pemeriksaan diri | Pemeriksaan CI |
|---|---|---|---|
| Windows Server 2025, build 26100, x64 | bawaan, Brave | 0 FAIL | 87 dari 87 |
| Windows Server 2025, build 26100, x64 | semua, Chrome, keenam aplikasi | 0 FAIL | 99 dari 99 |
| Windows 11 Enterprise 25H2, build 26200, ARM64 | bawaan, Brave | 0 FAIL | 87 dari 87 |
| Windows 11 Enterprise 25H2, build 26200, ARM64 | semua, Firefox | 0 FAIL | 88 dari 88 |

Yang terbukti:

- **Pintasan**: di job semua-opsi, log pemasangan memperlihatkan Steam, Epic, EA app, dan
  Spotify sudah membuat pintasannya sendiri, sedangkan untuk **Ubisoft Connect dan Discord
  TGOS harus menambahkan pintasan Start dan Desktop** (sama dengan yang hilang di VM).
  Laporan verifikasi: keenam aplikasi PASS di Start dan Desktop. Percobaan sebelumnya
  menemukan bug di pemeriksanya sendiri (pintasan per pengguna tidak dikenali saat diperiksa
  sebagai TrustedInstaller), sudah diperbaiki.
- **Antrean Windows Installer**: selama CI memegang mutex `Global\_MSIExecute`,
  `Install-Software.ps1` menunggu ("Windows Installer is free after 24-27 s"), lalu memasang
  7-Zip.
- **Coba lagi setelah restart**: 7-Zip dicopot lalu dipasang lagi oleh tugas
  `\TGOS\Finish after restart` sebagai SYSTEM di keempat job; di Windows 11 bawaan juga .NET
  Framework 3.5 (203 detik). Pada satu percobaan, unduhan VC++ dari aka.ms terputus saat
  playbook: VC++ otomatis dijadwalkan ulang dan diselesaikan oleh tugas itu (sejak itu
  unduhan yang terputus juga dicoba lagi sampai 3 kali).
- Lompatan jam tidak bisa dibuat di runner (mengubah jam runner berisiko memutus job);
  validator menjamin skrip playbook tidak lagi memakai jam Windows untuk batas waktu.
