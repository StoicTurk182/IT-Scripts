<#
.SYNOPSIS
    Zips the folder this script is placed in and saves the archive alongside it.

.DESCRIPTION
    Automatically detects the folder it lives in, compresses all contents
    (excluding itself and the log) into a timestamped zip file, and writes
    a log of every file included. The zip and log are saved in the same folder.

.EXAMPLE
    Place this script in any folder and run:
    .\Compress-Folder.ps1

.NOTES
    Author: Andrew Jones
    Version: 1.0
    Requires: PowerShell 5.1+
#>

#Requires -Version 5.1

# ============================================================================
# CONFIG - auto-detected from script location, no edits needed
# ============================================================================

$ScriptName  = "Compress-Folder.ps1"
$TargetDir   = $PSScriptRoot
$FolderName  = Split-Path $TargetDir -Leaf
$Timestamp   = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$ZipPath     = Join-Path $TargetDir "$FolderName`_$Timestamp.zip"
$LogPath     = Join-Path $TargetDir "CompressLog_$Timestamp.txt"

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
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message"
    Write-Host $line -ForegroundColor $colours[$Level]
    Add-Content -LiteralPath $LogPath -Value $line
}

# ============================================================================
# MAIN
# ============================================================================

Write-Host "`n=== Folder Compress Utility ===`n" -ForegroundColor Cyan

# Validate source folder
if (-not (Test-Path -LiteralPath $TargetDir)) {
    Write-Host "[ERROR] Target folder not found: $TargetDir" -ForegroundColor Red
    exit 1
}

# Initialise log file
New-Item -ItemType File -Path $LogPath -Force | Out-Null
Add-Content -LiteralPath $LogPath -Value "=== Compress Log - $Timestamp ==="
Add-Content -LiteralPath $LogPath -Value "Source  : $TargetDir"
Add-Content -LiteralPath $LogPath -Value "Archive : $ZipPath"
Add-Content -LiteralPath $LogPath -Value ""

Write-Log "Source  : $TargetDir"
Write-Log "Archive : $ZipPath"
Write-Log "Log     : $LogPath"
Write-Host ""

# Collect all items excluding this script, any existing zips, and the log
$allItems = Get-ChildItem -LiteralPath $TargetDir -Recurse -File |
    Where-Object {
        $_.Name -ne $ScriptName -and
        $_.Extension -ne ".zip" -and
        $_.FullName -ne $LogPath
    }

if ($allItems.Count -eq 0) {
    Write-Log "No files found to compress." -Level WARNING
    exit 0
}

Write-Log "Files to compress: $($allItems.Count)" -Level INFO
Write-Host ""

# Log every file that will be included
Add-Content -LiteralPath $LogPath -Value "--- Files Included ---"
foreach ($item in $allItems) {
    $relativePath = $item.FullName.Substring($TargetDir.Length + 1)
    Add-Content -LiteralPath $LogPath -Value "  $relativePath"
}
Add-Content -LiteralPath $LogPath -Value ""

# Compress - uses a temp staging folder so the zip entry paths are clean
$TempDir = Join-Path $env:TEMP "CompressStage_$Timestamp"
Write-Log "Staging files to temp folder..." -Level INFO

try {
    # Replicate folder structure into temp
    foreach ($item in $allItems) {
        $relativePath = $item.FullName.Substring($TargetDir.Length + 1)
        $destPath     = Join-Path $TempDir $relativePath
        $destParent   = Split-Path $destPath -Parent

        if (-not (Test-Path $destParent)) {
            New-Item -ItemType Directory -Path $destParent -Force | Out-Null
        }
        Copy-Item -LiteralPath $item.FullName -Destination $destPath -Force
    }

    Write-Log "Compressing to zip..." -Level INFO
    Compress-Archive -Path "$TempDir\*" -DestinationPath $ZipPath -CompressionLevel Optimal -Force

    $zipSize = [math]::Round((Get-Item $ZipPath).Length / 1MB, 2)
    Write-Host ""
    Write-Log "Archive created: $ZipPath ($zipSize MB)" -Level SUCCESS
    Write-Log "Files included : $($allItems.Count)" -Level SUCCESS
    Write-Log "Log saved      : $LogPath" -Level SUCCESS

    Add-Content -LiteralPath $LogPath -Value "--- Result ---"
    Add-Content -LiteralPath $LogPath -Value "Status : SUCCESS"
    Add-Content -LiteralPath $LogPath -Value "Archive: $ZipPath"
    Add-Content -LiteralPath $LogPath -Value "Size   : $zipSize MB"
    Add-Content -LiteralPath $LogPath -Value "Files  : $($allItems.Count)"
}
catch {
    Write-Log "Compression failed: $_" -Level ERROR
    Add-Content -LiteralPath $LogPath -Value "Status : FAILED - $_"
    exit 1
}
finally {
    # Always clean up temp staging folder
    if (Test-Path $TempDir) {
        Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
