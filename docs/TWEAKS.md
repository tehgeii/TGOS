# Daftar tweak TGOS

> File ini dibuat otomatis oleh `tools/make-tweaks-doc.py` dari file di
> `src/Configuration/Tasks/`. Jangan diedit langsung: ubah YAML-nya (termasuk komentar
> di atas tiap aksi), lalu jalankan skrip itu lagi.

Versi playbook: `0.9.1`

Kolom **Syarat** kosong berarti tweak selalu diterapkan. `opsi: nama` berarti hanya bila
opsi itu dicentang di AME Wizard; `build: ...` berarti hanya di build Windows tersebut.

## Yang tidak pernah disentuh

Windows Firewall, UAC, Secure Boot, TPM, layanan audio, jaringan, Windows Update, Store,
Bluetooth, dan printer. Windows Defender tidak disentuh saat instalasi; hanya bisa diubah
pengguna lewat TGOS Toolbox sesudahnya.

## Cara mengembalikan

| Jenis | Cara |
|---|---|
| Aplikasi yang dihapus | Pasang lagi dari Microsoft Store (cari namanya), atau `winget install <nama>`. |
| Defender, VBS, mitigasi CPU, update otomatis, indexing, hibernasi | File *Turn ON* di **TGOS Toolbox** (pintasan di Desktop). |
| Layanan | `services.msc` > klik dua kali layanan > ubah *Startup type*. |
| Tugas terjadwal | Task Scheduler > cari tugasnya > *Enable*. |
| Power plan | Control Panel > Power Options > pilih skema lain. Skema lama tidak dihapus. |
| Nilai di `...\Policies\...` | Bawaan Windows: nilainya tidak ada. Hapus nilainya di Registry Editor, lalu restart. |
| Nilai `HKCU` selain Policies | Sebagian besar punya tombol di Settings. Atau hapus nilainya supaya Windows memakai bawaan. |
| Semua perubahan registry sekaligus | Pulihkan restore point "Before TGOS <versi>" lewat *Create a restore point* > *System Restore*. Restore point **tidak** mengembalikan aplikasi yang dihapus. |

Catatan: restore point terbukti terbuat dari dalam playbook pada uji otomatis di
Windows 11. Yang masih harus dibuktikan di uji VM adalah apakah aplikasi yang dihapus bisa
dipasang lagi dari Store (lihat [TESTING.md](TESTING.md)).



## Persiapan (`00-preflight.yml`)

| Skrip | Syarat | Keterangan |
|---|---|---|
| `Scripts\Test-Compatibility.ps1` |  | AME Wizard hanya memeriksa nomor build (SupportedBuilds), tidak memeriksa edisi. Skrip ini keluar dengan kode bukan 0 bila edisi bukan Pro, build terlalu lama, atau arsitektur bukan x64. Kode bukan 0 menghentikan seluruh playbook. |
| `Scripts\New-RestorePoint.ps1` |  | Restore point "Before TGOS <versi>" sebagai jaring pengaman untuk perubahan registry. Tidak fatal: skrip selalu keluar 0 dan mencatat hasilnya di %ProgramData%\TGOS\restore-point.txt, yang lalu disalin ke install-info.txt. |


## Aplikasi bawaan (`10-debloat-appx.yml`)


### Berita, cuaca, iklan

| Aplikasi | Paket | Syarat | Keterangan |
|---|---|---|---|
| Microsoft News | `Microsoft.BingNews*` |  |  |
| Weather | `Microsoft.BingWeather*` |  |  |
| Bing Search (pencarian web di Start) | `Microsoft.BingSearch*` |  |  |

### Game dan hiburan bawaan

| Aplikasi | Paket | Syarat | Keterangan |
|---|---|---|---|
| Solitaire & Casual Games | `Microsoft.MicrosoftSolitaireCollection*` |  |  |
| Movies & TV | `Microsoft.ZuneVideo*` |  | Media Player (Microsoft.ZuneMusic) sengaja dipertahankan sebagai pemutar audio/video bawaan. |

### Bantuan, tips, umpan balik

| Aplikasi | Paket | Syarat | Keterangan |
|---|---|---|---|
| Get Help | `Microsoft.GetHelp*` |  |  |
| Tips | `Microsoft.Getstarted*` |  |  |
| Feedback Hub | `Microsoft.WindowsFeedbackHub*` |  |  |
| Quick Assist | `MicrosoftCorporationII.QuickAssist*` |  |  |

### Office, kerja, komunikasi

| Aplikasi | Paket | Syarat | Keterangan |
|---|---|---|---|
| Outlook (new) | `Microsoft.OutlookForWindows*` |  | Microsoft.MicrosoftOfficeHub ("Microsoft 365 Copilot") ada di bagian opsi Copilot di bawah: di 26H2 paket itu adalah identitas aplikasi Copilot. |
| Mail and Calendar | `microsoft.windowscommunicationsapps*` |  | Microsoft.MicrosoftOfficeHub ("Microsoft 365 Copilot") ada di bagian opsi Copilot di bawah: di 26H2 paket itu adalah identitas aplikasi Copilot. |
| People | `Microsoft.People*` |  | Microsoft.MicrosoftOfficeHub ("Microsoft 365 Copilot") ada di bagian opsi Copilot di bawah: di 26H2 paket itu adalah identitas aplikasi Copilot. |
| Microsoft To Do | `Microsoft.Todos*` |  | Microsoft.MicrosoftOfficeHub ("Microsoft 365 Copilot") ada di bagian opsi Copilot di bawah: di 26H2 paket itu adalah identitas aplikasi Copilot. |
| Power Automate | `Microsoft.PowerAutomateDesktop*` |  | Microsoft.MicrosoftOfficeHub ("Microsoft 365 Copilot") ada di bagian opsi Copilot di bawah: di 26H2 paket itu adalah identitas aplikasi Copilot. |
| Dev Home | `Microsoft.Windows.DevHome*` |  | Microsoft.MicrosoftOfficeHub ("Microsoft 365 Copilot") ada di bagian opsi Copilot di bawah: di 26H2 paket itu adalah identitas aplikasi Copilot. |
| Teams versi pribadi (22H2/23H2) | `MicrosoftTeams_*` |  | Microsoft.MicrosoftOfficeHub ("Microsoft 365 Copilot") ada di bagian opsi Copilot di bawah: di 26H2 paket itu adalah identitas aplikasi Copilot. |
| Microsoft Teams | `MSTeams_*` |  | Microsoft.MicrosoftOfficeHub ("Microsoft 365 Copilot") ada di bagian opsi Copilot di bawah: di 26H2 paket itu adalah identitas aplikasi Copilot. |
| Clipchamp | `Clipchamp.Clipchamp*` |  | Microsoft.MicrosoftOfficeHub ("Microsoft 365 Copilot") ada di bagian opsi Copilot di bawah: di 26H2 paket itu adalah identitas aplikasi Copilot. |

### Utilitas yang jarang dipakai

| Aplikasi | Paket | Syarat | Keterangan |
|---|---|---|---|
| Maps | `Microsoft.WindowsMaps*` |  |  |
| Phone Link | `Microsoft.YourPhone*` |  |  |
| Cross Device Experience Host (pasangan Phone Link) | `MicrosoftWindows.CrossDevice*` |  |  |
| Sound Recorder | `Microsoft.WindowsSoundRecorder*` |  |  |
| Clock | `Microsoft.WindowsAlarms*` |  |  |
| Sticky Notes | `Microsoft.MicrosoftStickyNotes*` |  |  |
| Family | `MicrosoftCorporationII.MicrosoftFamily*` |  |  |
| Cortana | `Microsoft.549981C3F5F10*` |  |  |

### Opsi: Copilot dan Widgets

| Aplikasi | Paket | Syarat | Keterangan |
|---|---|---|---|
| Microsoft 365 Copilot (dulu Office hub) | `Microsoft.MicrosoftOfficeHub*` | opsi: `remove-ai-widgets` | Di 26H2 Copilot adalah program biasa (bukan paket Store) dengan uninstaller sendiri. Uninstaller itu harus jalan SEBELUM paket Microsoft.MicrosoftOfficeHub di bawah dihapus, karena paket itu identitas aplikasinya. Di TGOS 0.9.1 urutannya terbalik: identitasnya hilang, programnya (1,7 GB) tertinggal, dan pin taskbar-nya jadi kotak abu-abu. Tidak fatal; di build tanpa program Copilot skrip ini tidak berbuat apa-apa. |
| Copilot | `Microsoft.Copilot*` | opsi: `remove-ai-widgets` | Proses Widgets dihentikan dulu. Tanpa ini filenya masih terkunci saat paketnya dihapus, dan sisa file tertinggal di disk. |
| Copilot provider | `Microsoft.Windows.Ai.Copilot.Provider*` | opsi: `remove-ai-widgets` | Proses Widgets dihentikan dulu. Tanpa ini filenya masih terkunci saat paketnya dihapus, dan sisa file tertinggal di disk. |
| Widgets (Windows Web Experience Pack) | `MicrosoftWindows.Client.WebExperience*` | opsi: `remove-ai-widgets` | Proses Widgets dihentikan dulu. Tanpa ini filenya masih terkunci saat paketnya dihapus, dan sisa file tertinggal di disk. |
| Widgets Platform Runtime | `Microsoft.WidgetsPlatformRuntime*` | opsi: `remove-ai-widgets` | Proses Widgets dihentikan dulu. Tanpa ini filenya masih terkunci saat paketnya dihapus, dan sisa file tertinggal di disk. |
| Start Experiences App (host Widgets baru) | `Microsoft.StartExperiencesApp*` | opsi: `remove-ai-widgets` | Proses Widgets dihentikan dulu. Tanpa ini filenya masih terkunci saat paketnya dihapus, dan sisa file tertinggal di disk. |
| Skrip | Syarat | Keterangan |
|---|---|---|
| `Scripts\Remove-Copilot.ps1` | opsi: `remove-ai-widgets` | Di 26H2 Copilot adalah program biasa (bukan paket Store) dengan uninstaller sendiri. Uninstaller itu harus jalan SEBELUM paket Microsoft.MicrosoftOfficeHub di bawah dihapus, karena paket itu identitas aplikasinya. Di TGOS 0.9.1 urutannya terbalik: identitasnya hilang, programnya (1,7 GB) tertinggal, dan pin taskbar-nya jadi kotak abu-abu. Tidak fatal; di build tanpa program Copilot skrip ini tidak berbuat apa-apa. |
| `Scripts\Remove-AppxLeftovers.ps1` | opsi: `remove-ai-widgets` | Sebagian file Widgets tetap terkunci Windows walau prosesnya sudah dihentikan. Skrip ini menghapus folder sisanya, atau mendaftarkannya untuk dihapus saat restart. |

### Opsi: Xbox app dan Game Bar

| Aplikasi | Paket | Syarat | Keterangan |
|---|---|---|---|
| Xbox app | `Microsoft.GamingApp*` | opsi: `remove-xbox` | Microsoft.XboxIdentityProvider dan Microsoft.GamingServices TIDAK dihapus: keduanya dibutuhkan untuk login dan menjalankan game dari Microsoft Store / PC Game Pass. |
| Game Bar | `Microsoft.XboxGamingOverlay*` | opsi: `remove-xbox` | Microsoft.XboxIdentityProvider dan Microsoft.GamingServices TIDAK dihapus: keduanya dibutuhkan untuk login dan menjalankan game dari Microsoft Store / PC Game Pass. |
| Game Bar overlay | `Microsoft.XboxGameOverlay*` | opsi: `remove-xbox` | Microsoft.XboxIdentityProvider dan Microsoft.GamingServices TIDAK dihapus: keduanya dibutuhkan untuk login dan menjalankan game dari Microsoft Store / PC Game Pass. |
| Xbox speech-to-text overlay | `Microsoft.XboxSpeechToTextOverlay*` | opsi: `remove-xbox` | Microsoft.XboxIdentityProvider dan Microsoft.GamingServices TIDAK dihapus: keduanya dibutuhkan untuk login dan menjalankan game dari Microsoft Store / PC Game Pass. |
| Xbox Live dialog UI | `Microsoft.Xbox.TCUI*` | opsi: `remove-xbox` | Microsoft.XboxIdentityProvider dan Microsoft.GamingServices TIDAK dihapus: keduanya dibutuhkan untuk login dan menjalankan game dari Microsoft Store / PC Game Pass. |

### Segarkan cache Start dan Search

Bukan penghapusan: hanya mengosongkan cache `*Client.CBS*`, `*StartMenuExperienceHost*`, `*Windows.Search*`. Anjuran dokumentasi AME setelah menghapus paket AppX, supaya ubin aplikasi yang sudah dihapus tidak tertinggal di Start dan hasil pencarian.


## Privasi (`20-privacy.yml`)


### Telemetri

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection` | `AllowTelemetry` | `0` |  | Level diagnostik minimum. Di edisi Pro, 0 diperlakukan Windows sebagai 1 (Required); telemetri baru benar-benar berhenti setelah layanan DiagTrack dimatikan di v0.1.1. |
| `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection` | `AllowTelemetry` | `0` |  | Level diagnostik minimum. Di edisi Pro, 0 diperlakukan Windows sebagai 1 (Required); telemetri baru benar-benar berhenti setelah layanan DiagTrack dimatikan di v0.1.1. |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection` | `DoNotShowFeedbackNotifications` | `1` |  | Windows tidak lagi meminta umpan balik. |
| `HKCU\SOFTWARE\Microsoft\Siuf\Rules` | `NumberOfSIUFInPeriod` | `0` |  | Windows tidak lagi meminta umpan balik. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy` | `TailoredExperiencesWithDiagnosticDataEnabled` | `0` |  | Pengalaman yang disesuaikan berdasarkan data diagnostik. |

### Advertising ID

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo` | `Enabled` | `0` |  |  |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo` | `DisabledByGroupPolicy` | `1` |  |  |

### Aplikasi promosi yang terpasang sendiri

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` | `SilentInstalledAppsEnabled` | `0` |  | Mencegah Windows memasang diam-diam aplikasi sponsor, termasuk memasang ulang aplikasi yang dihapus modul 10. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` | `PreInstalledAppsEnabled` | `0` |  | Mencegah Windows memasang diam-diam aplikasi sponsor, termasuk memasang ulang aplikasi yang dihapus modul 10. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` | `OemPreInstalledAppsEnabled` | `0` |  | Mencegah Windows memasang diam-diam aplikasi sponsor, termasuk memasang ulang aplikasi yang dihapus modul 10. |

### Saran, tips, dan iklan di Start, Settings, lock screen

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` | `SystemPaneSuggestionsEnabled` | `0` |  | Saran aplikasi di Start. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` | `SubscribedContent-338388Enabled` | `0` |  | Saran aplikasi di Start. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` | `SoftLandingEnabled` | `0` |  | Tips dan trik Windows. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` | `SubscribedContent-338389Enabled` | `0` |  | Tips dan trik Windows. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` | `SubscribedContent-310093Enabled` | `0` |  | Layar "Welcome experience" setelah update. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` | `SubscribedContent-338393Enabled` | `0` |  | Konten yang disarankan di aplikasi Settings. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` | `SubscribedContent-353694Enabled` | `0` |  | Konten yang disarankan di aplikasi Settings. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` | `SubscribedContent-353696Enabled` | `0` |  | Konten yang disarankan di aplikasi Settings. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` | `RotatingLockScreenOverlayEnabled` | `0` |  | Tips dan fakta di lock screen. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | `Start_IrisRecommendations` | `0` |  | Rekomendasi tips dan aplikasi di Start (Windows 11). |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | `Start_AccountNotifications` | `0` |  | Notifikasi akun Microsoft di Start. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | `ShowSyncProviderNotifications` | `0` |  | Iklan penyedia sinkronisasi (OneDrive) di File Explorer. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement` | `ScoobeSystemSettingEnabled` | `0` |  | Layar "Let's finish setting up your device". |

