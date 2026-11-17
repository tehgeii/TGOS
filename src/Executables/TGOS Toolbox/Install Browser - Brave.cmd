@echo off
rem TGOS Toolbox - download and install Brave from its official site
setlocal
fltmc >nul 2>&1
if not errorlevel 1 goto run
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b
:run
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Support\Install-Software.ps1" -Item brave -Force
echo.
pause
