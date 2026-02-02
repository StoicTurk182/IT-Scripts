# Universal Winget Package Generator

PowerShell script for exporting installed Winget packages to a portable, self-documenting JSON format with embedded restore commands.


> Utility 
*adding applications in bulk via BATCH*


```batch
@echo off
:: Batch script to install multiple applications silently
echo Starting installation of apps...

winget install --id Google.Chrome -e --silent --accept-source-agreements --accept-package-agreements
winget install --id VideoLAN.VLC -e --silent
winget install --id 7zip.7zip -e --silent
winget install --id Microsoft.VisualStudioCode -e --silent

echo ---------------------------------------
echo All installations are complete!
pause
```

## Overview

This script creates a complete snapshot of Winget-installed applications on a Windows system and packages them into a JSON file containing both the application list and the exact PowerShell commands needed to restore them on any other machine.

The generated JSON files are stored in a centralized location with standardized naming for easy identification and version control.

## Key Features

The script provides the following capabilities:

**Automated Export** - Queries Winget for all installed packages and exports them with version information to ensure accurate restoration.

**Smart Filtering** - Excludes Windows system components (Microsoft.Windows.*, Microsoft.BioEnrollment, Microsoft.Language.*) that should not be reinstalled to prevent system conflicts.

**Dual Restore Methods** - Embeds both local file execution and web-based IEX commands in the JSON output for flexibility in different deployment scenarios.

**Standardized Naming** - Uses hostname and date stamp in filenames (Winget_HOSTNAME_2026-01-25.json) for clear identification and tracking.

**Self-Documenting** - The JSON output contains metadata about the source system, generation timestamp, total package count, and usage instructions.

## File Structure

```
C:\WingetExports\
└── Winget_[Hostname]_[Date].json
```

The output directory is created automatically if it does not exist.

## Generated JSON Structure

```json
{
  "Hostname": "DESKTOP-ABC123",
  "TotalApps": 47,
  "GeneratedOn": "2026-01-25 14:30",
  "_OPTION_1_LOCAL": "If this file is on the machine, run this in PowerShell:",
  "Local_Command": "$j = Get-Content -Raw 'C:\\WingetExports\\Winget_DESKTOP-ABC123_2026-01-25.json' | ConvertFrom-Json; $j.Commands | % { Write-Host 'Installing: ' $_ -FG Cyan; Invoke-Expression $_ }",
  "_OPTION_2_WEB": "If you uploaded this file to the web (GitHub/Gist), run this:",
  "Web_IEX_Command": "$j = Invoke-RestMethod 'YOUR_RAW_JSON_URL_HERE'; $j.Commands | % { Invoke-Expression $_ }",
  "Commands": [
    "winget install --id Google.Chrome -e --silent --accept-package-agreements --accept-source-agreements --force",
    "winget install --id 7zip.7zip -e --silent --accept-package-agreements --accept-source-agreements --force"
  ]
}
```

## How It Works

### Step 1: Environment Setup

The script determines the hostname and current date to construct the output filename. The export folder is created if it does not already exist.

```powershell
$Hostname = $env:COMPUTERNAME
$Date = Get-Date -Format "yyyy-MM-dd"
$ExportFolder = "C:\WingetExports"
$FileName = "Winget_$( $Hostname )_$( $Date ).json"
```

### Step 2: Winget Source Update

The Winget package manager sources are updated to ensure the export contains the most current package information. This step runs non-interactively to support automation scenarios.

```powershell
winget source update --disable-interactivity
```

Reference: Microsoft Winget documentation on source management at https://learn.microsoft.com/en-us/windows/package-manager/winget/source

### Step 3: Package Export

The script uses Winget's native export functionality to create a temporary JSON file containing all installed packages with version information. The temporary file approach prevents partial writes to the final output location.

```powershell
winget export -o $TempExportPath --include-versions --accept-source-agreements
```

Reference: Microsoft Winget export command documentation at https://learn.microsoft.com/en-us/windows/package-manager/winget/export

### Step 4: Package Filtering