### Activity History

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\System` | `EnableActivityFeed` | `0` |  |  |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\System` | `PublishUserActivities` | `0` |  |  |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\System` | `UploadUserActivities` | `0` |  |  |

### Pencarian web di Start

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKCU\SOFTWARE\Policies\Microsoft\Windows\Explorer` | `DisableSearchBoxSuggestions` | `1` |  | Start hanya mencari aplikasi, file, dan pengaturan lokal; tidak mengirim ketikan ke Bing. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Search` | `BingSearchEnabled` | `0` |  | Start hanya mencari aplikasi, file, dan pengaturan lokal; tidak mengirim ketikan ke Bing. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings` | `IsDynamicSearchBoxEnabled` | `0` |  | "Search highlights" (gambar dan berita di kotak pencarian). |

### Data ketikan dan tulisan tangan

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKCU\SOFTWARE\Microsoft\InputPersonalization` | `RestrictImplicitInkCollection` | `1` |  |  |
| `HKCU\SOFTWARE\Microsoft\InputPersonalization` | `RestrictImplicitTextCollection` | `1` |  |  |
| `HKCU\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore` | `HarvestContacts` | `0` |  |  |
| `HKCU\SOFTWARE\Microsoft\Input\TIPC` | `Enabled` | `0` |  |  |

### Pelaporan error dan berbagi update

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting` | `Disabled` | `1` |  | Windows Error Reporting tidak mengirim laporan crash ke Microsoft. |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization` | `DODownloadMode` | `0` |  | Delivery Optimization: unduh update hanya dari Microsoft, tidak mengunggah ke PC lain. |

### Recall dan analisis data AI (ada mulai 24H2)

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI` | `DisableAIDataAnalysis` | `1` | build: `>=26100` | Selalu dimatikan: Recall merekam isi layar secara berkala. |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI` | `AllowRecallEnablement` | `0` | build: `>=26100` | Selalu dimatikan: Recall merekam isi layar secara berkala. |

### Opsi: Copilot dan Widgets

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKLM\SOFTWARE\Policies\Microsoft\Dsh` | `AllowNewsAndInterests` | `0` | opsi: `remove-ai-widgets` | Widgets dimatikan lewat policy. Tombol taskbar-nya (TaskbarDa) tidak ditulis langsung karena nilai itu dilindungi Windows dan penulisan dari luar ditolak. |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI` | `DisableClickToDo` | `1` | opsi: `remove-ai-widgets`; build: `>=26100` | Click to Do (aksi AI atas isi layar) dimatikan. Aplikasinya bagian dari Windows dan tidak bisa dihapus. |
| `HKCU\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot` | `TurnOffWindowsCopilot` | `1` | opsi: `remove-ai-widgets`; build: `<26100` | Copilot versi panel samping hanya ada di 22H2 dan 23H2; di 24H2 ke atas Copilot adalah aplikasi biasa yang dihapus modul 10. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | `ShowCopilotButton` | `0` | opsi: `remove-ai-widgets`; build: `<26100` | Copilot versi panel samping hanya ada di 22H2 dan 23H2; di 24H2 ke atas Copilot adalah aplikasi biasa yang dihapus modul 10. |


## Layanan (`30-services.yml`)


### Telemetri dan diagnostik

| Layanan | Startup menjadi | Syarat | Keterangan |
|---|---|---|---|
| `DiagTrack` | Disabled |  | Connected User Experiences and Telemetry: pengirim utama data telemetri. |
| `dmwappushservice` | Disabled |  | Perutean pesan push WAP untuk telemetri perangkat. |
| `diagnosticshub.standardcollector.service` | Disabled |  | Pengumpul data untuk Diagnostics Hub (alat profiling pengembang). |
| `WerSvc` | Disabled |  | Windows Error Reporting: mengirim laporan crash ke Microsoft. |
| `wisvc` | Disabled |  | Windows Insider Service: hanya dipakai bila ikut program Insider. |
| `InventorySvc` | Disabled |  | Inventory and Compatibility Appraisal: menginventaris aplikasi dan perangkat untuk telemetri kompatibilitas. Berjalan otomatis di 24H2 ke atas. |
| `whesvc` | Disabled |  | Windows Health and Optimized Experiences: pengumpul data kesehatan perangkat. Berjalan otomatis di 24H2 ke atas. |

### Aktivitas latar yang tidak perlu

| Layanan | Startup menjadi | Syarat | Keterangan |
|---|---|---|---|
| `SysMain` | Disabled |  | SysMain (Superfetch): memuat aplikasi ke RAM lebih dulu. Di SSD manfaatnya kecil, sedangkan aktivitas disk dan RAM-nya mengganggu saat bermain. |
| `MapsBroker` | Disabled |  | Pengunduh peta offline untuk aplikasi Maps (aplikasinya sudah dihapus). |
| `RetailDemo` | Disabled |  | Mode demo toko. |
| `WpcMonSvc` | Disabled |  | Kontrol orang tua (Family Safety; aplikasinya sudah dihapus). |
| `TrkWks` | Disabled |  | Pelacak tautan file antar-komputer dalam domain NTFS. |

### Fitur yang tidak dipakai di PC gaming

| Layanan | Startup menjadi | Syarat | Keterangan |
|---|---|---|---|
| `Fax` | Disabled |  |  |
| `RemoteRegistry` | Disabled |  | Mengizinkan registry diubah dari komputer lain. Mematikannya juga menambah keamanan. |
| `AJRouter` | Disabled |  | Router AllJoyn untuk perangkat IoT. |
| `WalletService` | Disabled |  | Dompet dan pembayaran NFC. |
| `SEMgrSvc` | Disabled |  | Dompet dan pembayaran NFC. |
| `WMPNetworkSvc` | Disabled |  | Berbagi pustaka Windows Media Player ke jaringan. |

### Opsi: Copilot dan Widgets

| Layanan | Startup menjadi | Syarat | Keterangan |
|---|---|---|---|
| `WSAIFabricSvc` | Manual | opsi: `remove-ai-widgets` | Windows AI Fabric: runtime fitur AI. Dijadikan Manual (bukan Disabled) supaya hanya jalan bila ada yang memintanya. |

### Opsi: Windows Search

| Layanan | Startup menjadi | Syarat | Keterangan |
|---|---|---|---|
| `WSearch` | Disabled | opsi: `disable-indexing` | Pengindeksan isi file. Tanpa ini pencarian file di Explorer lebih lambat, tetapi pencarian aplikasi di Start tetap jalan. |


## Tugas terjadwal (`40-scheduled-tasks.yml`)

| Skrip | Syarat | Keterangan |
|---|---|---|
| `Scripts\Disable-ScheduledTasks.ps1` |  | Tugas terjadwal dinonaktifkan lewat skrip, bukan aksi !scheduledTask bawaan AME: aksi itu gagal bila tugasnya tidak ada, padahal daftar tugas berbeda antar-build. Skrip membaca daftar di Executables\TGOS\scheduled-tasks.txt, melewati tugas yang tidak ada, dan tidak pernah menghapus tugas (hanya Disable, bisa di-Enable lagi di Task Scheduler). |

Tugas yang dinonaktifkan (dari `src/Executables/TGOS/scheduled-tasks.txt`; tugas yang tidak ada di build tertentu dilewati):

| Tugas | Kelompok | Keterangan |
|---|---|---|
| `\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser` | Telemetri dan Customer Experience Improvement Program | Mengumpulkan data kompatibilitas aplikasi dan mengirimnya ke Microsoft. |
| `\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp` | Telemetri dan Customer Experience Improvement Program | Mengumpulkan data kompatibilitas aplikasi dan mengirimnya ke Microsoft. |
| `\Microsoft\Windows\Application Experience\ProgramDataUpdater` | Telemetri dan Customer Experience Improvement Program | Mengumpulkan data kompatibilitas aplikasi dan mengirimnya ke Microsoft. |
| `\Microsoft\Windows\Application Experience\StartupAppTask` | Telemetri dan Customer Experience Improvement Program | Mengumpulkan data kompatibilitas aplikasi dan mengirimnya ke Microsoft. |
| `\Microsoft\Windows\Customer Experience Improvement Program\Consolidator` | Telemetri dan Customer Experience Improvement Program | Mengirim data pemakaian (CEIP). |
| `\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip` | Telemetri dan Customer Experience Improvement Program | Mengirim data pemakaian (CEIP). |
| `\Microsoft\Windows\Autochk\Proxy` | Telemetri dan Customer Experience Improvement Program | Mengirim data pemakaian (CEIP). |
| `\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector` | Telemetri dan Customer Experience Improvement Program | Mengirim data diagnostik disk. |
| `\Microsoft\Windows\Flighting\FeatureConfig\BootstrapUsageDataReporting` | Telemetri dan Customer Experience Improvement Program | Pelaporan data pemakaian fitur Windows (ada mulai 24H2). |
| `\Microsoft\Windows\Flighting\FeatureConfig\GovernedFeatureUsageProcessing` | Telemetri dan Customer Experience Improvement Program | Pelaporan data pemakaian fitur Windows (ada mulai 24H2). |
| `\Microsoft\Windows\Flighting\FeatureConfig\UsageDataFlushing` | Telemetri dan Customer Experience Improvement Program | Pelaporan data pemakaian fitur Windows (ada mulai 24H2). |
| `\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReceiver` | Telemetri dan Customer Experience Improvement Program | Pelaporan data pemakaian fitur Windows (ada mulai 24H2). |
| `\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReporting` | Telemetri dan Customer Experience Improvement Program | Pelaporan data pemakaian fitur Windows (ada mulai 24H2). |
| `\Microsoft\Windows\UsageAndQualityInsights\UsageAndQualityInsights-MaintenanceTask` | Telemetri dan Customer Experience Improvement Program | Pelaporan data pemakaian fitur Windows (ada mulai 24H2). |
| `\Microsoft\Windows\Sustainability\SustainabilityTelemetry` | Telemetri dan Customer Experience Improvement Program | Pelaporan data pemakaian fitur Windows (ada mulai 24H2). |
| `\Microsoft\Windows\DiskFootprint\Diagnostics` | Telemetri dan Customer Experience Improvement Program | Mengukur ukuran folder untuk laporan diagnostik. |
| `\Microsoft\Windows\Feedback\Siuf\DmClient` | Umpan balik |  |
| `\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload` | Umpan balik |  |
| `\Microsoft\Windows\PerformanceTrace\ShowFeedbackToast` | Umpan balik | Pop-up yang meminta umpan balik performa. |
| `\Microsoft\Windows\Windows Error Reporting\QueueReporting` | Pelaporan error |  |
| `\Microsoft\Windows\Shell\FamilySafetyMonitor` | Fitur yang sudah dimatikan | Kontrol orang tua (layanannya WpcMonSvc sudah dimatikan). |
| `\Microsoft\Windows\Shell\FamilySafetyRefreshTask` | Fitur yang sudah dimatikan | Kontrol orang tua (layanannya WpcMonSvc sudah dimatikan). |
| `\Microsoft\Windows\RetailDemo\CleanupOfflineContent` | Fitur yang sudah dimatikan | Mode demo toko. |
| `\Microsoft\Windows\Maps\MapsUpdateTask` | Maps (aplikasinya sudah dihapus) |  |
| `\Microsoft\Windows\Maps\MapsToastTask` | Maps (aplikasinya sudah dihapus) |  |


## Performa (`50-performance.yml`)


### Perekaman game di latar belakang

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKCU\System\GameConfigStore` | `GameDVR_Enabled` | `0` |  | Game DVR merekam terus-menerus di latar; mematikannya menghilangkan overhead itu. Bisa dinyalakan lagi di Settings > Gaming > Captures. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR` | `AppCaptureEnabled` | `0` |  | Game DVR merekam terus-menerus di latar; mematikannya menghilangkan overhead itu. Bisa dinyalakan lagi di Settings > Gaming > Captures. |

### Game Mode

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKCU\SOFTWARE\Microsoft\GameBar` | `AutoGameModeEnabled` | `1` |  | Menahan Windows Update dan notifikasi saat game berjalan, dan memprioritaskan game. |
| `HKCU\SOFTWARE\Microsoft\GameBar` | `AllowAutoGameMode` | `1` |  | Menahan Windows Update dan notifikasi saat game berjalan, dan memprioritaskan game. |

