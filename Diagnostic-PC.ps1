<#
    Diagnostic-PC.ps1
    Vérifie l'état d'un PC Windows et produit un rapport lisible sur le Bureau.

    Le script ne modifie rien : il se contente de lire des informations.
    Lancez-le de préférence avec « Lancer-Diagnostic.bat » (qui demande les droits
    administrateur), sinon certaines vérifications seront incomplètes.
#>

$ErrorActionPreference = 'Stop'

$Rapport   = New-Object System.Collections.Generic.List[string]
$Problemes = New-Object System.Collections.Generic.List[object]

function Ligne([string]$Texte) { $Rapport.Add($Texte) }

function Titre([string]$Texte) {
    Ligne ''
    Ligne ('=' * 78)
    Ligne "  $Texte"
    Ligne ('=' * 78)
}

# Niveau : Critique, Attention ou Conseil
function Probleme([string]$Niveau, [string]$Texte) {
    $Problemes.Add([pscustomobject]@{ Niveau = $Niveau; Texte = $Texte })
}

function Tableau($Objets) {
    if (-not $Objets) { Ligne '  (rien à signaler)'; return }
    $texte = ($Objets | Format-Table -AutoSize -Wrap | Out-String -Width 220).TrimEnd()
    foreach ($l in ($texte -split "`r?`n")) { Ligne "  $l" }
}

function Section([string]$Nom, [scriptblock]$Code) {
    Write-Host "  - $Nom..." -ForegroundColor Gray
    Titre $Nom
    try { & $Code }
    catch { Ligne "  Vérification impossible : $($_.Exception.Message)" }
}

function Evenements([hashtable]$Filtre) {
    try { @(Get-WinEvent -FilterHashtable $Filtre -ErrorAction Stop) }
    catch { @() }  # aucun événement trouvé (ou journal absent)
}

function PremiereLigne([string]$Texte) {
    if (-not $Texte) { return '' }
    $l = ($Texte -split "`r?`n")[0].Trim()
    if ($l.Length -gt 110) { $l = $l.Substring(0, 107) + '...' }
    $l
}

$EstAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host ''
Write-Host 'Diagnostic du PC en cours, cela prend environ 1 minute...' -ForegroundColor Cyan
if (-not $EstAdmin) {
    Write-Host 'Attention : lancé sans droits administrateur, certaines vérifications seront incomplètes.' -ForegroundColor Yellow
    Probleme 'Conseil' "Le diagnostic a été lancé sans droits administrateur : relancez-le avec « Lancer-Diagnostic.bat » pour un rapport complet."
}

# ---------------------------------------------------------------------------
Section 'Système' {
    $os   = Get-CimInstance Win32_OperatingSystem
    $cs   = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $allume = (Get-Date) - $os.LastBootUpTime

    Ligne "  Ordinateur      : $($cs.Manufacturer) $($cs.Model)"
    Ligne "  Nom du PC       : $($env:COMPUTERNAME)"
    Ligne "  Windows         : $($os.Caption) (version $($os.Version), build $($os.BuildNumber))"
    Ligne "  Installé le     : $($os.InstallDate.ToString('dd/MM/yyyy'))"
    Ligne "  BIOS            : $($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)"
    Ligne ("  Allumé depuis   : {0} jour(s) {1} h {2} min" -f $allume.Days, $allume.Hours, $allume.Minutes)

    if ([int]$os.BuildNumber -lt 22000) {
        Probleme 'Attention' "Ce PC est sous Windows 10, qui ne reçoit plus de mises à jour de sécurité gratuites depuis le 14 octobre 2025. Passez à Windows 11 si le PC est compatible."
    }
    if ($allume.TotalDays -gt 7) {
        Probleme 'Conseil' ("Le PC n'a pas été redémarré depuis {0} jours. Un redémarrage règle souvent les lenteurs (« Arrêter » ne suffit pas toujours, choisissez « Redémarrer »)." -f $allume.Days)
    }
}

