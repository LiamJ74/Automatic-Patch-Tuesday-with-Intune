# This script is used by Intune to detect if the application is already installed.
# It checks if the device's OS Update Build Revision (UBR) is at or above the required minimum.

# The script's PSScriptRoot is the ...\Scripts directory. The kbmap.csv is one level up.
try {
    $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $kbMapPath = Join-Path $PSScriptRoot "..\" "kbmap.csv"
} catch {
    Write-Error "Failed to construct path to kbmap.csv. Error: $_"
    exit 1
}

# Check if the map file exists.
if (-not (Test-Path $kbMapPath)) {
    Write-Error "Detection script failed: kbmap.csv not found at the expected path '$kbMapPath'."
    exit 1
}
$kbMap = Import-Csv -Path $kbMapPath -ErrorAction SilentlyContinue

# If the CSV map is empty or unreadable, something is wrong with the package content.
if ($null -eq $kbMap) {
    Write-Error "Detection script failed: Could not import or parse kbmap.csv from '$kbMapPath'."
    exit 1
}

# Get OS and architecture information
try {
    $osInfo = Get-CimInstance Win32_OperatingSystem
    $currentBuild = $osInfo.BuildNumber
    $currentUBR = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "UBR" -ErrorAction Stop).UBR

    # Determine system architecture to find the correct entry in the map.
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -eq 'AMD64') {
        $mappedArch = 'x64'
    } elseif ($arch -eq 'ARM64') {
        $mappedArch = 'arm64'
    } else {
        Write-Error "Detection failed: Unsupported processor architecture '$arch'."
        exit 1
    }
}
catch {
    # This key might not exist on a freshly installed OS before the first CU.
    if ($_.Exception.Message -like "*Cannot find path*HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion*because it does not exist*") {
        $currentUBR = 0
    } else {
        Write-Error "Detection failed: Could not retrieve OS or architecture information. Error: $_"
        exit 1
    }
}

# Find the entry in the map for this specific OS build and architecture.
$kbEntry = $kbMap | Where-Object { $_.Build -eq $currentBuild -and $_.Arch -eq $mappedArch }

if ($kbEntry) {
    # Ensure there is only one entry found. If multiple, it's an error.
    if ($kbEntry.Count -gt 1) {
        Write-Error "Detection failed: Found multiple matching entries for build $currentBuild and architecture $mappedArch."
        exit 1
    }

    try {
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
    catch {
        Write-Error "Detection script failed during UBR comparison. Error: $_"
        exit 1
    }
}

# If we get here, the OS build was not found in the map.
Write-Host "Detection failed: OS Build $currentBuild with architecture $mappedArch not found in kbmap.csv."
exit 1