### Penjadwalan GPU

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers` | `HwSchMode` | `2` |  | Hardware-accelerated GPU scheduling. Diabaikan Windows bila GPU atau driver tidak mendukung. Menjadi syarat frame generation di GPU modern. |

### Mouse

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKCU\Control Panel\Mouse` | `MouseSpeed` | `0` |  | Mematikan "Enhance pointer precision" (akselerasi) supaya gerakan mouse 1:1. |
| `HKCU\Control Panel\Mouse` | `MouseThreshold1` | `0` |  | Mematikan "Enhance pointer precision" (akselerasi) supaya gerakan mouse 1:1. |
| `HKCU\Control Panel\Mouse` | `MouseThreshold2` | `0` |  | Mematikan "Enhance pointer precision" (akselerasi) supaya gerakan mouse 1:1. |

### Penjadwal multimedia

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile` | `SystemResponsiveness` | `10` |  | Porsi CPU yang dicadangkan untuk tugas latar saat ada multimedia: 20% -> 10%. |
| `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile` | `NetworkThrottlingIndex` | `4294967295` |  | Mematikan pembatasan paket jaringan saat audio/video diputar (4294967295 = 0xFFFFFFFF). |

### Timer

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel` | `GlobalTimerResolutionRequests` | `1` |  | Windows 11 membuat resolusi timer berlaku per proses; nilai ini mengembalikan perilaku global yang diandalkan sebagian game dan limiter FPS. |

