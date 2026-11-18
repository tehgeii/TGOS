# TGOS — Rencana Pengembangan Playbook

**TGOS (Tech Gameplay Operating System)** adalah playbook untuk AME Wizard yang mengubah
instalasi Windows 11 Pro menjadi OS gaming yang sangat ringan. Urutan prioritasnya:
**performa dulu, keamanan belakangan** — tetapi setiap pengorbanan keamanan dibuat sebagai
pilihan sadar pengguna, bukan sesuatu yang terjadi diam-diam.

| | |
|---|---|
| Status dokumen | v6 — `1.0.0` |
| Versi playbook saat ini | `1.0.0` — perbaikan dari uji VM `0.9.1`, pilihan browser, opsi baru; lolos uji mesin AME di Windows Server 2025 dan Windows 11 Enterprise 25H2; menunggu uji ulang di VM Windows 11 Pro; belum diuji di hardware asli |
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

Angka target ini tebakan awal yang masuk akal, **bukan** hasil pengukuran.

Hasil ukur pertama (`0.9.0`, Windows 11 Pro 26H2 di VMware, semua opsi dicentang):
proses −18%, RAM −30%, layanan berjalan −15%, disk −5,3 GB. Target RAM tercapai; target
proses dan layanan **belum**. Potret "sesudah" diambil sekitar 2,5 menit setelah boot,
jadi angka itu indikatif.

