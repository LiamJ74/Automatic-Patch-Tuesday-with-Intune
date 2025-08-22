# This script is used by Intune to detect if the application is already installed.
# It checks if the correct KB for the device's OS build is present.

$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$kbMap = Import-Csv -Path (Join-Path $PSScriptRoot "kbmap.csv") -ErrorAction SilentlyContinue

# If the CSV map doesn't exist, something is wrong with the package content.
if ($null -eq $kbMap) {
    exit 1
}

$osInfo = Get-CimInstance Win32_OperatingSystem
$build = [int]$osInfo.BuildNumber

# Find the entry in the map for this specific OS build.
$kbEntry = $kbMap | Where-Object { $_.Build -eq $build.ToString() }

if ($kbEntry) {
    $kbNumber = $kbEntry.KB
    # Check if the hotfix is installed. If so, exit with 0 to indicate "Found".
    if (Get-HotFix -Id $kbNumber -ErrorAction SilentlyContinue) {
        Write-Host "Detection successful: KB$($kbNumber) is installed."
        exit 0
    }
}

# If we get here, the KB is not installed or not applicable. Exit with 1 to indicate "Not Found".
exit 1
