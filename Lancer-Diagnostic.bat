@echo off
rem Verifie que le script est bien a cote (dossier ZIP decompresse).
if not exist "%~dp0Diagnostic-PC.ps1" (
    echo.
    echo  Le fichier Diagnostic-PC.ps1 est introuvable.
    echo.
    echo  Vous avez sans doute lance ce fichier directement depuis le ZIP.
    echo  Fermez cette fenetre, faites un clic droit sur le fichier ZIP,
    echo  choisissez "Extraire tout...", puis relancez Lancer-Diagnostic.bat
    echo  depuis le dossier extrait.
    echo.
    pause
    exit /b
)
rem Relance ce fichier en administrateur si besoin, puis lance le diagnostic.
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Diagnostic-PC.ps1"
echo.
pause
