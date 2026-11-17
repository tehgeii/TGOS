@echo off
rem TGOS Toolbox - download and install software from official sites
setlocal
fltmc >nul 2>&1
if not errorlevel 1 goto run
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b
:run
set "INSTALLER=%~dp0Support\Install-Software.ps1"
:menu
cls
echo TGOS Toolbox - Install Software
echo.
echo Each program is downloaded from its official site, and its digital signature
echo is checked before it runs. Needs internet. A program that is already
echo installed is installed again (repaired or updated).
echo Diunduh dari situs resminya dan tanda tangannya diperiksa. Butuh internet.
echo.
echo    1  Brave
echo    2  Google Chrome
echo    3  Mozilla Firefox
echo    4  7-Zip
echo    5  Game runtimes (Visual C++ 2005-2022, DirectX, XNA)
echo    6  .NET (Framework 3.5 and Desktop Runtime)
echo    7  Steam
echo    8  Epic Games Launcher
echo    9  EA app
echo   10  Ubisoft Connect
echo   11  Discord (for this account)
echo   12  Spotify (for this account)
echo    0  Exit / Keluar
echo.
set "PICK="
set /p "PICK=Type a number, then Enter / Ketik nomor lalu Enter: "
if not defined PICK exit /b 0
if "%PICK%"=="0" exit /b 0
if "%PICK%"=="1" call :install brave
if "%PICK%"=="2" call :install chrome
if "%PICK%"=="3" call :install firefox
if "%PICK%"=="4" call :install 7zip
if "%PICK%"=="5" call :install vcredist
if "%PICK%"=="5" call :install vcredist-legacy
if "%PICK%"=="5" call :install xna
if "%PICK%"=="5" call :install directx
if "%PICK%"=="6" call :install netfx3
if "%PICK%"=="6" call :install dotnet
if "%PICK%"=="7" call :install steam
if "%PICK%"=="8" call :install epic
if "%PICK%"=="9" call :install ea
if "%PICK%"=="10" call :install ubisoft
if "%PICK%"=="11" call :install discord
if "%PICK%"=="12" call :install spotify
echo.
pause
goto menu
:install
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%" -Item %1 -Force
exit /b
