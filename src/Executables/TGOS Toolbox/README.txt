TGOS Toolbox
============

Double-click a file to change one Windows feature. Each file asks for Administrator
rights. "Turn OFF" disables the Windows feature for performance; "Turn ON" restores the
Windows default. Most changes need a restart.

Klik dua kali sebuah file untuk mengubah satu fitur Windows. "Turn OFF" mematikan fitur
itu demi performa; "Turn ON" mengembalikannya ke bawaan Windows. Sebagian besar perubahan
butuh restart.

  Windows Defender       Antivirus scanning. OFF = no antivirus protection.
                         Turn off Tamper Protection in Windows Security first.
  Core Isolation VBS     Virtualization-Based Security and Memory Integrity.
  CPU Mitigations        Spectre/Meltdown mitigations. OFF helps mostly on older CPUs.
  Automatic Updates      OFF = Windows only updates when you check manually.
  Search Indexing        OFF = slower file search, less background disk activity.
  Hibernation            Hibernation and Fast Startup.

  Collect TGOS Report    Makes TGOS-report.zip on the Desktop: a check of every TGOS
                         change plus a system snapshot. It changes nothing.

Firewall, UAC, Secure Boot and TPM are never changed by TGOS.

Every change made here is written to C:\ProgramData\TGOS\toolbox.log.