# ---------------------------------------------------------------------------
Section 'Processeur et mémoire' {
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $mesures = 1..3 | ForEach-Object {
        (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
        Start-Sleep -Seconds 1
    }
    $charge = [math]::Round(($mesures | Measure-Object -Average).Average)

    $os = Get-CimInstance Win32_OperatingSystem
    $totalGo = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $libreGo = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $utilise = [math]::Round(100 - ($os.FreePhysicalMemory / $os.TotalVisibleMemorySize * 100))

    Ligne "  Processeur      : $($cpu.Name.Trim()) ($($cpu.NumberOfCores) cœurs)"
    Ligne "  Charge actuelle : $charge %"
    Ligne "  Mémoire (RAM)   : $totalGo Go au total, $libreGo Go libres ($utilise % utilisée)"

    if ($charge -ge 80) {
        Probleme 'Attention' "Le processeur est très sollicité ($charge %) alors que le diagnostic tourne. Regardez la liste des programmes gourmands plus bas."
    }
    if ($utilise -ge 85) {
        Probleme 'Attention' "La mémoire est presque pleine ($utilise % utilisée). Fermez des programmes ou onglets, ou redémarrez le PC."
    }
    if ($totalGo -lt 7.5) {
        Probleme 'Conseil' "Le PC n'a que $totalGo Go de mémoire. Pour Windows 10/11, 8 Go est un minimum confortable : ajouter de la RAM peut nettement l'accélérer."
    }
}

# ---------------------------------------------------------------------------
Section 'Disques' {
    $physiques = @(Get-PhysicalDisk)
    Tableau ($physiques | Select-Object `
        @{ n = 'Disque';  e = { $_.FriendlyName } },
        @{ n = 'Type';    e = { $_.MediaType } },
        @{ n = 'Taille';  e = { '{0:N0} Go' -f ($_.Size / 1GB) } },
        @{ n = 'Santé';   e = { $_.HealthStatus } },
        @{ n = 'État';    e = { $_.OperationalStatus } })

    foreach ($d in $physiques) {
        if ("$($d.HealthStatus)" -ne 'Healthy') {
            Probleme 'Critique' "Le disque « $($d.FriendlyName) » est signalé en mauvaise santé ($($d.HealthStatus)). Sauvegardez vos fichiers importants DÈS MAINTENANT."
        }
        try {
            $f = $d | Get-StorageReliabilityCounter -ErrorAction Stop
            $details = @()
            if ($null -ne $f.Temperature -and $f.Temperature -gt 0) { $details += "température $($f.Temperature) °C" }
            if ($null -ne $f.Wear) { $details += "usure $($f.Wear) %" }
            if ($null -ne $f.ReadErrorsUncorrected) { $details += "erreurs de lecture $($f.ReadErrorsUncorrected)" }
            if ($details) { Ligne "  $($d.FriendlyName) : $($details -join ', ')" }

            if ($f.Wear -ge 80) {
                Probleme 'Attention' "Le disque « $($d.FriendlyName) » est usé à $($f.Wear) %. Prévoyez de le remplacer et gardez une sauvegarde à jour."
            }
            if ($f.ReadErrorsUncorrected -gt 0) {
                Probleme 'Critique' "Le disque « $($d.FriendlyName) » a $($f.ReadErrorsUncorrected) erreur(s) de lecture non corrigées : il est peut-être en train de lâcher. Sauvegardez vos fichiers."
            }
            if ($f.Temperature -ge 60) {
                Probleme 'Attention' "Le disque « $($d.FriendlyName) » chauffe ($($f.Temperature) °C)."
            }
        } catch { }
    }

    Ligne ''
    $volumes = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')
    Tableau ($volumes | Select-Object `
        @{ n = 'Lecteur'; e = { $_.DeviceID } },
        @{ n = 'Nom';     e = { $_.VolumeName } },
        @{ n = 'Taille';  e = { '{0:N0} Go' -f ($_.Size / 1GB) } },
        @{ n = 'Libre';   e = { '{0:N1} Go' -f ($_.FreeSpace / 1GB) } },
        @{ n = '% libre'; e = { '{0:N0} %' -f ($_.FreeSpace / $_.Size * 100) } })

    foreach ($v in $volumes) {
        if (-not $v.Size) { continue }
        $pct    = $v.FreeSpace / $v.Size * 100
        $libreGo = [math]::Round($v.FreeSpace / 1GB, 1)
        if ($pct -lt 10 -or $libreGo -lt 5) {
            Probleme 'Critique' ("Le lecteur {0} est presque plein ({1} Go libres). Windows ralentit fortement et les mises à jour peuvent échouer : libérez de la place (Paramètres > Système > Stockage)." -f $v.DeviceID, $libreGo)
        } elseif ($pct -lt 20) {
            Probleme 'Attention' ("Le lecteur {0} commence à être plein ({1:N0} % libres)." -f $v.DeviceID, $pct)
        }
    }
}

# ---------------------------------------------------------------------------
Section 'Plantages et erreurs graves (30 derniers jours)' {
    $depuis = (Get-Date).AddDays(-30)

    $ecransBleus = Evenements @{ LogName = 'System'; Id = 1001; StartTime = $depuis } |
        Where-Object { $_.ProviderName -match 'BugCheck|WER-SystemErrorReporting' }
    $coupures   = Evenements @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $depuis }
    $materiel   = Evenements @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $depuis }
    $disque     = Evenements @{ LogName = 'System'; ProviderName = 'disk', 'Ntfs', 'volmgr', 'stornvme', 'storahci'; Level = 1, 2, 3; StartTime = $depuis }
    $applis     = Evenements @{ LogName = 'Application'; ProviderName = 'Application Error', 'Application Hang'; StartTime = $depuis }

    Ligne "  Écrans bleus (BSOD)                 : $($ecransBleus.Count)"
    Ligne "  Arrêts brutaux / coupures           : $($coupures.Count)"
    Ligne "  Erreurs matérielles (WHEA)          : $($materiel.Count)"
    Ligne "  Erreurs / alertes disque            : $($disque.Count)"
    Ligne "  Programmes qui ont planté / figé    : $($applis.Count)"

    if ($ecransBleus.Count -gt 0) {
        Ligne ''
        Ligne '  Derniers écrans bleus :'
        foreach ($e in ($ecransBleus | Select-Object -First 5)) {
            Ligne "    $($e.TimeCreated.ToString('dd/MM/yyyy HH:mm'))  $(PremiereLigne $e.Message)"
        }
        Probleme 'Critique' "$($ecransBleus.Count) écran(s) bleu(s) ces 30 derniers jours. Causes fréquentes : pilote défectueux, mémoire (RAM) ou disque en panne."
    }
    if ($coupures.Count -gt 0) {
        Probleme 'Attention' "$($coupures.Count) arrêt(s) brutal(aux) ces 30 derniers jours (PC éteint sans passer par « Arrêter », plantage, coupure de courant ou surchauffe)."
    }
    if ($materiel.Count -gt 0) {
        Probleme 'Critique' "$($materiel.Count) erreur(s) matérielle(s) signalée(s) par le processeur, la mémoire ou la carte mère (journal WHEA)."
    }
    if ($disque.Count -gt 0) {
        Ligne ''
        Ligne '  Dernières alertes disque :'
        foreach ($e in ($disque | Select-Object -First 5)) {
            Ligne "    $($e.TimeCreated.ToString('dd/MM/yyyy HH:mm'))  [$($e.ProviderName) $($e.Id)] $(PremiereLigne $e.Message)"
        }
        Probleme 'Attention' "$($disque.Count) alerte(s) liée(s) au disque ces 30 derniers jours. Sauvegardez vos fichiers et surveillez la santé du disque."
    }
    if ($applis.Count -gt 0) {
        Ligne ''
        Ligne '  Programmes qui plantent le plus :'
        $parAppli = $applis | Group-Object { if ($_.Properties.Count -gt 0) { $_.Properties[0].Value } else { '?' } } |
            Sort-Object Count -Descending | Select-Object -First 8
        Tableau ($parAppli | Select-Object @{ n = 'Programme'; e = { $_.Name } }, @{ n = 'Plantages'; e = { $_.Count } })
        $gros = $parAppli | Where-Object Count -ge 5
        foreach ($g in $gros) {
            Probleme 'Attention' "Le programme « $($g.Name) » a planté $($g.Count) fois en 30 jours : mettez-le à jour ou réinstallez-le."
        }
    }
}

