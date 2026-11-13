# TGOS — Rencana Pengembangan Playbook

**TGOS (Tech Gameplay Operating System)** adalah playbook untuk AME Wizard yang mengubah
instalasi Windows 11 Pro menjadi OS gaming yang sangat ringan. Urutan prioritasnya:
**performa dulu, keamanan belakangan** — tetapi setiap pengorbanan keamanan dibuat sebagai
pilihan sadar pengguna, bukan sesuatu yang terjadi diam-diam.

| | |
|---|---|
| Status dokumen | Draf v3 — keputusan pemilik proyek, branding, dan acuan website TGO sudah masuk |
| Versi playbook saat ini | `0.1.0` — aplikasi bawaan + privasi; Fase 0 sudah lolos uji, `0.1.0` menunggu uji VM |
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
   pengubah dan pembalik di folder **TGOS Toolbox** setelah instalasi.
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
| `!registryValue:` | `path`, `value`, `data`, `type`, `operation` (`add`/`set`/`delete`), `scope` | `type`: `REG_SZ`, `REG_DWORD`, `REG_QWORD`, `REG_BINARY`, `REG_MULTI_SZ`, `REG_EXPAND_SZ`. `set` = hanya bila nilai sudah ada. Data `REG_DWORD`/`REG_QWORD` harus **desimal** (AME tidak menerima `0x...`). Nilai `HKCU` berlaku untuk semua pengguna kecuali `scope` diisi (`allUsers`, `activeUsers`, `defaultUser`, `currentUser`). |
| `!registryKey:` | `path`, `operation` (`delete`/`add`), `scope` | Default: `delete`. |
| `!service:` | `name`, `operation` (`change`/`stop`/`start`/`delete`/…), `startup`, `device` | Default: `delete` — **selalu tulis `operation` eksplisit.** |
| `!scheduledTask:` | `path`, `operation` (`disable`/`enable`/`delete`/`deleteFolder`) | Default: `delete` — tulis eksplisit. |
| `!appx:` | `name`, `type` (`family`/`package`/`app`), `operation` (`remove`/`clearCache`), `unregister` | Wildcard `*` boleh di awal, akhir, atau keduanya. Paket yang tidak ada dilewati tanpa error. TGOS hanya mengizinkan wildcard di akhir untuk penghapusan. |
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

**Keputusan pemilik proyek: Opsi A.** Skrip build sudah membuat kedua file:
`TGOS-vX.Y.Z.apbx` dan pembungkusnya `TGOS-vX.Y.Z.7z`.

Dua aturan yang dipakai:

- Password distribusi **tidak ditulis di repo** (kalau repo publik, password ikut publik).
  Skrip build membacanya dari variabel lingkungan `TGOS_DIST_PASSWORD`.
