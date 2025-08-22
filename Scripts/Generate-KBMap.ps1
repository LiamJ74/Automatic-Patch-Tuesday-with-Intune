<#
.SYNOPSIS
    Automated script to download KBs, package them, and create/assign the app in Intune.
.DESCRIPTION
    This script performs the end-to-end process for Patch Tuesday deployment.
    If an app with the current month's name exists, it updates the assignments.
    If not, it creates a new application.

    Prerequisites:
    - PowerShell 5.1 or higher
    - MSCatalogLTS module: 'Install-Module -Name MSCatalogLTS'
    - IntuneWin32App module: 'Install-Module -Name IntuneWin32App -Repository PSGallery'
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
    [string[]]$GroupTest,
    [string[]]$GroupRing1,
    [string[]]$GroupRing2,
    [string[]]$GroupRing3,
    [string[]]$GroupLast
)

#Requires -Modules MSCatalogLTS, IntuneWin32App

# --- Function Definitions ---

function Get-IntuneWinAppUtil {
    param([string]$ToolsDir)
    $UtilPath = Join-Path $ToolsDir "IntuneWinAppUtil.exe"
    if (Test-Path $UtilPath) {
        Write-Host "[+] Intune Win32 Content Prep Tool found at '$UtilPath'."
        return $UtilPath
    }
    Write-Host "[i] Intune Win32 Content Prep Tool not found. Downloading..."
    if (-not (Test-Path $ToolsDir)) {
        New-Item -ItemType Directory -Path $ToolsDir | Out-Null
    }
    $DownloadUrl = "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe"
    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $UtilPath -UseBasicParsing
        Write-Host "[+] Successfully downloaded IntuneWinAppUtil.exe to '$UtilPath'."
        return $UtilPath
    }
    catch {
        throw "[!] Failed to download IntuneWinAppUtil.exe. Please download it manually from '$DownloadUrl' and place it in the '$ToolsDir' folder."
    }
}