# ---------------------------------------------------------------------------
Section 'Erreurs du journal système (7 derniers jours)' {
    $erreurs = Evenements @{ LogName = 'System'; Level = 1, 2; StartTime = (Get-Date).AddDays(-7) }
    Ligne "  Nombre total d'erreurs : $($erreurs.Count)"
    if ($erreurs.Count -gt 0) {
        Ligne ''
        Ligne '  Erreurs les plus fréquentes :'
        $groupes = $erreurs | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 12
        Tableau ($groupes | Select-Object `
            @{ n = 'Nb';      e = { $_.Count } },
            @{ n = 'Source';  e = { $_.Group[0].ProviderName } },
            @{ n = 'Id';      e = { $_.Group[0].Id } },
            @{ n = 'Message'; e = { PremiereLigne $_.Group[0].Message } })
    }
}

# ---------------------------------------------------------------------------
Section 'Intégrité de Windows' {
    if (-not $EstAdmin) { Ligne '  Nécessite les droits administrateur.'; return }
    $etat = (Repair-WindowsImage -Online -CheckHealth).ImageHealthState
    Ligne "  État des fichiers système : $etat"
    if ("$etat" -ne 'Healthy') {
        Probleme 'Attention' "Des fichiers de Windows sont endommagés ($etat). Réparation : dans un terminal administrateur, tapez « DISM /Online /Cleanup-Image /RestoreHealth » puis « sfc /scannow »."
    }
}

# ---------------------------------------------------------------------------
Section 'Mises à jour Windows' {
    $attente = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
               (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
    Ligne "  Redémarrage en attente : $(if ($attente) { 'OUI' } else { 'non' })"
    if ($attente) {
        Probleme 'Attention' "Des mises à jour attendent un redémarrage pour s'installer : redémarrez le PC."
    }

    $maj = @(Get-HotFix | Where-Object InstalledOn | Sort-Object InstalledOn -Descending)
    Ligne ''
    Ligne '  Dernières mises à jour installées :'
    Tableau ($maj | Select-Object -First 5 `
        @{ n = 'Date';        e = { $_.InstalledOn.ToString('dd/MM/yyyy') } },
        @{ n = 'Mise à jour'; e = { $_.HotFixID } },
        @{ n = 'Type';        e = { $_.Description } })

    if ($maj.Count -gt 0) {
        $jours = [int]((Get-Date) - $maj[0].InstalledOn).TotalDays
        if ($jours -gt 45) {
            Probleme 'Attention' "Aucune mise à jour Windows installée depuis $jours jours. Allez dans Paramètres > Windows Update > Rechercher des mises à jour."
        }
    }
}

# ---------------------------------------------------------------------------
Section 'Sécurité (antivirus et pare-feu)' {
    $antivirus = @()
    try { $antivirus = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop) } catch { }
    Ligne "  Antivirus installé(s) : $(if ($antivirus) { ($antivirus.displayName | Select-Object -Unique) -join ', ' } else { 'aucun détecté' })"

    $autreAntivirus = @($antivirus | Where-Object { $_.displayName -notmatch 'Windows Defender|Microsoft Defender' }).Count -gt 0

    $defenderLisible = $false
    try {
        $mp = Get-MpComputerStatus
        $defenderLisible = $true
        Ligne "  Microsoft Defender actif     : $($mp.AntivirusEnabled)"
        Ligne "  Protection en temps réel     : $($mp.RealTimeProtectionEnabled)"
        Ligne "  Définitions à jour du        : $($mp.AntivirusSignatureLastUpdated.ToString('dd/MM/yyyy'))"
        Ligne "  Dernière analyse rapide il y a : $($mp.QuickScanAge) jour(s)"

        if (-not $autreAntivirus) {
            if (-not $mp.RealTimeProtectionEnabled) {
                Probleme 'Critique' "La protection antivirus en temps réel est désactivée. Réactivez-la dans Sécurité Windows > Protection contre les virus et menaces."
            }
            if (((Get-Date) - $mp.AntivirusSignatureLastUpdated).TotalDays -gt 7) {
                Probleme 'Attention' "Les définitions de l'antivirus ne sont pas à jour (dernière mise à jour le $($mp.AntivirusSignatureLastUpdated.ToString('dd/MM/yyyy')))."
            }
        }

        $menaces = @(Get-MpThreatDetection -ErrorAction SilentlyContinue |
            Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddDays(-30) })
        if ($menaces.Count -gt 0) {
            Ligne ''
            Ligne '  Menaces détectées ces 30 derniers jours :'
            foreach ($m in $menaces) {
                $nom = (Get-MpThreat -ThreatID $m.ThreatID -ErrorAction SilentlyContinue).ThreatName
                Ligne "    $($m.InitialDetectionTime.ToString('dd/MM/yyyy'))  $nom  ($($m.Resources -join ', '))"
            }
            Probleme 'Attention' "$($menaces.Count) menace(s) détectée(s) par l'antivirus ces 30 derniers jours : vérifiez dans Sécurité Windows > Historique de protection qu'elles ont bien été supprimées."
        }
    } catch {
        if (-not $autreAntivirus) { Ligne "  État de Microsoft Defender illisible : $($_.Exception.Message)" }
    }

    if (-not $defenderLisible -and -not $autreAntivirus) {
        Probleme 'Critique' "Aucun antivirus actif n'a été détecté."
    }

    Ligne ''
    $pareFeu = @(Get-NetFirewallProfile)
    Tableau ($pareFeu | Select-Object @{ n = 'Pare-feu'; e = { $_.Name } }, @{ n = 'Activé'; e = { $_.Enabled } })
    foreach ($p in $pareFeu) {
        if (-not $p.Enabled -and $p.Name -ne 'Domain') {
            Probleme 'Attention' "Le pare-feu Windows est désactivé pour le profil « $($p.Name) »."
        }
    }
}

