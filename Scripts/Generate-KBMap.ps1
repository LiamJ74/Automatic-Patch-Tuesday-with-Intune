<#
.SYNOPSIS
    Automated script to download KBs, package them, and create/assign the app in Intune.
.DESCRIPTION
    This script performs the end-to-end process for Patch Tuesday deployment:
    1. Downloads the latest KBs for specified Windows builds using MSCatalogLTS.
    2. Automatically fetches the Intune Win32 Content Prep Tool if not present.
    3. Packages the deployment scripts and KBs into an .intunewin file.
    4. Connects to MS Graph and uses the IntuneWin32App module to create a new app in Intune.
    5. Assigns the new application to specified groups.

    Prerequisites:
    - PowerShell 5.1 or higher
    - MSCatalogLTS module: 'Install-Module -Name MSCatalogLTS'
    - IntuneWin32App module: 'Install-Module -Name IntuneWin32App'
#>

[CmdletBinding()]
param(
    # --- Authentication Parameters (Mandatory for Intune upload) ---
    [string]$ClientId,
    [string]$ClientSecret,
    [string]$TenantId,

    # --- Application Metadata (Mandatory for Intune upload) ---
    [string]$AppName = "Patch Tuesday - $(Get-Date -Format 'MMMM yyyy')",
    [string]$Description = "Universal KB package for Patch Tuesday. Installs the correct MSU based on build.",
    [string]$Publisher = "Automated Script",

    # --- Assignment Parameters (Optional) ---
    [string[]]$GroupPilot,
    [string[]]$GroupBroad,
    [string[]]$GroupProd
)

#Requires -Modules MSCatalogLTS, IntuneWin32App

# --- Function Definitions ---

function Get-IntuneWinAppUtil {
    param([string]$ToolsDir)

    $UtilPath = Join-Path $ToolsDir "IntuneWinAppUtil.exe"
    if (Test-Path $UtilPath) {
        Write-Host "✅ Intune Win32 Content Prep Tool found at '$UtilPath'."
        return $UtilPath
    }

    Write-Host "🔎 Intune Win32 Content Prep Tool not found. Downloading..."
    if (-not (Test-Path $ToolsDir)) {
        New-Item -ItemType Directory -Path $ToolsDir | Out-Null
    }

    $DownloadUrl = "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe"
    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $UtilPath -UseBasicParsing
        Write-Host "✅ Successfully downloaded IntuneWinAppUtil.exe to '$UtilPath'."
        return $UtilPath
    }
    catch {
        throw "❌ Failed to download IntuneWinAppUtil.exe. Please download it manually from '$DownloadUrl' and place it in the '$ToolsDir' folder."
    }
}

