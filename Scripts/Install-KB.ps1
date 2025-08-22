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

$CsvFile = Join-Path $PSScriptRoot "kbmap.csv"

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
}
catch {
    Write-Error "[!] Failed to get OS information."
    throw $_
}


$kbMap = Import-Csv $CsvFile | Where-Object { $_.OS -eq $osName }

$kbEntry = $kbMap | Where-Object { $_.Build -eq $build.ToString() }

if (-not $kbEntry) {
    Write-Host "[+] No applicable KB found for $osName build $build in kbmap.csv. Nothing to do."
    exit 0
}

$msuFile = Join-Path $PSScriptRoot $kbEntry.FileName

if (-not (Test-Path $msuFile)) {
    Write-Error "[!] MSU file not found at '$msuFile'. The package seems to be incomplete."
    exit 1
}

Write-Host "[i] Installing KB $($kbEntry.KB) for $osName build $build..."
$exitCode = 0 # Default to success unless changed
try {
    # Using wusa.exe to install the update package silently.
    # /quiet and /norestart are used for unattended installation.
    # -PassThru returns the process object, which we wait for and then get the exit code from.
    $process = Start-Process "wusa.exe" -ArgumentList "`"$msuFile`" /quiet /norestart" -Wait -PassThru -ErrorAction Stop
    $exitCode = $process.ExitCode
    Write-Host "[+] Installation process for KB $($kbEntry.KB) completed with exit code: $exitCode"
}
catch {
    Write-Error "[!] Failed to start wusa.exe to install the update."
    # We will exit with a generic failure code if the process fails to start.
    # The error record from the 'throw' will be in the logs.
    exit 1
}

# Exit with the code from wusa.exe. Intune uses this to determine success/failure/reboot.
# 0 = Success
# 3010 = Success, reboot required
# Other non-zero = Failure
exit $exitCode
