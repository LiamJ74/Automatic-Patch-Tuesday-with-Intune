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

# --- Mode-aware installation logic ---
$csvHeaders = $kbMap[0].psobject.Properties.Name
$finalExitCode = 0 # Default to success

if ($csvHeaders -contains 'FileName') {
    # --- PREPACKAGE MODE ---
    Write-Host "[i] 'FileName' column found. Running in Prepackage mode."
    $files = $kbEntry.FileName.Split(' ')
    Write-Host "[i] Found $($files.Count) update file(s) to install for KB $($kbEntry.KB)."

    foreach ($file in $files) {
        if (-not $file) { continue }
        $msuFile = Join-Path $PSScriptRoot "..\$file"
        if (-not (Test-Path $msuFile)) {
            Write-Error "[!] MSU file not found at '$msuFile'."
            exit 1
        }

        Write-Host "[i] Installing file: $file..."
        try {
            $process = Start-Process "wusa.exe" -ArgumentList "`"$msuFile`" /quiet /norestart" -Wait -PassThru -ErrorAction Stop
            $exitCode = $process.ExitCode
            Write-Host "[+] Installation of $file completed with exit code: $exitCode"
            if ($exitCode -eq 3010) { $finalExitCode = 3010 }
            elseif ($exitCode -ne 0 -and $finalExitCode -ne 3010) { $finalExitCode = $exitCode }
        }
        catch {
            Write-Error "[!] Failed to execute wusa.exe for '$msuFile'. Error: $_"
            exit 1
        }
    }

}
elseif ($csvHeaders -contains 'Title') {
    # --- ONDEMAND MODE ---
    Write-Host "[i] 'Title' column found. Running in OnDemand mode."
    $tempDir = Join-Path $env:TEMP "KBInstaller-$(New-Guid)"
    if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }

    try {
        if (-not (Get-Module -ListAvailable -Name MSCatalogLTS)) {
            Write-Error "[!] MSCatalogLTS module is not available on this system."
            exit 1
        }
        Import-Module MSCatalogLTS -Force

        Write-Host "[i] Searching for update with Title: '$($kbEntry.Title)'"
        $update = Get-MSCatalogUpdate -Search $kbEntry.Title | Where-Object { $_.Title -eq $kbEntry.Title } | Select-Object -First 1
        if (-not $update) {
            Write-Error "[!] Could not find required update (KB$($kbEntry.KB)) in Catalog."
            exit 1
        }

        Write-Host "[i] Downloading KB$($kbEntry.KB)..."
        Save-MSCatalogUpdate -Update $update -Destination $tempDir
        $msuFile = Get-ChildItem -Path $tempDir -Filter "*.msu" | Select-Object -First 1
        if (-not $msuFile) {
            Write-Error "[!] Failed to download MSU file for KB$($kbEntry.KB)."
            exit 1
        }

        Write-Host "[i] Installing file: $($msuFile.Name)..."
        $process = Start-Process "wusa.exe" -ArgumentList "`"$($msuFile.FullName)`" /quiet /norestart" -Wait -PassThru -ErrorAction Stop
        $exitCode = $process.ExitCode
        Write-Host "[+] Installation of $($msuFile.Name) completed with exit code: $exitCode"
        if ($exitCode -eq 3010) { $finalExitCode = 3010 }
        elseif ($exitCode -ne 0) { $finalExitCode = $exitCode }
    }
    catch {
        Write-Error "[!] An error occurred during the OnDemand download/install process. Error: $_"
        if ($finalExitCode -eq 0) { $finalExitCode = 1 }
    }
    finally {
        if (Test-Path $tempDir) {
            Write-Host "[i] Cleaning up temporary directory..."
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
else {
    Write-Error "[!] Invalid kbmap.csv structure. Must contain either a 'FileName' or 'Title' column."
    exit 1
}

# --- Final Exit Code ---
Write-Host "[+] Process complete. Final exit code for Intune is: $finalExitCode"
exit $finalExitCode
