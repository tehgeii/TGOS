# TGOS — Rencana Pengembangan Playbook

**TGOS (Tech Gameplay Operating System)** adalah playbook untuk AME Wizard yang mengubah
instalasi Windows 11 Pro menjadi OS gaming yang sangat ringan. Urutan prioritasnya:
**performa dulu, keamanan belakangan** — tetapi setiap pengorbanan keamanan dibuat sebagai
pilihan sadar pengguna, bukan sesuatu yang terjadi diam-diam.

| | |
|---|---|
| Status dokumen | Draf v1 — menunggu review pemilik proyek |
| Versi playbook target pertama | `0.1.0` (uji di VMware) |
| Target OS | Windows 11 **Pro**, 22H2 sampai 26H2 |
| Cara pasang | File `.apbx` dibuka di AME Wizard |

Daftar isi:
[1. Tujuan](#1-tujuan) ·
[2. Fakta teknis AME](#2-fakta-teknis-ame-wizard-yang-sudah-diverifikasi) ·
[3. Soal password](#3-soal-password-apbx) ·
[4. Dukungan Windows](#4-dukungan-versi--edisi-windows) ·
[5. Prinsip desain](#5-prinsip-desain) ·
[6. Struktur repo](#6-struktur-repo) ·
[7. playbook.conf](#7-rancangan-playbookconf) ·
[8. Modul tweak](#8-rancangan-modul-tweak) ·
[9. Batasan](#9-yang-sengaja-tidak-dilakukan) ·
[10. Build](#10-build--packaging) ·
[11. Pengujian VMware](#11-rencana-pengujian-di-vmware) ·
[12. Roadmap](#12-roadmap) ·
[13. Risiko](#13-risiko--mitigasi) ·
[14. Aturan Git](#14-aturan-git) ·
[15. Pertanyaan terbuka](#15-pertanyaan-terbuka) ·
[16. Sumber](#16-sumber)

---

## 1. Tujuan

1. **Ringan.** Proses latar, layanan, tugas terjadwal, dan aplikasi bawaan dipangkas
   sampai yang benar-benar dibutuhkan untuk bermain game.
2. **Performa maksimal dan konsisten.** Fokus pada frame time yang stabil dan latensi
   input rendah, bukan cuma angka FPS rata-rata.
3. **Tetap bisa dipakai.** Game, launcher (Steam, Epic, Riot, Battle.net, Xbox app bila
   dipilih), driver GPU, Discord, dan browser harus tetap jalan normal.
4. **Bisa dibalik.** Keputusan besar (Defender, mitigasi, Windows Update) punya skrip
   pembalik di folder TGOS setelah instalasi.
5. **Terukur.** Setiap tweak yang diklaim "menambah performa" harus lolos benchmark
   sebelum jadi default. Tweak yang tidak terbukti tidak dimasukkan.

Kriteria keberhasilan `0.1.0` (diukur di VM, dibanding Windows 11 Pro bersih):

| Metrik | Cara ukur | Target awal |
|---|---|---|
| Jumlah proses saat idle | Task Manager, 5 menit setelah boot | Turun ≥ 35% |
| RAM terpakai saat idle | Task Manager → Memory "In use" | Turun ≥ 30% |
| Jumlah layanan berjalan | `Get-Service \| ? Status -eq Running` | Turun ≥ 30% |
| Ukuran disk terpakai | `Get-Volume C` | Turun (dicatat, tanpa target keras) |
| Stabilitas | 0 error di log AME, 0 BSOD, `sfc /verifyonly` bersih | Wajib |

Angka target ini tebakan awal yang masuk akal, **bukan** hasil pengukuran. Angka riilnya
baru ada setelah uji pertama dan dokumen ini diperbarui.

---

## 2. Fakta teknis AME Wizard yang sudah diverifikasi

Semua poin di bagian ini dicek langsung ke source code inti AME Wizard
(`Ameliorated-LLC/trusted-uninstaller-cli`) dan playbook AtlasOS terbaru, bukan dari ingatan.

### 2.1 Format file

- `.apbx` adalah **arsip 7z yang diganti ekstensinya**, dienkripsi dengan password `malte`.
- Isi wajib di root arsip:

```
playbook.conf            ← metadata + halaman opsi (XML)
Configuration/
  main.yml               ← titik masuk (kalau tidak ada, Wizard memakai custom.yml)
  Tasks/*.yml            ← file tugas yang dipanggil dari main.yml
Executables/             ← skrip & file pendukung; jadi working dir bila exeDir: true
playbook.png             ← ikon (opsional)
```

### 2.2 `playbook.conf`

Field yang dipakai TGOS:

| Field | Fungsi |
|---|---|
| `Name`, `Username`, `Title`, `ShortDescription`, `Description`, `Details` | Identitas & teks di Wizard. `Name` tidak boleh mengandung `\ / : * ? < > \|` dan ada batas lebar tampilan. |
| `Version` | Format `1`, `1.0`, atau `1.0.0`. |
| `UniqueId` | UUID v4. Tidak boleh UUID kosong. Dibuat sekali dan **tidak pernah diganti**. |
| `SupportedBuilds` | Daftar nomor build (bilangan bulat) menurut dokumentasi AME; tidak ada sintaks rentang yang terdokumentasi. |
| `Requirements` | Syarat sebelum jalan (lihat di bawah). |
| `FeaturePages` | Halaman pilihan: `RadioPage`, `CheckboxPage`, `RadioImagePage`. |
| `UpgradableFrom` | Versi lama yang boleh di-upgrade: `1.0.0`, `1.0.0-2.0.0`, atau `any`. |
| `Overhaul`, `UseKernelDriver`, `EstimatedMinutes`, `ProgressText`, `Git`, `Website`, `InstallGuide` | Perilaku & tautan. |

Nilai `Requirement` yang dikenali: `Internet`, `NoInternet`, `DefenderDisabled`,
`DefenderToggled`, `NoPendingUpdates`, `Activation`, `NoAntivirus`, `LocalAccounts`,
`PasswordSet`, `AdministratorPasswordSet`, `PluggedIn`, `NoTweakware`, `FreshInstall`,
`UCPDDisabled`.

> **Penting:** Wizard hanya memeriksa **nomor build**, tidak memeriksa **edisi**. Jadi
> pembatasan "hanya Pro" harus kita tulis sendiri (lihat [4.2](#42-pembatasan-edisi-pro)).

### 2.3 Aksi YAML

| Tag | Properti utama | Catatan |
|---|---|---|
| `!task:` | `path` | Memanggil file YAML lain. |
| `!writeStatus:` | `status` | Teks progres di Wizard. |
| `!registryValue:` | `path`, `value`, `data`, `type`, `operation` (`add`/`set`/`delete`), `scope` | `type`: `REG_SZ`, `REG_DWORD`, `REG_QWORD`, `REG_BINARY`, `REG_MULTI_SZ`, `REG_EXPAND_SZ`. `set` = hanya bila nilai sudah ada. |
| `!registryKey:` | `path`, `operation` (`delete`/`add`), `scope` | Default: `delete`. |
| `!service:` | `name`, `operation` (`change`/`stop`/`start`/`delete`/…), `startup`, `device` | Default: `delete` — **selalu tulis `operation` eksplisit.** |
| `!scheduledTask:` | `path`, `operation` (`disable`/`enable`/`delete`/`deleteFolder`) | Default: `delete` — tulis eksplisit. |
| `!appx:` | `name`, `type` (`family`/`package`/`app`), `operation` (`remove`/`clearCache`), `unregister` | Mendukung wildcard pada `name`. |
| `!run:` | `exe`, `args`, `runas`, `exeDir`, `wait`, `timeout`, `handleExitCodes`, `showOutput`, `showError` | `handleExitCodes: {"!0": halt}` menghentikan playbook bila gagal. |
| `!cmd:` / `!powerShell:` | `command`, `runas`, `exeDir`, `wait`, `timeout`, `handleExitCodes` | |
| `!file:` | `path` | Menghapus file/folder. |
| `!taskKill:` | `name`, `pathContains` | |
| `!systemPackage:` | `name`, `arch`, `language` | Menghapus paket komponen Windows. Berisiko tinggi, dipakai hemat. |

Filter yang bisa ditaruh di aksi apa pun:

- `option: 'nama'` / `option: '!nama'` — jalan hanya bila opsi dipilih / tidak dipilih.
  `'a&b'` berarti keduanya harus dipilih.
- `options: [...]` — daftar; salah satu cocok sudah cukup.
- `builds: ['>=26100']` — operator `>=`, `<=`, `>`, `<`, `!`. Bisa juga `build.update`
  (mis. `'>=26100.2314'`), tapi Wizard membandingkannya sebagai **bilangan desimal**:
  `26100.500` dianggap lebih besar dari `26100.2314`. Jadi TGOS hanya memfilter
  berdasarkan nomor build utama.
- `cpuArch`, `onUpgrade`, `onUpgradeVersions`, `ignoreErrors`, `errorAction`.

`runas` yang dipakai: `trustedInstaller` (default), `system`, `currentUser`,
`currentUserElevated`.

---

## 3. Soal password `.apbx`

**Permintaan awal:** file `.apbx` diberi password sendiri supaya tidak bisa diekstrak
sembarang orang.

**Kenyataannya:** itu **tidak bisa** dilakukan pada file `.apbx` yang dibuka AME Wizard.
Wizard membuka semua playbook dengan satu password tetap, yaitu `malte`. Kalau `.apbx`
dienkripsi dengan password lain, Wizard gagal memuatnya. Password `malte` tertulis di
dokumentasi publik AME, jadi siapa pun yang punya file `.apbx` bisa mengekstraknya dengan
7-Zip. Enkripsi itu memang bukan untuk merahasiakan isi; tujuannya supaya antivirus tidak
memindai dan salah menandai isi arsip.

Pilihan yang realistis:

| Opsi | Cara kerja | Yang didapat | Kelemahan |
|---|---|---|---|
| **A. Pembungkus distribusi** (usulan) | `TGOS-vX.Y.Z.apbx` (password `malte`) dimasukkan ke `TGOS-vX.Y.Z.7z` berpassword milik TGOS. Pembeli mengekstrak 7z dulu, baru membuka `.apbx` di Wizard. | Tautan unduhan yang bocor tidak berguna tanpa password. | Siapa pun yang sudah punya password tetap bisa mengekstrak `.apbx`-nya. |
| B. Payload terenkripsi di dalam | Skrip inti disimpan sebagai arsip terenkripsi di `Executables/`, lalu diekstrak saat instalasi. | Isi tidak terbaca sekilas. | Kuncinya harus ada di dalam playbook, jadi ini cuma penyamaran. Menambah titik gagal dan kemungkinan ditandai antivirus. |
| C. Tanpa perlindungan | `.apbx` standar saja. | Paling sederhana, bisa diaudit pengguna. | Tidak ada perlindungan. |

Kesimpulan jujurnya: **tidak ada cara membuat isi playbook benar-benar rahasia** selama
dijalankan AME Wizard di komputer pengguna. Perlindungan yang berarti untuk produk premium
ada di sisi lisensi (misalnya verifikasi lisensi lewat aplikasi TGO), bukan di password arsip.

Dua aturan yang dipakai apa pun opsinya:

- Password distribusi **tidak ditulis di repo** (kalau repo publik, password ikut publik).
  Skrip build membacanya dari variabel lingkungan `TGOS_DIST_PASSWORD`.
- Kalau repo ini publik, source playbook-nya sudah terbuka, jadi password arsip tidak
  melindungi apa-apa. Repo sebaiknya **private** bila isi playbook ingin dijaga.

---

## 4. Dukungan versi & edisi Windows

### 4.1 Build yang didukung

| Versi | Build | Status di TGOS 0.1.0 |
|---|---|---|
| 22H2 | 22621 | Didukung (sudah habis masa dukungan Microsoft untuk Pro) |
| 23H2 | 22631 | Didukung (sudah habis masa dukungan Microsoft untuk Pro) |
| 24H2 | 26100 | Didukung (masa dukungan Microsoft untuk Pro berakhir 13 Oktober 2026) |
| 25H2 | 26200 | Didukung |
| 26H2 | 26300 | Didukung — **target uji utama** |

Karena `SupportedBuilds` berisi nomor build satu per satu, **versi Windows masa depan
tidak otomatis didukung**. Setiap rilis Windows baru butuh rilis TGOS baru yang menambah
nomor build-nya setelah diuji. Ini disengaja: menjalankan playbook yang menghapus komponen
sistem di build yang belum pernah diuji adalah cara tercepat merusak instalasi.

Perbedaan antar-build ditangani dengan filter `builds:`. Contoh: Copilot dan Recall hanya
ada mulai 24H2, jadi aksinya diberi `builds: ['>=26100']`.

### 4.2 Pembatasan edisi Pro

Aksi pertama di `main.yml` menjalankan `Executables\Scripts\Test-Compatibility.ps1` yang:

1. Membaca `EditionID` dari `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion`.
2. Lolos hanya bila nilainya `Professional`.
3. Memastikan build ≥ 22621 dan arsitektur x64.
4. Keluar dengan kode bukan 0 bila gagal → `handleExitCodes: {"!0": halt}` menghentikan
   playbook **sebelum ada perubahan apa pun**.

Yang perlu diputuskan: apakah varian `ProfessionalN`, `ProfessionalWorkstation`, dan
`ProfessionalEducation` ikut diterima. Default rencana ini: **tidak**, hanya `Professional`.

---

## 5. Prinsip desain

1. **Satu perubahan, satu alasan.** Setiap aksi di YAML punya komentar singkat: apa yang
   diubah dan kenapa. Tidak ada blok registry tanpa keterangan.
2. **Tidak ada tweak mitos.** Banyak "tweak gaming" yang beredar tidak berpengaruh atau
   malah merugikan. Tweak seperti itu masuk daftar "perlu bukti" di
   [8.5](#85-kandidat-yang-butuh-bukti-benchmark-dulu), bukan default.
3. **Keamanan dikurangi lewat opsi, bukan diam-diam.** Mematikan Defender, VBS, dan
   mitigasi CPU ditawarkan di halaman opsi Wizard dengan penjelasan risikonya.
4. **Pisahkan "hapus" dari "matikan".** Sebisa mungkin layanan diubah startup-nya, bukan
   dihapus, supaya bisa dibalik. Penghapusan permanen hanya untuk bloat murni.
5. **Jangan rusak yang dibutuhkan game.** Microsoft Store, Xbox/Gaming Services, dan
   Windows Update dipertahankan fungsinya (bisa dimatikan otomatisnya, tidak dicabut).
6. **Uji di VM dulu, baru hardware asli.** Tidak ada rilis tanpa lolos checklist
   [bagian 11](#11-rencana-pengujian-di-vmware).

---

## 6. Struktur repo

```
TGOS/
├─ README.md
├─ PLAN.md                         ← dokumen ini
├─ CHANGELOG.md
├─ .gitignore                      ← mengabaikan release/, *.apbx, *.7z
├─ .gitattributes                  ← CRLF untuk .ps1/.cmd/.reg, LF untuk .yml
├─ src/
│  ├─ playbook.conf
│  ├─ playbook.png
│  ├─ Configuration/
│  │  ├─ main.yml                  ← urutan eksekusi
│  │  └─ Tasks/
│  │     ├─ 00-preflight.yml       ← cek edisi/build, restore point
│  │     ├─ 10-debloat-appx.yml
│  │     ├─ 20-privacy.yml
│  │     ├─ 30-services.yml
│  │     ├─ 40-scheduled-tasks.yml
│  │     ├─ 50-performance.yml
│  │     ├─ 60-security-options.yml
│  │     ├─ 70-components.yml      ← Edge, OneDrive
│  │     ├─ 80-interface.yml
│  │     └─ 90-finalize.yml        ← folder TGOS, pembersihan
│  └─ Executables/
│     ├─ Scripts/                  ← skrip PowerShell yang dipanggil playbook
│     └─ TGOS/                     ← disalin ke sistem: skrip toggle & pembalik
├─ tools/
│  ├─ build.ps1                    ← build di Windows (butuh 7-Zip)
│  ├─ build.sh                     ← build di Linux/CI
│  └─ validate.py                  ← cek XML + YAML terhadap skema aksi AME
├─ docs/
│  ├─ TESTING.md                   ← checklist & hasil uji per versi
│  └─ TWEAKS.md                    ← daftar semua tweak + alasan + cara balik
└─ release/                        ← hasil build (tidak di-commit)
```

Penomoran file tugas menentukan urutan dan memudahkan mematikan satu modul saat mencari
penyebab masalah.

---

## 7. Rancangan `playbook.conf`

### 7.1 Metadata

| Field | Nilai rencana |
|---|---|
| `Name` | `TGOS` |
| `Username` | `tehgeii` |
| `Title` | `TGOS v0.1.0` |
| `ShortDescription` | `Tech Gameplay Operating System for Windows 11 Pro` |
| `Version` | `0.1.0` |
| `UniqueId` | UUID v4 baru, dibuat sekali |
| `SupportedBuilds` | `22621`, `22631`, `26100`, `26200`, `26300` |
| `Overhaul` | `true` |
| `UseKernelDriver` | `false` |
| `EstimatedMinutes` | `15` (dikoreksi setelah uji) |
| `Website` | `https://tgopremium.my.id` |

### 7.2 Requirements

| Requirement | Dipakai? | Alasan |
|---|---|---|
| `DefenderToggled` | Ya | Wizard butuh proteksi real-time mati selama proses. |
| `NoAntivirus` | Ya | Antivirus pihak ketiga mengganggu modifikasi sistem. |
| `NoPendingUpdates` | Ya | Update yang menggantung bisa menimpa perubahan atau merusak servicing. |
| `PluggedIn` | Ya | Mencegah laptop mati di tengah proses. |
| `Internet` | Tidak (0.1.0) | Belum ada yang diunduh. Ditambahkan bila nanti memasang software. |
| `Activation` | Tidak | Tidak relevan untuk uji VM. Dipertimbangkan untuk rilis. |

### 7.3 Halaman opsi (FeaturePages)

Kolom "Nama opsi" adalah yang dipakai di filter `option:` pada YAML. Default checkbox
diatur lewat atribut `IsChecked` (bawaan Wizard: tercentang); default radio lewat
`DefaultOption`. Halaman bisa dibuat bergantung pada opsi lain dengan `DependsOn`.

**Halaman 1 — Defender** (`RadioPage`, wajib)

| Pilihan | Nama opsi |
|---|---|
| Matikan Defender (performa maksimal) | `defender-disable` |
| Biarkan Defender aktif | `defender-enable` |

**Halaman 2 — Mitigasi CPU** (`RadioPage`, wajib)

| Pilihan | Nama opsi |
|---|---|
| Mitigasi default Windows | `mitigations-default` |
| Matikan semua mitigasi | `mitigations-disable` |

**Halaman 3 — Windows Update** (`RadioPage`, wajib)

| Pilihan | Nama opsi |
|---|---|
| Matikan update otomatis (tetap bisa manual) | `updates-manual` |
| Biarkan default | `updates-default` |

**Halaman 4 — Performa** (`CheckboxPage`)

| Pilihan | Nama opsi | Default |
|---|---|---|
| Matikan VBS / Core Isolation | `disable-vbs` | ✔ |
| Matikan hibernasi & Fast Startup | `disable-hibernation` | ✔ |
| Matikan penghematan daya (desktop) | `disable-power-saving` | ✔ |
| Matikan Windows Search indexing | `disable-indexing` | ✔ |

**Halaman 5 — Komponen** (`CheckboxPage`)

| Pilihan | Nama opsi | Default |
|---|---|---|
| Hapus Microsoft Edge | `remove-edge` | ✘ |
| Hapus OneDrive | `remove-onedrive` | ✔ |
| Hapus aplikasi Xbox (Game Bar, Xbox app) | `remove-xbox` | ✘ |
| Hapus Widgets, Copilot, Recall | `remove-ai-widgets` | ✔ |

Default Halaman 1–3 menunggu keputusan pemilik proyek
(lihat [bagian 15](#15-pertanyaan-terbuka)).

---

## 8. Rancangan modul tweak

Kolom **Risiko** menilai kemungkinan merusak fungsi: R = rendah, S = sedang, T = tinggi.
Kolom **Balik** menandai apakah ada skrip pembalik di folder TGOS.

### 8.1 Debloat aplikasi (`10-debloat-appx.yml`)

Dihapus tanpa syarat (bloat murni): Clipchamp, Bing News, Bing Weather, Bing Search,
Solitaire, Get Help, Get Started/Tips, Feedback Hub, Office Hub, People, Maps, Your Phone /
Phone Link, Power Automate, To Do, Teams (consumer), Dev Home, Outlook (new), Quick Assist,
Mixed Reality Portal, Skype, Zune Music/Video, Sound Recorder, Alarms, Family, Sticky Notes.

Dipertahankan: Microsoft Store, App Installer (winget), Desktop App Installer, VCLibs,
.NET Native, UI.Xaml, Notepad, Paint, Photos, Calculator, Snipping Tool, Terminal,
Windows Security (UI), dan semua ekstensi codec (HEIF, HEVC, VP9, WebP, AV1).

Bersyarat: Xbox & Game Bar (`remove-xbox`), Copilot/Recall/Widgets (`remove-ai-widgets`).

| Risiko | Balik |
|---|---|
| R — semua bisa dipasang lagi dari Store | Lewat Store |

### 8.2 Privasi & telemetri (`20-privacy.yml`)

| Tweak | Lokasi | Risiko |
|---|---|---|
| Telemetri ke level minimum | `HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection` → `AllowTelemetry=0` | R |
| Matikan Advertising ID | `HKCU\...\AdvertisingInfo` → `Enabled=0` | R |
| Matikan saran, tips, iklan Start & Settings | `HKCU\...\ContentDeliveryManager` (banyak nilai) | R |
| Matikan pemasangan aplikasi promosi otomatis | `SilentInstalledAppsEnabled=0`, `DisableWindowsConsumerFeatures=1` | R |
| Matikan Activity History & Timeline | `HKLM\SOFTWARE\Policies\Microsoft\Windows\System` | R |
| Matikan pencarian web di Start | `DisableSearchBoxSuggestions=1` | R |
| Matikan Recall & analisis data AI (≥ 24H2) | `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI` | R |
| Matikan Widgets | `HKLM\SOFTWARE\Policies\Microsoft\Dsh` → `AllowNewsAndInterests=0` | R |
| Matikan pelaporan error (WER) | `HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting` → `Disabled=1` | R |
| Matikan Delivery Optimization P2P | `DODownloadMode=0` | R |

Catatan jujur: di edisi Pro, `AllowTelemetry=0` diperlakukan Windows sebagai level 1
(Required). Telemetri baru benar-benar berhenti setelah layanan `DiagTrack` dimatikan
di modul layanan.

### 8.3 Layanan (`30-services.yml`)

Semua memakai `operation: change` dengan `startup: 4` (disabled) kecuali disebut lain.

| Kelompok | Layanan | Risiko | Catatan |
|---|---|---|---|
| Telemetri | `DiagTrack`, `dmwappushservice`, `diagnosticshub.standardcollector.service` | R | |
| Pelaporan error | `WerSvc` | R | |
| Prefetch | `SysMain` | R | Di SSD manfaatnya kecil; mengurangi I/O latar. |
| Pengindeksan | `WSearch` | S | Opsi `disable-indexing`. Pencarian file jadi lebih lambat. |
| Peta | `MapsBroker` | R | |
| Retail demo | `RetailDemo` | R | |
| Faks | `Fax` | R | |
| Remote Registry | `RemoteRegistry` | R | Sekaligus menambah keamanan. |
| Geolokasi | `lfsvc` | S | Aplikasi cuaca/peta kehilangan lokasi. |
| Dompet & pembayaran NFC | `WalletService`, `SEMgrSvc` | R | |
| Parental control | `WpcMonSvc` | R | |
| Biometrik | `WbioSrvc` | S | **Tidak dimatikan** bila Windows Hello dipakai → dijadikan Manual (3). |
| Print Spooler | `Spooler` | S | **Tidak disentuh** di 0.1.0. Banyak pengguna butuh printer. |
| Bluetooth | `bthserv`, `BTAGService` | T | **Tidak disentuh.** Controller & headset bergantung padanya. |
| Xbox | `XblAuthManager`, `XblGameSave`, `XboxNetApiSvc`, `XboxGipSvc` | S | Hanya bila `remove-xbox`. `GamingServices` tidak dihapus. |

Yang **tidak pernah** disentuh: `AudioSrv`, `AudioEndpointBuilder`, `Dhcp`, `Dnscache`,
`nsi`, `NlaSvc`, `BFE`, `mpssvc` (firewall), `CryptSvc`, `RpcSs`, `DcomLaunch`,
`EventLog`, `Schedule`, `TrustedInstaller`, `wuauserv`, `BITS`, `UsoSvc`, `AppXSvc`,
`ClipSVC`, `StateRepository`, `TokenBroker`, `LicenseManager`.

### 8.4 Performa (`50-performance.yml`)

Tweak yang efeknya terdokumentasi dan masuk default:

| Tweak | Lokasi / perintah | Efek | Risiko |
|---|---|---|---|
| Power plan Ultimate Performance | `powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61` lalu `-setactive` | CPU tidak turun frekuensi, tidak ada core parking | R (opsi `disable-power-saving`) |
| Matikan hibernasi & Fast Startup | `powercfg /h off`, `HiberbootEnabled=0` | Boot bersih, membebaskan `hiberfil.sys` (seukuran sebagian RAM) | R |
| Matikan Game DVR / perekaman latar | `HKCU\System\GameConfigStore` → `GameDVR_Enabled=0`; policy `AllowGameDVR=0` | Menghilangkan overhead perekaman latar | R |
| Game Mode aktif | `HKCU\SOFTWARE\Microsoft\GameBar` → `AutoGameModeEnabled=1` | Menahan Windows Update & notifikasi saat bermain | R |
| Hardware-accelerated GPU scheduling | `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers` → `HwSchMode=2` | Mengurangi latensi di GPU yang mendukung; syarat frame generation | R |
| Matikan akselerasi mouse | `HKCU\Control Panel\Mouse` → `MouseSpeed=0`, threshold 0 | Gerakan mouse 1:1 | R |
| Prioritas multimedia | `...\Multimedia\SystemProfile` → `SystemResponsiveness=10`, `NetworkThrottlingIndex=0xFFFFFFFF` | CPU lebih banyak untuk proses latar depan; tidak ada throttling paket saat audio/video aktif | R |
| Timer resolution global (Win11) | `...\Session Manager\kernel` → `GlobalTimerResolutionRequests=1` | Mengembalikan perilaku timer lama yang diandalkan sebagian game | R |
| Matikan aplikasi latar | `LetAppsRunInBackground=2` (policy) | Mengurangi proses UWP menganggur | R |
| Matikan efek transparansi & animasi | `HKCU\...\Themes\Personalize`, `VisualFXSetting` | Sedikit meringankan compositor | R |
| Matikan startup delay | `HKCU\...\Explorer\Serialize` → `StartupDelayInMSec=0` | Login terasa lebih cepat | R |
| Matikan power throttling | `...\Control\Power\PowerThrottling` → `PowerThrottlingOff=1` | Proses latar tidak dipaksa ke mode hemat | R (opsi `disable-power-saving`) |
| Matikan USB selective suspend | Setelan power plan | Mencegah jeda perangkat input | R (opsi `disable-power-saving`) |
| Matikan NTFS last-access update | `fsutil behavior set disablelastaccess 1` | Mengurangi tulis disk | R |
| Matikan notifikasi & tips sistem | Beberapa nilai `HKCU` | Tidak ada pop-up di tengah game | R |

### 8.5 Kandidat yang butuh bukti benchmark dulu

Tidak masuk default sampai terbukti di hardware asli. Banyak dari ini populer di panduan
"optimasi" tapi hasilnya tidak konsisten atau negatif:

| Kandidat | Kenapa ditahan |
|---|---|
| `Win32PrioritySeparation` selain default | Efeknya bergantung beban kerja; nilai "ajaib" yang beredar tidak punya dasar umum. |
| `bcdedit /set disabledynamictick yes`, `useplatformclock`, `useplatformtick` | Di sistem modern sering **menambah** latensi. Efeknya sangat bergantung hardware. |
| Mematikan HPET di Device Manager | Sama; tidak ada manfaat konsisten. |
| Tweak TCP (`TcpAckFrequency`, `TCPNoDelay`) | Hanya berlaku untuk koneksi tertentu; hampir tidak relevan untuk game modern berbasis UDP. |
| Mematikan memory compression | Di RAM kecil malah memperburuk; di RAM besar tidak terasa. |
| Mematikan `SvcHostSplitThresholdInKB` | Mengurangi jumlah proses tapi satu layanan crash menjatuhkan yang lain. |
| MSI mode & affinity interrupt per perangkat | Spesifik hardware, tidak aman dijadikan default. |
| Mematikan paging file | Menyebabkan crash di game yang butuh commit besar. **Tidak akan dipakai.** |

Hasil benchmark tiap kandidat dicatat di `docs/TWEAKS.md` beserta keputusannya.

### 8.6 Opsi keamanan (`60-security-options.yml`)

Semua di modul ini hanya jalan bila opsinya dipilih di Wizard.

| Opsi | Yang dilakukan | Dampak keamanan | Balik |
|---|---|---|---|
| `defender-disable` | Mematikan layanan & driver Defender, SmartScreen | Tidak ada antivirus. Malware dari cheat, crack, dan mod jadi ancaman nyata. | Ya |
| `disable-vbs` | `EnableVirtualizationBasedSecurity=0`, HVCI `Enabled=0` | Proteksi kernel berkurang. Di banyak sistem ini memberi kenaikan performa terukur. | Ya |
| `mitigations-disable` | `FeatureSettingsOverride=3`, `FeatureSettingsOverrideMask=3` | Rentan terhadap Spectre/Meltdown. Manfaatnya terutama di CPU lama; di CPU baru bisa nol atau negatif. | Ya |
| `updates-manual` | Policy menunda update otomatis; update manual tetap bisa | Patch keamanan tertunda sampai pengguna memasangnya. | Ya |

Yang **tetap aktif** apa pun pilihannya: Windows Firewall, UAC, dan Secure Boot/TPM (tidak
disentuh sama sekali karena dibutuhkan anti-cheat).

### 8.7 Komponen (`70-components.yml`)

| Opsi | Catatan |
|---|---|
| `remove-edge` | WebView2 Runtime **dipertahankan** — banyak launcher dan aplikasi bergantung padanya. Tanpa browser, pengguna harus memasang browser lain lewat `winget`. |
| `remove-onedrive` | Menjalankan uninstaller resmi dan membersihkan entri Explorer. |

### 8.8 Antarmuka (`80-interface.yml`)

Mode gelap, menu klik kanan klasik, taskbar tanpa Search/Task View/Widgets/Chat, File
Explorer membuka "This PC", ekstensi file ditampilkan. Wallpaper dan aksen warna TGOS
menyusul setelah aset desainnya tersedia.

### 8.9 Finalisasi (`90-finalize.yml`)

- Menyalin folder `TGOS` ke `%SystemDrive%\TGOS` dan membuat pintasan di Desktop, berisi
  skrip: aktifkan/matikan Defender, VBS, mitigasi, update otomatis, indexing; dan
  `Info.txt` yang mencatat versi TGOS serta opsi yang dipilih.
- Membersihkan cache komponen (`DISM /StartComponentCleanup`) dan file sementara.
- Wizard meminta restart.

---

## 9. Yang sengaja tidak dilakukan

- Tidak mengutak-atik aktivasi atau lisensi Windows.
- Tidak mencabut Windows Update, Store, atau servicing stack. Sistem tetap bisa di-update.
- Tidak mematikan Secure Boot, TPM, atau firewall.
- Tidak memakai driver kernel (`UseKernelDriver=false`).
- Tidak mengunduh atau menjalankan binary pihak ketiga yang tidak bisa diaudit.
- Tidak menghapus komponen yang dibutuhkan anti-cheat (Vanguard, EAC, BattlEye, FACEIT).

Soal anti-cheat: beberapa anti-cheat menolak jalan bila fitur keamanan tertentu mati.
Kombinasi opsi TGOS terhadap game populer harus diuji di hardware asli sebelum rilis
publik, dan hasilnya ditulis di dokumentasi.

---

## 10. Build & packaging

```
src/  ──validate.py──▶  7z (password malte, format 7z)  ──▶  release/TGOS-v0.1.0.apbx
                                                                   │
                                     (opsional, opsi A bagian 3)   ▼
                              7z (password dari TGOS_DIST_PASSWORD, header terenkripsi)
                                                                   ▼
                                                      release/TGOS-v0.1.0.7z
```

1. `tools/validate.py` — memeriksa `playbook.conf` (XML valid, field wajib, UUID bukan
   kosong, format versi), setiap YAML (tag aksi dikenal, nama properti dikenal, opsi yang
   dirujuk memang ada di `playbook.conf`, file yang dirujuk `!task` ada).
2. `tools/build.ps1` / `tools/build.sh` — menjalankan validasi, lalu mengarsipkan **isi**
   `src/` (bukan foldernya) menjadi `.apbx`.
3. Hasil build tidak di-commit. Distribusi lewat GitHub Releases atau website.

Validasi otomatis ini penting karena playbook tidak bisa dijalankan di luar Windows; salah
ketik nama properti baru ketahuan saat Wizard gagal di tengah jalan.

---

## 11. Rencana pengujian di VMware

### 11.1 Persiapan VM

| Item | Setelan |
|---|---|
| Hypervisor | VMware Workstation |
| ISO | Windows 11 Pro terbaru (26H2) resmi dari Microsoft |
| CPU / RAM / Disk | 4 core / 8 GB / 64 GB (NVMe virtual) |
| Firmware | UEFI + Secure Boot, vTPM aktif |
| Akun | Akun lokal |
| VMware Tools | Dipasang **sebelum** snapshot dasar |

Urutan snapshot:

1. `S0-clean` — Windows baru terpasang, VMware Tools terpasang.
2. `S1-updated` — semua Windows Update selesai, sudah restart, tidak ada update menggantung.
3. `S2-baseline-measured` — metrik awal sudah dicatat. **Semua uji mulai dari sini.**
4. `S3-tgos-<versi>-<opsi>` — setelah playbook diterapkan.

Setiap percobaan dimulai dengan kembali ke `S2`. Jangan menerapkan playbook dua kali di
atas hasil sebelumnya kecuali memang sedang menguji upgrade.

### 11.2 Langkah uji

1. Catat metrik dasar di `S2` (tabel [bagian 1](#1-tujuan)).
2. Salin AME Wizard dan `TGOS-vX.Y.Z.apbx` ke VM.
3. Jalankan Wizard, seret `.apbx`, ikuti langkah syarat (termasuk mematikan Defender).
4. Pilih kombinasi opsi sesuai matriks di bawah, jalankan, tunggu restart.
5. Setelah login: tunggu 5 menit, catat metrik, jalankan checklist fungsi.
6. Simpan log AME dan hasilnya ke `docs/TESTING.md`.

### 11.3 Matriks opsi

| Run | Defender | Mitigasi | Update | Lainnya | Tujuan |
|---|---|---|---|---|---|
| A | enable | default | default | semua checkbox mati | Jalur paling aman — dasar perbandingan |
| B | disable | default | manual | default rencana | Konfigurasi yang paling mungkin dipakai |
| C | disable | disable | manual | semua checkbox nyala | Jalur paling agresif — mencari yang rusak |

### 11.4 Checklist fungsi setelah instalasi

- [ ] Boot normal, login normal, tidak ada pesan error.
- [ ] Jaringan: internet jalan, DNS jalan.
- [ ] Audio keluar.
- [ ] Settings terbuka di semua halaman utama.
- [ ] Start menu & pencarian aplikasi jalan.
- [ ] Microsoft Store terbuka dan bisa memasang satu aplikasi.
- [ ] `winget` jalan.
- [ ] Windows Update bisa memeriksa update secara manual.
- [ ] Bisa memasang: Steam, Discord, satu browser, driver GPU (di hardware asli).
- [ ] Pemasang .NET / Visual C++ Redistributable / DirectX jalan.
- [ ] `sfc /verifyonly` tanpa pelanggaran integritas.
- [ ] Event Viewer: tidak ada error berulang dari layanan yang dimatikan.
- [ ] Skrip pembalik di folder TGOS jalan dan efeknya benar setelah restart.
- [ ] Restart 3 kali berturut-turut tanpa masalah.

### 11.5 Batasan uji di VM

VM cocok untuk memastikan playbook **tidak merusak sistem** dan mengukur keringanan (RAM,
proses, layanan, disk). VM **tidak cocok** untuk mengukur FPS, frame time, latensi input,
HAGS, atau perilaku power plan, karena GPU dan timer-nya virtual. Semua klaim performa
gaming harus diukur di hardware asli pada fase beta.

Selain itu, beberapa anti-cheat menolak jalan di VM, jadi uji kompatibilitas game juga
menunggu hardware asli.

---

## 12. Roadmap

| Fase | Versi | Isi | Selesai bila |
|---|---|---|---|
| 0. Kerangka | `0.0.1` | `playbook.conf`, `main.yml` berisi cek kompatibilitas saja, skrip build & validasi | `.apbx` dimuat Wizard, cek edisi menolak non-Pro, tidak ada perubahan sistem |
| 1. Inti | `0.1.0` | Debloat, privasi, layanan, tugas terjadwal | Run A lolos checklist di 26H2 |
| 2. Performa | `0.2.0` | Modul performa + opsi daya | Run B lolos checklist |
| 3. Opsi keamanan | `0.3.0` | Defender, VBS, mitigasi, update + skrip pembalik | Run C lolos, semua pembalik terbukti jalan |
| 4. Komponen & tampilan | `0.4.0` | Edge, OneDrive, antarmuka, folder TGOS, branding | Checklist lolos di 24H2, 25H2, 26H2 |
| 5. Beta hardware asli | `0.9.x` | Benchmark, uji anti-cheat, uji 22H2/23H2, keputusan [8.5](#85-kandidat-yang-butuh-bukti-benchmark-dulu) | Data benchmark tercatat, tidak ada bug kritis |
| 6. Rilis | `1.0.0` | Dokumentasi pengguna, paket distribusi | Disetujui pemilik proyek |

Fase 0 sengaja kecil: tujuannya memastikan rantai build → Wizard → eksekusi bekerja
sebelum ada satu pun tweak yang ditambahkan.

---

## 13. Risiko & mitigasi

| Risiko | Dampak | Mitigasi |
|---|---|---|
| Update Windows mengembalikan atau bentrok dengan tweak | Sedang | Filter `builds:`, uji ulang tiap update fitur, opsi update manual |
| Menghapus terlalu banyak sampai fitur penting rusak | Tinggi | Daftar "tidak pernah disentuh" di [8.3](#83-layanan-30-servicesyml), matikan bukan hapus, checklist fungsi |
| Anti-cheat menolak jalan | Tinggi | Tidak menyentuh Secure Boot/TPM, uji game populer di fase beta, dokumentasikan kombinasi opsi yang aman |
| Pengguna terkena malware setelah Defender mati | Tinggi | Peringatan jelas di halaman opsi, skrip pengaktif kembali di folder TGOS |
| Salah ketik YAML baru ketahuan saat instalasi | Sedang | `tools/validate.py` wajib lolos sebelum build |
| Versi AME Wizard baru mengubah format | Sedang | Catat versi Wizard yang dipakai uji di `docs/TESTING.md` |
| Build Windows baru belum diuji | Sedang | `SupportedBuilds` eksplisit; build baru ditambah hanya setelah lolos uji |
| Hasil VM tidak mewakili hardware asli | Sedang | Fase 5 khusus hardware asli sebelum rilis |

---

## 14. Aturan Git

- Semua commit atas nama **tehgeii** saja. Tidak ada co-author dan tidak ada baris
  atribusi lain di pesan commit atau deskripsi pull request.
- Email commit memakai alamat noreply GitHub akun tehgeii, supaya commit tetap tertaut ke
  akun tanpa menampilkan email pribadi.
- Hasil build (`release/`, `*.apbx`, `*.7z`) dan password tidak pernah di-commit.
- Pesan commit singkat dengan awalan jenis: `docs:`, `feat:`, `fix:`, `build:`, `test:`.

---

## 15. Pertanyaan terbuka

1. **Password** — pilih opsi A, B, atau C di [bagian 3](#3-soal-password-apbx)?
2. **Default Defender** — default-nya mati atau aktif di halaman opsi?
3. **Edisi** — hanya `Professional`, atau varian Pro N / Workstation / Education ikut?
4. **Visibilitas repo** — private atau publik? (Menentukan apakah password arsip ada artinya.)
5. **Aplikasi TGO v2** — apakah TGOS memasang atau menautkan aplikasi TGO v2 di akhir
   instalasi? Kalau ya, dari mana installer-nya diambil?
6. **Branding** — ikon playbook (`playbook.png`), wallpaper, dan warna aksen: ada asetnya?
7. **Browser** — bila Edge dihapus, apakah Wizard menawarkan pemasangan browser lain?
8. **Bahasa** — teks di Wizard dan skrip TGOS pakai bahasa Indonesia, Inggris, atau keduanya?

---

## 16. Sumber

- Source code inti AME Wizard: `github.com/Ameliorated-LLC/trusted-uninstaller-cli`
  (parser aksi, field `playbook.conf`, daftar requirement, filter build/opsi).
- Dokumentasi developer AME: `docs.amelabs.net` (pengemasan `.apbx`, password `malte`).
- Playbook AtlasOS v0.6.0: `github.com/Atlas-OS/Atlas` (contoh `playbook.conf` nyata untuk
  build 26200 dan 26300).
- Blog Windows Insider & liputan rilis 26H2 (nomor build 26300).

Catatan: website `tgopremium.my.id` dan halaman `docs.amelabs.net` tidak bisa dibuka dari
lingkungan kerja saat dokumen ini ditulis (diblokir kebijakan jaringan), jadi branding dan
fitur TGO v2 belum dijadikan acuan. Isi dokumentasi AME diambil dari hasil pencarian dan
dicocokkan dengan source code-nya.
