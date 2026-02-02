# Drive Mapping Toolkit

PowerShell scripts for auditing drive letter availability and automatically mapping network shares with custom labels.

## Overview

This toolkit contains two scripts that work together to manage network drive mappings on Windows workstations. `Drive_Discovery.ps1` audits what drive letters are available and what shares exist on a remote server. `Drive_Map.ps1` then maps those shares to available letters with custom labels, handling conflicts and server availability automatically.

## Scripts

| Script | Purpose | Admin Required |
|--------|---------|----------------|
| Drive_Discovery.ps1 | Audit drive letters and list remote shares | No (SMB read perms on target) |
| Drive_Map.ps1 | Map network shares to available letters with labels | No (SMB access to shares) |

## Drive_Discovery.ps1

Performs a two-part audit: scans all drive letters (Z down to D) for availability, then queries a remote server for non-hidden SMB shares.

### Configuration

Edit these variables at the top of the script:

```powershell
$Server = "ORIONVI"
$Exclusions = @('C', 'Y', 'Z')
```

| Variable | Purpose | Default |
|----------|---------|---------|
| `$Server` | Hostname of the file server to audit shares on | `ORIONVI` |
| `$Exclusions` | Drive letters to mark as reserved (skipped during mapping) | `C`, `Y`, `Z` |

### How It Works

The script runs four stages:

**Stage 1 - Physical/Local Drives:** Queries `System.IO.DriveInfo` to get all letters currently assigned to physical disks, USB drives, and optical media.

**Stage 2 - Network Drives:** Queries `Win32_NetworkConnection` via CIM to identify letters already mapped to network paths. Handles null results gracefully if no network drives exist.

**Stage 3 - Letter Scan:** Iterates from Z to D (ASCII 90 to 68) and colour-codes each letter:

| Colour | Status | Meaning |
|--------|--------|---------|
| Green | `[FREE]` | Available for mapping |
| Red | `[USED/OCCUPIED]` | In use by a local or network drive |
| Yellow | `[RESERVED/SKIPPED]` | Listed in `$Exclusions` array |

**Stage 4 - Remote Share Audit:** Pings the target server, then uses `Get-SmbShare` via a CIM session to list all non-hidden shares (filters out administrative shares ending with `$`). Outputs share name, full UNC path, and description.

### Example Output

```
--- DEEP SCAN DRIVE AUDIT ---
Letter Z: [RESERVED/SKIPPED]
Letter Y: [RESERVED/SKIPPED]
Letter X: [FREE]
Letter W: [FREE]
...
Letter D: [USED/OCCUPIED]

--- REMOTE SHARE AUDIT (ORIONVI) ---
Connecting to ORIONVI...

Share Name   Network Path      Description
----------   ------------      -----------
a            \\ORIONVI\a       Server Tools
o            \\ORIONVI\o       VM Lab
s            \\ORIONVI\s       Backup Local
```

### Requirements

- PowerShell 5.1+
- `SmbShare` module (included in Windows 8.1/Server 2012 R2 and later)
- Network connectivity to the target server
- Read permissions on target server shares

## Drive_Map.ps1

Automatically maps defined network shares to the next available drive letters and applies custom labels visible in File Explorer.

### Configuration

Edit these variables at the top of the script:

```powershell
$Server = "Orion-i"
$Timeout = 30

$DriveMap = @{
    "\\Orion-i\a" = "Server_Tools"
    "\\Orion-i\o" = "VM_Lab"
    "\\Orion-i\s" = "Backup_Local"
}
```

| Variable | Purpose | Default |
|----------|---------|---------|
| `$Server` | Hostname to check connectivity against before mapping | `Orion-i` |
| `$Timeout` | Seconds to wait for server response before aborting | `30` |
| `$DriveMap` | Hashtable of UNC paths (keys) and display labels (values) | Three shares defined |

### How It Works

**Stage 1 - Pre-Check:** Uses a `Stopwatch` timer loop to ping the server every 2 seconds. If the server does not respond within the timeout period, the script exits with an error to prevent ghost drives (mapped letters pointing to unreachable paths).

**Stage 2 - Available Letter Calculation:** Gets all letters currently used by `FileSystem` PSDrives, then generates a list from Z down to D excluding used letters, `Y`, and `C`. This produces a pool of available letters in descending order.

**Stage 3 - Mapping Loop:** For each entry in `$DriveMap`:

1. Checks if the UNC path is already mapped to an existing drive via `Get-PSDrive` DisplayRoot comparison
2. If already mapped, skips the `New-PSDrive` call and refreshes the label only
3. If not mapped, creates a new persistent global PSDrive mapping using `New-PSDrive`
4. Applies the custom label using the `Shell.Application` COM object, which sets the display name visible in File Explorer