### Aplikasi latar

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy` | `LetAppsRunInBackground` | `2` |  | Aplikasi Store tidak berjalan di latar belakang (2 = paksa tolak). Efek samping: aplikasi Store tidak mengirim notifikasi saat tertutup. |

### Microsoft Edge di latar belakang

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKLM\SOFTWARE\Policies\Microsoft\Edge` | `StartupBoostEnabled` | `0` |  | Edge tidak dimuat lebih dulu saat login (Startup Boost) dan tidak tetap berjalan setelah jendelanya ditutup. Edge tetap bisa dipakai seperti biasa. |
| `HKLM\SOFTWARE\Policies\Microsoft\Edge` | `BackgroundModeEnabled` | `0` |  | Edge tidak dimuat lebih dulu saat login (Startup Boost) dan tidak tetap berjalan setelah jendelanya ditutup. Edge tetap bisa dipakai seperti biasa. |

### Efek visual

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize` | `EnableTransparency` | `0` |  | Transparansi dan animasi dimatikan untuk meringankan compositor. |
| `HKCU\Control Panel\Desktop\WindowMetrics` | `MinAnimate` | `0` |  | Transparansi dan animasi dimatikan untuk meringankan compositor. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | `TaskbarAnimations` | `0` |  | Transparansi dan animasi dimatikan untuk meringankan compositor. |

### Startup

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize` | `StartupDelayInMSec` | `0` |  | Menghilangkan jeda sebelum aplikasi startup dijalankan setelah login. |

