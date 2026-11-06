#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Selectively clears Temp, Prefetch, Windows Update cache, Recycle Bin and
    Downloads with size reporting.

.DESCRIPTION
    Reports the current size of:
      - User Temp      ($env:TEMP)
      - System Temp    (C:\Windows\Temp)
      - Prefetch       (C:\Windows\Prefetch)
      - Update Cache   (C:\Windows\SoftwareDistribution)
      - Recycle Bin    (current user, all local fixed drives)
      - Downloads      (current user, honours folder redirection)

    Prompts for confirmation before clearing each target individually.
    Downloads requires typing YES as it contains user data.
    The Update Cache step stops wuauserv and BITS, clears the folder, then
    restarts only the services that were running beforehand.
    Files locked by running processes are skipped silently.
    Total space reclaimed is reported at completion.
    All output is logged to $env:TEMP\CacheCleanLogs\.

.EXAMPLE
    .\clear_pre_v3.ps1
    Reports sizes and prompts for confirmation on each target.

.INPUTS
    None.

.OUTPUTS
    None. All output is written to the console host.

.NOTES
    Author:   Andrew Jones
    Version:  1.3
    Created:  2026-04-06
    Modified: 2026-11-06

    Changelog:
      1.3 - Added SoftwareDistribution (Update Cache), Recycle Bin, Downloads.
            Size/clear functions accept multiple paths and use -LiteralPath.
      1.2 - Null guard on size calc, timestamp, transcript logging, negative reclaim fix
      1.1 - Initial release

    Requires: Administrator privileges
    Note:     Recycle Bin, Downloads and User Temp resolve to the account the
              elevated session runs as. If elevated with a separate admin
              account, those targets belong to that account, not the
              logged-on user.
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
    param ([string[]]$Path)
    $total = 0
    foreach ($p in $Path) {
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
        # Null guard: Measure-Object returns $null Sum if folder is empty
        $sum = (Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
        if ($null -ne $sum) { $total += $sum }
    }
    return $total / 1MB
}

