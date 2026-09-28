<#
    Ranger-Bureau.ps1
    Trie les icônes du Bureau : les icônes indispensables restent en place, les autres
    sont rangées dans le dossier « Rangement du Bureau » (sur le Bureau), classées par type.

    Restent sur le Bureau :
      - les raccourcis des programmes courants (navigateur, messagerie, Office, etc.) ;
      - les fichiers modifiés récemment (travail en cours) ;
      - les dossiers ;
      - la Corbeille et Ce PC (icônes système, jamais touchées).
    Rien n'est supprimé et rien n'est déplacé sans confirmation.
    Pour tout remettre comme avant : Annuler-Rangement-Bureau.bat
#>

param([switch]$Annuler)

$ErrorActionPreference = 'Continue'

# Programmes considérés comme indispensables : nom de l'exécutable ciblé par le raccourci…
$programmesIndispensables = @(
    'chrome', 'msedge', 'firefox', 'opera', 'brave',
    'outlook', 'thunderbird', 'hxoutlook', 'olk',
    'winword', 'excel', 'powerpnt', 'onenote', 'soffice', 'swriter', 'scalc',
    'acrord32', 'acrobat', 'vlc', 'zoom', 'teams', 'ms-teams', 'whatsapp', 'skype'
)
# …ou mot présent dans le nom de l'icône (à compléter selon vos habitudes).
$nomsIndispensables = @(
    'Chrome', 'Edge', 'Firefox', 'Opera', 'Brave', 'Outlook', 'Thunderbird', 'Mail',
    'Word', 'Excel', 'PowerPoint', 'OneNote', 'LibreOffice', 'Acrobat', 'Adobe Reader',
    'VLC', 'Zoom', 'Teams', 'WhatsApp', 'Skype', 'Ce PC', 'Panneau de configuration'
)
$joursRecents = 14

$bureau      = [Environment]::GetFolderPath('Desktop')
$bureauPublic = [Environment]::GetFolderPath('CommonDesktopDirectory')
$rangement   = Join-Path $bureau 'Rangement du Bureau'
$journalCsv  = Join-Path $rangement 'journal.csv'

function Chemin-Libre([string]$Dossier, [string]$Nom) {
    $chemin = Join-Path $Dossier $Nom
    $base = [IO.Path]::GetFileNameWithoutExtension($Nom)
    $ext  = [IO.Path]::GetExtension($Nom)
    $i = 2
    while (Test-Path -LiteralPath $chemin) {
        $chemin = Join-Path $Dossier ("{0} ({1}){2}" -f $base, $i, $ext)
        $i++
    }
    $chemin
}

