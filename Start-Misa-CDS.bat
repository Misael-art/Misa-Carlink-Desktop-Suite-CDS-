@echo off
TITLE Misa CDS V5.2 Launcher
echo Iniciando Misa Carlink Desktop Suite...
echo.
powershell.exe -ExecutionPolicy Bypass -File "%~dp0setup_android.ps1"
pause
