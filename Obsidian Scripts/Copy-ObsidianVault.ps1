<#
.SYNOPSIS
    Copies the Obsidian vault from OneDrive to Andrew J IT Labs.

.DESCRIPTION
    Uses Robocopy to mirror all files and folders from
    C:\Users\orion\OneDrive\Obsidian to C:\Users\orion\Andrew J IT Labs.
    Existing files at the destination are overwritten. Source files are not
    deleted. A timestamped log is written to the destination root.

.NOTES
    Author: Andrew Jones
    Version: 1.0
    Requires: PowerShell 5.1+, Robocopy (included in Windows)
#>

#Requires -Version 5.1

# ============================================================================
# CONFIG
# ============================================================================

$Source      = "C:\Users\Administrator\OneDrive\Obsidian"
$Destination = "C:\Users\orion\Andrew J IT Labs\Andrew J IT Labs - Andrew J IT Labs\Obsidian"
$LogFile     = "$Destination\CopyLog_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt"

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
    $colours = @{
        "INFO"    = "Cyan"
        "SUCCESS" = "Green"
        "WARNING" = "Yellow"
        "ERROR"   = "Red"
    }
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message" -ForegroundColor $colours[$Level]
}

# ============================================================================
# MAIN
# ============================================================================

Write-Host "`n=== Obsidian Vault Copy ===`n" -ForegroundColor Cyan

# Validate source
if (-not (Test-Path -LiteralPath $Source)) {
    Write-Log "Source not found: $Source" -Level ERROR
    exit 1
}

# Create destination if it does not exist
if (-not (Test-Path -LiteralPath $Destination)) {
    Write-Log "Creating destination: $Destination" -Level WARNING
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}

Write-Log "Source      : $Source"      -Level INFO
Write-Log "Destination : $Destination" -Level INFO
Write-Log "Log file    : $LogFile"     -Level INFO
Write-Host ""

# Robocopy flags:
#   /E        - Copy subdirectories including empty ones
#   /COPYALL  - Copy all file attributes (data, timestamps, attributes, owner, ACL)
#   /IS       - Include same files (forces overwrite of identical files)
#   /IT       - Include tweaked files (forces overwrite of files with different attributes)
#   /R:3      - Retry 3 times on failed copies
#   /W:5      - Wait 5 seconds between retries
#   /TEE      - Output to console AND log file simultaneously
#   /LOG+     - Append to log file

$robocopyArgs = @(
    "`"$Source`""
    "`"$Destination`""
    "*.*"
    "/E"
    "/COPYALL"
    "/IS"
    "/IT"
    "/R:3"
    "/W:5"
    "/TEE"
    "/LOG+:`"$LogFile`""
)

Write-Log "Starting copy..." -Level INFO
Write-Host ""

$process = Start-Process -FilePath "robocopy" `
                         -ArgumentList $robocopyArgs `
                         -Wait `
                         -PassThru `
                         -NoNewWindow

# Robocopy exit codes: 0-7 = success/warnings, 8+ = one or more failures
# https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy#exit-return-codes
Write-Host ""
if ($process.ExitCode -lt 8) {
    Write-Log "Copy completed successfully. Exit code: $($process.ExitCode)" -Level SUCCESS
    Write-Log "Log saved to: $LogFile" -Level INFO
}
else {
    Write-Log "Copy completed with errors. Exit code: $($process.ExitCode)" -Level ERROR
    Write-Log "Review log for details: $LogFile" -Level WARNING
}

Write-Host ""