- Repo ini **publik** (keputusan pemilik), jadi source playbook-nya terbuka untuk siapa
  pun. Pembungkus `.7z` hanya menjaga unduhan hasil build, bukan isi playbook.

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
3. **Keamanan dikurangi lewat pilihan sadar, bukan diam-diam.** VBS dan mitigasi CPU
   ditawarkan di halaman opsi Wizard dengan penjelasan risikonya. Defender **tidak
   disentuh saat instalasi**; pengguna bisa mematikannya sendiri sesudahnya lewat
   TGOS Toolbox.
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
├─ assets/
│  └─ branding/                    ← logo TGO asli, ikon TGOS, wallpaper
├─ src/
│  ├─ playbook.conf
│  ├─ playbook.png                 ← ikon 256x256, dibuat tools/make-icon.py
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
│  │     └─ 90-finalize.yml        ← TGOS Toolbox, info instalasi, pembersihan
│  └─ Executables/
│     ├─ Scripts/                  ← skrip PowerShell yang dipanggil playbook (Common.ps1 = fungsi bersama)
│     └─ TGOS Toolbox/             ← disalin ke sistem: skrip pengubah & pembalik
├─ tools/
│  ├─ build.ps1                    ← build di Windows (butuh 7-Zip)
│  ├─ build.sh                     ← build di Linux/CI
│  ├─ validate.py                  ← cek XML + YAML terhadap skema aksi AME
│  ├─ make-icon.py                 ← membuat ikon TGOS dari logo TGO
│  ├─ make-tweaks-doc.py           ← membuat docs/TWEAKS.md dari YAML
│  ├─ Get-SystemSnapshot.ps1       ← potret sistem (dijalankan di Windows, hanya membaca)
│  ├─ compare-snapshots.py         ← membandingkan potret sebelum dan sesudah
│  └─ selftest.py                  ← memastikan validator & cek kompatibilitas benar
├─ docs/
│  ├─ TESTING.md                   ← checklist & hasil uji per versi
│  └─ TWEAKS.md                    ← daftar semua tweak + cara balik (dibuat otomatis)
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
| `Title` | `TGOS v<versi>` |
| `ShortDescription` | `Tech Gameplay Operating System for Windows 11 Pro` |
| `Version` | Mengikuti roadmap; saat ini `0.0.2` |
| `UniqueId` | UUID v4 baru, dibuat sekali |
| `SupportedBuilds` | `22621`, `22631`, `26100`, `26200`, `26300` |
| `Overhaul` | `true` mulai `0.1.0` (Fase 0 memakai `false` karena belum mengubah sistem) |
| `UseKernelDriver` | `false` |
| `EstimatedMinutes` | `15` (dikoreksi setelah uji) |
| `Website` | `https://tgopremium.my.id` |
| `Git` | Belum diisi. Wizard memakai field ini untuk mengambil update dari rilis repo dan tombol *Source Code*. Diisi di `0.1.0`, bersamaan dengan GitHub Release pertama. |

### 7.2 Requirements

| Requirement | Dipakai? | Alasan |
|---|---|---|
| `DefenderToggled` | Tidak | Keputusan pemilik: Defender tetap aktif selama instalasi. Terbukti di uji Fase 0: AME Beta menjalankan playbook tanpa meminta Defender dimatikan. Tetap diamati di `0.1.0` karena sekarang playbook benar-benar mengubah sistem; bila Defender memblokir, requirement ini terpaksa dipakai. |
| `NoAntivirus` | Ya (mulai `0.1.0`) | Antivirus pihak ketiga mengganggu modifikasi sistem. |
| `NoPendingUpdates` | Ya (mulai `0.1.0`) | Update yang menggantung bisa menimpa perubahan atau merusak servicing. |
| `PluggedIn` | Ya (sudah di Fase 0) | Mencegah laptop mati di tengah proses. |
| `Internet` | Tidak (0.1.0) | Belum ada yang diunduh. Ditambahkan bila nanti memasang software. |
| `Activation` | Tidak | Tidak relevan untuk uji VM. Dipertimbangkan untuk rilis. |

### 7.3 Halaman opsi (FeaturePages)

Kolom "Nama opsi" adalah yang dipakai di filter `option:` pada YAML. Default checkbox
diatur lewat atribut `IsChecked` (bawaan Wizard: tercentang); default radio lewat
`DefaultOption`. Halaman bisa dibuat bergantung pada opsi lain dengan `DependsOn`.

Tidak ada halaman Defender: Defender tetap aktif selama dan sesudah instalasi, dan hanya
bisa dimatikan pengguna lewat TGOS Toolbox.

Batas dari Wizard: satu halaman maksimal 4 opsi; 3 bila halaman punya `TopLine` atau
`BottomLine`; 2 bila punya keduanya.

**Halaman Aplikasi** (`CheckboxPage`) — sudah ada sejak `0.1.0`

| Pilihan | Nama opsi | Default |
|---|---|---|
| Remove Copilot and Widgets | `remove-ai-widgets` | ✔ |
| Remove Xbox app and Game Bar | `remove-xbox` | ✘ |

Recall dan analisis data AI selalu dimatikan lewat policy, tanpa opsi.

Halaman berikut baru direncanakan:

**Halaman 1 — Mitigasi CPU** (`RadioPage`, wajib)

| Pilihan | Nama opsi |
|---|---|
| Mitigasi default Windows | `mitigations-default` |
| Matikan semua mitigasi | `mitigations-disable` |

**Halaman 2 — Windows Update** (`RadioPage`, wajib)