# ---------------------------------------------------------------------------
Section 'Périphériques en erreur' {
    $enErreur = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne 22 })
    # 22 = périphérique désactivé volontairement
    Tableau ($enErreur | Select-Object `
        @{ n = 'Périphérique';  e = { if ($_.Name) { $_.Name } else { $_.DeviceID } } },
        @{ n = 'Code erreur';   e = { $_.ConfigManagerErrorCode } })
    if ($enErreur.Count -gt 0) {
        Probleme 'Attention' "$($enErreur.Count) périphérique(s) ne fonctionne(nt) pas correctement (pilote manquant ou en erreur) : ouvrez le Gestionnaire de périphériques et cherchez les points d'exclamation jaunes."
    }
}

# ---------------------------------------------------------------------------
Section 'Température' {
    $zones = @()
    try { $zones = @(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop) } catch { }
    if (-not $zones) {
        Ligne '  Ce PC ne donne pas accès à sa température (fréquent, ce n''est pas un problème).'
        return
    }
    foreach ($z in $zones) {
        $c = [math]::Round($z.CurrentTemperature / 10 - 273.15)
        Ligne "  $($z.InstanceName) : $c °C"
        if ($c -ge 85 -and $c -lt 150) {
            Probleme 'Attention' "Température élevée ($c °C). Nettoyez les grilles d'aération (poussière) et vérifiez que le ventilateur tourne."
        }
    }
}

# ---------------------------------------------------------------------------
Section 'Batterie' {
    $batterie = Get-CimInstance Win32_Battery
    if (-not $batterie) { Ligne '  Pas de batterie (PC fixe).'; return }
    Ligne "  Charge actuelle : $($batterie.EstimatedChargeRemaining) %"
    try {
        $conception = (Get-CimInstance -Namespace root/wmi -ClassName BatteryStaticData -ErrorAction Stop | Select-Object -First 1).DesignedCapacity
        $actuelle   = (Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1).FullChargedCapacity
        if ($conception -gt 0) {
            $sante = [math]::Round($actuelle / $conception * 100)
            Ligne "  Capacité d'origine : $conception mWh, capacité actuelle : $actuelle mWh (santé $sante %)"
            if ($sante -lt 60) {
                Probleme 'Attention' "La batterie ne garde plus que $sante % de sa capacité d'origine : son autonomie est fortement réduite, envisagez de la remplacer."
            }
        }
    } catch { Ligne '  Santé de la batterie non disponible.' }
}

# ---------------------------------------------------------------------------
Section 'Programmes lancés au démarrage' {
    $demarrage = @(Get-CimInstance Win32_StartupCommand)
    Tableau ($demarrage | Sort-Object Name | Select-Object @{ n = 'Programme'; e = { $_.Name } }, @{ n = 'Emplacement'; e = { $_.Location } })
    if ($demarrage.Count -gt 15) {
        Probleme 'Conseil' "$($demarrage.Count) programmes se lancent au démarrage, ce qui ralentit l'allumage du PC. Désactivez les inutiles dans le Gestionnaire des tâches > onglet Démarrage."
    }
}

# ---------------------------------------------------------------------------
Section 'Programmes les plus gourmands en mémoire' {
    $proc = Get-Process | Group-Object ProcessName | ForEach-Object {
        [pscustomobject]@{
            Programme      = $_.Name
            Instances      = $_.Count
            'Mémoire (Mo)' = [math]::Round(($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB)
        }
    } | Sort-Object 'Mémoire (Mo)' -Descending | Select-Object -First 10
    Tableau $proc
}

# ---------------------------------------------------------------------------
Section 'Réseau et Internet' {
    $cartes = @(Get-NetAdapter | Where-Object Status -eq 'Up')
    Tableau ($cartes | Select-Object @{ n = 'Carte réseau'; e = { $_.Name } }, @{ n = 'Type'; e = { $_.InterfaceDescription } }, @{ n = 'Vitesse'; e = { $_.LinkSpeed } })

    $ping = $false
    try { $ping = Test-Connection -ComputerName 1.1.1.1 -Count 2 -Quiet } catch { }
    $dns = $false
    try { $null = Resolve-DnsName www.microsoft.com -ErrorAction Stop; $dns = $true } catch { }

    Ligne "  Accès à Internet       : $(if ($ping) { 'OK' } else { 'ÉCHEC' })"
    Ligne "  Résolution des noms    : $(if ($dns) { 'OK' } else { 'ÉCHEC' })"

    if (-not $cartes) {
        Probleme 'Attention' "Aucune connexion réseau active (Wi-Fi ou câble)."
    } elseif (-not $ping -and -not $dns) {
        Probleme 'Attention' "Le PC n'accède pas à Internet. Redémarrez la box et le PC."
    } elseif ($ping -and -not $dns) {
        Probleme 'Attention' "Internet répond mais les adresses de sites ne sont pas trouvées (problème DNS). Dans un terminal, essayez « ipconfig /flushdns »."
    }
}

# ---------------------------------------------------------------------------
Section 'Fichiers temporaires' {
    $total = 0
    foreach ($dossier in @($env:TEMP, "$env:SystemRoot\Temp")) {
        if (-not (Test-Path $dossier)) { continue }
        $taille = (Get-ChildItem $dossier -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        $total += $taille
        Ligne ("  {0} : {1:N2} Go" -f $dossier, ($taille / 1GB))
    }
    if ($total -gt 2GB) {
        Probleme 'Conseil' ("{0:N1} Go de fichiers temporaires. Vous pouvez les supprimer avec Paramètres > Système > Stockage > Fichiers temporaires." -f ($total / 1GB))
    }
}

# ---------------------------------------------------------------------------
# Assemblage du rapport : le résumé en premier, les détails ensuite
$ordre   = @{ 'Critique' = 0; 'Attention' = 1; 'Conseil' = 2 }
$tries   = @($Problemes | Sort-Object { $ordre[$_.Niveau] })

$entete = New-Object System.Collections.Generic.List[string]
$entete.Add('RAPPORT DE DIAGNOSTIC DU PC')
$entete.Add("Date : $((Get-Date).ToString('dd/MM/yyyy HH:mm'))   -   PC : $env:COMPUTERNAME   -   Administrateur : $(if ($EstAdmin) { 'oui' } else { 'non' })")
$entete.Add('')
$entete.Add(('=' * 78))
$entete.Add('  RÉSUMÉ')
$entete.Add(('=' * 78))
if ($tries.Count -eq 0) {
    $entete.Add('  Aucun problème détecté. Le PC semble en bonne santé.')
} else {
    foreach ($p in $tries) { $entete.Add("  [$($p.Niveau.ToUpper())] $($p.Texte)") }
}
$entete.Add('')
$entete.Add('  CRITIQUE = à traiter rapidement  |  ATTENTION = à surveiller  |  CONSEIL = amélioration possible')

$fichier = Join-Path ([Environment]::GetFolderPath('Desktop')) ("Diagnostic_PC_{0}.txt" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
($entete + $Rapport) | Out-File -FilePath $fichier -Encoding UTF8

# Résumé à l'écran
Write-Host ''
Write-Host '================ RÉSUMÉ ================' -ForegroundColor Cyan
if ($tries.Count -eq 0) {
    Write-Host 'Aucun problème détecté. Le PC semble en bonne santé.' -ForegroundColor Green
} else {
    $couleurs = @{ 'Critique' = 'Red'; 'Attention' = 'Yellow'; 'Conseil' = 'Gray' }
    foreach ($p in $tries) { Write-Host "[$($p.Niveau.ToUpper())] $($p.Texte)" -ForegroundColor $couleurs[$p.Niveau] }
}
Write-Host ''
Write-Host "Rapport complet enregistré sur le Bureau : $fichier" -ForegroundColor Cyan

try { Start-Process notepad.exe -ArgumentList "`"$fichier`"" } catch { }