function Publish-NewIntuneApp {
    param(
        [string]$ToolsDir,
        [string]$SourceFolder
    )

    $UtilPath = Get-IntuneWinAppUtil -ToolsDir $ToolsDir

    # Define paths and settings for packaging
    $SetupFile = Join-Path $SourceFolder "Scripts\Install-KB.ps1"
    $PackageDir = Join-Path $SourceFolder "IntunePackage"
    if (-not (Test-Path $PackageDir)) {
        New-Item -ItemType Directory -Path $PackageDir | Out-Null
    }

    Write-Host "🎁 Starting Intune package creation..."
    $packageArgs = @{
        SourceFolder = $SourceFolder
        SetupFile    = $SetupFile
        OutputFolder = $PackageDir
    }
    Invoke-Expression "& `"$UtilPath`" -c `"$($packageArgs.SourceFolder)`" -s `"$($packageArgs.SetupFile)`" -o `"$($packageArgs.OutputFolder)`" -q"

    $IntuneWinFile = Join-Path $PackageDir "Install-KB.intunewin"
    if (-not (Test-Path $IntuneWinFile)) {
        throw "❌ Packaging failed. '$IntuneWinFile' not created."
    }
    Write-Host "✅ Package created successfully: '$IntuneWinFile'."

    # Connect to Graph
    Write-Host "🔐 Connecting to Microsoft Graph with App Registration..."
    Set-IntuneWin32AppAuthentication -ClientId $ClientId -ClientSecret $ClientSecret -TenantId $TenantId
    Connect-IntuneWin32App -TenantId $TenantId

    # Create and upload the new application
    Write-Host "⬆️ Creating and uploading new application '$AppName' to Intune..."
    $appParams = @{
        FilePath              = $IntuneWinFile
        DisplayName           = $AppName
        Description           = $Description
        Publisher             = $Publisher
        InstallCommandLine    = 'powershell.exe -executionpolicy bypass -file ".\Install-KB.ps1"'
        UninstallCommandLine  = 'cmd.exe /c "exit 0"' # No real uninstall needed
        InstallExperience     = "system"
        RestartBehavior       = "suppress"
        DetectionRuleScriptFile = (Join-Path $SourceFolder "Scripts\Detection.ps1")
    }
    $app = Add-IntuneWin32App @appParams

    if (-not $app) {
        throw "❌ Failed to create application in Intune."
    }
    Write-Host "✅ Application '$($app.DisplayName)' created successfully (ID: $($app.id))."

    # Handle assignments
    $assignments = @()
    if ($GroupPilot) { $assignments += New-IntuneWin32AppAssignmentObject -GroupId $GroupPilot -Intent "required" -Notification "showAll" }
    if ($GroupBroad) { $assignments += New-IntuneWin32AppAssignmentObject -GroupId $GroupBroad -Intent "required" -Notification "showAll" -DeliveryOptimizationPriority "foreground" }
    if ($GroupProd)  { $assignments += New-IntuneWin32AppAssignmentObject -GroupId $GroupProd  -Intent "required" -Notification "showAll" -DeliveryOptimizationPriority "background" }

    if ($assignments.Count -gt 0) {
        Write-Host "✍️ Applying assignments..."
        Add-IntuneWin32AppAssignment -AppId $app.id -Assignments $assignments
        Write-Host "✅ Assignments applied."
    } else {
        Write-Warning "⚠️ No group IDs provided. Skipping assignment."
    }
}

# --- Main Script Logic ---

$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseDir = Resolve-Path -Path (Join-Path $PSScriptRoot "..")
$ToolsDir = Join-Path $BaseDir "Tools"
$OutputFolder = Join-Path $BaseDir "KBs"
$CsvFile = Join-Path $BaseDir "kbmap.csv"

# --- Configuration for KB download ---
$TargetBuilds = @(
    @{ OS = "Windows 10"; Build = "19045"; Arch = "x64" },
    @{ OS = "Windows 11"; Build = "22631"; Arch = "x64" }
)
# --------------------

if (-not (Test-Path $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder | Out-Null }

$KBMap = @()
# ... (KB download logic remains the same) ...
foreach ($target in $TargetBuilds) {
    $os = $target.OS; $build = $target.Build; $arch = $target.Arch
    $searchTerm = "Cumulative Update for $os Version $($build.Substring(0,2))H2 for $arch-based Systems"
    if ($os -eq "Windows 10") { $searchTerm = "Cumulative Update for Windows 10 Version 22H2 for $arch-based Systems" }
    Write-Host "🔍 Searching for latest update for $os Build $build ($arch)..."
    $update = Get-MSCatalogUpdate -Search $searchTerm -ExcludeFramework -IncludePreview:$false | Select-Object -First 1
    if ($update) {
        $kbNumber = ($update.Title -split "KB" | Select-Object -Last 1) -replace "\)", ""
        $fileName = "$($kbNumber).msu"
        $destination = Join-Path $OutputFolder $fileName
        if (-not (Test-Path $destination)) {
            Save-MSCatalogUpdate -Update $update -Destination $OutputFolder -FileName $fileName
        }
        $KBMap += [PSCustomObject]@{ OS = $os; Build = $build; KB = $kbNumber; FileName = "KBs\$fileName" }
    }
}

if ($KBMap.Count -eq 0) {
    Write-Warning "⚠️ No updates were downloaded. Skipping packaging and upload."
    exit
}

$KBMap | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8
Write-Host "✅ Successfully generated kbmap.csv."

# --- Execute Publishing Workflow ---
if ($PSBoundParameters.ContainsKey('ClientId')) {
    # A detection script is needed by the IntuneWin32App module.
    # It will check if the KB is already installed.
    $detectionScriptContent = @"
`$kbMap = Import-Csv -Path "kbmap.csv"
`$osInfo = Get-CimInstance Win32_OperatingSystem
`$build = [int]`$osInfo.BuildNumber
`$kbEntry = `$kbMap | Where-Object { `$_.Build -eq `$build.ToString() }
if (`$kbEntry) {
    `$kbNumber = `$kbEntry.KB
    if (Get-HotFix -Id `$kbNumber -ErrorAction SilentlyContinue) {
        Write-Host "Found"
        exit 0
    }
}
exit 1
"@
    $detectionScriptPath = Join-Path $BaseDir "Scripts\Detection.ps1"
    Set-Content -Path $detectionScriptPath -Value $detectionScriptContent

    Publish-NewIntuneApp -ToolsDir $ToolsDir -SourceFolder $BaseDir
} else {
    Write-Host "✅ KB download and mapping complete. Skipping Intune publishing."
}
