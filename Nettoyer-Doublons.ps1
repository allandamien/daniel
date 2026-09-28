<#
    Nettoyer-Doublons.ps1
    Repère les fichiers en double dans le dossier Téléchargements (contenu identique,
    même si le nom est différent) et envoie les copies à la Corbeille.

    Pour chaque groupe de doublons, le script garde un seul fichier :
      1. celui dont le nom n'a pas de numéro de copie, comme « (1) » ou « - Copie » ;
      2. sinon, le plus ancien.
    Rien n'est supprimé sans confirmation, et tout passe par la Corbeille.
#>

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName Microsoft.VisualBasic

$dossier = $null
try { $dossier = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path } catch { }
if (-not $dossier -or -not (Test-Path $dossier)) { $dossier = Join-Path $env:USERPROFILE 'Downloads' }

Write-Host ''
Write-Host "Recherche des doublons dans : $dossier" -ForegroundColor Cyan
Write-Host ''

# Comparer d'abord la taille (rapide), puis le contenu uniquement pour les tailles identiques
$fichiers = @(Get-ChildItem -LiteralPath $dossier -File -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -gt 0 })
$memeTaille = @($fichiers | Group-Object Length | Where-Object Count -gt 1)

$groupes = @()
$n = 0
foreach ($g in $memeTaille) {
    $n++
    Write-Progress -Activity 'Comparaison des fichiers' -Status "$n / $($memeTaille.Count)" -PercentComplete ($n / $memeTaille.Count * 100)
    $avecEmpreinte = foreach ($f in $g.Group) {
        try {
            [pscustomobject]@{ Fichier = $f; Empreinte = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash }
        } catch { }
    }
    $groupes += @($avecEmpreinte | Group-Object Empreinte | Where-Object Count -gt 1)
}
Write-Progress -Activity 'Comparaison des fichiers' -Completed

if ($groupes.Count -eq 0) {
    Write-Host 'Aucun doublon trouvé. Le dossier Téléchargements est propre.' -ForegroundColor Green
    return
}

# Choix du fichier à garder dans chaque groupe
$motifCopie = '\s*\(\d+\)|\s*-\s*(Copie|Copy)(\s*\(\d+\))?'
$aSupprimer = New-Object System.Collections.Generic.List[object]
$journal    = New-Object System.Collections.Generic.List[string]
$gain = 0

foreach ($g in $groupes) {
    $tries = @($g.Group.Fichier | Sort-Object `
        @{ e = { if ($_.BaseName -match $motifCopie) { 1 } else { 0 } } },
        @{ e = { $_.CreationTime } },
        @{ e = { $_.Name.Length } })
    $garde = $tries[0]
    $copies = $tries | Select-Object -Skip 1

    Write-Host "GARDÉ   : $($garde.FullName.Substring($dossier.Length + 1))" -ForegroundColor Green
    $journal.Add("GARDÉ     : $($garde.FullName)")
    foreach ($c in $copies) {
        Write-Host ("  copie : {0}  ({1:N1} Mo)" -f $c.FullName.Substring($dossier.Length + 1), ($c.Length / 1MB)) -ForegroundColor Yellow
        $journal.Add("CORBEILLE : $($c.FullName)")
        $aSupprimer.Add($c)
        $gain += $c.Length
    }
    Write-Host ''
}

Write-Host ("{0} copie(s) en double trouvée(s), {1:N1} Mo à libérer." -f $aSupprimer.Count, ($gain / 1MB)) -ForegroundColor Cyan
Write-Host 'Les copies iront dans la Corbeille (récupérables).' -ForegroundColor Cyan
Write-Host ''
$reponse = Read-Host 'Envoyer les copies à la Corbeille ? Tapez O puis Entrée pour confirmer'
if ($reponse -notmatch '^[oOyY]') { Write-Host 'Annulé, rien n''a été modifié.'; return }

$ok = 0
foreach ($c in $aSupprimer) {
    try {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($c.FullName, 'OnlyErrorDialogs', 'SendToRecycleBin')
        $ok++
    } catch {
        Write-Host "Impossible de déplacer $($c.Name) : $($_.Exception.Message)" -ForegroundColor Red
        $journal.Add("ÉCHEC     : $($c.FullName) - $($_.Exception.Message)")
    }
}

$fichierJournal = Join-Path ([Environment]::GetFolderPath('Desktop')) ("Doublons_Telechargements_{0}.txt" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
$journal | Out-File -FilePath $fichierJournal -Encoding UTF8

Write-Host ''
Write-Host ("{0} copie(s) envoyée(s) à la Corbeille, {1:N1} Mo libérés." -f $ok, ($gain / 1MB)) -ForegroundColor Green
Write-Host "Liste détaillée enregistrée sur le Bureau : $fichierJournal" -ForegroundColor Cyan
Write-Host 'Pour récupérer un fichier : ouvrez la Corbeille, clic droit > Restaurer.'
