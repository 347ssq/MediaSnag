@echo off
chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion

echo =========================================
echo   MediaSnag - Windows Installer
echo =========================================
echo.

set "INSTALL_DIR=%LOCALAPPDATA%\ytdlp"
set "SCRIPT_DIR=%~dp0"

echo 安装目录: %INSTALL_DIR%
echo.

:: Step 1: Create directories
echo [1/5] 创建安装目录...
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
if not exist "%INSTALL_DIR%\bin" mkdir "%INSTALL_DIR%\bin"
if not exist "%INSTALL_DIR%\userscript" mkdir "%INSTALL_DIR%\userscript"

:: Step 2: Extract payload
echo [2/5] 解压运行环境...
if exist "%SCRIPT_DIR%\windows\runtime.zip" (
    powershell -NoProfile -Command "Expand-Archive -Path '%SCRIPT_DIR%\windows\runtime.zip' -DestinationPath '%INSTALL_DIR%' -Force"
) else (
    echo   未找到预打包负载，将使用系统 Python...
)

:: Step 3: Copy app source
echo [3/5] 安装应用程序...
if exist "%SCRIPT_DIR%\app" (
    xcopy /E /Y /Q "%SCRIPT_DIR%\app\*" "%INSTALL_DIR%\bin\" >nul
)

:: Create VBS launcher (no console window)
echo [4/5] 创建启动器...
(
echo Set WshShell = CreateObject^("WScript.Shell"^)
echo WshShell.Run "pythonw -m app", 0, False
) > "%INSTALL_DIR%\launch.vbs"

:: Create batch launcher for URL scheme
(
echo @echo off
echo set "INSTALL_DIR=%%LOCALAPPDATA%%\ytdlp"
echo set "PYTHON=%%INSTALL_DIR%%\bin\python.exe"
echo if not exist "%%PYTHON%%" set "PYTHON=python"
echo "%%PYTHON%%" -c "import sys; sys.path.insert(0, '%%INSTALL_DIR%%\\bin'^); from app.__main__ import main; sys.argv = ['mediasnag', '%%1'^]; main(^)"
) > "%INSTALL_DIR%\url_handler.bat"

:: Step 5: Register URL scheme
echo [5/5] 注册 URL Scheme...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\register_scheme.ps1"

echo.
echo =========================================
echo   安装完成!
echo =========================================
echo.
echo 已安装:
echo   - 运行环境 → %INSTALL_DIR%\
echo   - URL Scheme: ytdl:// ytdla://
echo.

:: Start server and open userscript
echo 正在启动服务器...
start "" /B "%INSTALL_DIR%\bin\python.exe" -c "import sys; sys.path.insert(0, '%INSTALL_DIR%\bin'); from app.__main__ import main; sys.argv = ['mediasnag', '--serve']; main()"
timeout /t 2 /nobreak >nul

echo 请在浏览器中安装 Tampermonkey 脚本:
echo   http://127.0.0.1:19527/userscript.user.js
echo.
start "" "http://127.0.0.1:19527/userscript.user.js"

echo 按任意键退出安装程序...
pause >nul
