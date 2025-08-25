<#
.SYNOPSIS
    Installs the correct KB according to the OS build.
.DESCRIPTION
    - Reads kbmap.csv to find the right update.
    - Detects the current OS build.
    - Installs the corresponding KB silently.
#>

# The script is running from the root of the extracted package on the client.
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# The script runs from the 'Scripts' subdirectory, but the CSV is at the root.
$CsvFile = Join-Path $PSScriptRoot "..\kbmap.csv"

if (-not (Test-Path $CsvFile)) {
    # This error will be visible in Intune logs if something goes wrong.
    Write-Error "[!] kbmap.csv not found at $CsvFile. Cannot proceed."
    exit 1
}

try {
    $osInfo = Get-CimInstance Win32_OperatingSystem
    $build = [int]$osInfo.BuildNumber
    # Use -like for broader compatibility
    $osName = if ($osInfo.Caption -like "*Windows 10*") { "Windows 10" } else { "Windows 11" }

    # Determine system architecture to find the correct entry in the map.
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -eq 'AMD64') {
        $mappedArch = 'x64'
    } elseif ($arch -eq 'ARM64') {
        $mappedArch = 'arm64'
    } else {
        Write-Error "Installation failed: Unsupported processor architecture '$arch'."
        exit 1
    }
}
catch {
    Write-Error "[!] Failed to get OS or architecture information."
    throw $_
}


$kbMap = Import-Csv $CsvFile | Where-Object { $_.OS -eq $osName }

$kbEntry = $kbMap | Where-Object { $_.Build -eq $build.ToString() -and $_.Arch -eq $mappedArch }

if (-not $kbEntry) {
    Write-Host "[+] No applicable KB found for $osName build $build and architecture $mappedArch in kbmap.csv. Nothing to do."
    exit 0
}

# Ensure there is only one entry found. If multiple, it's an error.
if ($kbEntry.Count -gt 1) {
    Write-Error "[!] Found multiple matching entries for build $build and architecture $mappedArch. Cannot proceed."
    exit 1
}

# Split filename field by space to handle one or more files.
$files = $kbEntry.FileName.Split(' ')
$finalExitCode = 0 # Default to success

Write-Host "[i] Found $($files.Count) update file(s) to install for KB $($kbEntry.KB) on $osName build $build."

foreach ($file in $files) {
    if (-not $file) { continue } # Skip empty entries if there are extra spaces

    # The $file path (e.g., "KBs\...") is relative to the package root, not the script's location.
    $msuFile = Join-Path $PSScriptRoot "..\$file"
    if (-not (Test-Path $msuFile)) {
        Write-Error "[!] MSU file not found at '$msuFile'. The package seems to be incomplete."
        exit 1 # Exit immediately if a file is missing
    }

    Write-Host "[i] Installing file: $file..."
    try {
        $process = Start-Process "wusa.exe" -ArgumentList "`"$msuFile`" /quiet /norestart" -Wait -PassThru -ErrorAction Stop
        $exitCode = $process.ExitCode
        Write-Host "[+] Installation of $file completed with exit code: $exitCode"

        # Handle exit codes for Intune.
        # 3010 (reboot required) has the highest priority.
        # Any other non-zero code indicates a failure.
        if ($exitCode -eq 3010) {
            $finalExitCode = 3010
        } elseif ($exitCode -ne 0 -and $finalExitCode -ne 3010) {
            # If an error occurs, record it, but don't overwrite a pending reboot code.
            $finalExitCode = $exitCode
        }
    }
    catch {
        Write-Error "[!] Failed to execute wusa.exe for '$msuFile'. Error details below."
        # Capture the actual error record from the catch block.
        Write-Error $_
        exit 1 # Exit with a generic failure code if the process fails to start.
    }
}

# Exit with the final aggregated code. Intune uses this to determine success/failure/reboot.
# 0 = Success
# 3010 = Success, reboot required
# Other non-zero = Failure
Write-Host "[+] All installations are complete. Final exit code for Intune is: $finalExitCode"
exit $finalExitCode
