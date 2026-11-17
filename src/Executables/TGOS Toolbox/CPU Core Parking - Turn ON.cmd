@echo off
rem TGOS Toolbox - CPU Core Parking: turn ON
setlocal
fltmc >nul 2>&1
if not errorlevel 1 goto run
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b
:run
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Support\Set-TgosFeature.ps1" -Feature CoreParking -State On
echo.
pause