**Stage 4 - Label Application:** The `Shell.Application` COM object's `NameSpace().Self.Name` property sets the drive label that appears in File Explorer. This is the same mechanism Windows uses when you manually rename a drive.

### Drive Letter Assignment

Letters are assigned from the first available in descending order (Z toward D). The script excludes:

- Any letter already in use by a local or mapped drive
- `Y` and `C` (hardcoded exclusions)

If you need to exclude additional letters, modify the `Where-Object` filter on line 27:

```powershell
$AvailableLetters = 90..68 | ForEach-Object { [char]$_ } | Where-Object { 
    $UsedLetters -notcontains $_ -and $_ -ne 'Y' -and $_ -ne 'C' -and $_ -ne 'D'
}
```

### Persistence

The `-Persist` parameter on `New-PSDrive` creates a mapping that survives the current PowerShell session. However, these mappings are per-user and may not survive a reboot depending on Windows credential caching. For logon persistence, deploy via:

- Group Policy Preferences (drive maps)
- Logon script via GPO
- Scheduled task triggered at logon
- Intune PowerShell script assignment

### Example Output

```
Waiting for Orion-i to respond...
Success: [X:] -> Server_Tools
Success: [W:] -> VM_Lab
Success: [V:] -> Backup_Local
```

### Requirements

- PowerShell 5.1+
- Network connectivity to the file server
- SMB read/write permissions on target shares
- No elevation required (maps to current user context)

## Customisation Guide

### Adding a New Share

Add an entry to the `$DriveMap` hashtable in `Drive_Map.ps1`:

```powershell
$DriveMap = @{
    "\\Orion-i\a" = "Server_Tools"
    "\\Orion-i\o" = "VM_Lab"
    "\\Orion-i\s" = "Backup_Local"
    "\\Orion-i\projects" = "Active_Projects"
}
```

Add the share name to `$Exclusions` in `Drive_Discovery.ps1` if you want it marked as reserved during audits.

### Changing the Target Server

Update `$Server` in both scripts. In `Drive_Map.ps1`, also update the UNC paths in `$DriveMap` to match the new server hostname:

```powershell
$Server = "NEWSERVER"

$DriveMap = @{
    "\\NEWSERVER\share1" = "Label_One"
    "\\NEWSERVER\share2" = "Label_Two"
}
```

### Reserving Additional Letters

In `Drive_Discovery.ps1`, add letters to the exclusions array:

```powershell
$Exclusions = @('C', 'D', 'Y', 'Z')
```

In `Drive_Map.ps1`, add conditions to the `Where-Object` filter:

```powershell
Where-Object { 
    $UsedLetters -notcontains $_ -and $_ -ne 'Y' -and $_ -ne 'C' -and $_ -ne 'D'
}
```

## Troubleshooting

### "Server not found. Aborting mapping to prevent ghost drives."

The target server did not respond to ICMP ping within the timeout window. Check:

- Server hostname resolves via DNS (`Resolve-DnsName $Server`)
- Server is online and ICMP is not blocked by firewall
- Increase `$Timeout` if the server is slow to respond after boot

### "Could not list shares. Check permissions on $Server."

`Get-SmbShare` via CIM session failed. This typically means:

- WinRM/CIM is not enabled on the target (run `Enable-PSRemoting` on the server)
- Firewall is blocking WMI/CIM traffic (TCP 5985/5986)
- The current user lacks permissions to enumerate shares

### "Could not set label for X:"

The `Shell.Application` COM object failed to set the drive name. This can occur if:

- The drive letter was not successfully mapped in the previous step
- Explorer shell is not fully loaded (common in early logon script execution)
- Another process has a lock on the drive namespace

### Drives Disappear After Reboot

`-Persist` creates the mapping in the current session and writes it to the user's profile, but credential caching may expire. For reliable persistence, deploy the script as a logon script via Group Policy or Intune.

## References

- System.IO.DriveInfo: https://learn.microsoft.com/en-us/dotnet/api/system.io.driveinfo
- Win32_NetworkConnection: https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-networkconnection
- Get-SmbShare: https://learn.microsoft.com/en-us/powershell/module/smbshare/get-smbshare
- New-PSDrive: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/new-psdrive
- Get-PSDrive: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-psdrive
- Test-Connection: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/test-connection
- Shell.Application COM Object: https://learn.microsoft.com/en-us/windows/win32/shell/shell
- Get-CimInstance: https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/get-ciminstance
- GPO Drive Maps: https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/dn581922(v=ws.11)
