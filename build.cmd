@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1"
set "result=%errorlevel%"
if not defined CI pause
exit /b %result%
