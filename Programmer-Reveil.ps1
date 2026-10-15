<#
    Programmer-Reveil.ps1
    Fait sortir le PC de la veille tous les jours à 7h00.

    Le script crée une tâche planifiée « Réveil PC 7h » qui réveille le PC,
    et autorise les minuteurs de réveil dans les options d'alimentation.
    Il ne peut pas allumer un PC complètement éteint : pour cela, il faut
    régler l'option « RTC Alarm » dans le BIOS.
    Si le réveil est déjà programmé, le script propose de le supprimer.
#>

$ErrorActionPreference = 'Stop'
$nomTache = 'Réveil PC 7h'
$heure = '07:00'

Write-Host ''
$existante = Get-ScheduledTask -TaskName $nomTache -ErrorAction SilentlyContinue
if ($existante) {
    Write-Host 'Le réveil de 7h00 est déjà programmé.' -ForegroundColor Cyan
    $reponse = Read-Host 'Voulez-vous le SUPPRIMER ? Tapez O pour oui, ou Entrée pour le garder'
    if ($reponse -match '^[oO]') {
        Unregister-ScheduledTask -TaskName $nomTache -Confirm:$false
        Write-Host 'Réveil supprimé. Le PC ne se réveillera plus tout seul.' -ForegroundColor Green
    } else {
        Write-Host "Rien n'a été changé." -ForegroundColor Green
    }
    return
}

# Tâche qui ne fait rien (cmd /c exit) : elle sert uniquement à réveiller le PC.
# Compte SYSTEM : fonctionne même si personne n'est connecté.
try {
    $action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c exit'
    $declencheur = New-ScheduledTaskTrigger -Daily -At $heure
    $parametres = New-ScheduledTaskSettingsSet -WakeToRun -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $compte = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $nomTache -Action $action -Trigger $declencheur -Settings $parametres `
        -Principal $compte -Description 'Sort le PC de la veille tous les jours à 7h00.' | Out-Null
} catch {
    Write-Host "Impossible de créer le réveil : $($_.Exception.Message)" -ForegroundColor Red
    return
}
Write-Host 'Réveil programmé tous les jours à 7h00.' -ForegroundColor Green

# Autoriser les minuteurs de réveil (sur secteur et sur batterie).
powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 1 | Out-Null
powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 1 | Out-Null
# Après un réveil automatique, Windows se rendort au bout de 2 minutes sans
# activité : on laisse 30 minutes pour avoir le temps d'arriver devant le PC.
powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP UNATTENDSLEEP 1800 2>$null | Out-Null
powercfg /setactive SCHEME_CURRENT | Out-Null
Write-Host 'Minuteurs de réveil autorisés dans les options d''alimentation.' -ForegroundColor Green

$prochain = (Get-ScheduledTaskInfo -TaskName $nomTache).NextRunTime
if ($prochain) {
    Write-Host ''
    Write-Host ("Prochain réveil : {0:dddd d MMMM 'à' HH'h'mm}" -f $prochain) -ForegroundColor Cyan
}

Write-Host ''
Write-Host 'IMPORTANT :' -ForegroundColor Yellow
Write-Host ' - Le soir, mettez le PC en VEILLE (Démarrer > Marche/Arrêt > Mettre en veille),'
Write-Host '   ou laissez-le se mettre en veille tout seul. Ne choisissez pas « Arrêter ».'
Write-Host ' - Un PC portable doit rester branché sur le secteur.'
Write-Host ' - L''écran peut rester noir au réveil : bougez la souris pour l''allumer.'
Write-Host ' - Pour supprimer le réveil, relancez simplement Programmer-Reveil.bat.'
