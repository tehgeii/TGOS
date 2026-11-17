@echo off
rem TGOS Toolbox - reinstall the Microsoft Store (needs internet)
setlocal
fltmc >nul 2>&1
if not errorlevel 1 goto run
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b
:run
echo Reinstalling the Microsoft Store. This needs internet and can take a few minutes.
echo Memasang ulang Microsoft Store. Butuh internet dan bisa makan beberapa menit.
wsreset.exe -i
echo.
echo Windows downloads the Store in the background. It appears in Start when it is done.
echo This is not guaranteed to work. If the Store has not come back after a restart,
echo use Settings, System, Recovery, "Fix problems using Windows Update".
echo Tidak dijamin berhasil. Bila Store belum kembali setelah restart, gunakan
echo Settings, System, Recovery, "Fix problems using Windows Update".
echo.
pause
