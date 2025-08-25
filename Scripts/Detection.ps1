# --- DIAGNOSTIC SCRIPT ---
# This script is designed to help debug the execution context of Intune detection scripts.
# It logs environment information and then exits with an error code to ensure the output is captured.

try {
    Write-Host "--- Starting Diagnostic Logging ---"

    # 1. Log Current Working Directory
    $cwd = Get-Location
    Write-Host "Current Working Directory: $($cwd.Path)"

    # 2. Log content of automatic variables
    Write-Host "PSScriptRoot automatic variable: $PSScriptRoot"
    Write-Host "MyInvocation.MyCommand.Path: $($MyInvocation.MyCommand.Path)"
    Write-Host "MyInvocation.MyCommand.Definition: $($MyInvocation.MyCommand.Definition)"

    # 3. Log recursive file listing from the current directory
    Write-Host "--- Recursive File Listing from CWD ---"
    Get-ChildItem -Path $cwd.Path -Recurse | ForEach-Object { Write-Host $_.FullName }
    Write-Host "--- End File Listing ---"

    # 4. Attempt to find the kbmap.csv from a few common relative paths
    $pathsToTest = @("kbmap.csv", ".\kbmap.csv", "..\kbmap.csv", "Scripts\kbmap.csv", ".\Scripts\kbmap.csv")
    foreach ($path in $pathsToTest) {
        $found = Test-Path $path -PathType Leaf
        Write-Host "Testing path '$path'... Found: $found"
    }
}
catch {
    Write-Error "An error occurred during diagnostic script execution: $_"
}
finally {
    Write-Error "--- Diagnostic Run Complete. Exiting with error code 1 to ensure logs are visible. ---"
    exit 1
}
