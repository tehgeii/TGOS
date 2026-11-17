@echo off
rem TGOS Toolbox - rebuild the taskbar and Start pins as the TGOS set (your own pins are removed)
setlocal
fltmc >nul 2>&1
if not errorlevel 1 goto run
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b
:run
echo This replaces ALL taskbar and Start pins with the TGOS set. Your own pins are removed.
echo Ini mengganti SEMUA pin taskbar dan Start dengan set TGOS. Pin buatanmu ikut hilang.
echo Close this window now to cancel.
pause
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Support\Set-ShellLayout.ps1" -RestartExplorer
echo.
pause
