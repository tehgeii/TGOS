# Changelog

Semua perubahan penting pada TGOS dicatat di sini. Nomor versi mengikuti roadmap di
[PLAN.md](PLAN.md#12-roadmap).

## 1.0.0 — pilihan browser, opsi baru, dan perbaikan dari uji 0.9.1

**Revisi kedua setelah uji VM revisi pertama** (nomor versi tetap). Revisi pertama diuji
pemilik di VMware (Windows 11 Pro 26H2, semua opsi, Brave): setelah restart **226 PASS,
0 FAIL, 0 WARN**, instalasi ~10 menit; dibanding Windows bersih RAM −35%, thread −37%,
proses −25%, layanan berjalan −22%. Permintaan pemilik dan tambahan di revisi ini:

- **Windows Update tiga pilihan: Pause (bawaan), Manual, Automatic.** Pause memakai fitur
  pause bawaan Settings, ditahan 10 tahun sampai pengguna menekan "Resume updates"; sebagai
  cadangan update otomatis juga dimatikan, jadi bila Windows mengabaikan pause hasilnya
  tetap Manual. Tombol Toolbox *Windows Updates - Pause / Resume*.
- **Game Bar mati total bersama opsi Xbox**: tombol Xbox di controller dan View + Menu
  tidak membuka Game Bar, policy perekaman dimatikan, dan **Win+G diblokir**
  (`DisabledHotkeys` Explorer). Alasannya ditemukan uji otomatis Windows 11 25H2: sesudah
  aplikasi Game Bar dihapus, cache AppX Windows masih mengaitkan `ms-gamebar` dengan paket
  yang sudah tidak ada, sehingga Win+G memunculkan jendela "Pick an app" walaupun
  protokolnya diberi penangan pengganti. Cache itu bagian dalam Windows, jadi TGOS tidak
  mengubahnya; pemicunya yang dimatikan. Game Mode tetap aktif. Tombol Toolbox *Xbox Game
  Bar - Turn ON* mengembalikan semuanya.
- **Halaman launcher game**: Steam, Epic Games Launcher, EA app, Ubisoft Connect; dan
  **halaman aplikasi** per pengguna: Discord dan Spotify. Semua bawaan tidak tercentang,
  versi terbaru dari alamat resmi, tanda tangan diperiksa, dipasang senyap; jendela yang
  dibuka installer sesudah pasang ditutup otomatis.
- **.NET untuk game lama** (bawaan tercentang): .NET Framework 3.5 dan .NET Desktop
  Runtime 10 (x64 dan x86).
- **Runtime game lengkap**: ditambah Visual C++ 2005, 2008, 2010, 2012, 2013 (x86 dan
  x64) dan XNA Framework 4.0, semua dari Microsoft.
- **Opsi baru**: *Block background apps* (✔), *End task di menu taskbar* (✔), *Skip the
  lock screen* (password/PIN tetap diminta), *Block driver updates from Windows Update*,
  *Deep clean* (✔) dan *Deep clean+*.
- **Deep clean** di akhir instalasi: file sementara, cache Windows Update dan Delivery
  Optimization, laporan error, file dump, `DISM /StartComponentCleanup`, Reserved
  Storage dimatikan. **Deep clean+** (tidak bisa dibatalkan): `Windows.old` dan sisa
  upgrade, `/ResetBase`. Folder dihapus dengan `rd /s /q`, yang tidak mengikuti junction.
  Tombol Toolbox *Deep Clean*.
- **Layar kunci dan login bertema TGO** (wallpaper yang sama).
- **USB**: selain USB selective suspend (sudah sejak 1.0.0), USB 3 Link Power Management
  dimatikan di skema TGOS Ultimate.
- **TGOS Toolbox ditata ulang**: tombol ON/OFF di subfolder *Turn ON or OFF* (dibuat
  `tools/make-toolbox.py` dan diperiksa uji diri), satu menu *Install Software*, tombol
  *Deep Clean*, dan fitur baru: Windows Updates, Driver Updates, Background Apps, Lock
  Screen, Xbox Game Bar, TGO Login Screen, Reserved Storage.
- **Uji otomatis**: pemantau jendela selama seluruh playbook (dengan kontrol Notepad),
  uji popup `ms-gamebar:`, uji tombol `.cmd` Toolbox sungguhan termasuk menu, bolak-balik
  semua fitur Toolbox baru, uji Deep clean; validator menolak `-Feature`/`-Item` yang
  tidak ada di skripnya.

Revisi pertama (setelah uji VM build pertama):

**Direvisi setelah uji VM build pertama 1.0.0** (nomor versi tetap). Build pertama diuji
pemilik di VMware (Windows 11 Pro 26H2, semua opsi, Chrome): Copilot, kotak abu-abu
taskbar, Start, dan Edge sudah beres; RAM −35%, thread −39%, proses −24%. Pemeriksaan
diri 225 PASS / 1 FAIL saat instalasi dan 224 PASS / 2 FAIL setelah restart. Yang
diperbaiki di revisi ini:

- **Logo browser asli** di halaman pilihan browser (Brave, Chrome, Firefox), di atas
  kotak gelap TGO yang seragam, menggantikan ikon huruf.
- **DirectX tanpa jendela.** Installer web `dxwebsetup.exe` tetap menampilkan jendela
  "Installing Microsoft DirectX" walaupun diberi `/Q`, lalu macet sampai batas 15 menit
  (FAIL). Sekarang dipakai paket lengkap resmi `directx_Jun2010_redist.exe`: diekstrak
  tanpa tampilan (`/Q:A /C /T:`), lalu `DXSETUP.exe /silent`. Tanda tangan Microsoft
  diperiksa pada paket dan pada `DXSETUP.exe`, dan SHA256 paket harus sama dengan
  checksum yang dikunci. Uji otomatis sekarang memantau jendela yang terlihat selama
  pemasangan DirectX (dengan kontrol Notepad untuk membuktikan pemantaunya bekerja); uji
  itu sempat menangkap jendela progres pengekstrak saat masih memakai `/Q` saja.
  Instalasi juga jadi jauh lebih cepat.
- **Perekam telemetri bertahan setelah restart.** Nilai `Start` perekam
  `AutoLogger-Diagtrack-Listener` hilang setelah restart (FAIL kedua): layanan DiagTrack
  masih berjalan selama instalasi dan menulis ulang konfigurasinya saat shutdown.
  DiagTrack sekarang dihentikan saat itu juga (`Stop-DisabledServices.ps1`), dan nilai
  perekam ditulis sesudahnya.
- **Ikon TGOS Toolbox tidak lagi di tengah Desktop.** Pintasannya dibuat paling akhir,
  setelah Explorer hidup lagi.
- **Pin taskbar bersih.** Reset pin juga menghapus file pintasan pin lama, sehingga
  tidak ada lagi `File Explorer (2).lnk` ganda.

Rilis 1.0.0 seperti semula:

Versi `0.9.1` diuji pemilik di VMware (Windows 11 Pro 26H2 build 26300, AME Beta 0.8.4,
semua opsi): 163 pemeriksaan lolos, 0 gagal; Edge terhapus di edisi Pro; RAM −32%. Tiga
hal masih salah dan diperbaiki di sini. Lolos uji otomatis; belum diuji ulang di VM, dan
uji di hardware asli (benchmark, anti-cheat) belum dilakukan.

**Perbaikan**

- **Copilot.** Di 26H2 Copilot bukan paket Store, tetapi program biasa (1,7 GB) dengan
  uninstaller sejenis Edge. `0.9.1` membuang identitasnya dan meninggalkan programnya.
  Sekarang uninstaller-nya dijalankan dulu (`Remove-Copilot.ps1`). Paket
  `Microsoft.MicrosoftOfficeHub`, yang ternyata identitas aplikasi Copilot, pindah ke
  opsi *Remove Copilot and Widgets*: tidak dicentang berarti Copilot utuh.
- **Kotak abu-abu di taskbar.** Itu pin Copilot yang identitasnya terhapus. Daftar pin
  taskbar sekarang direset paksa dan disusun ulang: File Explorer, browser, Store.
- **Start menu.** Pin diganti set TGOS (File Explorer, Settings, Store, browser, Notepad,
  Calculator, Terminal); ubin promosi dan bagian Recent hilang.
- Sisa folder Widgets yang terkunci dijadwalkan terhapus saat restart.

**Baru**

- **Halaman pilihan browser** dengan logo resmi: Brave (bawaan), Chrome, Firefox, atau
  None.
- **Software**: 7-Zip dan runtime game (Visual C++ x64/x86, DirectX). Semuanya diunduh
  dari sumber resmi dan tanda tangan digitalnya diperiksa sebelum dijalankan; 7-Zip, yang
  tidak ditandatangani pembuatnya, dicocokkan dengan checksum di manifest winget
  Microsoft, dan tidak pernah diturunkan versinya. Brave
  dipasang untuk semua pengguna, lengkap dengan updater-nya. Tanpa internet instalasi
  tetap lanjut; pemasangan bisa diulang dari Toolbox.
- **Pengaman Edge**: Edge tidak dihapus bila browser yang dipilih gagal terpasang.
- **Opsi baru**: hapus Microsoft Store (default mati, ditandai *hard to undo*), matikan core parking CPU (pengaturan
  itu jadi tampil di Advanced power settings), matikan animasi, pangkas layanan ekstra (printer, diagnostik, penemuan jaringan; default
  mati), menu klik kanan klasik, taskbar rata kiri.
- **Telemetri maksimal tanpa blokir jaringan**: policy tambahan, perekam otomatis
  dimatikan, dan `CompatTelRunner.exe` serta `DeviceCensus.exe` dicegah jalan.
- Jalan pintas Sticky/Filter/Toggle Keys dimatikan; warna aksen biru TGO; info TGOS di
  Settings > About; Click to Do dimatikan bersama Copilot.
- Aplikasi tambahan yang dihapus: Cross Device Experience Host, Start Experiences App,
  Edge Game Assist (bersama Edge).
- **TGOS Toolbox**: pasang browser / 7-Zip / runtime game, mencoba pasang ulang Microsoft
  Store (`wsreset -i`; di uji otomatis Store tidak kembali dalam 5 menit, jadi tidak
  dijamin),
  reset taskbar dan Start, dan tombol ON/OFF untuk core parking, layanan ekstra, dan
  pengumpul telemetri.
- Laporan (`Collect TGOS Report`) sekarang memuat daftar program terpasang, ID aplikasi
  Start, dan pin taskbar.

**Alat**

- Validator: halaman `RadioImagePage` dan gambarnya; Store dan `Spooler` hanya boleh
  disentuh lewat opsinya sendiri.
- Uji diri: pemindai yang menolak variabel PowerShell bernama sama dengan parameter skrip
  (beda huruf besar-kecil; bug jenis ini sempat merusak satu tombol Toolbox sebelum
  rilis), uji pembaca checksum winget dan pembanding versi, dan uji pemilihan browser
  untuk pin taskbar.
- Uji otomatis: tiap browser dipasang sungguhan oleh playbook di salah satu job (program
  yang sudah ada di image runner dicopot dulu); pemasangan ulang lewat Toolbox, dengan
  pemeriksaan versi tidak turun; uji unduhan gagal dan pengaman Edge; percobaan pasang
  ulang Microsoft Store (hasilnya dicatat, tidak menggagalkan uji).

**Perubahan perilaku dari 0.9.1**: animasi tidak lagi selalu dimatikan (sekarang opsi,
bawaan tercentang); label "(experimental)" pada opsi hapus Edge dicabut; pin taskbar dan
Start buatan pengguna ikut diganti saat instalasi.

## 0.9.1 — perbaikan dari uji pertama di Windows 11 Pro 26H2

Versi `0.9.0` diuji pemilik di VMware (Windows 11 Pro 26H2 build 26300, AME Beta 0.8.4,
semua opsi dicentang): 139 pemeriksaan lolos, 1 gagal (Edge). Rilis ini memperbaiki yang
ditemukan di uji itu. Lolos uji otomatis di kelima job; belum diuji ulang di VM.

- **Teks Wizard tidak lagi terpotong.** Deskripsi playbook, deskripsi halaman opsi, dan
  status progres dipendekkan. Batas panjangnya sekarang dijaga `tools/validate.py`,
  jadi teks yang terlalu panjang menggagalkan build.
- **OneDrive tanpa prompt.** Uninstaller-nya dijalankan dengan hak admin pengguna yang
  login, supaya Windows tidak menampilkan jendela "Yes/No" di tengah instalasi.
- **Taskbar.** Pin bawaan diganti lewat policy layout taskbar Windows: File Explorer,
  Edge, Microsoft Store. Pin Copilot yang tertinggal (kotak abu-abu) hilang. Pencarian
  tampil sebagai ikon; tombol Task View disembunyikan.
- **Edge (tetap eksperimental).** Uninstaller Edge menolak bekerja di Windows 11 Pro 26H2
  (kode 93). Skrip sekarang mencoba dua cara tambahan. Belum terbukti di edisi Pro:
  mesin uji otomatis memakai edisi Enterprise, tempat Edge memang bisa dihapus.
- **Edge di latar belakang.** Startup Boost dan mode latar Edge dimatikan lewat policy,
  baik Edge dihapus maupun tidak.
- **Widgets.** Prosesnya dihentikan sebelum paketnya dihapus, supaya filenya tidak
  tertinggal terkunci di disk.
- **Wallpaper** digambar ulang 3840x2160 dengan gradasi halus (`tools/make-wallpaper.py`);
  file lama 2000x1125 bergaris. Windows juga dicegah mengompres ulang wallpaper.
- **Layanan:** `InventorySvc` dan `whesvc` dimatikan; `WSAIFabricSvc` dijadikan Manual
  bila opsi Copilot dan Widgets dipilih. Ketiganya berjalan otomatis di 26H2.
- **Tugas terjadwal:** 12 tugas ditambahkan (pelaporan pemakaian fitur, telemetri
  Sustainability, Family Safety, RetailDemo, DiskFootprint, pop-up umpan balik); total 25.
- Pemeriksaan diri memeriksa file layout taskbar.
- Uji otomatis: log menampilkan hasil skrip OneDrive, Edge, dan Toolbox, dan
  mengelompokkan baris error mesin AME yang berulang.

Bukan bug, tapi perlu diketahui: wallpaper dan mode gelap baru tampil setelah restart,
karena Windows membaca pengaturan itu saat login.

## 0.9.0 — semua modul, TGOS Toolbox, dan uji otomatis

Rilis pertama yang berisi semua modul rencana. Lolos uji lewat mesin AME yang asli di
GitHub Actions, di Windows Server 2025 dan Windows 11 Enterprise 25H2, dengan opsi bawaan
maupun semua opsi (rincian di `docs/TESTING.md`). Uji di Windows 11 Pro x64 lewat AME
Wizard menunggu VM pemilik.

- **Layanan:** 16 layanan telemetri dan fitur yang tidak dipakai dimatikan (tidak ada yang
  dihapus); Windows Search lewat opsi.
- **Tugas terjadwal:** 13 tugas telemetri, CEIP, feedback, dan Maps dinonaktifkan lewat
  skrip yang melewati tugas yang tidak ada.
- **Performa:** Game DVR latar mati, Game Mode, HAGS, akselerasi mouse mati, penjadwal
  multimedia, timer global, aplikasi latar, efek visual; opsi power plan Ultimate
  Performance dan hibernasi.
- **Opsi keamanan:** VBS, mitigasi CPU, update otomatis. Defender tidak disentuh playbook.
- **Komponen:** OneDrive (uninstaller resmi); Edge sebagai opsi eksperimental, default
  mati, WebView2 dipertahankan.
- **Tampilan:** mode gelap, Explorer, wallpaper TGO.
- **TGOS Toolbox** di `C:\TGOS Toolbox` dengan pintasan Desktop: pasangan *Turn OFF /
  Turn ON* untuk Defender, VBS, mitigasi, update otomatis, indexing, hibernasi; dan
  *Collect TGOS Report* yang membuat satu `TGOS-report.zip`.
- **Pemeriksaan diri:** `expected-state.json` dibuat dari YAML; `Test-TgosResult.ps1`
  mencocokkan sistem dengannya dan menulis `verify-report.txt`.
- **Uji otomatis:** `.github/workflows/test.yml` menjalankan playbook lewat runner
  command-line AME di setiap push, termasuk uji tolak edisi bukan Pro.
- Validator: daftar layanan yang dilindungi; `!service` hanya `change`; `!scheduledTask`
  dan `options:` dilarang; setiap opsi harus tercatat di `install-info.txt`.
- `Get-SystemSnapshot.ps1` pindah ke TGOS Toolbox.

Menyimpang dari rencana awal: menu klik kanan klasik, tombol taskbar, dan pembersihan
DISM tidak dikerjakan; layanan Xbox dan geolokasi tidak disentuh; policy `AllowGameDVR`
tidak dipakai supaya perekaman tetap bisa dinyalakan pengguna.

## 0.1.0 — aplikasi bawaan dan privasi (hanya diuji lewat mesin AME di CI)

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
