@echo off
setlocal
cd /d "%~dp0.."

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_windows.ps1"
if errorlevel 1 (
    echo Windows build failed.
    pause
    exit /b 1
)

echo Windows release, portable, and setup bundle artifacts completed.
pause
