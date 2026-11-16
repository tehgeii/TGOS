@echo off
rem TGOS Toolbox - membuat TGOS-report.zip di Desktop untuk memeriksa hasil instalasi
setlocal
fltmc >nul 2>&1
if not errorlevel 1 goto run
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b
:run
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Support\Collect-TgosReport.ps1" -OutputDirectory "%USERPROFILE%\Desktop"
echo.
pause
