@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo Starting MediaSnag...
echo.
python\python.exe app\launcher.pyw
echo.
echo Press any key to exit...
pause >nul
