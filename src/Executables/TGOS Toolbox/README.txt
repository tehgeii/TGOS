TGOS Toolbox
============

Double-click a file to use it. Each file asks for Administrator rights.
Klik dua kali sebuah file. Tiap file meminta hak Administrator.

In this folder
--------------
  Install Software       Menu: downloads a program from its official site, checks its
                         digital signature, then installs it (browsers, 7-Zip, game
                         runtimes). Type a number and press Enter. Needs internet.
                         It also adds a missing Start menu or desktop shortcut for an
                         app that is already installed.
  Reinstall Microsoft Store
                         Tries to bring the Store back if you removed it. Not
                         guaranteed: if it has not come back after a restart, use
                         Settings > System > Recovery > "Fix problems using
                         Windows Update".
  Reset Taskbar and Start
                         Rebuilds the taskbar and Start pins as the TGOS set.
                         Your own pins are removed.
  Collect TGOS Report    Makes TGOS-report.zip on the Desktop: a check of every TGOS
                         change plus a system snapshot. It changes nothing. User and
                         computer names in it are replaced by <user> and <computer>.

Turn ON or OFF (folder)
-----------------------
"Turn OFF" disables a Windows feature for performance; "Turn ON" restores it.
Most changes need a restart.
"Turn OFF" mematikan fitur Windows demi performa; "Turn ON" mengembalikannya.

  Windows Defender       Antivirus scanning. OFF = no antivirus protection.
                         Turn off Tamper Protection in Windows Security first.
  Core Isolation VBS     Virtualization-Based Security and Memory Integrity.
  CPU Mitigations        Spectre/Meltdown mitigations. OFF helps mostly on older CPUs.
  Windows Updates        Pause = no Windows updates until you resume them.
                         Resume = updates again (same as "Resume updates" in
                         Settings > Windows Update).
  Automatic Updates      OFF = Windows only updates when you check manually.
  Driver Updates         OFF = Windows Update does not replace your drivers (for
                         example the NVIDIA or AMD driver you installed yourself).
  Search Indexing        OFF = slower file search, less background disk activity.
  Hibernation            Hibernation and Fast Startup.
  CPU Core Parking       OFF = all CPU cores stay active. Not for laptops.
  Extra Services         Printing, Windows troubleshooters and network discovery.
                         Turn ON if you need a printer.
  Telemetry Collectors   Windows data collectors. Turn ON before a Windows feature
                         upgrade (for example 25H2 to 26H2), then OFF again.
  Background Apps        OFF = Microsoft Store apps do not run in the background.
  Lock Screen            OFF = the picture screen before sign-in is skipped. Your
                         password or PIN is still asked.
  Xbox Game Bar          OFF = the controller buttons do not open Game Bar, and Win+G
                         is blocked (from the next sign-in). ON removes the TGOS
                         blocks; if the Game Bar app was removed, install "Xbox Game
                         Bar" again from the Microsoft Store.
  TGO Login Screen       ON = TGO picture on the lock and sign-in screens.
                         OFF = the Windows picture.

After a restart
---------------
If Windows was busy during the install (for example .NET Framework 3.5 could not be
downloaded, or Windows was using its reserved storage for an update), TGOS finishes
that step by itself a few minutes after the next restart, in the background, up to
three times. The result is written to toolbox.log.
Bila Windows sedang sibuk saat instalasi, TGOS menyelesaikan langkah itu sendiri
beberapa menit setelah restart berikutnya, di latar belakang.

Firewall, UAC, Secure Boot and TPM are never changed by TGOS.

Every change made here is written to C:\ProgramData\TGOS\toolbox.log.
