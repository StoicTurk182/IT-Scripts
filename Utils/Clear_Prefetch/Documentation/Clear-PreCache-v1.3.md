---
title: "Clear PreCache v1.3 - Temp, Update Cache, Recycle Bin and Downloads"
created: 2026-11-06T12:00:00
updated: 2026-11-06T12:00:00


---
# Clear PreCache v1.3 - Temp, Update Cache, Recycle Bin and Downloads

**Table of Contents**

1. [Overview](#overview)
2. [What Changed from v1.2](#what-changed-from-v12)
3. [Targets](#targets)
4. [How Each New Target Works](#how-each-new-target-works)
	1. [Update Cache (SoftwareDistribution)](#update-cache-softwaredistribution)
	2. [Recycle Bin](#recycle-bin)
	3. [Downloads](#downloads)
5. [Confirmation Behaviour](#confirmation-behaviour)
6. [Usage](#usage)
7. [Adding to IT-Scripts Menu](#adding-to-it-scripts-menu)
8. [Caveats](#caveats)
9. [Full Script](#full-script)
10. [References](#references)

## Overview

Interactive cleanup script that reports sizes, prompts per target, clears the selected locations and reports space reclaimed. Version 1.3 adds the Windows Update download cache (`C:\Windows\SoftwareDistribution`), the Recycle Bin and the user Downloads folder.

Requires Administrator. Tested logic targets Windows PowerShell 5.1; a fallback is included for PowerShell 7 where `Clear-RecycleBin` is not present.

## What Changed from v1.2

| Change | Detail |
|--------|--------|
| New target: Update Cache | Stops `wuauserv` and `bits`, clears `SoftwareDistribution`, restarts services that were running |
| New target: Recycle Bin | Current user's bin on all local fixed drives |
| New target: Downloads | Resolved from the Known Folder registry value so redirection and OneDrive are honoured |
| Typed confirmation | Downloads requires typing `YES` (case-sensitive) |
| Empty targets skipped | No prompt if a target is 0 MB |
| Functions take `[string[]]` | Size and clear functions accept multiple paths (needed for per-drive Recycle Bin) |
| `-LiteralPath` | Paths containing `$` (for example `$Recycle.Bin`) or brackets are not treated as wildcards |
| Size calc uses `-File` | Directories excluded from `Measure-Object` (they have no `Length`) |

## Targets

| Name | Path | Clear Method | Confirmation |
|------|------|--------------|--------------|
| User Temp | `$env:TEMP` | Delete contents | Y/N |
| System Temp | `C:\Windows\Temp` | Delete contents | Y/N |
| Prefetch | `C:\Windows\Prefetch` | Delete contents | Y/N |
| Update Cache | `C:\Windows\SoftwareDistribution` | Stop services, delete contents, restart | Y/N |
| Recycle Bin | `<Drive>:\$Recycle.Bin\<SID>` | `Clear-RecycleBin -Force` (5.1) or direct delete (7.x) | Y/N |
| Downloads | Known Folder `{374DE290-123F-4565-9164-39C4925E467B}` | Delete contents | Typed `YES` |

## How Each New Target Works

### Update Cache (SoftwareDistribution)

`SoftwareDistribution` holds downloaded update payloads (`Download`) and the Windows Update database (`DataStore`). Microsoft's documented reset procedure stops the Windows Update and BITS services before renaming or clearing this folder, because both services hold handles on it.

The script:

1. Records whether `wuauserv` and `bits` are running
2. Stops them with `Stop-Service -Force`
3. Waits up to 30 seconds for each to reach `Stopped`
4. Deletes the folder contents
5. Starts only the services that were running at step 1

Equivalent manual commands:

```powershell
Stop-Service wuauserv, bits -Force
Remove-Item "$env:SystemRoot\SoftwareDistribution\*" -Recurse -Force
Start-Service wuauserv, bits
```

Effect: Windows Update rebuilds the folder on its next scan. The update history list in Settings is reset because `DataStore` is removed. Installed updates are not affected and still appear under `Get-HotFix` / Programs and Features.

Narrower alternative if history must be preserved: target `$env:SystemRoot\SoftwareDistribution\Download` only by changing the path in the `$targets` block.

### Recycle Bin

Each user's bin lives at `<Drive>:\$Recycle.Bin\<User SID>` on every NTFS volume. The script:

- Gets the current SID via `[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value`
- Enumerates local fixed disks with `Win32_LogicalDisk` where `DriveType=3` (avoids slow lookups on mapped network drives)
- Measures only that SID's folder on each drive

Clearing uses `Clear-RecycleBin -Force`, which empties the current user's bin across all drives. Sizing is scoped to the same SID so the reported reclaim matches what is actually emptied (an elevated session can see other users' SID folders, which would otherwise inflate the before figure).

`Clear-RecycleBin` ships in Windows PowerShell 5.1 (`Microsoft.PowerShell.Management`). If not found, the script deletes the contents of the per-SID folders directly.

### Downloads

Downloads has no entry in `[Environment+SpecialFolder]`, so `[Environment]::GetFolderPath()` cannot be used. The path is read from:

```
HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders
Value: {374DE290-123F-4565-9164-39C4925E467B}
```

This GUID is `FOLDERID_Downloads`. Reading it means a Downloads folder redirected by GPO, moved by the user, or backed up by OneDrive Known Folder Move resolves to the real location. Fallback is `$env:USERPROFILE\Downloads`.

The resolved path is printed at start so it can be checked before confirming.

## Confirmation Behaviour

| Target Type | Prompt | Accepts |
|-------------|--------|---------|
| System/cache folders | `Clear X (n MB)? [Y/N]` | `Y` or `y` |
| Update Cache | Note about history reset, then Y/N | `Y` or `y` |
| Downloads | Red warning, then `Type YES to confirm` | `YES` exactly (`-ceq`) |
| Any target at 0 MB | No prompt | Skipped |

Downloads is deleted with `Remove-Item`, which does not send files to the Recycle Bin. Deletion is permanent.

## Usage

Run from an elevated prompt:

```powershell
.\clear_pre_v3.ps1
```

Via IT-Scripts (once pushed):

```powershell
iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Utils/CacheClean/clear_pre_v3.ps1")
```

Note: `#Requires -RunAsAdministrator` is only enforced when the script runs as a file. When run through `iex`, it is ignored, so launch the shell elevated first.

Logs are written to:

```
$env:TEMP\CacheCleanLogs\CacheClean_yyyyMMdd_HHmm.txt
```

## Adding to IT-Scripts Menu

Path assumes the script is placed in `Utils/CacheClean/`. Adjust to the actual location.

```powershell
"Utilities" = @(
    @{ Name = "Cache and Temp Cleanup"; Path = "Utils/CacheClean/clear_pre_v3.ps1"; Description = "Clear Temp, Prefetch, WU cache, Recycle Bin, Downloads" }
)
```

```powershell
git add -A
git commit -m "Update: clear_pre v1.3 - add Update Cache, Recycle Bin, Downloads"
git push
```

## Caveats

| Issue | Detail |
|-------|--------|
| Elevated as a different account | User Temp, Recycle Bin and Downloads resolve to the account running the elevated session. If you elevate with a separate admin account (common on client machines), those targets are the admin's, not the logged-on user's. The script prints `Running as:` and the Downloads path so this is visible before confirming. |
| OneDrive-backed Downloads | If Known Folder Move is enabled, deleting locally also deletes from OneDrive (items go to the OneDrive online recycle bin). Cloud-only placeholders report their full logical size, so the reclaimed figure may overstate actual disk space freed. |
| wuauserv trigger start | `wuauserv` is trigger-started. Inferred: if something requests an update scan between stop and delete, the service can restart and lock files; those files are skipped silently. Re-run if Update Cache is not fully cleared. |
| Log retention | The log folder sits in `$env:TEMP`. Clearing User Temp removes previous logs (the current transcript is locked and survives). Move `$LogDir` to `$env:ProgramData\CacheCleanLogs` if history is needed. |
| Prefetch | Clearing Prefetch causes slower first launches until Windows rebuilds the trace files. It does not generally improve performance. |

## Full Script

```powershell
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
```

## References

- Microsoft Learn - Reset Windows Update components (stop BITS/wuauserv, rename SoftwareDistribution): https://learn.microsoft.com/en-us/troubleshoot/windows-client/installing-updates-features-roles/additional-resources-for-windows-update
- Microsoft Learn - Clear-RecycleBin (Windows PowerShell 5.1): https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/clear-recyclebin?view=powershell-5.1
- Microsoft Learn - KNOWNFOLDERID (FOLDERID_Downloads GUID): https://learn.microsoft.com/en-us/windows/win32/shell/knownfolderid
- Microsoft Learn - Stop-Service: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/stop-service
- Microsoft Learn - ServiceController.WaitForStatus: https://learn.microsoft.com/en-us/dotnet/api/system.serviceprocess.servicecontroller.waitforstatus
- Microsoft Learn - Remove-Item (-LiteralPath, permanent deletion): https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/remove-item
- Microsoft Learn - Win32_LogicalDisk (DriveType values): https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-logicaldisk
- Microsoft Learn - about_Requires (RunAsAdministrator only applies to scripts): https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_requires
- Microsoft Learn - OneDrive Known Folder Move: https://learn.microsoft.com/en-us/sharepoint/redirect-known-folders