### Sistem file

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKLM\SYSTEM\CurrentControlSet\Control\FileSystem` | `NtfsDisableLastAccessUpdate` | `2147483649` |  | NTFS tidak memperbarui waktu akses terakhir setiap file dibaca (2147483649 = 0x80000001, "dimatikan oleh pengguna"), mengurangi penulisan disk. |

### Opsi: hibernasi dan Fast Startup

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power` | `HiberbootEnabled` | `0` | opsi: `disable-hibernation` | Fast Startup membuat shutdown menjadi hibernasi parsial; mematikannya memberi boot bersih. Hibernasi dimatikan dan hiberfil.sys dihapus oleh skrip di bawah. |

| Skrip | Syarat | Keterangan |
|---|---|---|
| `Scripts\Set-PowerPlan.ps1` `-DisableHibernation` | opsi: `disable-hibernation` | Fast Startup membuat shutdown menjadi hibernasi parsial; mematikannya memberi boot bersih. Hibernasi dimatikan dan hiberfil.sys dihapus oleh skrip di bawah. |

### Opsi: penghematan daya

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling` | `PowerThrottlingOff` | `1` | opsi: `disable-power-saving` | Windows tidak memperlambat proses latar demi hemat daya. |

| Skrip | Syarat | Keterangan |
|---|---|---|
| `Scripts\Set-PowerPlan.ps1` `-UltimatePerformance` | opsi: `disable-power-saving` | Mengaktifkan power plan Ultimate Performance dan mematikan USB selective suspend. |


## Opsi keamanan (`60-security-options.yml`)


### Opsi: Virtualization-Based Security

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard` | `EnableVirtualizationBasedSecurity` | `0` | opsi: `disable-vbs` | VBS dan Memory Integrity (HVCI) menjalankan sebagian kernel di dalam hypervisor. Mematikannya mengurangi proteksi kernel dan memberi kenaikan performa di banyak sistem. Berlaku setelah restart. |
| `HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity` | `Enabled` | `0` | opsi: `disable-vbs` | VBS dan Memory Integrity (HVCI) menjalankan sebagian kernel di dalam hypervisor. Mematikannya mengurangi proteksi kernel dan memberi kenaikan performa di banyak sistem. Berlaku setelah restart. |

### Opsi: mitigasi CPU

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management` | `FeatureSettingsOverride` | `3` | opsi: `mitigations-disable` | Mematikan mitigasi Spectre dan Meltdown. Sistem menjadi rentan terhadap serangan itu. Manfaat performanya terutama di CPU lama; di CPU baru bisa nol atau negatif. |
| `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management` | `FeatureSettingsOverrideMask` | `3` | opsi: `mitigations-disable` | Mematikan mitigasi Spectre dan Meltdown. Sistem menjadi rentan terhadap serangan itu. Manfaat performanya terutama di CPU lama; di CPU baru bisa nol atau negatif. |

### Opsi: update otomatis

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU` | `NoAutoUpdate` | `1` | opsi: `updates-manual` | Windows tidak mengunduh atau memasang update sendiri. Update tetap bisa dipasang manual lewat Settings > Windows Update. Patch keamanan tertunda sampai dipasang. |


## Komponen (`70-components.yml`)


### Opsi: OneDrive

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive` | `DisableFileSyncNGSC` | `1` | opsi: `remove-onedrive` | Mencegah OneDrive dipakai atau dipasang lagi untuk sinkronisasi file. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` | `OneDriveSetup` | *(dihapus)* | opsi: `remove-onedrive` | Pengguna baru tidak mendapat pemasangan OneDrive otomatis saat login pertama. |

| Skrip | Syarat | Keterangan |
|---|---|---|
| `Scripts\Remove-OneDrive.ps1` | opsi: `remove-onedrive` | OneDrive terpasang per pengguna, jadi uninstaller resminya dijalankan sebagai pengguna yang sedang login, dengan token yang sudah ter-elevasi: uninstaller itu meminta hak admin, dan tanpa elevasi Windows menampilkan prompt UAC di tengah instalasi. Tidak fatal: hasilnya diperiksa di laporan verifikasi. |

### Opsi: Microsoft Edge (eksperimental)

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate` | `Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}` | `0` | opsi: `remove-edge` | Edge Update tidak memasang Edge lagi. GUID di bawah adalah ID produk Edge Stable. |

| Skrip | Syarat | Keterangan |
|---|---|---|
| `Scripts\Remove-Edge.ps1` | opsi: `remove-edge` | Memakai uninstaller milik Edge sendiri. WebView2 Runtime TIDAK dihapus karena banyak launcher dan aplikasi bergantung padanya. Di Windows 11 Pro 26H2 Microsoft menolak uninstall biasa (kode 93), jadi skrip mencoba dua cara tambahan; tetap bisa gagal, dan update Windows bisa memasang Edge kembali. Hasilnya diperiksa di laporan verifikasi. Tidak fatal. |


## Tampilan (`80-interface.yml`)


### Taskbar

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer` | `StartLayoutFile` | `%ProgramData%\TGOS\TaskbarLayout.xml` |  | Pin taskbar ditetapkan lewat policy "Start Layout" resmi Windows. File layout-nya ditulis Set-ShellLayout.ps1 di modul finalisasi, sesuai browser yang terpasang: File Explorer, browser, Microsoft Store. Skrip itu juga mereset daftar pin yang tersimpan di profil, karena policy ini saja tidak membuang pin yang sudah ada. |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer` | `LockedStartLayout` | `1` |  | Pin taskbar ditetapkan lewat policy "Start Layout" resmi Windows. File layout-nya ditulis Set-ShellLayout.ps1 di modul finalisasi, sesuai browser yang terpasang: File Explorer, browser, Microsoft Store. Skrip itu juga mereset daftar pin yang tersimpan di profil, karena policy ini saja tidak membuang pin yang sudah ada. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Search` | `SearchboxTaskbarMode` | `1` |  | Pencarian tampil sebagai ikon saja (0 = sembunyi, 1 = ikon, 2 = kotak). |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | `ShowTaskViewButton` | `0` |  | Tombol Task View disembunyikan (Win+Tab tetap jalan). |

