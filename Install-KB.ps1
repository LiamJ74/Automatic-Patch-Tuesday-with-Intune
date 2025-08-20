<#
.SYNOPSIS
    Installe le KB correct selon la build du poste
.DESCRIPTION
    - Lit kbmap.csv
    - Détecte la build actuelle
    - Installe le KB correspondant
#>

$CsvFile = Join-Path $PSScriptRoot "kbmap.csv"

$osInfo = Get-CimInstance Win32_OperatingSystem
$build = [int]$osInfo.BuildNumber
$osName = if ($osInfo.Caption -match "Windows 10") { "Windows10" } else { "Windows11" }

$kbMap = Import-Csv $CsvFile | Where-Object { $_.OS -eq $osName }

$kbEntry = $kbMap | Where-Object { $_.Build -eq $build.ToString() }

if (-not $kbEntry) {
    Write-Host "⚠️ Aucun KB trouvé pour $osName build $build"
    exit 0
}

$msuFile = Join-Path $PSScriptRoot $kbEntry.FileName

if (-not (Test-Path $msuFile)) {
    Write-Host "⚠️ Fichier MSU introuvable : $msuFile"
    exit 1
}

Write-Host "⬇️ Installation du KB $($kbEntry.KB) pour $osName build $build"
Start-Process "wusa.exe" -ArgumentList "$msuFile /quiet /norestart" -Wait
