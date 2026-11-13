# Daftar tweak TGOS

> File ini dibuat otomatis oleh `tools/make-tweaks-doc.py` dari file di
> `src/Configuration/Tasks/`. Jangan diedit langsung: ubah YAML-nya (termasuk komentar
> di atas tiap aksi), lalu jalankan skrip itu lagi.

Versi playbook: `0.1.0`

Kolom **Syarat** kosong berarti tweak selalu diterapkan. `opsi: nama` berarti hanya bila
opsi itu dicentang di AME Wizard; `build: ...` berarti hanya di build Windows tersebut.

## Yang tidak disentuh versi ini

Layanan Windows, tugas terjadwal, Windows Defender, Windows Update, Microsoft Edge,
OneDrive, pengaturan performa, dan tampilan. Semua itu dijadwalkan di versi berikutnya
(lihat [PLAN.md](../PLAN.md#12-roadmap)).

## Cara mengembalikan

| Jenis | Cara |
|---|---|
| Aplikasi yang dihapus | Pasang lagi dari Microsoft Store (cari namanya), atau `winget install <nama>`. |
| Nilai di `...\Policies\...` | Bawaan Windows: nilainya tidak ada. Hapus nilainya di Registry Editor, lalu restart. |
| Nilai `HKCU` selain Policies | Sebagian besar punya tombol di Settings (Privacy & security, Personalization > Start, System > Notifications). Atau hapus nilainya supaya Windows memakai bawaan. |
| Semua perubahan registry sekaligus | Pulihkan restore point "Before TGOS <versi>" lewat *Create a restore point* > *System Restore*. Restore point **tidak** mengembalikan aplikasi yang dihapus. |

Catatan: apakah aplikasi yang dihapus bisa dipasang lagi dari Store, dan apakah restore
point berhasil dibuat dari dalam playbook, masih harus dibuktikan di uji VM
(lihat [TESTING.md](TESTING.md)).


## Aplikasi bawaan (`10-debloat-appx.yml`)

Nama paket memakai awalan + `*`. Paket yang tidak ada di sistem dilewati.


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
| Microsoft 365 (Office hub) | `Microsoft.MicrosoftOfficeHub*` |  |  |
| Outlook (new) | `Microsoft.OutlookForWindows*` |  |  |
| Mail and Calendar | `microsoft.windowscommunicationsapps*` |  |  |
| People | `Microsoft.People*` |  |  |
| Microsoft To Do | `Microsoft.Todos*` |  |  |
| Power Automate | `Microsoft.PowerAutomateDesktop*` |  |  |
| Dev Home | `Microsoft.Windows.DevHome*` |  |  |
| Teams versi pribadi (22H2/23H2) | `MicrosoftTeams_*` |  |  |
| Microsoft Teams | `MSTeams_*` |  |  |
| Clipchamp | `Clipchamp.Clipchamp*` |  |  |

### Utilitas yang jarang dipakai

| Aplikasi | Paket | Syarat | Keterangan |
|---|---|---|---|
| Maps | `Microsoft.WindowsMaps*` |  |  |
| Phone Link | `Microsoft.YourPhone*` |  |  |
| Sound Recorder | `Microsoft.WindowsSoundRecorder*` |  |  |
| Clock | `Microsoft.WindowsAlarms*` |  |  |
| Sticky Notes | `Microsoft.MicrosoftStickyNotes*` |  |  |
| Family | `MicrosoftCorporationII.MicrosoftFamily*` |  |  |
| Cortana | `Microsoft.549981C3F5F10*` |  |  |

### Opsi: Copilot dan Widgets

| Aplikasi | Paket | Syarat | Keterangan |
|---|---|---|---|
| Copilot | `Microsoft.Copilot*` | opsi: `remove-ai-widgets` |  |
| Copilot provider | `Microsoft.Windows.Ai.Copilot.Provider*` | opsi: `remove-ai-widgets` |  |
| Widgets (Windows Web Experience Pack) | `MicrosoftWindows.Client.WebExperience*` | opsi: `remove-ai-widgets` |  |
| Widgets Platform Runtime | `Microsoft.WidgetsPlatformRuntime*` | opsi: `remove-ai-widgets` |  |

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

Semua berupa nilai registry `REG_DWORD`. Nilai `HKCU` diterapkan ke semua pengguna.


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
| `HKCU\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot` | `TurnOffWindowsCopilot` | `1` | opsi: `remove-ai-widgets`; build: `<26100` | Copilot versi panel samping hanya ada di 22H2 dan 23H2; di 24H2 ke atas Copilot adalah aplikasi biasa yang dihapus modul 10. |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | `ShowCopilotButton` | `0` | opsi: `remove-ai-widgets`; build: `<26100` | Copilot versi panel samping hanya ada di 22H2 dan 23H2; di 24H2 ke atas Copilot adalah aplikasi biasa yang dihapus modul 10. |
