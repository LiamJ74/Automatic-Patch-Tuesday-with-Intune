# This script is used by Intune to detect if the application is already installed.
# It checks if the device's OS Update Build Revision (UBR) is at or above the required minimum.

$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$kbMapPath = Join-Path $PSScriptRoot "kbmap.csv"

# Check if the map file exists.
if (-not (Test-Path $kbMapPath)) {
    Write-Host "Detection script failed: kbmap.csv not found at '$kbMapPath'."
    exit 1
}
$kbMap = Import-Csv -Path $kbMapPath -ErrorAction SilentlyContinue

# If the CSV map is empty or unreadable, something is wrong with the package content.
if ($null -eq $kbMap) {
    Write-Host "Detection script failed: Could not import or parse kbmap.csv."
    exit 1
}

# Get OS Build and UBR (Update Build Revision)
$osInfo = Get-CimInstance Win32_OperatingSystem
$currentBuild = $osInfo.BuildNumber
try {
    $currentUBR = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "UBR" -ErrorAction Stop).UBR
} catch {
    # This key might not exist on a freshly installed OS before the first CU.
    $currentUBR = 0
}


# Find the entry in the map for this specific OS build.
$kbEntry = $kbMap | Where-Object { $_.Build -eq $currentBuild }

if ($kbEntry) {
    $requiredUBR = [int]$kbEntry.UBR

    # Check if the current UBR is greater than or equal to the required UBR.
    if ($currentUBR -ge $requiredUBR) {
        Write-Host "Detection successful: Current UBR ($currentUBR) meets or exceeds required UBR ($requiredUBR)."
        exit 0
    } else {
        Write-Host "Detection failed: Current UBR ($currentUBR) is less than required UBR ($requiredUBR)."
        exit 1
    }
}

# If we get here, the OS build was not found in the map.
Write-Host "Detection failed: OS Build $currentBuild not found in kbmap.csv."
exit 1
