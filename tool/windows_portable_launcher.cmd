@echo off
setlocal
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0windows_portable_launcher.ps1" -PayloadPath "%~dp0payload.zip"
exit /b %errorlevel%
