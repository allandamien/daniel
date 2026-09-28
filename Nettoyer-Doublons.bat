@echo off
rem Verifie que le script est bien a cote (dossier ZIP decompresse).
if not exist "%~dp0Nettoyer-Doublons.ps1" (
    echo.
    echo  Le fichier Nettoyer-Doublons.ps1 est introuvable.
    echo.
    echo  Vous avez sans doute lance ce fichier directement depuis le ZIP.
    echo  Fermez cette fenetre, faites un clic droit sur le fichier ZIP,
    echo  choisissez "Extraire tout...", puis relancez Nettoyer-Doublons.bat
    echo  depuis le dossier extrait.
    echo.
    pause
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Nettoyer-Doublons.ps1"
echo.
pause