| Pilihan | Nama opsi |
|---|---|
| Matikan update otomatis (tetap bisa manual) | `updates-manual` |
| Biarkan default | `updates-default` |

**Halaman 3 — Performa** (`CheckboxPage`)

| Pilihan | Nama opsi | Default |
|---|---|---|
| Matikan VBS / Core Isolation | `disable-vbs` | ✔ |
| Matikan hibernasi & Fast Startup | `disable-hibernation` | ✔ |
| Matikan penghematan daya (desktop) | `disable-power-saving` | ✔ |
| Matikan Windows Search indexing | `disable-indexing` | ✔ |

**Halaman 4 — Komponen** (`CheckboxPage`)

| Pilihan | Nama opsi | Default |
|---|---|---|
| Hapus Microsoft Edge | `remove-edge` | ✘ |
| Hapus OneDrive | `remove-onedrive` | ✔ |

Default radio rencana: `mitigations-default` dan `updates-manual`. Keduanya masih bisa
diubah pemilik proyek sebelum `0.3.0`.

---

## 8. Rancangan modul tweak

Kolom **Risiko** menilai kemungkinan merusak fungsi: R = rendah, S = sedang, T = tinggi.
Kolom **Balik** menandai apakah ada skrip pembalik di TGOS Toolbox.

### 8.1 Debloat aplikasi (`10-debloat-appx.yml`)

**Sudah dibuat di `0.1.0`.** Daftar persisnya ada di [docs/TWEAKS.md](docs/TWEAKS.md),
yang dibuat otomatis dari YAML.

Dihapus tanpa syarat (26 paket): News, Weather, Bing Search, Solitaire, Movies & TV,
Get Help, Tips, Feedback Hub, Quick Assist, Microsoft 365 hub, Outlook (new), Mail and
Calendar, People, To Do, Power Automate, Dev Home, Teams (lama dan baru), Clipchamp,
Maps, Phone Link, Sound Recorder, Clock, Sticky Notes, Family, Cortana.

Dipertahankan: Microsoft Store, App Installer (winget), VCLibs, .NET Native, UI.Xaml,
Notepad, Paint, Photos, Calculator, Snipping Tool, Terminal, Camera, **Media Player**,
Windows Security (UI), semua ekstensi codec, serta `XboxIdentityProvider` dan
`GamingServices`. Daftar ini ditulis sebagai `PROTECTED_APPX` di `tools/validate.py`:
validasi gagal bila ada aksi yang akan menghapus salah satunya.

Bersyarat: Xbox app & Game Bar (`remove-xbox`), Copilot & Widgets (`remove-ai-widgets`).

Penghapusan memakai aksi `!appx` bawaan AME. Apakah aplikasi yang dihapus cara ini bisa
dipasang lagi dari Store masih harus dibuktikan di uji VM; bila tidak, caranya diganti.

| Risiko | Balik |
|---|---|
| R | Lewat Store (menunggu bukti uji VM) |

### 8.2 Privasi & telemetri (`20-privacy.yml`)

**Sudah dibuat di `0.1.0`** (40 nilai registry; daftar persis di
[docs/TWEAKS.md](docs/TWEAKS.md)). Tabel di bawah adalah rancangan awalnya. Dua
penyimpangan dari rancangan: `DisableWindowsConsumerFeatures` tidak dipakai karena policy
itu hanya dipatuhi edisi Enterprise/Education (di Pro tidak berpengaruh), dan policy
Widgets hanya diterapkan bila opsi `remove-ai-widgets` dipilih.

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

Beberapa kandidat di atas (Nagle/`TcpAckFrequency`, dynamic tick, TSC sync) sudah ada di
aplikasi TGO v2 sebagai tweak Premium, dan website TGO menerbitkan hasil ujinya. Jadi
untuk TGOS keputusannya memakai metode ukur yang sama dengan TGO v2 (LatencyMon,
TimerBench, beban idle di Task Manager) di hardware asli: yang terbukti membantu masuk,
yang tidak terbukti tetap di luar default.

### 8.6 Opsi keamanan (`60-security-options.yml`)

Baris bertanda *Wizard* hanya jalan bila opsinya dipilih saat instalasi. Baris bertanda
*Toolbox* tidak pernah dijalankan playbook; hanya tersedia sebagai skrip sesudah instalasi.