Hasil ukur kedua (`0.9.1`, VM yang sama, semua opsi): proses 149 → 120 (−19%), RAM
3.345 → 2.285 MB (−32%), layanan berjalan 97 → 84 (−13%), disk 30,0 → 24,5 GB. Target
RAM tercapai; target proses (−35%) dan layanan (−30%) **tidak**, dan dengan cara yang
dipakai TGOS (mematikan, bukan mencabut komponen Windows) kecil kemungkinan tercapai:
sebagian besar proses dan layanan yang tersisa adalah inti Windows, driver, Defender, dan
VMware Tools. Opsi *Trim extra services* di `1.0.0` mematikan sekitar 6 layanan lagi.
Rincian di [docs/TESTING.md](docs/TESTING.md#catatan-hasil).

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

Ruang tampil teks di Wizard terbatas; yang lebih panjang dipotong dengan "...". Batas
berikut diukur dari screenshot uji `0.9.0` (AME Beta 0.8.4), diambil sedikit di bawah
batas sebenarnya karena font-nya proporsional, dan dijaga `tools/validate.py`:

| Teks | Ruang |
|---|---|
| `ShortDescription` | 2 baris x 20 karakter |
| `Description` | 5 baris x 44 karakter, baris kosong ikut dihitung |
| `Description` halaman opsi | 2 baris x 44 karakter |
| Teks opsi | 44 karakter |
| `!writeStatus` | 22 karakter |

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

### 2.4 Runner command-line AME

Selain Wizard, AME punya runner tanpa antarmuka: `TrustedUninstaller.CLI.exe "<folder
playbook hasil ekstrak>" opsi1 opsi2 ...` (rilis `CLI-Standalone.zip` di repo
`trusted-uninstaller-cli`). Runner ini dipakai TGOS untuk uji otomatis. Yang ditemukan
saat memakainya (versi 0.8.4):

- Tidak butuh interaksi selama playbook tidak punya requirement Defender.
- **Gagal bila tidak ada opsi yang dikirim**, jadi daftar opsi selalu dikirim eksplisit.
- Tidak memeriksa `SupportedBuilds` maupun requirement lain; itu tugas Wizard.
- `!service` dengan `operation: change` hanya menulis nilai `Start` layanan yang ada,
  jadi layanan yang tidak ada di sebuah build dilewati dengan aman.
- `!scheduledTask` dengan `operation: disable` **gagal bila tugasnya tidak ada**. Karena
  daftar tugas berbeda antar-build, TGOS menonaktifkan tugas lewat skrip sendiri.
- Log mesin ditulis ke `Output.txt` di folder kerjanya.

Yang terbukti saat runner itu menjalankan TGOS `0.9.0` di Windows 11 (Enterprise 25H2,
build 26200) pada uji otomatis:

- Aksi `!appx` benar-benar menghapus aplikasi bawaan (106 paket menjadi 87 dengan opsi
  bawaan, 83 dengan semua opsi).
- OneDrive terhapus lewat uninstaller resminya yang dijalankan sebagai pengguna aktif.
- Edge terhapus lewat uninstaller-nya sendiri, WebView2 tetap ada. Opsinya tetap
  berlabel eksperimental karena Microsoft bisa menolaknya di build atau wilayah lain.
- Toolbox menolak mematikan Defender selama Tamper Protection aktif.
- Restore point bisa dibuat dari skrip yang berjalan sebagai TrustedInstaller.
- Defender dengan proteksi real-time aktif tidak menghalangi playbook, dan tetap aktif
  sesudahnya. Requirement `DefenderToggled` tidak diperlukan.
- Tidak ada penulisan registry TGOS yang ditolak Windows.

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
├─ .github/workflows/test.yml      ← uji otomatis: lint + mesin AME di Windows
├─ assets/branding/                ← logo TGO asli, ikon TGOS, wallpaper
├─ src/                            ← isi .apbx
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
│  │     ├─ 70-components.yml      ← OneDrive, Edge
│  │     ├─ 80-interface.yml
│  │     └─ 90-finalize.yml        ← Toolbox, catatan instalasi, pemeriksaan diri
│  └─ Executables/
│     ├─ Scripts/                  ← skrip yang dipanggil playbook (Common.ps1 = fungsi bersama)
│     ├─ TGOS/                     ← data: daftar tugas terjadwal, wallpaper
│     └─ TGOS Toolbox/             ← disalin ke C:\TGOS Toolbox
│        ├─ *.cmd                  ← pasangan Turn OFF / Turn ON, Collect TGOS Report
│        └─ Support/               ← Set-TgosFeature, Test-TgosResult, Collect-TgosReport,
│                                    Get-SystemSnapshot, expected-state.json
├─ tools/
│  ├─ validate.py                  ← cek format AME + aturan pengaman TGOS
│  ├─ selftest.py                  ← memastikan validator & file turunan benar
│  ├─ build.ps1 / build.sh         ← membuat .apbx dan pembungkus .7z
│  ├─ make-expected-state.py       ← YAML → expected-state.json
│  ├─ make-tweaks-doc.py           ← YAML → docs/TWEAKS.md
│  ├─ make-icon.py                 ← logo TGO → ikon TGOS
│  ├─ compare-snapshots.py         ← membandingkan potret sebelum dan sesudah
│  └─ ci/Test-Engine.ps1           ← uji lewat mesin AME (hanya di GitHub Actions)
├─ docs/
│  ├─ TESTING.md                   ← tiga lapis pengujian dan catatan hasil
│  └─ TWEAKS.md                    ← semua tweak + cara balik (dibuat otomatis)
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
| `DefenderToggled` | Tidak | Keputusan pemilik: Defender tetap aktif selama instalasi. Terbukti dua kali: AME Beta menjalankan kerangka Fase 0 tanpa meminta Defender dimatikan, dan uji otomatis di Windows 11 menjalankan `0.9.0` penuh dengan proteksi real-time aktif. |
| `NoAntivirus` | Ya (mulai `0.1.0`) | Antivirus pihak ketiga mengganggu modifikasi sistem. |
| `NoPendingUpdates` | Ya (mulai `0.1.0`) | Update yang menggantung bisa menimpa perubahan atau merusak servicing. |
| `PluggedIn` | Ya (sudah di Fase 0) | Mencegah laptop mati di tengah proses. |
| `Internet` | Tidak | Mulai `1.0.0` playbook bisa mengunduh software pilihan, tetapi internet tidak diwajibkan: tanpa internet unduhan dilewati, playbook tetap selesai, dan pemasangan bisa diulang dari Toolbox. |
| `Activation` | Tidak | Tidak relevan untuk uji VM. Dipertimbangkan untuk rilis. |

### 7.3 Halaman opsi (FeaturePages)

Batas dari Wizard: satu halaman maksimal 4 opsi; 3 bila halaman punya `TopLine` atau
`BottomLine`; 2 bila punya keduanya. Default checkbox lewat `IsChecked`, default radio
lewat `DefaultOption`. Kolom "Nama opsi" dipakai di filter `option:` pada YAML.

Susunan `1.0.0` (revisi kedua; ✔ = bawaan tercentang):

| # | Halaman | Pilihan | Nama opsi | Default |
|---|---|---|---|---|
| 1 | Komponen (`CheckboxPage`) | Remove Copilot and Widgets | `remove-ai-widgets` | ✔ |
| | | Remove OneDrive | `remove-onedrive` | ✔ |
| | | Remove Xbox app and turn Game Bar off | `remove-xbox` | ✘ |
| | | Remove Microsoft Store (hard to undo) | `remove-store` | ✘ |
| 2 | Browser (`RadioImagePage`) | Brave | `browser-brave` | bawaan |
| | | Chrome | `browser-chrome` | |
| | | Firefox | `browser-firefox` | |
| | | None | (tidak mengirim opsi) | |
| 3 | Software (`CheckboxPage`) | Install 7-Zip | `install-7zip` | ✔ |
| | | Install game runtimes (VC++, DirectX, XNA) | `install-runtimes` | ✔ |
| | | Install .NET for older games and tools | `install-dotnet` | ✔ |
| | | Remove Microsoft Edge | `remove-edge` | ✘ |
| 4 | Launcher game (`CheckboxPage`) | Steam | `install-steam` | ✘ |
| | | Epic Games Launcher | `install-epic` | ✘ |
| | | EA app | `install-ea` | ✘ |
| | | Ubisoft Connect | `install-ubisoft` | ✘ |
| 5 | Aplikasi (`CheckboxPage`, per pengguna) | Discord | `install-discord` | ✘ |
| | | Spotify | `install-spotify` | ✘ |
| 6 | Daya (`CheckboxPage`) | Ultimate Performance plan (not for laptops) | `disable-power-saving` | ✔ |
| | | Disable CPU core parking (not for laptops) | `disable-core-parking` | ✔ |
| | | Disable hibernation and Fast Startup | `disable-hibernation` | ✔ |
| | | Disable search indexing | `disable-indexing` | ✔ |
| 7 | Sistem (`CheckboxPage`) | Disable Core Isolation (VBS) | `disable-vbs` | ✔ |
| | | Disable animations | `disable-animations` | ✔ |
| | | Trim extra services (printing, discovery) | `trim-services` | ✘ |
| | | Block background apps (Store apps) | `block-background-apps` | ✔ |
| 8 | Tampilan (`CheckboxPage`) | Classic right-click menu | `classic-context-menu` | ✔ |
| | | Taskbar icons on the left | `taskbar-left` | ✘ |
| | | Add End task to the taskbar menu | `taskbar-end-task` | ✔ |
| | | Skip the lock screen (sign-in stays) | `skip-lock-screen` | ✘ |
| 9 | Bersih-bersih (`CheckboxPage`) | Deep clean at the end | `deep-clean` | ✔ |
| | | Deep clean+: Windows.old and ResetBase | `deep-clean-plus` | ✘ |
| | | Block driver updates from Windows Update | `block-driver-updates` | ✘ |
| 10 | Mitigasi CPU (`RadioPage`, wajib) | Keep default / Disable | `mitigations-default` / `mitigations-disable` | default |
| 11 | Update Windows (`RadioPage`, wajib) | Pause / Manual / Automatic | `updates-pause` / `updates-manual` / `updates-default` | pause |

Keputusan pemilik untuk revisi kedua: Pause jadi bawaan dan ditahan sampai dilanjutkan
sendiri (~10 tahun); Game Bar dimatikan total hanya bila opsi Xbox dicentang; semua
launcher dan aplikasi bawaan tidak tercentang; lewati layar kunci bawaan tidak
tercentang; Deep clean+ dipisah dari Deep clean karena tidak bisa dibatalkan.

Halaman browser memakai `RadioImagePage`: satu gambar PNG setinggi 128 piksel per opsi
di folder `Images/` playbook, di atas gradasi dua warna, dan opsi `None="true"` yang tidak
punya nama. Gambarnya logo resmi tiap browser, dari koleksi
[alrra/browser-logos](https://github.com/alrra/browser-logos) (sumber 512 px di
`assets/branding/browser-logos/`, beserta catatan bahwa logo itu merek dagang
pemiliknya), diperkecil ke 128 px oleh `tools/make-option-images.py`. Ketiga kotak memakai
gradasi gelap TGO yang sama, `#1B2232` ke `#2C3650` (keputusan pemilik; build pertama
1.0.0 memakai inisial huruf di atas warna tiap browser, dan itu terlihat kurang rapi).

Yang sengaja tidak dijadikan opsi: telemetri (selalu dimatikan sejauh mungkin, tanpa
memblokir jaringan) dan Windows Defender (tidak disentuh playbook; hanya lewat Toolbox).

---

## 8. Rancangan modul tweak

> **Semua modul di bagian ini sudah dibuat di `0.9.0`.** Daftar persis apa yang
> diterapkan ada di [docs/TWEAKS.md](docs/TWEAKS.md), yang dibuat otomatis dari YAML.
> Subbagian di bawah adalah rancangan awalnya dan alasan di baliknya. Yang berbeda dari
> rancangan:
>
> - Tugas terjadwal dinonaktifkan lewat skrip, bukan aksi `!scheduledTask` (lihat 2.4).
> - Layanan Xbox dan geolokasi (`lfsvc`) tidak disentuh.
> - Policy `AllowGameDVR` hanya dipakai bersama opsi `remove-xbox` (Game Bar sudah dihapus);
>   tanpa opsi itu perekaman tetap bisa dinyalakan pengguna.
> - Menu klik kanan klasik tidak dikerjakan. Taskbar baru diatur di `0.9.1`
>   (lihat [8.8](#88-antarmuka-80-interfaceyml)); tombol Widgets tidak ditulis karena
>   nilainya dilindungi Windows.
> - Pembersihan komponen (`DISM /StartComponentCleanup`) tidak dijalankan.
> - "Matikan Defender" di Toolbox mematikan pemindaian lewat policy; layanan Defender
>   tidak dicabut.
> - Hapus Edge berstatus eksperimental dan default mati.

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

Penghapusan memakai aksi `!appx` bawaan AME, dan terbukti bekerja di Windows 11 pada uji
otomatis. Apakah aplikasi yang dihapus cara ini bisa dipasang lagi dari Store masih harus
dibuktikan di uji VM; bila tidak, caranya diganti.

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

Perekam otomatis telemetri (`AutoLogger-Diagtrack-Listener`, `SQMLogger`) dimatikan di
modul layanan, **sesudah** DiagTrack dihentikan. Di uji VM build pertama 1.0.0 nilai
`Start` perekam itu ditulis di modul privasi saat DiagTrack masih berjalan, dan sudah
hilang setelah restart: DiagTrack menulis ulang konfigurasi perekamnya sendiri saat
dimatikan ketika shutdown. Karena aksi `!service` hanya mengubah Startup type, DiagTrack
dihentikan oleh skrip kecil `Stop-DisabledServices.ps1`, yang hanya menghentikan layanan
yang sudah Disabled.

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
| Inventaris & kesehatan perangkat | `InventorySvc`, `whesvc` | R | Ditambah di `0.9.1` dari potret 26H2: keduanya berjalan otomatis. |
| AI Fabric | `WSAIFabricSvc` | S | Dijadikan Manual (3) pada opsi `remove-ai-widgets`. |

Dari potret 26H2 juga terlihat `PcaSvc`, `DPS`, `camsvc`, dan `CDPSvc` berjalan. Keempatnya
sengaja **tidak** disentuh: dipakai pemecah masalah kompatibilitas, diagnostik jaringan,
izin kamera/mikrofon, dan berbagi antarperangkat.

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

Dua temuan dari uji `0.9.0` di Windows 11 Pro 26H2:

- **Edge.** Uninstaller Edge (`setup.exe --uninstall`) keluar dengan kode 93 tanpa
  menghapus apa pun, padahal di Enterprise dan Server ia bekerja. `0.9.1` mencoba dua
  cara dari pengamatan komunitas: berkas penanda Edge lama di `SystemApps`, lalu
  menjalankan uninstaller tanpa variabel `windir` (hanya untuk proses itu). Keduanya
  bukan cara resmi dan bisa berhenti bekerja; opsi ini tetap eksperimental dan tidak
  fatal. Baik Edge terhapus maupun tidak, Startup Boost dan mode latarnya dimatikan
  lewat policy.
- **OneDrive.** Uninstaller-nya meminta hak admin. Dijalankan sebagai pengguna biasa
  (`runas: currentUser`) Windows menampilkan prompt UAC di tengah instalasi, jadi
  sejak `0.9.1` dipakai `runas: currentUserElevated`.

Hasil uji `0.9.1` di VM yang sama: Edge **terhapus** pada cara pertama (kode keluar 19),
OneDrive terhapus dalam 10 detik tanpa prompt. Label "experimental" pada opsi Edge
dicabut di `1.0.0`; update Windows tetap bisa memasang Edge kembali.

Temuan dari uji `0.9.1`, ditangani di `1.0.0`:

- **Copilot bukan paket Store di 26H2.** Paket `Microsoft.Copilot` tidak ada. Copilot
  adalah program biasa di `%ProgramFiles(x86)%\Microsoft\Copilot` (1,7 GB), terdaftar di
  `...\Uninstall\Microsoft Copilot` dengan
  `copilot_setup.exe --uninstall --mscopilot --channel=stable --system-level`. Identitas
  aplikasinya di Start dan taskbar adalah paket `Microsoft.MicrosoftOfficeHub`
  (`CopilotAppHost`). `0.9.1` menghapus paket itu sebagai "Microsoft 365" dan
  meninggalkan programnya. `1.0.0`: `Remove-Copilot.ps1` menjalankan uninstaller-nya
  lebih dulu, dengan teknik yang sama seperti Edge, dan paket OfficeHub pindah ke opsi
  Copilot. Belum terbukti: runner uji tidak punya program itu.
- **Pengaman browser.** Sejak `1.0.0` playbook bisa memasang browser. Bila browser yang
  dipilih tidak terpasang (mis. unduhan gagal), `Remove-Edge.ps1` tidak menghapus Edge.

Software pilihan (`05-software.yml`, `Install-Software.ps1`) diunduh dari sumber resmi:
Brave (rilis GitHub Brave), Chrome (MSI enterprise `dl.google.com`), Firefox
(`download.mozilla.org`), Visual C++ (`aka.ms`), DirectX (`download.microsoft.com`),
7-Zip (rilis resmi `ip7z/7zip` di GitHub). Tanda tangan Authenticode tiap file harus sah
dan penerbitnya harus cocok sebelum dijalankan. Pengecualian: installer 7-Zip tidak
ditandatangani pembuatnya, jadi filenya dicocokkan dengan SHA256 yang tercantum di
manifest winget Microsoft (`microsoft/winget-pkgs`) untuk versi itu, ditambah nama produk
dan versi. Bila manifest versi baru belum terbit, hanya nama dan versi yang diperiksa, dan
itu dicatat di log.

Pelajaran dari uji otomatis sebelum rilis `1.0.0` (semuanya diperbaiki sebelum rilis):

- **Brave.** `BraveBrowserStandaloneSilentSetup.exe` memasang **per pengguna**
  ([issue Brave #18711](https://github.com/brave/brave-browser/issues/18711)). Dijalankan
  playbook (sebagai sistem), Brave masuk ke profil SYSTEM yang tidak terlihat dan uji
  menyatakannya tidak terpasang. Yang benar untuk semua pengguna adalah
  `BraveBrowserStandaloneSetup.exe /silent /install`, sama dengan manifest winget
  `Brave.Brave` (scope machine). Installer itu juga memasang updater Brave, jadi Brave
  tetap update otomatis.
- **7-Zip.** Versi semula dibaca dari tautan pertama di halaman 7-zip.org, dan di uji
  menghasilkan 7-Zip 23.01 yang terpasang menimpa 26.05. Sekarang versi dibaca dari
  `releases/latest` GitHub (tidak pernah pre-release), dan **TGOS tidak pernah memasang
  7-Zip yang lebih lama dari yang sudah terpasang**. Aturan ini sempat juga dipasang
  untuk Firefox, dan uji menunjukkan itu salah: installer Firefox membawa nomor versi
  installer-nya sendiri (18.5), bukan versi Firefox (160.0), sehingga Firefox tidak
  pernah dipasang ulang. Untuk browser aturan itu dicabut; browser memperbarui dirinya
  sendiri.
- **Konteks pemasangan.** Image runner uji sudah berisi Chrome, Firefox, dan 7-Zip,
  sehingga pemasangan oleh playbook (sebagai sistem) untuk ketiganya semula tidak
  teruji. Uji sekarang mencopot program itu dulu.
- **Tombol Toolbox *Extra Services*.** Menulis nilai `Start` langsung ke registry
  ditolak untuk Administrator di sebagian layanan ("Requested registry access is not
  allowed"); playbook tidak terkena karena berjalan sebagai TrustedInstaller. Toolbox
  sekarang memakai `sc.exe config` (Service Control Manager), menangani tiap layanan
  sendiri, dan menyebut yang gagal.
- **Microsoft Store.** `wsreset -i` di runner Windows 11 keluar dengan kode 0 tetapi
  Store tidak kembali dalam 5 menit. Opsi hapus Store diberi label *hard to undo*.
- **DirectX** hanya dipasang di Windows x64. Di runner uji Windows 11 ARM64 installernya
  gagal (kode -9); di PC sungguhan TGOS sudah menolak ARM64 di langkah pertama.

Pelajaran dari uji VM build pertama `1.0.0`:

- **DirectX.** Installer web `dxwebsetup.exe /Q` menampilkan jendela "Installing
  Microsoft DirectX" di tengah instalasi dan macet sampai batas 15 menit. Sekarang
  dipakai paket lengkap resmi `directx_Jun2010_redist.exe` (~96 MB, alamat yang sama
  dengan paket Chocolatey dan npackd): diekstrak dengan `/Q:A /C /T:<folder>`, lalu
  `DXSETUP.exe /silent`, mode senyap yang didokumentasikan Microsoft untuk installer
  game. Paket itu self-extractor IExpress; dengan `/Q` saja ia masih menampilkan jendela
  progres "DirectX June 2010 SDK" (tertangkap pemantau jendela di uji otomatis), `/Q:A`
  menyembunyikan semuanya. Pemeriksaan: tanda tangan Microsoft pada paket, SHA256 paket
  harus `053F76DC...F89C73B` (dikunci di skrip; sama dengan checksum paket Chocolatey
  `directx`, file ini tidak berubah sejak 2010), lalu tanda tangan Microsoft pada
  `DXSETUP.exe` hasil ekstraknya. SHA256 tiap file yang lolos pemeriksaan dicatat di
  log.

### 8.8 Antarmuka (`80-interface.yml`)

Mode gelap, File Explorer membuka "This PC", ekstensi file ditampilkan. Wallpaper dan
mode gelap baru tampil setelah restart.

Taskbar: pencarian jadi ikon (`SearchboxTaskbarMode = 1`), tombol Task View
disembunyikan (`ShowTaskViewButton = 0`). Tombol Widgets tidak ditulis (nilainya
dilindungi Windows); Widgets dimatikan lewat policy.

Pin taskbar dan Start (`Set-ShellLayout.ps1`, sejak `1.0.0`). Di `0.9.1` pin hanya diatur
lewat policy layout taskbar (`StartLayoutFile`, `PinListPlacement="Replace"`), dan uji VM
menunjukkan itu **tidak** membuang pin yang sudah tersimpan di profil: pin Copilot yang
mati tetap tampil sebagai kotak abu-abu. Pin itu tidak punya file pintasan; ia tersimpan
di registry `HKCU\...\Explorer\Taskband`. Jadi sekarang:

- Layout taskbar ditulis saat instalasi sesuai keadaan: File Explorer, browser yang
  terpasang (Edge bila tidak ada yang lain), Microsoft Store (bila tidak dihapus).
- Pin Start ditulis lewat policy `ConfigureStartPins`: File Explorer, Settings, Store,
  browser, Notepad, Calculator, Terminal.
- Explorer dihentikan, kunci `Taskband`, file pintasan pin di
  `...\Quick Launch\User Pinned\TaskBar` (bukan subfolder `ImplicitAppShortcuts`), dan
  file `start*.bin` tiap profil dihapus, lalu Explorer dijalankan lagi, sehingga Windows
  menyusun keduanya dari layout di atas. Pintasan pin lama ikut dihapus karena di uji VM
  build pertama 1.0.0 Windows membuat salinan di sebelahnya (`File Explorer (2).lnk`).
  **Pin buatan pengguna ikut hilang** (keputusan pemilik).
- Bagian Recent/rekomendasi di Start disembunyikan.

Belum terbukti: runner uji tidak punya kunci `Taskband`, dan satu sumber menyebut policy
pin Start tidak berlaku untuk profil yang sudah ada (itu sebabnya `start*.bin` dihapus).
Hasilnya baru terlihat di uji VM.

Opsi tampilan (`1.0.0`): menu klik kanan klasik (kunci kosong
`{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32`) dan taskbar rata kiri
(`TaskbarAl = 0`). Warna aksen Windows dijadikan biru TGO, dan Settings > About
menampilkan "TGOS".

Di uji otomatis Windows 11, Windows menolak satu penulisan registry langsung
(`UnauthorizedAccessException`; paling mungkin salah satu dari dua nilai taskbar itu), lalu
mesin AME mengulanginya dengan cara cadangannya sendiri dan nilainya tertulis. Bila di
Windows 11 Pro nilainya ternyata tidak bertahan, penggantinya policy `SearchOnTaskbarMode`
dan `HideTaskViewButton`, dengan konsekuensi pengaturannya terkunci di Settings.

Branding (aset di `assets/branding/`):

| Aset | File | Pemakaian |
|---|---|---|
| Logo TGO asli | `tgo-logo.png` (1024x1024) | Sumber; tidak diubah |
| Ikon TGOS | `tgos-icon.png` → `src/playbook.png` (256x256) | Logo TGO + garis merah + label `OS`; ikon playbook di Wizard |
| Wallpaper asli | `tgo-wallpaper.webp` (2000x1125) | Sumber desain; tidak dipakai langsung karena gradasinya bergaris |
| Wallpaper TGOS | `tgos-wallpaper.png` → `src/Executables/TGOS/TGOS.png` (3840x2160) | Digambar ulang oleh `tools/make-wallpaper.py` dengan dithering supaya gradasinya halus |

Warna mengikuti website TGO: latar `#05070d`, permukaan `#0f1522` / `#151c2c`, teks
`#e8edf7`, aksen biru `#3b82f6`, merah logo `#eb121c`. Aksen Windows TGOS memakai biru
itu supaya senada dengan web dan aplikasi.

Catatan: dari source code Wizard, ikon playbook yang sudah diterapkan hanya ditampilkan
bila playbook terverifikasi AME. Saat memuat `.apbx`, ikon TGOS tampil (uji Fase 0).

### 8.9 Finalisasi (`90-finalize.yml`)

- Menyalin folder **TGOS Toolbox** ke `%SystemDrive%\TGOS Toolbox` dan membuat pintasan di
  Desktop. Pintasan dibuat paling akhir, setelah Explorer hidup lagi dari reset pin;
  di build pertama 1.0.0 pintasan yang dibuat sebelumnya muncul di tengah Desktop. Isinya skrip berpasangan (matikan / aktifkan lagi) untuk: Defender, VBS,
  mitigasi CPU, update otomatis, indexing, hibernasi.
- Menulis `%ProgramData%\TGOS\install-info.txt` berisi versi TGOS, edisi, build, dan
  (mulai `0.1.0`) opsi yang dipilih. Bagian ini sudah ada sejak Fase 0.
- Membersihkan cache komponen (`DISM /StartComponentCleanup`) dan file sementara.
- Wizard meminta restart.

---

### 8.10 Revisi kedua `1.0.0`: update, launcher, bersih-bersih

**Pause Windows Update** (`updates-pause`, bawaan). Nilai yang ditulis halaman Settings
sendiri saat tombol pause diklik, di `HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings`:
`FlightSettingsMaxPauseDays` (batas pause, 3650 hari) dan pasangan
`Pause{Feature,Quality}Updates{Start,End}Time`, `PauseUpdates{Start,Expiry}Time`. Nilai ini
tidak didokumentasikan resmi Microsoft dan satu laporan menyebut tidak jalan di LTSC 24H2,
jadi cadangannya `NoAutoUpdate=1`: bila pause diabaikan, hasilnya tetap Manual. Di runner
uji, layanan Windows Update belum mencatat status pause (`PausedQualityStatus = 0`) tepat
setelah nilainya ditulis; bukti akhirnya di Settings VM. Definisi Defender tetap bisa
diperbarui saat pause (uji otomatis: `MpCmdRun -SignatureUpdate` keluar 0).

**Game Bar** (bersama `remove-xbox`): `UseNexusForGameBarEnabled=0`,
`GamepadNexusChordEnabled=0` (nama nilai kedua dari satu sumber forum, dicek di VM),
`AllowGameDVR=0`, penangan pengganti `systray.exe` untuk `ms-gamebar`,
`ms-gamebarservices`, `ms-gamingoverlay`, dan Win+G diblokir lewat `DisabledHotkeys`
Explorer (huruf `G` ditambahkan ke isi yang sudah ada; dicabut lagi oleh Toolbox *Turn
ON*). Riwayat temuan di uji otomatis Windows 11 25H2: penangan pengganti saja tidak cukup
("Pick an app" tetap muncul); `AssocQueryString` menjawab "no application is associated"
untuk `ms-gamebar`, sama dengan protokol yang tidak ada, sedangkan protokol buatan sendiri
dengan penangan yang sama bekerja. Penyebabnya dua catatan AppX yang masih menunjuk ke
paket Game Bar yang sudah dihapus: katalog `PackageRepository\Extensions\windows.protocol`
dan cache `AppModel\StateRepository\Cache\Protocol`. Menghapus entri katalog sudah dicoba
dan tidak mengubah jawaban Windows; cache StateRepository adalah data internal layanan
Windows yang bisa dibangun ulang dari databasenya, jadi tidak disentuh. Karena itu
pemicunya (Win+G) yang dimatikan. Di Server 2025 (tanpa Game Bar sejak awal) penangan
pengganti langsung dipakai Windows.

**Framework AppX yang dibuang Windows.** Dengan *Remove Microsoft Store*, Store adalah
pemakai terakhir .NET Native 2.2 di Windows Server, dan Windows kadang langsung membuang
framework itu (log AppX: operasi Remove biasa). Itu bukan kerusakan: tidak ada aplikasi
tersisa yang memakainya, dan aplikasi yang dipasang lagi membawa framework-nya. Potret
sistem sekarang mencatat dependensi tiap aplikasi, dan `compare-snapshots.py` hanya
menandai BAHAYA bila framework hilang padahal masih ada aplikasi yang memakainya (atau
datanya tidak ada).

**Launcher dan aplikasi.** Semua dari alamat "latest" resmi, tanda tangan diperiksa
(Valve, Epic Games, Electronic Arts, Ubisoft, Discord), dipasang senyap. Program yang
dibuka installer sesudah pasang (EA app, Discord) ditutup otomatis. Discord dipasang per
pengguna, jadi dijalankan sebagai pengguna yang login, bukan TrustedInstaller.
Spotify: installer web (`SpotifySetup.exe /silent`) tetap menampilkan jendela "Spotify
Installer" dan macet sampai batas waktu di uji otomatis. TGOS memakai installer lengkap
resmi `download.scdn.co/SpotifyFullSetup.exe` (`/silent`, tanda tangan Spotify), yang
terbukti senyap. Installer Spotify menolak hak admin, jadi dijalankan dengan token
pengguna biasa (`runas /trustlevel:0x20000`), batas waktu 5 menit. Catatan jujur: versi
installer lengkap tertinggal dari versi web (uji: 1.2.53); Spotify memperbarui dirinya
sendiri saat pertama dibuka.

**Pemantau jendela di uji otomatis.** Selama seluruh playbook, proses terpisah mencatat
setiap jendela baru yang terlihat beserta ukurannya; kontrolnya jendela Notepad. Installer
WiX Burn (VC++ 2012/2013), installer EA app, dan updater Brave membuat jendela pesan tanpa
judul yang secara teknis "visible" tetapi tidak tampil; yang dihitung pelanggaran hanya
jendela berjudul atau berukuran nyata. Jendela Explorer "Personalized Settings" (Active
Setup saat Explorer dijalankan ulang) dicatat sebagai bagian shell.

**Deep clean** (`Invoke-DeepClean.ps1`). Isi dan pengamannya ada di kepala skrip. Prinsip:
hanya sampah yang dibuat ulang Windows sendiri; Prefetch, Recycle Bin, Event Log, dan data
pengguna tidak disentuh; folder dihapus dengan `rd /s /q` yang tidak mengikuti junction
(Windows.old berisi junction yang bisa menunjuk ke folder pengguna sekarang); folder
playbook yang sedang berjalan dan folder AME dilewati. Deep clean+ (`Windows.old`,
`/ResetBase`) dipisah karena tidak bisa dibatalkan.

### 8.11 Revisi ketiga `1.0.0`: dari uji VM revisi kedua

**Terminal bawaan selama instalasi** (`Set-ConsoleHost.ps1`, dicabut di revisi keempat,
lihat 8.12). Pemilik melihat beberapa
jendela kosong bergaya terminal di akhir instalasi, dengan Windows Terminal aktif di
taskbar. Fakta yang terkumpul: (1) AME menjalankan tiap `!run` dengan
`CreateNoWindow = true` (kode sumber AME, `RunAction.cs`), jadi langkah TGOS tidak membuat
jendela konsol; (2) uji otomatis yang menjalankan mesin AME tanpa konsol seperti AME Wizard
(`DETACHED_PROCESS`), dengan Windows Terminal 1.24 sebagai terminal bawaan, tidak melihat
satu pun jendela; jejak proses menunjukkan semua konsol selama playbook tanpa jendela
(PowerShell langkah TGOS, `ame-assassin.exe` milik AME, ngen/DISM milik servicing); (3)
konsol tersembunyi dengan Windows Terminal 1.24 tetap tersembunyi; (4) teks status
"Reticulating splines..." di screenshot bukan dari TGOS (status terakhir TGOS adalah
"Finishing up"). Penyebab pasti di VM belum diketahui. Sebagai pengaman, terminal bawaan tiap
akun yang login (dan SYSTEM) disetel ke Windows Console Host sesudah restore point dan
dikembalikan persis sesudah langkah terakhir yang menjalankan ulang Explorer; catatan nilai
lama tidak ditimpa bila instalasi sebelumnya berhenti di tengah. Potret sistem mencatat
versi Windows Terminal dan pengaturan terminal untuk laporan berikutnya.

**.NET Framework 3.5.** DISM gagal di VM dengan `0x8024001E` (WU_E_SERVICE_STOP).
`Install-Software.ps1` memastikan `wuauserv` berjalan (menolak bila Disabled, karena
NetFx3 diunduh lewat layanan itu), lalu mencoba sekali lagi sesudah layanan dijalankan
ulang dan jeda 30 detik; baris `, Error` terakhir dari `dism.log` ikut di pesan. Terbukti
di uji otomatis: tombol Toolbox memasang .NET 3.5 saat update di-pause.

**Reserved Storage.** `0x800F0975`: cadangan sedang dipakai operasi servicing (VM baru masih
menyiapkan update sebelum TGOS mem-pause-nya). `Invoke-DeepClean.ps1` mendaftarkan
`\TGOS\Reserved Storage Off` (SYSTEM, saat startup + 2 menit, Hidden, batas 30 menit) yang
menjalankan `Set-TgosFeature.ps1 -Feature ReservedStorage -State Off -FromStartupTask`;
skrip itu menghapus tugasnya setelah berhasil, bila tidak didukung, atau setelah 3
percobaan (penghitung di `ProgramData\TGOS\reserved-storage-retry.txt`), dan juga saat
pengguna memakai tombol Toolbox Reserved Storage. Kondisi "sedang dipakai" tidak bisa
dibuat di runner; pendaftaran dan penghapusan-diri diuji langsung.

### 8.12 Revisi keempat `1.0.0`: dari uji VM revisi ketiga

**Jendela cmd di akhir instalasi: sisa uninstaller OneDrive.** Screenshot revisi ketiga
memperlihatkan isinya: `C:\Windows\System32\cmd.exe` menjalankan `rd /s` pada
`%LOCALAPPDATA%\Microsoft\OneDrive\ListSync\...` dan gagal ("being used by another
process"), pukul 06:00 UTC, tepat saat `Set-ShellLayout.ps1` menghentikan Explorer dan
`Start-Shell.ps1` menjalankannya lagi. Uninstaller OneDrive berjalan 10 menit sebelumnya.
`Remove-OneDrive.ps1` dulu hanya menghentikan `OneDrive.exe`; `Microsoft.SharePoint.exe`
(sinkronisasi Microsoft Lists) masih mengunci file ListSync, sehingga uninstaller
meninggalkan perintah bersih-bersih yang dijalankan Explorer saat start (di revisi kedua
jendela yang sama tampil kosong lewat Windows Terminal). Perbaikan di `Remove-OneDrive.ps1`:
hentikan semua proses keluarga OneDrive di sesi pengguna (`OneDrive`, `OneDriveSetup`,
`OneDriveStandaloneUpdater`, `OneDriveLauncher`, `OneDriveFileLauncher`,
`Microsoft.SharePoint`, `FileCoAuth`, `FileSyncConfig`) sebelum dan sesudah uninstall;
entri RunOnce (HKCU, HKLM, WOW6432Node) yang menyebut OneDrive dicatat isinya lalu dihapus;
folder aplikasi `%LOCALAPPDATA%\Microsoft\OneDrive` dihapus lewat `Remove-TgosFolder`
(Common.ps1: file terkunci dihapus saat restart dengan MoveFileEx, folder yang berisi link
tidak disentuh). Folder file pengguna `%USERPROFILE%\OneDrive` tidak pernah disentuh.
`Test-TgosResult.ps1` memeriksa RunOnce semua pengguna yang login. CI memasang dan
menjalankan OneDrive per pengguna di runner sebelum playbook, mencatat setiap `cmd.exe`
beserta induk dan baris perintahnya, dan gagal bila Explorer menjalankan `cmd.exe` selama
playbook; kontrol: entri RunOnce buatan harus dijalankan Explorer saat dinyalakan ulang.
Pengaturan terminal sementara (8.11) dicabut atas keputusan pemilik: terbukti bukan
penyebab.

**Langkah yang menunggu restart** (`Complete-AfterRestart.ps1`). Di VM, .NET 3.5 tetap gagal
(`0x8024001E` dua kali) dan Reserved Storage tetap dipakai servicing selama instalasi.
`Add-TgosAfterRestartItem` (Common.ps1) menulis langkah ke
`%ProgramData%\TGOS\after-restart.txt` (`langkah|percobaan`) dan mendaftarkan
`\TGOS\Finish after restart` (SYSTEM, startup + 3 menit, Hidden, batas 2 jam) bila TGOS
Toolbox sudah terpasang; bila belum (.NET 3.5 di `05-software`), `Install-Toolbox.ps1`
mendaftarkannya. Tugas yang sudah ada tidak didaftarkan ulang (bisa sedang berjalan).
`Complete-AfterRestart.ps1` menjalankan `Set-TgosFeature.ps1 -Feature ReservedStorage
-State Off` dan `Install-Software.ps1 -Item netfx3` tanpa jendela; keduanya tidak mengubah
apa pun bila keadaannya sudah benar, jadi langkah yang sudah dikerjakan dari Toolbox
langsung selesai. Maksimal 3 percobaan per langkah, hasil di `toolbox.log`, lalu tugas dan
folder `\TGOS` dihapus. Menggantikan `\TGOS\Reserved Storage Off` dan `-FromStartupTask`.

**Bug pembeda Reserved Storage.** Pesan DISM untuk `0x800F0975` berbunyi "...is not supported
when reserved storage is in use"; pola lama `not supported` cocok dengannya, sehingga tugas
startup revisi ketiga menganggapnya tidak didukung dan menghapus dirinya. Sekarang
`Get-ReservedStorageProblem` (Set-TgosFeature.ps1) mengecek "in use"/`0x800F0975` lebih dulu
(kode keluar baru 4); diuji di `tools/selftest.py` lewat AST dengan 7 contoh.

**Diagnosa.** `Collect-TgosReport.ps1` menulis `servicing.txt` (Reserved Storage, NetFx3,
layanan WU/UsoSvc/BITS/DoSvc/TrustedInstaller, tanda restart tertunda, daftar dan tugas
"after restart", RunOnce, 80 baris terakhir `dism.log`), dengan nama pengguna dan nama
komputer disamarkan.

**Teks Wizard** tanpa titik koma (permintaan pemilik); `validate.py` menolak `;` di semua
teks `playbook.conf`, dengan mutasi uji diri.

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

0. Setiap push dijalankan `.github/workflows/test.yml`: validasi, uji diri, lalu playbook
   dijalankan lewat mesin AME di Windows (lihat [docs/TESTING.md](docs/TESTING.md)).
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

> Pengujian sekarang berlapis tiga (uji bentuk, mesin AME di GitHub Actions, VM). Alur
> yang berlaku dan catatan hasilnya ada di [docs/TESTING.md](docs/TESTING.md). Matriks
> opsi di 11.3 kini dijalankan otomatis di lapis kedua; uji VM cukup sekali dengan opsi
> bawaan. Subbagian di bawah tetap berlaku untuk persiapan VM.

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
| 0. Kerangka | `0.0.1`–`0.0.2` | `playbook.conf`, cek kompatibilitas, pencatat info instalasi, branding, skrip build & validasi | **Lolos** di AME Beta, 14 Nov 2026 |
| 1–4. Semua modul | `0.9.0`–`0.9.1` | Aplikasi bawaan, privasi, layanan, tugas terjadwal, performa, opsi keamanan, komponen, tampilan, TGOS Toolbox, pemeriksaan diri, uji otomatis. **`0.9.0` diuji di VM 16 Nov 2026: 139 lolos, 1 gagal (Edge), beberapa cacat tampilan. `0.9.1` memperbaikinya.** | Uji ulang `0.9.1` di VM Windows 11 Pro 26H2 tanpa temuan |
| 5. Rilis | `1.0.0` | Perbaikan dari uji `0.9.1` (Copilot, taskbar, Start), pilihan browser, software, opsi baru, Toolbox lengkap. **Diberi label `1.0.0` atas keputusan pemilik.** | Uji ulang di VM Windows 11 Pro 26H2 tanpa temuan |
| 6. Hardware asli | `1.0.x` | Benchmark, uji anti-cheat, uji 22H2/23H2, keputusan [8.5](#85-kandidat-yang-butuh-bukti-benchmark-dulu). **Belum dilakukan**: semua uji sejauh ini di VM dan runner uji. | Data benchmark tercatat, tidak ada bug kritis |

Fase 1 sampai 4 semula direncanakan bertahap. Atas keputusan pemilik semuanya digabung ke
satu rilis, dan pengujian berulangnya dipindah ke uji otomatis
([docs/TESTING.md](docs/TESTING.md)) supaya uji di VM cukup sekali.

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
| Defender aktif memblokir AME Wizard saat instalasi | Rendah | Tidak terjadi di uji Fase 0 maupun uji otomatis Windows 11; cadangannya requirement `DefenderToggled` |
| Salah ketik YAML baru ketahuan saat instalasi | Sedang | `tools/validate.py` wajib lolos sebelum build |
| Versi AME Wizard baru mengubah format | Sedang | Catat versi Wizard yang dipakai uji di `docs/TESTING.md` |
| Build Windows baru belum diuji | Sedang | `SupportedBuilds` eksplisit; build baru ditambah hanya setelah lolos uji |
| Hasil VM tidak mewakili hardware asli | Sedang | Fase 5 khusus hardware asli sebelum rilis |
| Microsoft menolak uninstall Edge di edisi Pro | Rendah | Opsi eksperimental, default mati, tidak fatal; hasilnya diperiksa laporan verifikasi; Edge di latar dimatikan lewat policy apa pun hasilnya |
| Mesin uji otomatis (Enterprise, Server) berperilaku beda dari Pro | Sedang | Terbukti pada Edge. Setiap rilis tetap diuji sekali di VM Windows 11 Pro sebelum dianggap lolos |
| Teks Wizard terpotong | Rendah | Batas panjang dijaga validator ([2.2](#22-playbookconf)) |

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

1. **Potret VM** — `TGOS-snapshot-before.json` dari snapshot bersih pemilik, untuk
   mencocokkan daftar layanan dan tugas terjadwal dengan Windows 11 Pro 26H2 yang nyata.
2. **Browser** — bila Edge dihapus, apakah Wizard menawarkan pemasangan browser lain?
   Saat ini tidak; pengguna memasang sendiri lewat Store atau `winget`.
3. **Wallpaper** — file asli beresolusi tinggi (lihat [8.8](#88-antarmuka-80-interfaceyml)).
   Yang terpasang sekarang adalah file 2000x1125 yang dikirim, apa adanya.

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
