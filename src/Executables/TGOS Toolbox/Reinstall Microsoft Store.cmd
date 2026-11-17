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
echo.
pause
