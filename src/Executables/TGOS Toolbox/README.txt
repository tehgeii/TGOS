TGOS Toolbox
============

Double-click a file to change one thing. Each file asks for Administrator rights.
"Turn OFF" disables a Windows feature for performance; "Turn ON" restores it.
Most changes need a restart.

Klik dua kali sebuah file untuk mengubah satu hal. "Turn OFF" mematikan fitur Windows
demi performa; "Turn ON" mengembalikannya. Sebagian besar perubahan butuh restart.

Windows features
----------------
  Windows Defender       Antivirus scanning. OFF = no antivirus protection.
                         Turn off Tamper Protection in Windows Security first.
  Core Isolation VBS     Virtualization-Based Security and Memory Integrity.
  CPU Mitigations        Spectre/Meltdown mitigations. OFF helps mostly on older CPUs.
  Automatic Updates      OFF = Windows only updates when you check manually.
  Search Indexing        OFF = slower file search, less background disk activity.
  Hibernation            Hibernation and Fast Startup.
  CPU Core Parking       OFF = all CPU cores stay active. Not for laptops.
  Extra Services         Printing, Windows troubleshooters and network discovery.
                         Turn ON if you need a printer.
  Telemetry Collectors   Windows data collectors. Turn ON before a Windows feature
                         upgrade (for example 25H2 to 26H2), then OFF again.

Software (needs internet)
-------------------------
  Install Browser - ...  Downloads Brave, Chrome or Firefox from its official site,
                         checks its digital signature, then installs it.
  Install 7-Zip          Same, for 7-Zip.
  Install Game Runtimes  Visual C++ and DirectX runtimes from Microsoft.
  Reinstall Microsoft Store
                         Tries to bring the Store back if you removed it. Not
                         guaranteed: if it has not come back after a restart, use
                         Settings > System > Recovery > "Fix problems using
                         Windows Update".

Other
-----
  Reset Taskbar and Start
                         Rebuilds the taskbar and Start pins as the TGOS set.
                         Your own pins are removed.
  Collect TGOS Report    Makes TGOS-report.zip on the Desktop: a check of every TGOS
                         change plus a system snapshot. It changes nothing.

Firewall, UAC, Secure Boot and TPM are never changed by TGOS.

Every change made here is written to C:\ProgramData\TGOS\toolbox.log.