| Opsi | Lewat | Yang dilakukan | Dampak keamanan | Balik |
|---|---|---|---|---|
| Matikan Defender | Toolbox | Mematikan proteksi real-time, layanan Defender, SmartScreen | Tidak ada antivirus. Malware dari cheat, crack, dan mod jadi ancaman nyata. | Ya |
| `disable-vbs` | Wizard | `EnableVirtualizationBasedSecurity=0`, HVCI `Enabled=0` | Proteksi kernel berkurang. Di banyak sistem ini memberi kenaikan performa terukur. | Ya |
| `mitigations-disable` | Wizard | `FeatureSettingsOverride=3`, `FeatureSettingsOverrideMask=3` | Rentan terhadap Spectre/Meltdown. Manfaatnya terutama di CPU lama; di CPU baru bisa nol atau negatif. | Ya |
| `updates-manual` | Wizard | Policy menunda update otomatis; update manual tetap bisa | Patch keamanan tertunda sampai pengguna memasangnya. | Ya |

Yang **tetap aktif** apa pun pilihannya: Windows Firewall, UAC, dan Secure Boot/TPM (tidak
disentuh sama sekali karena dibutuhkan anti-cheat).

Catatan soal mematikan Defender sesudah instalasi: di Windows 11, Tamper Protection
menolak perubahan pengaturan Defender dari skrip. Jadi skrip Toolbox tidak bisa
melakukannya sepenuhnya sendiri; pengguna harus mematikan Tamper Protection dulu di
Windows Security. Mekanisme pastinya (dan pembaliknya) dirancang dan dibuktikan di Fase 3,
bukan diasumsikan sekarang.

### 8.7 Komponen (`70-components.yml`)

| Opsi | Catatan |
|---|---|
| `remove-edge` | WebView2 Runtime **dipertahankan** — banyak launcher dan aplikasi bergantung padanya. Tanpa browser, pengguna harus memasang browser lain lewat `winget`. |
| `remove-onedrive` | Menjalankan uninstaller resmi dan membersihkan entri Explorer. |

### 8.8 Antarmuka (`80-interface.yml`)

Mode gelap, menu klik kanan klasik, taskbar tanpa Search/Task View/Widgets/Chat, File
Explorer membuka "This PC", ekstensi file ditampilkan.

Branding (aset di `assets/branding/`):

| Aset | File | Pemakaian |
|---|---|---|
| Logo TGO asli | `tgo-logo.png` (1024x1024) | Sumber; tidak diubah |
| Ikon TGOS | `tgos-icon.png` → `src/playbook.png` (256x256) | Logo TGO + garis merah + label `OS`; ikon playbook di Wizard |
| Wallpaper | `tgo-wallpaper.webp` (2000x1125) | Diterapkan di Fase 4, dikonversi ke PNG/JPG |

Warna mengikuti website TGO: latar `#05070d`, permukaan `#0f1522` / `#151c2c`, teks
`#e8edf7`, aksen biru `#3b82f6`, merah logo `#eb121c`. Aksen Windows TGOS memakai biru
itu supaya senada dengan web dan aplikasi.

Dua catatan: file wallpaper yang ada hanya 9 KB dan gradasinya bergaris, jadi perlu
file asli beresolusi tinggi sebelum Fase 4. Dan dari source code Wizard, ikon playbook
yang sudah diterapkan hanya ditampilkan bila playbook terverifikasi AME; apakah ikon
TGOS tampil saat memuat `.apbx` harus dilihat di uji VM.

### 8.9 Finalisasi (`90-finalize.yml`)

- Menyalin folder **TGOS Toolbox** ke `%SystemDrive%\TGOS Toolbox` dan membuat pintasan di
  Desktop. Isinya skrip berpasangan (matikan / aktifkan lagi) untuk: Defender, VBS,
  mitigasi CPU, update otomatis, indexing, hibernasi.