The exported JSON is parsed and system packages are filtered out based on package identifier patterns. This filtering prevents attempting to reinstall Windows system components that are managed by Windows Update.

Filtered package patterns:

| Pattern | Reason for Exclusion |
|---------|---------------------|
| Microsoft.Windows.* | Core Windows components managed by Windows Update |
| Microsoft.BioEnrollment | Windows Hello biometric enrollment service |
| Microsoft.Language.* | Windows language packs managed by system settings |

### Step 5: Command Generation

For each remaining package, a silent install command is generated with the following flags:

| Flag | Purpose |
|------|---------|
| --id | Specifies exact package identifier to prevent ambiguity |
| -e | Exact match only (prevents partial ID matches) |
| --silent | Suppresses interactive prompts during installation |
| --accept-package-agreements | Auto-accepts package license agreements |
| --accept-source-agreements | Auto-accepts source repository agreements |
| --force | Forces reinstallation even if package exists |

Reference: Microsoft Winget install command documentation at https://learn.microsoft.com/en-us/windows/package-manager/winget/install

### Step 6: JSON Construction

The script builds an ordered hashtable containing metadata and the command list. The ordered hashtable ensures consistent property ordering in the JSON output for readability.

Two restore commands are included:

**Local Restore** - Reads the JSON file from disk and executes each install command sequentially. This method is suitable when the JSON file is available on the target system or accessible via network share.

**Web Restore** - Fetches the JSON file via HTTP/HTTPS using Invoke-RestMethod and executes the commands. This method requires the JSON file to be hosted on a web server, GitHub repository, or Gist. The placeholder URL must be replaced with the actual raw JSON URL.

### Step 7: File Output

The hashtable is converted to JSON format with depth 5 (sufficient for the command array structure) and written to the final output path with UTF-8 encoding.

## Usage

### Running the Script

Execute the script in PowerShell with appropriate permissions:

```powershell
.\Winget_Package_Generator.ps1
```

No parameters are required. The script runs fully automated.

### Expected Output

```
--- Generating Universal Winget Package ---
Updating Winget sources...
Exporting installed apps...

SUCCESS! Universal JSON saved.
Location: C:\WingetExports\Winget_DESKTOP-ABC123_2026-01-25.json
```

The final line displays a clickable file path in Windows Terminal and PowerShell 7.

### Restoring Packages - Option 1: Local File

If the JSON file is present on the target machine or accessible via network path, use the Local_Command from the JSON file:

```powershell
$j = Get-Content -Raw 'C:\WingetExports\Winget_DESKTOP-ABC123_2026-01-25.json' | ConvertFrom-Json
$j.Commands | % { Write-Host 'Installing: ' $_ -FG Cyan; Invoke-Expression $_ }
```

This method reads the JSON from disk, extracts the Commands array, and executes each command while displaying installation progress in cyan text.

### Restoring Packages - Option 2: Web IEX

For remote deployment scenarios, upload the JSON file to a web location and modify the Web_IEX_Command with the actual URL:

Example using GitHub raw content:

```powershell
$j = Invoke-RestMethod 'https://raw.githubusercontent.com/username/repo/main/Winget_DESKTOP-ABC123_2026-01-25.json'
$j.Commands | % { Invoke-Expression $_ }
```

Example using GitHub Gist:

```powershell
$j = Invoke-RestMethod 'https://gist.githubusercontent.com/username/gist-id/raw/file.json'
$j.Commands | % { Invoke-Expression $_ }
```

The Invoke-RestMethod cmdlet fetches the JSON content directly from the web without writing to disk, making this method suitable for provisioning scripts or deployment automation.

Reference: Invoke-RestMethod documentation at https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-restmethod

## Use Cases

### System Migration

When migrating to a new Windows installation, run the generator on the source system, transfer the JSON file to the new system (via USB, network share, or cloud storage), and execute the Local_Command to restore all applications.

### Standardized Deployment

For deploying a consistent application set across multiple machines, generate the JSON once from a reference system and use the Web_IEX method during provisioning. Host the JSON on an internal web server or GitHub repository for centralized management.

### Backup and Recovery

