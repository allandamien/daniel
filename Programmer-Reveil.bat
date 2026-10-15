@echo off
rem Verifie que le script est bien a cote (dossier ZIP decompresse).
if not exist "%~dp0Programmer-Reveil.ps1" (
    echo.
    echo  Le fichier Programmer-Reveil.ps1 est introuvable.
    echo.
    echo  Vous avez sans doute lance ce fichier directement depuis le ZIP.
    echo  Fermez cette fenetre, faites un clic droit sur le fichier ZIP,
    echo  choisissez "Extraire tout...", puis relancez Programmer-Reveil.bat
    echo  depuis le dossier extrait.
    echo.
    pause
    exit /b
)
rem Relance ce fichier en administrateur si besoin, puis programme le reveil.
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Programmer-Reveil.ps1"
echo.
pause
