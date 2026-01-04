@echo off
TITLE Misa CDS V5.3 Launcher
echo Iniciando Misa Carlink Desktop Suite...
echo.
powershell.exe -ExecutionPolicy Bypass -File "%~dp0setup_android.ps1"
pause