function Publish-NewOrUpdateIntuneApp {
    param(
        [string]$ToolsDir,
        [string]$SourceFolder
    )
    
    # Resolve client secret. Prioritize parameter, then fall back to environment variable.
    $resolvedClientSecret = $ClientSecret
    if (-not $resolvedClientSecret) {
        Write-Host "[i] -ClientSecret parameter not provided. Checking for environment variable 'INTUNE_CLIENT_SECRET'..."
        $resolvedClientSecret = $env:INTUNE_CLIENT_SECRET
    }

    if (-not $resolvedClientSecret) {
        throw "[!] Client secret not provided. Please use the '-ClientSecret' parameter or set the 'INTUNE_CLIENT_SECRET' environment variable."
    }

    Write-Host "[i] Connecting to Microsoft Graph using the IntuneWin32App module..."
    try {
        Connect-MSIntuneGraph -ClientId $ClientId -ClientSecret $resolvedClientSecret -TenantId $TenantId
        Write-Host "[+] Authentication successful."
    } catch {
        Write-Error "[!] Failed to authenticate with Intune using Connect-MSIntuneGraph. The full error is below."
        throw $_ 
    }

    try {
        Write-Host "[i] Checking for existing application named '$AppName'..."
        $existingApp = Get-IntuneWin32App -DisplayName $AppName

        if ($existingApp) {
            Write-Host "[+] Application already exists (ID: $($existingApp.id)). Will update assignments only."
            $app = $existingApp
        }
        else {
            Write-Host "[i] No existing application found. Proceeding with new application creation..."
            
            $UtilPath = Get-IntuneWinAppUtil -ToolsDir $ToolsDir
            $SetupFile = Join-Path $SourceFolder "Scripts\Install-KB.ps1"
            $PackageDir = Join-Path $SourceFolder "IntunePackage"

            if (Test-Path $PackageDir) {
                Write-Host "[i] Cleaning previous package directory..."
                Remove-Item -Path $PackageDir -Recurse -Force
            }
            New-Item -ItemType Directory -Path $PackageDir | Out-Null

            Write-Host "[i] Starting Intune package creation (in background)..."
            Write-Progress -Activity "Packaging Win32 Application" -Status "Running IntuneWinAppUtil.exe... This may take a moment."
            $arguments = @("-c", "`"$SourceFolder`"", "-s", "`"$SetupFile`"", "-o", "`"$PackageDir`"", "-q")
            Start-Process -FilePath $UtilPath -ArgumentList $arguments -Wait -NoNewWindow
            Write-Progress -Activity "Packaging Win32 Application" -Completed
            
            $IntuneWinFile = Join-Path $PackageDir "Install-KB.intunewin"
            if (-not (Test-Path $IntuneWinFile)) {
                throw "[!] Packaging failed. The tool ran silently but '$IntuneWinFile' was not created."
            }
            Write-Host "[+] Package created successfully: '$IntuneWinFile'."
            
            $detectionRule = New-IntuneWin32AppDetectionRuleScript -ScriptFile (Join-Path $SourceFolder "Scripts\Detection.ps1")
            
            $appParams = @{
                FilePath              = $IntuneWinFile
                DisplayName           = $AppName
                Description           = $Description
                Publisher             = $Publisher
                InstallCommandLine    = 'powershell.exe -executionpolicy bypass -windowstyle hidden -file ".\Install-KB.ps1"'
                UninstallCommandLine  = 'cmd.exe /c "exit 0"'
                InstallExperience     = "system"
                RestartBehavior       = "suppress"
                DetectionRule         = @($detectionRule)
            }
            $app = Add-IntuneWin32App @appParams
            if (-not $app) {
                throw "[!] Failed to create application in Intune."
            }
            Write-Host "[+] Application '$($app.DisplayName)' created successfully (ID: $($app.id))."
        }

        # --- Assignment Logic (now handles updates and staggered deployment) ---
        Write-Host "[i] Setting assignments for app ID $($app.id)..."
        $currentAssignments = Get-IntuneWin32AppAssignment -ID $app.id
        if ($currentAssignments) {
            Write-Host "[i] Removing $($currentAssignments.Count) existing assignment(s)..."
            foreach ($assignment in $currentAssignments) {
                if ($null -ne $assignment.target.groupId) {
                    Remove-IntuneWin32AppAssignmentGroup -ID $app.id -GroupId $assignment.target.groupId
                }
            }
        }

        if ($GroupTest) {
            Write-Host "[i] Assigning to Test group for ASAP deployment..."
            Add-IntuneWin32AppAssignmentGroup -ID $app.id -GroupId $GroupTest[0] -Intent "required" -Notification "showAll" -Include
        }
        if ($GroupRing1) {
            Write-Host "[i] Assigning to Ring1 group for deployment in 3 days..."
            Add-IntuneWin32AppAssignmentGroup -ID $app.id -GroupId $GroupRing1[0] -Intent "required" -Notification "showAll" -Include -AvailableTime (Get-Date).AddDays(3) -DeadlineTime (Get-Date).AddDays(6)
        }
        if ($GroupRing2) {
            Write-Host "[i] Assigning to Ring2 group for deployment in 6 days..."
            Add-IntuneWin32AppAssignmentGroup -ID $app.id -GroupId $GroupRing2[0] -Intent "required" -Notification "showAll" -Include -AvailableTime (Get-Date).AddDays(6) -DeadlineTime (Get-Date).AddDays(9)
        }
        if ($GroupRing3) {
            Write-Host "[i] Assigning to Ring3 group for deployment in 8 days..."
            Add-IntuneWin32AppAssignmentGroup -ID $app.id -GroupId $GroupRing3[0] -Intent "required" -Notification "showAll" -Include -AvailableTime (Get-Date).AddDays(8) -DeadlineTime (Get-Date).AddDays(11)
        }
        if ($GroupLast) {
            Write-Host "[i] Assigning to Last group for deployment in 10 days..."
            Add-IntuneWin32AppAssignmentGroup -ID $app.id -GroupId $GroupLast[0] -Intent "required" -Notification "showAll" -Include -AvailableTime (Get-Date).AddDays(10) -DeadlineTime (Get-Date).AddDays(15)
        }

        Write-Host "[+] Assignments updated successfully."
    }
    finally {
        # No disconnect needed
    }
}

