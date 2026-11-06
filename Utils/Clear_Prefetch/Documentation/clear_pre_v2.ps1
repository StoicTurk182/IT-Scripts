#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Selectively clears Windows Temp and Prefetch folders with size reporting.

.DESCRIPTION
    Reports the current size of User Temp ($env:TEMP), System Temp
    (C:\Windows\Temp), and the Prefetch cache (C:\Windows\Prefetch).

    Prompts for confirmation before clearing each folder individually.
    Files locked by running processes are skipped silently.
    Total space reclaimed is reported at completion.
    All output is logged to $env:TEMP\CacheCleanLogs\.

.EXAMPLE
    .\clear_pre_v2.ps1
    Reports folder sizes and prompts for confirmation on each target.

.EXAMPLE
    Import-Module Clear-PreCache
    Clear-PreCache
    Runs the same logic via the installed PowerShell module.

.INPUTS
    None.

.OUTPUTS
    None. All output is written to the console host.

.NOTES
    Author:   Andrew Jones
    Version:  1.2
    Created:  2026-04-06
    Modified: 2026-04-07

    Changelog:
      1.2 — Null guard on size calc, timestamp, transcript logging, negative reclaim fix
      1.1 — Initial release

    Requires: Administrator privileges
    GitHub:   https://github.com/StoicTurk182/IT-Scripts

.LINK
    https://github.com/StoicTurk182/IT-Scripts
#>

# ============================================================================
# LOGGING
# ============================================================================

$LogDir  = "$env:TEMP\CacheCleanLogs"
if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$LogFile = "$LogDir\CacheClean_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"
Start-Transcript -Path $LogFile -Append | Out-Null

# ============================================================================
# FUNCTIONS
# ============================================================================

function Get-FolderSizeMB {
    param ([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    # Null guard: Measure-Object returns $null Sum if folder is empty
    $sum = (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return 0 }
    return $sum / 1MB
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

$RunTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
Write-Host "`n=== Temp and Prefetch Cleanup === $RunTime`n" -ForegroundColor Cyan

$targets = [ordered]@{
    "User Temp"   = $env:TEMP
    "System Temp" = "C:\Windows\Temp"
    "Prefetch"    = "C:\Windows\Prefetch"
}

# --- Report sizes ---
Write-Host "Current folder sizes:`n" -ForegroundColor Yellow

$sizes       = @{}
$totalBefore = 0

foreach ($name in $targets.Keys) {
    $size         = Get-FolderSizeMB -Path $targets[$name]
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
    $size        = Get-FolderSizeMB -Path $targets[$name]
    $totalAfter += $size
    $status      = if ($cleared -contains $name) { "cleared" } else { "skipped" }
    Write-Host ("  {0,-15} {1,8} MB  ({2})" -f $name, [math]::Round($size, 2), $status)
}

# Negative reclaim guard: new temp files written during script run can cause
# $totalAfter to exceed $totalBefore by a small amount. Floor at 0.
$reclaimed = [math]::Round($totalBefore - $totalAfter, 2)
if ($reclaimed -lt 0) { $reclaimed = 0 }
Write-Host ("`n  Reclaimed: $reclaimed MB`n") -ForegroundColor Green

# ============================================================================
# CLEANUP
# ============================================================================

Stop-Transcript | Out-Null
Write-Host "Log saved: $LogFile`n" -ForegroundColor Gray
