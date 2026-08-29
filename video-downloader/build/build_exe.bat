@echo off
chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion

echo =========================================
echo   MediaSnag - Windows Build Script
echo =========================================
echo.

set "BUILD_DIR=%~dp0"
set "PROJECT_DIR=%BUILD_DIR%.."
set "STAGING_DIR=%BUILD_DIR%staging"
set "DOWNLOADS_DIR=%BUILD_DIR%downloads-win"

set "PYTHON_VERSION=3.12.3"
set "PYTHON_TAG=20240415"
set "YTDLP_VERSION=2024.08.06"

set "PYTHON_URL=https://github.com/astral-sh/python-build-standalone/releases/download/%PYTHON_TAG%/cpython-%PYTHON_VERSION%+%PYTHON_TAG%-x86_64-pc-windows-msvc-install_only.tar.gz"
set "YTDLP_URL=https://github.com/yt-dlp/yt-dlp/releases/download/%YTDLP_VERSION%/yt-dlp.exe"
set "FFMPEG_URL=https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"

set "PYTHON_ARCHIVE=cpython-%PYTHON_VERSION%+%PYTHON_TAG%-x86_64-pc-windows-msvc-install_only.tar.gz"
set "FFMPEG_ARCHIVE=ffmpeg-master-latest-win64-gpl.zip"

:: Clean staging
echo [1/6] Cleaning staging directory...
if exist "%STAGING_DIR%" rmdir /S /Q "%STAGING_DIR%"
mkdir "%STAGING_DIR%"
mkdir "%STAGING_DIR%\bin"
mkdir "%STAGING_DIR%\app"
mkdir "%DOWNLOADS_DIR%" 2>nul

:: Download Python standalone
echo [2/6] Downloading Python %PYTHON_VERSION%...
if not exist "%DOWNLOADS_DIR%\%PYTHON_ARCHIVE%" (
    powershell -NoProfile -Command "Invoke-WebRequest -Uri '%PYTHON_URL%' -OutFile '%DOWNLOADS_DIR%\%PYTHON_ARCHIVE%'"
    if errorlevel 1 (
        echo ERROR: Failed to download Python
        exit /b 1
    )
) else (
    echo   Already downloaded, skipping.
)

echo   Extracting Python...
tar -xzf "%DOWNLOADS_DIR%\%PYTHON_ARCHIVE%" -C "%STAGING_DIR%"
if errorlevel 1 (
    echo ERROR: Failed to extract Python. Make sure tar is available (Windows 10 1803+^)
    exit /b 1
)
:: python-build-standalone extracts to "python/" directory
if not exist "%STAGING_DIR%\python\python.exe" (
    echo ERROR: python.exe not found after extraction
    exit /b 1
)
echo   Python extracted OK.

:: Download yt-dlp
echo [3/6] Downloading yt-dlp %YTDLP_VERSION%...
if not exist "%DOWNLOADS_DIR%\yt-dlp.exe" (
    powershell -NoProfile -Command "Invoke-WebRequest -Uri '%YTDLP_URL%' -OutFile '%DOWNLOADS_DIR%\yt-dlp.exe'"
    if errorlevel 1 (
        echo ERROR: Failed to download yt-dlp
        exit /b 1
    )
)
copy /Y "%DOWNLOADS_DIR%\yt-dlp.exe" "%STAGING_DIR%\bin\yt-dlp.exe" >nul
echo   yt-dlp OK.

:: Download ffmpeg
echo [4/6] Downloading ffmpeg...
if not exist "%DOWNLOADS_DIR%\%FFMPEG_ARCHIVE%" (
    powershell -NoProfile -Command "Invoke-WebRequest -Uri '%FFMPEG_URL%' -OutFile '%DOWNLOADS_DIR%\%FFMPEG_ARCHIVE%'"
    if errorlevel 1 (
        echo ERROR: Failed to download ffmpeg
        exit /b 1
    )
) else (
    echo   Already downloaded, skipping.
)

echo   Extracting ffmpeg...
powershell -NoProfile -Command "Expand-Archive -Path '%DOWNLOADS_DIR%\%FFMPEG_ARCHIVE%' -DestinationPath '%DOWNLOADS_DIR%\ffmpeg-temp' -Force"
:: Find ffmpeg.exe inside the extracted folder
for /D %%D in ("%DOWNLOADS_DIR%\ffmpeg-temp\ffmpeg-*") do (
    copy /Y "%%D\bin\ffmpeg.exe" "%STAGING_DIR%\bin\ffmpeg.exe" >nul
    copy /Y "%%D\bin\ffprobe.exe" "%STAGING_DIR%\bin\ffprobe.exe" >nul
)
if not exist "%STAGING_DIR%\bin\ffmpeg.exe" (
    echo ERROR: ffmpeg.exe not found in archive
    exit /b 1
)
rmdir /S /Q "%DOWNLOADS_DIR%\ffmpeg-temp" 2>nul
echo   ffmpeg OK.

:: Copy app source
echo [5/6] Copying app source...
xcopy /E /Y /Q "%PROJECT_DIR%\app\*" "%STAGING_DIR%\app\" >nul
copy /Y "%PROJECT_DIR%\app\templates\universal_downloader.user.js" "%STAGING_DIR%\userscript.user.js" >nul
echo   App source OK.

:: Check Inno Setup
echo [6/6] Building installer...
set "ISCC="
if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (
    set "ISCC=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
) else if exist "C:\Program Files\Inno Setup 6\ISCC.exe" (
    set "ISCC=C:\Program Files\Inno Setup 6\ISCC.exe"
) else if exist "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" (
    set "ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
)

if not defined ISCC (
    echo.
    echo ERROR: Inno Setup 6 not found!
    echo.
    echo Please download and install Inno Setup 6 from:
    echo   https://jrsoftware.org/isdl.php
    echo.
    echo After installation, re-run this script.
    echo.
    echo Alternatively, the staging directory is ready at:
    echo   %STAGING_DIR%
    echo You can manually copy it to a Windows machine with Inno Setup.
    exit /b 1
)

echo   Using ISCC: %ISCC%
"%ISCC%" "%BUILD_DIR%mediasnag.iss"
if errorlevel 1 (
    echo ERROR: Inno Setup compilation failed
    exit /b 1
)

echo.
echo =========================================
echo   Build complete!
echo =========================================
echo.
echo   Output: %BUILD_DIR%installer\windows\output\MediaSnag-Setup.exe
echo.

:: Copy to desktop
if exist "%BUILD_DIR%installer\windows\output\MediaSnag-Setup.exe" (
    copy /Y "%BUILD_DIR%installer\windows\output\MediaSnag-Setup.exe" "%USERPROFILE%\Desktop\MediaSnag-Setup.exe" >nul
    echo   Copied to Desktop: MediaSnag-Setup.exe
)