Schedule the script to run weekly via Task Scheduler to maintain current application snapshots. Store the JSON files in a versioned location (Git repository, OneDrive, etc.) for point-in-time recovery capability.

### Documentation

The JSON files serve as documentation of installed software on each system. The hostname and date in the filename make it easy to track what was installed on which machine at what time.

## Customization

### Changing Output Location

Modify the `$ExportFolder` variable at the top of the script:

```powershell
$ExportFolder = "D:\Backups\Winget"
```

### Adjusting Filename Format

Modify the `$FileName` construction:

```powershell
# Include username
$FileName = "Winget_$($env:USERNAME)_$($Hostname)_$($Date).json"

# ISO 8601 timestamp
$Date = Get-Date -Format "yyyy-MM-ddTHH-mm-ss"
$FileName = "Winget_$($Hostname)_$($Date).json"
```

### Adding Additional Filters

Expand the filtering logic to exclude additional package patterns:

```powershell
if ($ID -notmatch "Microsoft.Windows.|Microsoft.BioEnrollment|Microsoft.Language|Adobe.Acrobat") {
    $CommandList += "winget install --id $ID -e --silent --accept-package-agreements --accept-source-agreements --force"
}
```

### Removing Version Locking

To allow Winget to install the latest version rather than the exported version, remove `--include-versions` from the export command:

```powershell
winget export -o $TempExportPath --accept-source-agreements
```

This causes Winget to install the current latest version of each package rather than the specific version that was installed on the source system.

## Error Handling

### Export Failed

If the script reports "Export failed. Winget could not write the temporary file", the most likely causes are:

**Winget Not Installed** - The winget command is not available. Install the App Installer package from the Microsoft Store or download the latest release from the winget-cli GitHub repository at https://github.com/microsoft/winget-cli/releases

**Insufficient Permissions** - The temporary file path is not writable. The script uses `[System.IO.Path]::GetTempFileName()` which writes to the user's temp directory. Verify write permissions to `%TEMP%`.

**Corrupted Winget Database** - The Winget package database may be corrupted. Reset Winget by running `winget source reset --force`.

Reference: Winget troubleshooting documentation at https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting

### Source Update Timeout

If `winget source update` hangs or times out, this typically indicates network connectivity issues to the package repositories (primarily the Microsoft Store and winget-pkgs repository on GitHub).

Check network connectivity to:

```
https://cdn.winget.microsoft.com
https://storeedgefd.dsx.mp.microsoft.com
https://github.com/microsoft/winget-pkgs
```

As a workaround, remove the source update step if working in offline or restricted network environments, though this may result in outdated package information.

### JSON Conversion Errors

If ConvertFrom-Json fails when restoring packages, the JSON file may be truncated or corrupted. Re-run the generator script or verify the file was completely downloaded if using the Web_IEX method.

Validate JSON structure manually:

```powershell
Get-Content 'C:\WingetExports\Winget_HOSTNAME_DATE.json' -Raw | ConvertFrom-Json
```

If this command completes without error, the JSON structure is valid.

### Package Installation Failures

Individual package installations may fail during restore for several reasons:

**Package No Longer Available** - The package has been removed from the repository or the package ID has changed. Check the winget-pkgs repository for the current package status.

**Architecture Mismatch** - The package was exported from a different CPU architecture (x64 vs ARM64). Winget should handle this automatically but may fail for architecture-specific packages.

**Dependency Failures** - The package has dependencies that are not available or fail to install. Review the Winget output for dependency error messages.

**Network Issues** - Download failures due to network connectivity. The --force flag should retry, but persistent network issues require manual resolution.

To identify which package failed, review the console output during restore. The cyan "Installing:" message indicates which package is currently being processed.

## Requirements

| Component | Minimum Version | Notes |
|-----------|----------------|-------|
| Windows | 10 (1809+) or 11 | Winget requires Windows 10 build 17763 or later |
| PowerShell | 5.1 or 7.x | Script uses standard cmdlets compatible with both versions |
| Winget | 1.0.0+ | Included with App Installer; verify with `winget --version` |
| Permissions | User | No administrative rights required for export; restore may require admin for system-level packages |

