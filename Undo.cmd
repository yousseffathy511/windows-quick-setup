@echo off
setlocal
title Windows Quick Setup - Undo
set "SCRIPT=%~dp0setup.ps1"
if exist "%SCRIPT%" goto run
set "SCRIPT=%LOCALAPPDATA%\WindowsQuickSetup\setup.ps1"
if exist "%SCRIPT%" goto run

echo Getting the setup script from GitHub...
set "SCRIPT=%TEMP%\windows-quick-setup.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/yousseffathy511/windows-quick-setup/main/setup.ps1' -OutFile (Join-Path $env:TEMP 'windows-quick-setup.ps1')"
if not exist "%SCRIPT%" (
    echo Could not download the setup script.
    pause
    exit /b 1
)

:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Undo %*
echo.
echo Finished. You can close this window.
pause >nul
