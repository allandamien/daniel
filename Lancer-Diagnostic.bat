@echo off
rem Relance ce fichier en administrateur si besoin, puis lance le diagnostic.
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Diagnostic-PC.ps1"
echo.
pause