Reference: Winget system requirements at https://learn.microsoft.com/en-us/windows/package-manager/winget/#prerequisites

## Security Considerations

### Invoke-Expression Usage

The restore commands use `Invoke-Expression` to execute the generated install commands. This cmdlet executes arbitrary code and should only be used with trusted JSON files. Always verify the source of JSON files before executing restore commands.

In enterprise environments, consider reviewing the Commands array contents before execution:

```powershell
$j = Get-Content -Raw 'C:\WingetExports\Winget_HOSTNAME_DATE.json' | ConvertFrom-Json
$j.Commands | Out-Host
Read-Host "Press Enter to continue or Ctrl+C to cancel"
$j.Commands | % { Invoke-Expression $_ }
```

Reference: PowerShell security best practices at https://learn.microsoft.com/en-us/powershell/scripting/learn/security-features

### Web-Hosted JSON Files

When using the Web_IEX method, ensure the hosting location is secure:

**HTTPS Only** - Always use HTTPS URLs to prevent man-in-the-middle tampering.

**Access Controls** - For private deployments, implement authentication or use private repository features.

**Immutable URLs** - Use specific commit hashes or tagged releases in GitHub URLs to prevent unexpected changes to the JSON content.

GitHub raw content URL format:

```
https://raw.githubusercontent.com/{owner}/{repo}/{commit-hash-or-tag}/{path}
```

### Package Source Trust

Winget packages come from configured sources. The default Microsoft source (msstore) is generally trustworthy, but custom sources should be evaluated before use. Review configured sources with:

```powershell
winget source list
```

Reference: Winget source configuration at https://learn.microsoft.com/en-us/windows/package-manager/winget/source

## Integration with Task Scheduler

To automate weekly exports, create a scheduled task:

```powershell
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"C:\Scripts\Winget_Package_Generator.ps1`""

$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2am

$Principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType S4U

Register-ScheduledTask -TaskName "Winget Export" -Action $Action -Trigger $Trigger -Principal $Principal -Description "Weekly Winget package export"
```

This creates a task that runs every Sunday at 2:00 AM under the current user context. The `-LogonType S4U` allows the task to run whether the user is logged in or not without storing credentials.

Reference: Scheduled tasks documentation at https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/

## Version Control Integration

For tracking application changes over time, commit the JSON files to a Git repository:

```powershell
cd C:\WingetExports
git init
git add *.json
git commit -m "Winget export $(Get-Date -Format 'yyyy-MM-dd')"
```

To compare package lists between dates:

```powershell
git diff HEAD~1 HEAD -- Winget_HOSTNAME_*.json
```

This shows additions and removals in the Commands array, making it easy to identify which applications were added or removed since the last export.

## Troubleshooting

### Multiple Exports Per Day

The filename includes only the date, not the time. Running the script multiple times in one day will overwrite the previous export. To preserve multiple exports per day, modify the filename to include time:

```powershell
$Date = Get-Date -Format "yyyy-MM-dd_HH-mm"
$FileName = "Winget_$( $Hostname )_$( $Date ).json"
```

### Large Package Lists

For systems with hundreds of packages, the restore process may take considerable time. To monitor progress, the embedded commands include a cyan progress message for each package. Restore operations can be safely interrupted with Ctrl+C and resumed by re-running the command; already-installed packages will be quickly skipped due to the --force flag.

### Package ID Changes

Some packages may change IDs between Winget versions or when publishers modify their package metadata. If a restore fails due to an unknown package ID, search for the current ID:

```powershell
winget search "package name"
```

Update the Commands array in the JSON file with the correct ID and re-run the restore.

## References

- Winget Documentation: https://learn.microsoft.com/en-us/windows/package-manager/winget/
- Winget CLI Repository: https://github.com/microsoft/winget-cli
- Winget Package Repository: https://github.com/microsoft/winget-pkgs
- PowerShell JSON Cmdlets: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertto-json
- Invoke-RestMethod: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-restmethod
- Invoke-Expression: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-expression