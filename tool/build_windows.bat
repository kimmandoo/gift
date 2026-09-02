@echo off
setlocal
cd /d "%~dp0.."

dart run tool\build_desktop.dart windows
if errorlevel 1 (
    echo Windows build failed.
    pause
    exit /b 1
)

echo Windows release build completed.
pause
