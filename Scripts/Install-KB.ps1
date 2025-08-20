<#
.SYNOPSIS
    Installe le KB correct selon la build du poste
.DESCRIPTION
    - Lit kbmap.csv
    - Détecte la build actuelle
    - Installe le KB correspondant
#>

# Get the parent directory of the current script's location
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseDir = Resolve-Path -Path (Join-Path $PSScriptRoot "..")

$CsvFile = Join-Path $BaseDir "kbmap.csv"

if (-not (Test-Path $CsvFile)) {
    Write-Host "⚠️ kbmap.csv not found at $CsvFile"
    exit 1
}

$osInfo = Get-CimInstance Win32_OperatingSystem
$build = [int]$osInfo.BuildNumber
$osName = if ($osInfo.Caption -match "Windows 10") { "Windows 10" } else { "Windows 11" }

$kbMap = Import-Csv $CsvFile | Where-Object { $_.OS -eq $osName }

$kbEntry = $kbMap | Where-Object { $_.Build -eq $build.ToString() }

if (-not $kbEntry) {
    Write-Host "✅ No applicable KB found for $osName build $build in kbmap.csv. Nothing to do."
    exit 0
}

$msuFile = Join-Path $BaseDir $kbEntry.FileName

if (-not (Test-Path $msuFile)) {
    Write-Host "⚠️ MSU file not found: $msuFile"
    exit 1
}

Write-Host "⬇️ Installing KB $($kbEntry.KB) for $osName build $build..."
Start-Process "wusa.exe" -ArgumentList "$msuFile /quiet /norestart" -Wait
Write-Host "✅ Installation process completed."
