# PowerShell - Check and Clear Temp and Prefetch

Covers checking folder sizes and safely clearing `%TEMP%`, `C:\Windows\Temp`, and `C:\Windows\Prefetch` via PowerShell. The full script prompts before clearing each folder individually.

---

## Folder Reference

| Folder | Path | Contents |
|--------|------|----------|
| User Temp | `$env:TEMP` / `%TEMP%` | Per-user temporary files created by running apps |
| System Temp | `C:\Windows\Temp` | System-wide temporary files, requires elevation |
| Prefetch | `C:\Windows\Prefetch` | Boot and app launch prefetch cache (`.pf` files + `*.db`) |

---

## Check Folder Sizes (No Clear)

### Individual Folder Size

```powershell
# User Temp
(Get-ChildItem "$env:TEMP" -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB

# System Temp (run elevated)
(Get-ChildItem "C:\Windows\Temp" -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB

# Prefetch (run elevated)
(Get-ChildItem "C:\Windows\Prefetch" -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
```

### All Three at Once (Formatted Output)

```powershell
$folders = @{
    "User Temp"     = $env:TEMP
    "System Temp"   = "C:\Windows\Temp"
    "Prefetch"      = "C:\Windows\Prefetch"
}

foreach ($name in $folders.Keys) {
    $size = (Get-ChildItem $folders[$name] -Recurse -Force -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum).Sum / 1MB
    Write-Host "$name : $([math]::Round($size, 2)) MB"
}
```

---

## Full Script: Check, Prompt, and Clear

Reports sizes for all three folders, then prompts individually whether to clear each one. Summarises reclaimed space at the end.

```powershell
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
```

---

## Example Run

```
=== Temp and Prefetch Cleanup ===

Current folder sizes:

  User Temp         312.47 MB
  System Temp        54.10 MB
  Prefetch           18.33 MB
  TOTAL             384.90 MB

Select folders to clear:

  Clear User Temp (312.47 MB)? [Y/N]: Y
  User Temp cleared.

  Clear System Temp (54.10 MB)? [Y/N]: N
  System Temp skipped.

  Clear Prefetch (18.33 MB)? [Y/N]: Y
  Prefetch cleared.

Summary:
  User Temp           0.00 MB  (cleared)
  System Temp        54.10 MB  (skipped)
  Prefetch            0.00 MB  (cleared)

  Reclaimed: 330.80 MB
```

---

## Non-Interactive One-Liner (Force Clear All)

For use in automated contexts where prompts are not appropriate:

```powershell
@("$env:TEMP","C:\Windows\Temp","C:\Windows\Prefetch") | ForEach-Object { Remove-Item "$_\*" -Recurse -Force -ErrorAction SilentlyContinue }
```

---

## Behaviour Notes

| Item | Behaviour |
|------|-----------|
| Locked files | Skipped silently via `-ErrorAction SilentlyContinue`. Files in use by running processes cannot be deleted and will remain. |
| Prefetch rebuild | Windows rebuilds prefetch on next boot and application launch automatically. First launches after clearing may be marginally slower. |
| System Temp elevation | `C:\Windows\Temp` requires an elevated session. The `#Requires -RunAsAdministrator` directive will terminate the script if not elevated. |
| `%TEMP%` vs `%TMP%` | On most systems these resolve to the same path (`C:\Users\<user>\AppData\Local\Temp`). PowerShell uses `$env:TEMP`. |

---

## References

- `Remove-Item`: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/remove-item
- `Get-ChildItem`: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-childitem
- `Measure-Object`: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/measure-object
- `Read-Host`: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/read-host
- Windows Prefetch overview: https://learn.microsoft.com/en-us/windows/win32/fileio/file-caching