- Menulis `%ProgramData%\TGOS\install-info.txt` berisi versi TGOS, edisi, build, dan
  (mulai `0.1.0`) opsi yang dipilih. Bagian ini sudah ada sejak Fase 0.
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
src/  ──validate.py──▶  7z (password malte, format 7z)  ──▶  release/TGOS-vX.Y.Z.apbx
                                                                   │
                                     (opsional, opsi A bagian 3)   ▼
                              7z (password dari TGOS_DIST_PASSWORD, header terenkripsi)
                                                                   ▼
                                                      release/TGOS-vX.Y.Z.7z
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

1. Catat metrik dasar di `S2` dengan `tools/Get-SystemSnapshot.ps1 -Label before`
   (mengisi tabel [bagian 1](#1-tujuan)); ulangi sesudah instalasi dan bandingkan dengan
   `tools/compare-snapshots.py`.
2. Salin AME Wizard dan `TGOS-vX.Y.Z.apbx` ke VM.
3. Jalankan Wizard, seret `.apbx`, ikuti langkah syarat. Defender dibiarkan aktif; catat
   bila Wizard atau Defender memblokir sesuatu.
4. Pilih kombinasi opsi sesuai matriks di bawah, jalankan, tunggu restart.
5. Setelah login: tunggu 5 menit, catat metrik, jalankan checklist fungsi.
6. Simpan log AME dan hasilnya ke `docs/TESTING.md`.

### 11.3 Matriks opsi

| Run | Mitigasi | Update | Checkbox | Tujuan |
|---|---|---|---|---|
| A | default | default | semua mati | Jalur paling aman — dasar perbandingan |
| B | default | manual | default rencana | Konfigurasi yang paling mungkin dipakai |
| C | disable | manual | semua nyala | Jalur paling agresif — mencari yang rusak |

Sesudah Run B dan C: jalankan skrip Toolbox "matikan Defender" lalu "aktifkan lagi", dan
ulangi checklist fungsi di tiap keadaan.

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
- [ ] Tiap pasangan skrip di TGOS Toolbox jalan dan efeknya benar setelah restart.
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
| 0. Kerangka | `0.0.1`–`0.0.2` | `playbook.conf`, cek kompatibilitas, pencatat info instalasi, branding, skrip build & validasi. | **Lolos** di AME Beta, 14 Nov 2026 ([docs/TESTING.md](docs/TESTING.md)). Uji tolak di edisi bukan Pro masih terutang. |
| 1a. Aplikasi & privasi | `0.1.0` | Hapus aplikasi bawaan, privasi lewat registry, restore point, potret sistem. **Sudah dibuat; menunggu uji VM.** | Uji A dan B lolos checklist di 26H2 |
| 1b. Layanan & tugas | `0.1.1` | Layanan dan tugas terjadwal, disusun dari potret sistem nyata hasil uji `0.1.0` | Run A lolos checklist di 26H2 |
| 2. Performa | `0.2.0` | Modul performa + opsi daya | Run B lolos checklist |
| 3. Opsi keamanan & Toolbox | `0.3.0` | VBS, mitigasi, update; TGOS Toolbox termasuk pengubah Defender | Run C lolos, semua pasangan skrip Toolbox terbukti jalan |
| 4. Komponen & tampilan | `0.4.0` | Edge, OneDrive, antarmuka, branding | Checklist lolos di 24H2, 25H2, 26H2 |
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
| Pengguna terkena malware setelah Defender mati | Tinggi | Defender aktif secara default; skrip Toolbox menampilkan peringatan dan menyediakan pengaktif kembali |
| Defender aktif memblokir AME Wizard saat instalasi | Sedang | Diuji sejak Fase 0; cadangannya requirement `DefenderToggled` |
| Salah ketik YAML baru ketahuan saat instalasi | Sedang | `tools/validate.py` wajib lolos sebelum build |
| Versi AME Wizard baru mengubah format | Sedang | Catat versi Wizard yang dipakai uji di `docs/TESTING.md` |
| Build Windows baru belum diuji | Sedang | `SupportedBuilds` eksplisit; build baru ditambah hanya setelah lolos uji |
| Hasil VM tidak mewakili hardware asli | Sedang | Fase 5 khusus hardware asli sebelum rilis |

---

## 14. Aturan Git

- Branch utama: `main`. Semua commit atas nama **tehgeii** saja. Tidak ada co-author dan tidak ada baris
  atribusi lain di pesan commit atau deskripsi pull request.
- Email commit memakai alamat noreply GitHub akun tehgeii, supaya commit tetap tertaut ke
  akun tanpa menampilkan email pribadi.
- Hasil build (`release/`, `*.apbx`, `*.7z`) dan password tidak pernah di-commit.
- Pesan commit singkat dengan awalan jenis: `docs:`, `feat:`, `fix:`, `build:`, `test:`.

---

## 15. Pertanyaan terbuka

Sudah diputuskan:

| Hal | Keputusan |
|---|---|
| Password | Opsi A: `.apbx` dibungkus `.7z` berpassword |
| Defender | Tetap aktif saat instalasi; diubah pengguna lewat TGOS Toolbox |
| Branch utama | `main` |
| Edisi | Hanya `Professional`; Pro N, Workstation, Education ditolak |
| Visibilitas repo | Publik |
| Branding | Ikon TGOS = logo TGO + label `OS`; wallpaper `PROJECT TGO` |
| Bahasa | Teks pengguna bahasa Inggris; deskripsi Wizard ditambah ringkasan Indonesia. Dokumen repo tetap Indonesia |
| Aplikasi TGO v2 | Ditunda; tidak dipasang atau ditautkan TGOS untuk sekarang |

Masih terbuka:

1. **Browser** — bila Edge dihapus, apakah Wizard menawarkan pemasangan browser lain?
2. **Wallpaper** — file asli beresolusi tinggi (lihat [8.8](#88-antarmuka-80-interfaceyml)).

---

## 16. Sumber

- Source code inti AME Wizard: `github.com/Ameliorated-LLC/trusted-uninstaller-cli`
  (parser aksi, field `playbook.conf`, daftar requirement, filter build/opsi).
- Dokumentasi developer AME: `docs.amelabs.net` (pengemasan `.apbx`, password `malte`).
- Playbook AtlasOS v0.6.0: `github.com/Atlas-OS/Atlas` (contoh `playbook.conf` nyata untuk
  build 26200 dan 26300).
- Blog Windows Insider & liputan rilis 26H2 (nomor build 26300).
- Website TGO: `tgopremium.my.id` (dibaca saja, tidak diubah).

### Yang dipakai dari website TGO

- **Nama.** TGO = *Tech Gameplay Optimizer* (aplikasi); TGOS = *Tech Gameplay Operating
  System* (playbook). Keduanya bagian dari ekosistem Tech Gameplay Indonesia.
- **Prinsip yang sama.** TGO v2 menjanjikan: tidak ada yang berubah tanpa dipilih, tiap
  tweak punya penjelasan dan label risiko, tweak berisiko (Defender, UAC, Windows Update)
  minta konfirmasi, dan perubahan bisa dikembalikan. TGOS mengikuti prinsip itu
  ([bagian 5](#5-prinsip-desain)).
- **Metode benchmark.** Website menerbitkan uji LatencyMon, TimerBench, dan beban idle
  Task Manager (5 menit setelah boot) di Windows 11 Pro 26H2 build 26300. TGOS memakai
  metode dan build yang sama supaya hasilnya bisa dibandingkan.
- **Pembanding idle.** Angka TGO v2 di halaman itu: RAM 4,3 GB → 2,5 GB dan 164 → 79
  proses, dengan Defender, UAC, dan Windows Update dimatikan. Target TGOS di
  [bagian 1](#1-tujuan) diukur dengan Defender **aktif**, jadi tidak setara langsung.
- **Warna dan font.** Lihat [8.8](#88-antarmuka-80-interfaceyml).

### Yang dikonfirmasi dari dokumentasi AME

- `SupportedBuilds` bertipe *integer array*; tidak ada sintaks rentang.
- Field wajib: `Name`, `Username`, `UniqueId`, `ShortDescription`, `Title`,
  `Description`, `Details`, `Version`.
- Pengemasan: format 7z, password `malte`. Menurut dokumentasinya, enkripsi itu supaya
  browser dan antivirus tidak memindai executable di dalam arsip.
- `ProductCode` dan `Website` dipakai untuk playbook yang diverifikasi AME.
- Ukuran `playbook.png` tidak didokumentasikan; 256x256 mengikuti ikon AtlasOS.