function Clear-Folder {
    param ([string[]]$Path)
    foreach ($p in $Path) {
        if (-not $p -or -not (Test-Path -LiteralPath $p)) {
            Write-Host "  Path not found: $p" -ForegroundColor Yellow
            continue
        }
        Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Confirm-Action {
    param ([string]$Prompt)
    $response = Read-Host "$Prompt [Y/N]"
    return $response -match '^[Yy]$'
}

function Confirm-Strong {
    param ([string]$Prompt)
    $response = Read-Host "$Prompt Type YES to confirm"
    return $response -ceq 'YES'
}

function Get-RecycleBinPaths {
    # Per-user bin is <Drive>:\$Recycle.Bin\<SID>. Scoped to the current SID
    # so the size reported matches what Clear-RecycleBin actually empties.
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path "$($_.DeviceID)\" "`$Recycle.Bin\$sid" } |
        Where-Object { Test-Path -LiteralPath $_ }
}

function Get-DownloadsPath {
    # Downloads has no [Environment+SpecialFolder] value. Read the Known Folder
    # GUID from User Shell Folders so redirected/OneDrive locations are honoured.
    $key  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $guid = '{374DE290-123F-4565-9164-39C4925E467B}'
    $raw  = (Get-ItemProperty -Path $key -Name $guid -ErrorAction SilentlyContinue).$guid
    if ($raw) { return [Environment]::ExpandEnvironmentVariables($raw) }
    return Join-Path $env:USERPROFILE 'Downloads'
}

function Clear-RecycleBinSafe {
    param ([string[]]$Path)
    if (Get-Command Clear-RecycleBin -ErrorAction SilentlyContinue) {
        # Windows PowerShell 5.1: empties the current user's bin on all drives
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    } else {
        # PowerShell 7 fallback: remove contents of the per-SID folders directly
        Clear-Folder -Path $Path
    }
}

function Clear-UpdateCache {
    param ([string[]]$Path)
    $services   = @('wuauserv', 'bits')
    $wasRunning = @()

    foreach ($svc in $services) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s -and $s.Status -eq 'Running') {
            $wasRunning += $svc
            Write-Host "  Stopping $svc..." -ForegroundColor DarkGray
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        }
    }

    foreach ($svc in $services) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if (-not $s) { continue }
        try {
            $s.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
        } catch {
            Write-Host "  Warning: $svc did not stop within 30s. Locked files will be skipped." -ForegroundColor Yellow
        }
    }

    Clear-Folder -Path $Path

    foreach ($svc in $wasRunning) {
        Write-Host "  Starting $svc..." -ForegroundColor DarkGray
        Start-Service -Name $svc -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# MAIN
# ============================================================================

$RunTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
Write-Host "`n=== Temp, Cache and User Data Cleanup === $RunTime`n" -ForegroundColor Cyan

# Type controls how each target is cleared and confirmed:
#   Folder     - plain content delete, Y/N
#   UpdateCache- stop wuauserv/BITS, delete, restart, Y/N
#   RecycleBin - Clear-RecycleBin (or per-SID delete), Y/N
#   UserData   - plain content delete, requires typed YES
$targets = [ordered]@{
    "User Temp"    = @{ Type = 'Folder';      Path = @($env:TEMP) }
    "System Temp"  = @{ Type = 'Folder';      Path = @("$env:SystemRoot\Temp") }
    "Prefetch"     = @{ Type = 'Folder';      Path = @("$env:SystemRoot\Prefetch") }
    "Update Cache" = @{ Type = 'UpdateCache'; Path = @("$env:SystemRoot\SoftwareDistribution") }
    "Recycle Bin"  = @{ Type = 'RecycleBin';  Path = @(Get-RecycleBinPaths) }
    "Downloads"    = @{ Type = 'UserData';    Path = @(Get-DownloadsPath) }
}

Write-Host "Running as: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ForegroundColor Gray
Write-Host "Downloads:  $($targets['Downloads'].Path -join ', ')`n" -ForegroundColor Gray

# --- Report sizes ---
Write-Host "Current sizes:`n" -ForegroundColor Yellow

$sizes       = @{}
$totalBefore = 0

foreach ($name in $targets.Keys) {
    $size         = Get-FolderSizeMB -Path $targets[$name].Path
    $sizes[$name] = $size
    $totalBefore += $size
    Write-Host ("  {0,-15} {1,10} MB" -f $name, [math]::Round($size, 2))
}

Write-Host ("  {0,-15} {1,10} MB`n" -f "TOTAL", [math]::Round($totalBefore, 2)) -ForegroundColor White

# --- Prompt and clear ---
Write-Host "Select targets to clear:`n" -ForegroundColor Yellow

$cleared = @()

foreach ($name in $targets.Keys) {
    $t      = $targets[$name]
    $sizeMB = [math]::Round($sizes[$name], 2)

    if ($sizes[$name] -eq 0) {
        Write-Host "  $name is empty, skipping.`n" -ForegroundColor DarkGray
        continue
    }

    switch ($t.Type) {
        'UpdateCache' {
            Write-Host "  Note: Windows Update history shown in Settings will be reset." -ForegroundColor DarkYellow
            $ok = Confirm-Action "  Clear $name ($sizeMB MB)?"
        }
        'UserData' {
            Write-Host "  WARNING: $name is user data and is deleted permanently (not sent to Recycle Bin)." -ForegroundColor Red
            $ok = Confirm-Strong "  Clear $name ($sizeMB MB)?"
        }
        default {
            $ok = Confirm-Action "  Clear $name ($sizeMB MB)?"
        }
    }

    if ($ok) {
        switch ($t.Type) {
            'UpdateCache' { Clear-UpdateCache    -Path $t.Path }
            'RecycleBin'  { Clear-RecycleBinSafe -Path $t.Path }
            default       { Clear-Folder         -Path $t.Path }
        }
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
    $size        = Get-FolderSizeMB -Path $targets[$name].Path
    $totalAfter += $size
    $status      = if ($cleared -contains $name) { "cleared" } else { "skipped" }
    Write-Host ("  {0,-15} {1,10} MB  ({2})" -f $name, [math]::Round($size, 2), $status)
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