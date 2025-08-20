<#
.SYNOPSIS
    Télécharge automatiquement les KB du Patch Tuesday et génère kbmap.csv
.DESCRIPTION
    - Compatible Windows 10 et 11
    - Permet d’ajouter plusieurs builds et KB dans le mapping
#>

$OutputFolder = "$PSScriptRoot\KBs"
$CsvFile = "$PSScriptRoot\kbmap.csv"

# Crée le dossier KB si inexistant
if (-not (Test-Path $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder }

# Liste des KB à traiter : tu peux rajouter les nouvelles entrées chaque mois
$KBList = @(
    @{ OS="Windows10"; Build="19045"; KB="5063709"; URL="https://www.catalog.update.microsoft.com/download/KB5063709" },
    @{ OS="Windows11"; Build="22621"; KB="5063875"; URL="https://www.catalog.update.microsoft.com/download/KB5063875" },
    @{ OS="Windows11"; Build="25300"; KB="5063878"; URL="https://www.catalog.update.microsoft.com/download/KB5063878" }
)

$KBMap = @()

foreach ($kb in $KBList) {
    $FileName = "$($kb.KB).msu"
    $Destination = Join-Path $OutputFolder $FileName

    if (-not (Test-Path $Destination)) {
        Write-Host "⬇️ Téléchargement de $($kb.KB)..."
        Invoke-WebRequest -Uri $kb.URL -OutFile $Destination
    } else {
        Write-Host "✅ $($kb.KB) déjà téléchargé"
    }

    $KBMap += [PSCustomObject]@{
        OS        = $kb.OS
        Build     = $kb.Build
        KB        = $kb.KB
        FileName  = "KBs\$FileName"
    }
}

# Génération du CSV
$KBMap | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8
Write-Host "✅ kbmap.csv généré avec succès"