### Start menu

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer` | `HideRecentlyAddedApps` | `1` |  | Daftar pin Start ditulis Set-ShellLayout.ps1 (bergantung pada browser yang terpasang). Di sini hanya bagian "Recent"/rekomendasi yang disembunyikan: aplikasi yang baru dipasang, aplikasi yang sering dipakai, dan file terakhir. |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer` | `HideRecommendedSection` | `1` |  | Daftar pin Start ditulis Set-ShellLayout.ps1 (bergantung pada browser yang terpasang). Di sini hanya bagian "Recent"/rekomendasi yang disembunyikan: aplikasi yang baru dipasang, aplikasi yang sering dipakai, dan file terakhir. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | `Start_TrackDocs` | `0` |  | Daftar pin Start ditulis Set-ShellLayout.ps1 (bergantung pada browser yang terpasang). Di sini hanya bagian "Recent"/rekomendasi yang disembunyikan: aplikasi yang baru dipasang, aplikasi yang sering dipakai, dan file terakhir. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | `Start_TrackProgs` | `0` |  | Daftar pin Start ditulis Set-ShellLayout.ps1 (bergantung pada browser yang terpasang). Di sini hanya bagian "Recent"/rekomendasi yang disembunyikan: aplikasi yang baru dipasang, aplikasi yang sering dipakai, dan file terakhir. |

### Mode gelap

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize` | `AppsUseLightTheme` | `0` |  |  |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize` | `SystemUsesLightTheme` | `0` |  |  |

### File Explorer

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | `LaunchTo` | `1` |  | Explorer membuka "This PC", bukan Home. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | `HideFileExt` | `0` |  | Ekstensi file ditampilkan (membantu membedakan .exe dari dokumen). |

### Wallpaper TGO

| Kunci | Nilai | Data | Syarat | Keterangan |
|---|---|---|---|---|
| `HKCU\Control Panel\Desktop` | `WallPaper` | `C:\Windows\Web\Wallpaper\TGOS\TGOS.png` |  | File gambarnya disalin skrip Install-Toolbox.ps1 ke C:\Windows\Web\Wallpaper\TGOS. 10 = Fill. JPEGImportQuality 100 mencegah Windows mengompres ulang wallpaper, yang membuat gradasi gelapnya bergaris. |
| `HKCU\Control Panel\Desktop` | `WallpaperStyle` | `10` |  | File gambarnya disalin skrip Install-Toolbox.ps1 ke C:\Windows\Web\Wallpaper\TGOS. 10 = Fill. JPEGImportQuality 100 mencegah Windows mengompres ulang wallpaper, yang membuat gradasi gelapnya bergaris. |
| `HKCU\Control Panel\Desktop` | `TileWallpaper` | `0` |  | File gambarnya disalin skrip Install-Toolbox.ps1 ke C:\Windows\Web\Wallpaper\TGOS. 10 = Fill. JPEGImportQuality 100 mencegah Windows mengompres ulang wallpaper, yang membuat gradasi gelapnya bergaris. |
| `HKCU\Control Panel\Desktop` | `JPEGImportQuality` | `100` |  | File gambarnya disalin skrip Install-Toolbox.ps1 ke C:\Windows\Web\Wallpaper\TGOS. 10 = Fill. JPEGImportQuality 100 mencegah Windows mengompres ulang wallpaper, yang membuat gradasi gelapnya bergaris. |


## Penyelesaian (`90-finalize.yml`)

| Skrip | Syarat | Keterangan |
|---|---|---|
| `Scripts\Install-Toolbox.ps1` |  | Menyalin TGOS Toolbox ke drive sistem, membuat pintasan di Desktop, dan menyalin wallpaper. |
| `Scripts\Write-InstallInfo.ps1` `-Modules "preflight,debloat-appx,privacy,services,scheduled-tasks,performance,security-options,components,interface"` |  | Menulis %ProgramData%\TGOS\install-info.txt: versi TGOS, edisi, build, waktu, hasil restore point, dan modul yang dijalankan. Nama modul di -Modules harus sama dengan modul yang dipanggil main.yml (dijaga tools/validate.py). |
| `Scripts\Set-ShellLayout.ps1` |  | Menyusun ulang pin taskbar dan Start menjadi set TGOS. Dijalankan setelah opsi tercatat (skrip membaca opsi "remove-store" dari install-info.txt) dan setelah browser terpasang. Skrip ini menghentikan Explorer; aksi berikutnya menjalankannya lagi sebagai pengguna yang login. |
| `Scripts\Start-Shell.ps1` |  |  |
| `TGOS Toolbox\Support\Test-TgosResult.ps1` |  | Mencocokkan sistem dengan expected-state.json dan menulis %ProgramData%\TGOS\verify-report.txt. Hanya membaca; tidak fatal. |
