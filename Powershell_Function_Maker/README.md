---
title: "PowerShell SSH Function Generator"
created: 2026-06-25T12:10:00
updated: 2026-06-25T12:10:00
---
# PowerShell SSH Function Generator

**Table of Contents**

1. [Overview](#overview)
2. [The Script](#the-script)
3. [How It Works](#how-it-works)
	1. [Profile Auto-Detection](#profile-auto-detection)
	2. [Managed Markers (Idempotency)](#managed-markers-idempotency)
	3. [The Log](#the-log)
4. [Usage](#usage)
	1. [Interactive (Prompted)](#interactive-prompted)
	2. [Non-Interactive (Parameters)](#non-interactive-parameters)
5. [Viewing the Log](#viewing-the-log)
6. [Updating or Removing a Function](#updating-or-removing-a-function)
7. [Notes and Limitations](#notes-and-limitations)
8. [References](#references)

A single script that creates reusable SSH connection functions, registers them in the active PowerShell profile, and records each one in a CSV log. Designed so the only required input is the function name; the SSH target and port are prompted (the port defaults to 22). Applies to Windows PowerShell 5.1 and PowerShell 7+.

## Overview

Manually editing `$PROFILE` for each new SSH host is repetitive and error-prone (duplicate functions, wrong profile file, forgotten reload). This script handles all of that:

| Capability | Behaviour |
|------------|-----------|
| Profile detection | Resolves `$PROFILE` for the running edition, creates the file and parent directory if missing |
| Input | Prompts for function name, target, port, and optional alias; or accepts them as parameters |
| Idempotency | Wraps each generated function in named markers; re-running with the same name updates in place rather than duplicating |
| Logging | Appends a row to a CSV log for every create or update |

## The Script

Save as `New-SshFunction.ps1`.

```powershell
<#
.SYNOPSIS
    Generate reusable SSH connection functions and register them in the PowerShell profile.

.DESCRIPTION
    Prompts for a function name and SSH connection details (or accepts them as
    parameters), auto-detects the active PowerShell profile, and appends a
    connection function wrapped in named markers so it can be safely updated or
    removed later. Each created or updated function is recorded in a CSV log.

.PARAMETER Name
    The function name to create (e.g. Connect-DebianVPS). Prompted if omitted.

.PARAMETER Target
    The SSH user@host string (e.g. debian@100.0.0.0). Prompted if omitted.

.PARAMETER Port
    The SSH port. Defaults to 22. Prompted if not supplied as a parameter.

.PARAMETER Alias
    Optional short alias for the function (e.g. vps). Prompted if not supplied.

.PARAMETER LogPath
    Path to the CSV log file. Defaults to $HOME\PowerShell-SSH-Functions.csv.

.EXAMPLE
    .\New-SshFunction.ps1
    Runs interactively, prompting for the function name and target.

.EXAMPLE
    .\New-SshFunction.ps1 -Name Connect-DebianVPS -Target debian@100.0.0.0 -Port 22023 -Alias vps
    Creates the function non-interactively.

.NOTES
    Author: Andrew Jones
    Version: 1.0
    Date: 2026-06-25
    Requires: OpenSSH client (ssh.exe) for the generated functions to run.
#>

[CmdletBinding()]
param (
    [string]$Name,
    [string]$Target,
    [int]$Port = 22,
    [string]$Alias,
    [string]$LogPath = (Join-Path $HOME 'PowerShell-SSH-Functions.csv')
)

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet('INFO','SUCCESS','WARNING','ERROR')]
        [string]$Level = 'INFO'
    )
    $colors = @{ INFO = 'Cyan'; SUCCESS = 'Green'; WARNING = 'Yellow'; ERROR = 'Red' }
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message" -ForegroundColor $colors[$Level]
}

function Test-FunctionName {
    param([string]$Value)
    # Letters, numbers, hyphen, underscore; must start with a letter.
    return $Value -match '^[A-Za-z][A-Za-z0-9_-]*$'
}

# ============================================================================
# MAIN
# ============================================================================

Write-Host "`n=== New SSH Function ===`n" -ForegroundColor Cyan

# --- Gather input ---
if (-not $Name) {
    $Name = Read-Host 'Function name (e.g. Connect-DebianVPS)'
}
if (-not (Test-FunctionName $Name)) {
    Write-Log "Invalid function name '$Name'. Use letters, numbers, hyphen or underscore; must start with a letter." 'ERROR'
    return
}

if (-not $Target) {
    $Target = Read-Host 'SSH target (user@host, e.g. debian@100.0.0.0)'
}
if ([string]::IsNullOrWhiteSpace($Target)) {
    Write-Log 'No target provided. Aborting.' 'ERROR'
    return
}

if (-not $PSBoundParameters.ContainsKey('Port')) {
    $portInput = Read-Host "SSH port (press Enter for $Port)"
    if (-not [string]::IsNullOrWhiteSpace($portInput)) {
        $parsed = 0
        if ([int]::TryParse($portInput, [ref]$parsed)) {
            $Port = $parsed
        } else {
            Write-Log "Invalid port '$portInput'. Aborting." 'ERROR'
            return
        }
    }
}

if (-not $PSBoundParameters.ContainsKey('Alias') -and -not $Alias) {
    $Alias = Read-Host 'Optional alias (press Enter to skip)'
}

# --- Resolve profile ---
$profilePath = $PROFILE
$profileDir  = Split-Path $profilePath -Parent

if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    Write-Log "Created profile directory: $profileDir" 'INFO'
}
if (-not (Test-Path $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
    Write-Log "Created profile: $profilePath" 'INFO'
}

# --- Build the managed block ---
$startMarker = "# region SSH-Function: $Name (auto-generated)"
$endMarker   = "# endregion SSH-Function: $Name"

$blockLines = New-Object System.Collections.Generic.List[string]
$blockLines.Add($startMarker)
$blockLines.Add("function $Name { ssh $Target -p $Port }")
if (-not [string]::IsNullOrWhiteSpace($Alias)) {
    $blockLines.Add("Set-Alias -Name $Alias -Value $Name")
}
$blockLines.Add($endMarker)

# --- Insert or replace within the profile (line-based, no regex pitfalls) ---
$existing = @(Get-Content -Path $profilePath -ErrorAction SilentlyContinue)

$startIdx = -1
$endIdx   = -1
for ($i = 0; $i -lt $existing.Count; $i++) {
    if ($existing[$i] -eq $startMarker) { $startIdx = $i }
    elseif ($existing[$i] -eq $endMarker -and $startIdx -ge 0) { $endIdx = $i; break }
}

if ($startIdx -ge 0 -and $endIdx -ge $startIdx) {
    $action = 'Updated'
    $before = if ($startIdx -gt 0) { $existing[0..($startIdx - 1)] } else { @() }
    $after  = if ($endIdx -lt ($existing.Count - 1)) { $existing[($endIdx + 1)..($existing.Count - 1)] } else { @() }
    $newContent = @($before) + $blockLines.ToArray() + @($after)
} else {
    $action = 'Created'
    $newContent = @($existing)
    if ($newContent.Count -gt 0 -and $newContent[-1] -ne '') { $newContent += '' }
    $newContent += $blockLines.ToArray()
}

Set-Content -Path $profilePath -Value $newContent -Encoding UTF8

# --- Log ---
$logEntry = [pscustomobject]@{
    Timestamp    = (Get-Date -Format 'o')
    FunctionName = $Name
    Target       = $Target
    Port         = $Port
    Alias        = if ($Alias) { $Alias } else { '' }
    Action       = $action
    Edition      = $PSVersionTable.PSEdition
    ProfilePath  = $profilePath
}
try {
    $logEntry | Export-Csv -Path $LogPath -NoTypeInformation -Append -ErrorAction Stop
} catch {
    Write-Log "Could not write to log '$LogPath': $($_.Exception.Message)" 'WARNING'
}

# --- Summary ---
Write-Log "$action function '$Name'  ->  ssh $Target -p $Port" 'SUCCESS'
if ($Alias) { Write-Log "Alias '$Alias' set for '$Name'." 'SUCCESS' }
Write-Log "Profile : $profilePath" 'INFO'
Write-Log "Log     : $LogPath" 'INFO'

Write-Host "`nReload your profile to use it now:" -ForegroundColor Yellow
Write-Host "    . `$PROFILE`n" -ForegroundColor Yellow
```

## How It Works

### Profile Auto-Detection

The script reads the automatic variable `$PROFILE`, which resolves to the current-user, current-host profile path for the running PowerShell edition. If the file or its parent directory does not exist, both are created. The resolved path is written to the log so it is always clear which profile a function landed in.

### Managed Markers (Idempotency)

Each generated function is wrapped in a pair of comment markers unique to the function name:

```powershell
# region SSH-Function: Connect-DebianVPS (auto-generated)
function Connect-DebianVPS { ssh debian@100.0.0.0 -p 22023 }
Set-Alias -Name vps -Value Connect-DebianVPS
# endregion SSH-Function: Connect-DebianVPS
```

On a re-run with the same `Name`, the script locates the existing marker block and replaces it in place rather than appending a duplicate. Running with a new `Name` appends a new block. This keeps the profile clean and makes the generated sections easy to identify by eye. The action taken (`Created` or `Updated`) is recorded in the log.

### The Log

Every run appends a row to the CSV at `$HOME\PowerShell-SSH-Functions.csv` (overridable with `-LogPath`):

| Column | Contents |
|--------|----------|
| Timestamp | ISO 8601 timestamp of the run |
| FunctionName | The function created or updated |
| Target | The `user@host` string |
| Port | The SSH port |
| Alias | The alias, if one was set |
| Action | `Created` or `Updated` |
| Edition | `Desktop` (5.1) or `Core` (7+) |
| ProfilePath | The profile file the function was written to |

CSV was chosen because it is machine-readable (`Import-Csv`) for later review or auditing. If you would rather log into your Obsidian vault, point `-LogPath` at a file inside it.

## Usage

### Interactive (Prompted)

Run with no arguments. You will be prompted for the function name, target, port (Enter for 22), and an optional alias:

```powershell
.\New-SshFunction.ps1
```

You can also run it straight from GitHub once it is in your IT-Scripts repo, consistent with the rest of your toolbox:

```powershell
iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Utils/SSH/New-SshFunction.ps1")
```

Note: the `iex (irm ...)` pattern runs the script in memory and does not pass parameters, so it always runs interactively. For non-interactive use, run the local `.ps1`.

### Non-Interactive (Parameters)

Supply everything up front, for example to recreate the Debian VPS function:

```powershell
.\New-SshFunction.ps1 -Name Connect-DebianVPS -Target debian@100.0.0.0 -Port 22023 -Alias vps
```

After either method, reload the profile to use the function immediately:

```powershell
. $PROFILE
```

## Viewing the Log

List everything the generator has created or updated:

```powershell
Import-Csv "$HOME\PowerShell-SSH-Functions.csv" | Format-Table -AutoSize
```

Show only the most recent entry per function:

```powershell
Import-Csv "$HOME\PowerShell-SSH-Functions.csv" |
    Sort-Object Timestamp -Descending |
    Group-Object FunctionName |
    ForEach-Object { $_.Group | Select-Object -First 1 }
```

## Updating or Removing a Function

Updating: re-run the script with the same `-Name` and new details. The marker block is replaced in place and the change is logged as `Updated`.

Removing: open the profile and delete the marker block for that function, then reload:

```powershell
notepad $PROFILE
# delete the "# region SSH-Function: <Name>" ... "# endregion SSH-Function: <Name>" block
. $PROFILE
```

The script does not currently remove functions automatically; deletion is manual by design to avoid accidentally stripping profile content. A `-Remove` switch could be added later if useful.

## Notes and Limitations

- Windows PowerShell 5.1 and PowerShell 7 use different `$PROFILE` files. A function created in one edition is not visible in the other. Run the script under each edition you use, or point one profile at the other. The `Edition` column in the log records which one was written.
- The generated functions depend on the OpenSSH client (`ssh.exe`). On Windows 10/11 and PowerShell 7 this is normally present; if not, install it with `Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0` (requires admin).
- If a name collides with an existing cmdlet, alias, or function, the profile function will normally shadow it in the session. Prefer the `Verb-Noun` convention (for example `Connect-DebianVPS`) to avoid surprises.
- `Set-Content -Encoding UTF8` writes a BOM under Windows PowerShell 5.1 and no BOM under PowerShell 7. Both load correctly as a profile.
- This pattern complements, rather than replaces, an `~/.ssh/config` file. For hosts shared across multiple shells and tools, an SSH config entry remains the more portable option; the generated function can simply wrap the config alias.

## References

- Microsoft Learn - about_Profiles: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles
- Microsoft Learn - about_Automatic_Variables ($PROFILE): https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_automatic_variables
- Microsoft Learn - about_Functions: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_functions
- Microsoft Learn - Export-Csv: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/export-csv
- Microsoft Learn - Import-Csv: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/import-csv
- Microsoft Learn - Read-Host: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/read-host
- Microsoft Learn - Set-Alias: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/set-alias
- Microsoft Learn - Get OpenSSH for Windows: https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse
