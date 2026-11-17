@echo off
rem TGOS Toolbox - clean temporary files, update caches, error reports and old components
setlocal
fltmc >nul 2>&1
if not errorlevel 1 goto run
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b
:run
echo Deep clean: removes temporary files, Windows Update caches, error reports, crash
echo dumps and replaced Windows components, and turns reserved storage off. It takes
echo a few minutes. Your files, games and the Recycle Bin are not touched.
echo Membersihkan file sementara dan sampah Windows. File pribadi tidak disentuh.
echo.
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Support\Invoke-DeepClean.ps1"
echo.
pause