# --- Main Script Logic ---
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseDir = Resolve-Path -Path (Join-Path $PSScriptRoot "..")
$ToolsDir = Join-Path $BaseDir "Tools"
$OutputFolder = Join-Path $BaseDir "KBs"
$CsvFile = Join-Path $BaseDir "kbmap.csv"

$TargetBuilds = @(
    # Windows 10
    @{ OS = "Windows 10"; Build = "19045"; Arch = "x64" },
    @{ OS = "Windows 10"; Build = "19045"; Arch = "arm64" },
    # Windows 11
    @{ OS = "Windows 11"; Build = "22631"; Arch = "x64" },   # 23H2
    @{ OS = "Windows 11"; Build = "22631"; Arch = "arm64" }, # 23H2
    @{ OS = "Windows 11"; Build = "26100"; Arch = "x64" },   # 24H2
    @{ OS = "Windows 11"; Build = "26100"; Arch = "arm64" }  # 24H2
)

if (-not (Test-Path $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder | Out-Null }

$KBMap = @()
foreach ($target in $TargetBuilds) {
    $os = $target.OS; $build = $target.Build; $arch = $target.Arch
    $searchTerm = "Cumulative Update for $($os) Version $($build.Substring(0,2))H2 for $($arch)-based Systems"
    if ($os -eq "Windows 10") { $searchTerm = "Cumulative Update for Windows 10 Version 22H2 for $arch-based Systems" }
    if ($os -eq "Windows 11" -and $build -eq "26100") { $searchTerm = "Cumulative Update for Windows 11 Version 24H2 for $arch-based Systems" }
    
    Write-Host "[i] Searching for latest update for $os Build $build ($arch)..."
    $update = Get-MSCatalogUpdate -Search $searchTerm -ExcludeFramework -IncludePreview:$false | Select-Object -First 1
    
    if ($update) {
        if ($update.Title -match "KB(\d+)") {
            $kbNumber = $Matches[1]
        } else {
            Write-Warning "[!] Could not parse KB number from title: $($update.Title)"
            continue
        }

        $fileName = "$($kbNumber).msu"
        $destination = Join-Path $OutputFolder $fileName
        if (-not (Test-Path $destination)) {
            Write-Host "[i] Downloading $($update.Title)..."
            Save-MSCatalogUpdate -Update $update -Destination $OutputFolder
            Start-Sleep -Seconds 2
            $downloadedFile = Get-ChildItem -Path $OutputFolder -Filter "*$kbNumber*.msu" | Select-Object -First 1
            if ($downloadedFile) {
                if ($downloadedFile.Name -ne $fileName){
                    Rename-Item -Path $downloadedFile.FullName -NewName $fileName -Force -ErrorAction Stop
                }
            } else {
                throw "[!] Could not find the downloaded file for KB $kbNumber in $OutputFolder."
            }
        }
        $KBMap += [PSCustomObject]@{ OS = $os; Build = $build; KB = $kbNumber; FileName = "KBs\$fileName" }
    }
}

if ($KBMap.Count -eq 0) {
    Write-Host "[!] No updates were downloaded. Skipping packaging and upload."
    exit
}

$KBMap | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8
Write-Host "[+] Successfully generated kbmap.csv."

if ($PSBoundParameters.ContainsKey('ClientId')) {
    # The Detection.ps1 script is now a standalone file, so we no longer generate it.
    # We just need to ensure it exists before trying to package it.
    $detectionScriptPath = Join-Path $BaseDir "Scripts\Detection.ps1"
    if (-not (Test-Path $detectionScriptPath)) {
        throw "[!] Detection script not found at '$detectionScriptPath'. It should be part of the script source."
    }

    Publish-NewOrUpdateIntuneApp -ToolsDir $ToolsDir -SourceFolder $BaseDir
} else {
    Write-Host "[+] KB download and mapping complete. Skipping Intune publishing."
}
