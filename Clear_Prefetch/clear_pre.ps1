#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Check and selectively clear Temp and Prefetch folders.

.DESCRIPTION
    Reports the size of User Temp, System Temp, and Prefetch.
    Prompts for confirmation before clearing each folder individually.
    Locked files in use by running processes are skipped silently.
    Outputs total space reclaimed at completion.

.NOTES
    Author: Andrew Jones
    Version: 1.1
    Requires: Administrator privileges
#>

# ============================================================================
# FUNCTIONS
# ============================================================================

function Get-FolderSizeMB {
    param ([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue |
     Measure-Object -Property Length -Sum).Sum / 1MB
}

function Clear-Folder {
    param ([string]$Path)
    if (-not (Test-Path $Path)) {
        Write-Host "  Path not found: $Path" -ForegroundColor Yellow
        return
    }
    Remove-Item "$Path\*" -Recurse -Force -ErrorAction SilentlyContinue
}

function Confirm-Action {
    param ([string]$Prompt)
    $response = Read-Host "$Prompt [Y/N]"
    return $response -match '^[Yy]$'
}

# ============================================================================
# MAIN
# ============================================================================

Write-Host "`n=== Temp and Prefetch Cleanup ===`n" -ForegroundColor Cyan

$targets = [ordered]@{
    "User Temp"   = $env:TEMP
    "System Temp" = "C:\Windows\Temp"
    "Prefetch"    = "C:\Windows\Prefetch"
}

# --- Report sizes ---
Write-Host "Current folder sizes:`n" -ForegroundColor Yellow

$sizes = @{}
$totalBefore = 0

foreach ($name in $targets.Keys) {
    $size = Get-FolderSizeMB -Path $targets[$name]
    $sizes[$name] = $size
    $totalBefore += $size
    Write-Host ("  {0,-15} {1,8} MB" -f $name, [math]::Round($size, 2))
}

Write-Host ("  {0,-15} {1,8} MB`n" -f "TOTAL", [math]::Round($totalBefore, 2)) -ForegroundColor White

# --- Prompt and clear ---
Write-Host "Select folders to clear:`n" -ForegroundColor Yellow

$cleared = @()

foreach ($name in $targets.Keys) {
    $sizeMB = [math]::Round($sizes[$name], 2)
    if (Confirm-Action "  Clear $name ($sizeMB MB)?") {
        Clear-Folder -Path $targets[$name]
        $cleared += $name
        Write-Host "  $name cleared.`n" -ForegroundColor Green
    } else {
        Write-Host "  $name skipped.`n" -ForegroundColor DarkGray
    }
}

# --- Summary ---
Write-Host "Summary:" -ForegroundColor Yellow

$totalAfter = 0
foreach ($name in $targets.Keys) {
    $size = Get-FolderSizeMB -Path $targets[$name]
    $totalAfter += $size
    $status = if ($cleared -contains $name) { "cleared" } else { "skipped" }
    Write-Host ("  {0,-15} {1,8} MB  ({2})" -f $name, [math]::Round($size, 2), $status)
}

$reclaimed = [math]::Round($totalBefore - $totalAfter, 2)
Write-Host ("`n  Reclaimed: $reclaimed MB`n") -ForegroundColor Green