# ---------------------------------------------------------------- Annulation
if ($Annuler) {
    if (-not (Test-Path -LiteralPath $journalCsv)) {
        Write-Host 'Aucun rangement à annuler (journal introuvable).' -ForegroundColor Yellow
        return
    }
    $ok = 0
    foreach ($l in (Import-Csv -LiteralPath $journalCsv)) {
        if (-not (Test-Path -LiteralPath $l.Nouveau)) { continue }
        $dossierOrigine = Split-Path $l.Origine -Parent
        $destination = Chemin-Libre $dossierOrigine (Split-Path $l.Origine -Leaf)
        try {
            Move-Item -LiteralPath $l.Nouveau -Destination $destination -ErrorAction Stop
            $ok++
        } catch {
            Write-Host "Impossible de remettre $(Split-Path $l.Origine -Leaf) : $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Remove-Item -LiteralPath $journalCsv -ErrorAction SilentlyContinue
    # Supprime les sous-dossiers de rangement devenus vides, puis le dossier lui-même s'il est vide
    Get-ChildItem -LiteralPath $rangement -Directory -ErrorAction SilentlyContinue |
        Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force) } |
        Remove-Item -ErrorAction SilentlyContinue
    if (-not (Get-ChildItem -LiteralPath $rangement -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $rangement -ErrorAction SilentlyContinue
    }
    Write-Host "$ok icône(s) remise(s) sur le Bureau." -ForegroundColor Green
    return
}

# ---------------------------------------------------------------- Tri
$categories = [ordered]@{
    'Documents'    = '.pdf .doc .docx .odt .rtf .txt .xls .xlsx .ods .csv .ppt .pptx .odp'
    'Images'       = '.jpg .jpeg .png .gif .bmp .heic .webp .tif .tiff'
    'Vidéos'       = '.mp4 .avi .mkv .mov .wmv'
    'Musique'      = '.mp3 .wav .wma .m4a .flac .ogg'
    'Archives'     = '.zip .rar .7z'
    'Installateurs' = '.exe .msi'
}
function Categorie-Fichier($Fichier) {
    foreach ($c in $categories.Keys) {
        if (($categories[$c] -split ' ') -contains $Fichier.Extension.ToLower()) { return $c }
    }
    'Autres'
}

$shell = New-Object -ComObject WScript.Shell
$motifNoms = '\b(' + (($nomsIndispensables | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\b'
$limiteRecente = (Get-Date).AddDays(-$joursRecents)

$elements = @(foreach ($d in @($bureau, $bureauPublic) | Select-Object -Unique) {
    Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue |
        Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::Hidden) -and
                       -not ($_.Attributes -band [IO.FileAttributes]::System) -and
                       $_.FullName -ne $rangement }
})

$gardes  = New-Object System.Collections.Generic.List[object]
$ranges  = New-Object System.Collections.Generic.List[object]

foreach ($e in $elements) {
    if ($e.PSIsContainer) { $gardes.Add([pscustomobject]@{ Nom = $e.Name; Raison = 'dossier' }); continue }

    $ext = $e.Extension.ToLower()
    if ($ext -eq '.lnk' -or $ext -eq '.url') {
        $cible = ''
        if ($ext -eq '.lnk') {
            try { $cible = [Environment]::ExpandEnvironmentVariables($shell.CreateShortcut($e.FullName).TargetPath) } catch { }
        }
        $exe = if ($cible) { [IO.Path]::GetFileNameWithoutExtension($cible).ToLower() } else { '' }

        if (($exe -and $programmesIndispensables -contains $exe) -or $e.BaseName -match $motifNoms) {
            $gardes.Add([pscustomobject]@{ Nom = $e.BaseName; Raison = 'programme indispensable' })
        } elseif ($cible -and $cible -notlike '\\*' -and -not (Test-Path -LiteralPath $cible)) {
            $ranges.Add([pscustomobject]@{ Element = $e; Categorie = 'Raccourcis cassés' })
        } else {
            $ranges.Add([pscustomobject]@{ Element = $e; Categorie = 'Raccourcis' })
        }
    } elseif ($e.LastWriteTime -ge $limiteRecente) {
        $gardes.Add([pscustomobject]@{ Nom = $e.Name; Raison = "modifié il y a moins de $joursRecents jours" })
    } else {
        $ranges.Add([pscustomobject]@{ Element = $e; Categorie = (Categorie-Fichier $e) })
    }
}

Write-Host ''
Write-Host "Tri des icônes du Bureau : $bureau" -ForegroundColor Cyan
Write-Host ''
Write-Host 'RESTENT SUR LE BUREAU (indispensables) :' -ForegroundColor Green
if ($gardes.Count -eq 0) { Write-Host '  (aucune)' }
foreach ($g in $gardes) { Write-Host "  $($g.Nom)  - $($g.Raison)" -ForegroundColor Green }
Write-Host ''

if ($ranges.Count -eq 0) {
    Write-Host 'Rien à ranger : le Bureau ne contient que des icônes indispensables.' -ForegroundColor Green
    return
}

Write-Host 'À RANGER dans « Rangement du Bureau » :' -ForegroundColor Yellow
foreach ($groupe in ($ranges | Group-Object Categorie)) {
    Write-Host "  [$($groupe.Name)]" -ForegroundColor Yellow
    foreach ($r in $groupe.Group) { Write-Host "     $($r.Element.Name)" }
}
Write-Host ''
Write-Host 'Rien ne sera supprimé. Pour tout remettre en place : Annuler-Rangement-Bureau.bat' -ForegroundColor Cyan
Write-Host 'Pour garder une icône, ajoutez son nom dans la liste en haut de Ranger-Bureau.ps1.' -ForegroundColor Cyan
Write-Host ''
$reponse = Read-Host "Ranger ces $($ranges.Count) icône(s) ? Tapez O puis Entrée pour confirmer"
if ($reponse -notmatch '^[oOyY]') { Write-Host 'Annulé, rien n''a été modifié.'; return }

New-Item -ItemType Directory -Path $rangement -Force | Out-Null
$journal = @(if (Test-Path -LiteralPath $journalCsv) { Import-Csv -LiteralPath $journalCsv })
$ok = 0
$refuses = 0
foreach ($r in $ranges) {
    $dossier = Join-Path $rangement $r.Categorie
    New-Item -ItemType Directory -Path $dossier -Force | Out-Null
    $destination = Chemin-Libre $dossier $r.Element.Name
    try {
        Move-Item -LiteralPath $r.Element.FullName -Destination $destination -ErrorAction Stop
        $journal += [pscustomobject]@{ Origine = $r.Element.FullName; Nouveau = $destination }
        $ok++
    } catch [UnauthorizedAccessException] {
        $refuses++
    } catch {
        if ($_.Exception.Message -match 'refus|denied') { $refuses++ }
        else { Write-Host "Impossible de ranger $($r.Element.Name) : $($_.Exception.Message)" -ForegroundColor Red }
    }
}
$journal | Export-Csv -LiteralPath $journalCsv -NoTypeInformation -Encoding UTF8

Write-Host ''
Write-Host "$ok icône(s) rangée(s) dans « Rangement du Bureau »." -ForegroundColor Green
if ($refuses -gt 0) {
    Write-Host "$refuses icône(s) communes à tous les utilisateurs n'ont pas pu être déplacées" -ForegroundColor Yellow
    Write-Host '(Windows demande les droits administrateur pour celles-là).' -ForegroundColor Yellow
}
Write-Host 'Pour tout remettre en place : double-cliquez sur Annuler-Rangement-Bureau.bat'
