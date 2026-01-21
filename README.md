# IT-Scripts Toolbox

Centralized PowerShell scripts for IT administration with on-the-fly execution from GitHub.

Repository: https://github.com/StoicTurk182/IT-Scripts

## Quick Start

```powershell
iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Menu.ps1")
```

If TLS errors occur (older systems):

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Menu.ps1")
```

## Repository Structure

```
IT-Scripts/
├── Menu.ps1
├── README.md
├── ActiveDirectory/
│   ├── migrate_groups/
│   │   ├── migrate_user_group_memberships_interactive.ps1
│   │   └── migrate_user_group_memberships_param.ps1
│   └── Rename-UPN/
│       └── UPN_NameChange.ps1
├── Setup/
│   └── HWH/
│       └── hwh.ps1
└── Utils/
    └── BACKUPS/
        └── Create_Folders_v2.ps1
```

## How It Works

| Cmdlet | Alias | Function |
|--------|-------|----------|
| Invoke-RestMethod | irm | Downloads raw script content from URL |
| Invoke-Expression | iex | Executes the downloaded content in memory |

Scripts are fetched from GitHub and executed in memory without writing to disk. This bypasses file-based execution policy and ensures the latest version is always used.

Raw GitHub URL format:
```
https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{path}
```

## Initial Repository Setup

This section documents how the repository was created for reference.

### Step 1: Create Folder Structure

```powershell
cd "C:\Users\Administrator\Andrew J IT Labs"
mkdir IT-Scripts
cd IT-Scripts
mkdir ActiveDirectory, Setup, Utils
```

### Step 2: Initialize Git

```powershell
git init
git branch -m main
```

### Step 3: Copy Existing Scripts

Copy scripts from source locations into the repository structure:

```powershell
Copy-Item "C:\Users\Administrator\OneDrive\Obsidian\Informal Notes\TERMINAL\POWERSHELL\Scripts\copy-ad-groups\*" -Destination "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts\ActiveDirectory\" -Recurse

Copy-Item "C:\Users\Administrator\OneDrive\Obsidian\Informal Notes\TERMINAL\POWERSHELL\Scripts\UPN_Name_Changer\*" -Destination "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts\ActiveDirectory\" -Recurse

Copy-Item "C:\Users\Administrator\OneDrive\Obsidian\Informal Notes\TERMINAL\POWERSHELL\Scripts\Create_Backup_folder_struct\*" -Destination "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts\Setup\" -Recurse

Copy-Item "C:\Users\Administrator\OneDrive\Obsidian\Informal Notes\TERMINAL\POWERSHELL\Scripts\HWH\*" -Destination "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts\Setup\" -Recurse
```

### Step 4: Verify Structure

```powershell
Get-ChildItem "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts" -Recurse | Select-Object FullName
```

### Step 5: Create GitHub Repository

1. Go to https://github.com/new
2. Create repository named `IT-Scripts`
3. Do not initialize with README (files already exist locally)

### Step 6: Connect and Push

```powershell
git remote add origin git@github.com:StoicTurk182/IT-Scripts.git
git add -A
git commit -m "Initial commit: IT-Scripts Toolbox with Menu launcher"
git push -u origin main
```

## File Handling

### Copying Scripts into Repository

Copy individual files:

```powershell
Copy-Item "C:\Source\Script.ps1" -Destination "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts\Utils\"
```

Copy folder contents recursively:

```powershell
Copy-Item "C:\Source\ScriptFolder\*" -Destination "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts\Utils\ScriptFolder\" -Recurse
```

Copy and overwrite existing files:

```powershell
Copy-Item "C:\Source\Script.ps1" -Destination "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts\Utils\" -Force
```

### Moving Scripts

Move instead of copy:

```powershell
Move-Item "C:\Source\Script.ps1" -Destination "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts\Utils\"
```

### Renaming Folders

Avoid spaces in folder names (causes URL issues):

```powershell
Rename-Item "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts\ActiveDirectory\Rename UPN" "Rename-UPN"
```

### Listing Repository Contents

```powershell
Get-ChildItem "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts" -Recurse | Select-Object FullName
```

### Removing Files

Remove a file:

```powershell
Remove-Item "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts\Utils\OldScript.ps1"
```

Remove a folder and contents:

```powershell
Remove-Item "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts\Utils\OldFolder" -Recurse
```

## Adding New Scripts - Detailed Guide

This section provides a complete walkthrough for adding new scripts to the toolbox.

### Understanding the Process

Adding a script involves three parts:

1. **The script file** - The actual .ps1 file containing your code
2. **The folder location** - Where the script lives in the repository
3. **The menu entry** - The entry in Menu.ps1 that makes the script appear in the launcher

All three must be correct for the script to work from the menu.

### Step 1: Decide on Location

Choose which category the script belongs to:

| Category | Folder | Use For | Examples |
|----------|--------|---------|----------|
| Active Directory | `ActiveDirectory/` | User, group, OU, GPO management | Copy groups, rename users, disable accounts |
| Device Setup | `Setup/` | Provisioning, imaging, enrollment | Autopilot hash, domain join, driver install |
| Utilities | `Utils/` | General tools, maintenance, backups | Backup folders, network tests, cleanup scripts |

If your script doesn't fit existing categories, you can create a new one (covered later).

### Step 2: Create Subfolder (Recommended)

Grouping related scripts in subfolders keeps things organised. Each script or script set should have its own subfolder.

Navigate to the repository:

```powershell
cd "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts"
```

Create a subfolder for your script:

```powershell
mkdir "Utils\NetworkTools"
```

This creates: `IT-Scripts/Utils/NetworkTools/`

Folder naming rules:
- No spaces (use hyphens: `Network-Tools` not `Network Tools`)
- Keep it short but descriptive
- Use PascalCase or hyphens

### Step 3: Create or Copy the Script File

**Option A: Create new script in VS Code**

```powershell
code "Utils\NetworkTools\Test-Connectivity.ps1"
```

This opens VS Code with a new file. Paste your script content.

**Option B: Copy existing script**

From another location:

```powershell
Copy-Item "C:\Scripts\Test-Connectivity.ps1" -Destination "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts\Utils\NetworkTools\"
```

From another folder in the repo:

```powershell
Copy-Item ".\Setup\HWH\hwh.ps1" -Destination ".\Utils\NetworkTools\Test-Connectivity.ps1"
```

**Option C: Copy entire folder of related scripts**

```powershell
Copy-Item "C:\Scripts\NetworkTools\*" -Destination "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts\Utils\NetworkTools\" -Recurse
```

### Step 4: Script Template

Your script should follow this template for consistency:

```powershell
<#
.SYNOPSIS
    One line description of what the script does

.DESCRIPTION
    Detailed description of the script's functionality.
    Can be multiple lines explaining what it does and how.

.PARAMETER ParameterName
    Description of each parameter the script accepts

.EXAMPLE
    .\Test-Connectivity.ps1
    Runs the script with default settings

.EXAMPLE
    .\Test-Connectivity.ps1 -Target "192.168.1.1"
    Runs the script targeting a specific IP

.NOTES
    Author: Andrew Jones
    Version: 1.0
    Date: 2026-01-18
    Requires: List any required modules or admin rights
#>

#Requires -Version 5.1
#Requires -Modules ActiveDirectory  # Remove if not needed

[CmdletBinding()]
param (
    [Parameter()]
    [string]$Target = "8.8.8.8"
)

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
    $colors = @{
        "INFO" = "Cyan"
        "SUCCESS" = "Green"
        "WARNING" = "Yellow"
        "ERROR" = "Red"
    }
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message" -ForegroundColor $colors[$Level]
}

# ============================================================================
# MAIN
# ============================================================================

Write-Host "`n=== Script Title ===`n" -ForegroundColor Cyan

# Your script logic here

Write-Host "`nScript completed.`n" -ForegroundColor Green
```

### Step 5: Update Menu.ps1

This is the critical step that makes your script appear in the menu.

Open Menu.ps1:

```powershell
code "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts\Menu.ps1"
```

Find the `$Script:MenuStructure` section near the top of the file. It looks like this:

```powershell
$Script:MenuStructure = [ordered]@{
    "Active Directory" = @(
        @{ Name = "Copy User Groups (Interactive)"; Path = "ActiveDirectory/migrate_groups/migrate_user_group_memberships_interactive.ps1"; Description = "Copy group memberships interactively" }
        @{ Name = "Copy User Groups (Parameters)"; Path = "ActiveDirectory/migrate_groups/migrate_user_group_memberships_param.ps1"; Description = "Copy group memberships with parameters" }
        @{ Name = "UPN Name Change"; Path = "ActiveDirectory/Rename-UPN/UPN_NameChange.ps1"; Description = "Change user UPN and display name" }
    )
    "Device Setup" = @(
        @{ Name = "Get Hardware Hash"; Path = "Setup/HWH/hwh.ps1"; Description = "Collect Autopilot hardware hash" }
    )
    "Utilities" = @(
        @{ Name = "Create Backup Folders"; Path = "Utils/BACKUPS/Create_Folders_v2.ps1"; Description = "Create backup folder structure for migrations" }
    )
}
```

Add your new script entry to the appropriate category array. Each entry has three properties:

| Property | Purpose | Example |
|----------|---------|---------|
| Name | Display name shown in menu | `"Test Network Connectivity"` |
| Path | Relative path to script file | `"Utils/NetworkTools/Test-Connectivity.ps1"` |
| Description | Short description shown below name | `"Test connectivity to common endpoints"` |

**Adding to existing category:**

Find the category (e.g., "Utilities") and add a new line before the closing parenthesis:

```powershell
"Utilities" = @(
    @{ Name = "Create Backup Folders"; Path = "Utils/BACKUPS/Create_Folders_v2.ps1"; Description = "Create backup folder structure for migrations" }
    @{ Name = "Test Connectivity"; Path = "Utils/NetworkTools/Test-Connectivity.ps1"; Description = "Test network connectivity to common endpoints" }
)
```

**Important syntax rules:**

- Each entry is wrapped in `@{ }` 
- Properties are separated by semicolons `;`
- Path uses forward slashes `/` not backslashes
- Path is case-sensitive (must match actual filename exactly)
- No leading slash in path
- Multiple entries in a category are separated by line breaks (no commas needed inside the `@()` array)

**Common mistakes:**

```powershell
# WRONG - backslashes
Path = "Utils\NetworkTools\Test-Connectivity.ps1"

# WRONG - leading slash
Path = "/Utils/NetworkTools/Test-Connectivity.ps1"

# WRONG - case mismatch (if file is Test-Connectivity.ps1)
Path = "Utils/NetworkTools/test-connectivity.ps1"

# CORRECT
Path = "Utils/NetworkTools/Test-Connectivity.ps1"
```

Save the file.

### Step 6: Verify the Path

Double-check your path is correct by testing the raw URL in a browser:

```
https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Utils/NetworkTools/Test-Connectivity.ps1
```

This won't work until you push, but you can verify the local path:

```powershell
Test-Path "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts\Utils\NetworkTools\Test-Connectivity.ps1"
```

Should return `True`.

### Step 7: Test Locally

Before pushing, test the menu runs without errors:

```powershell
& "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts\Menu.ps1"
```

Navigate to your category and verify your script appears. You can select it to test - it will fail to fetch from GitHub (not pushed yet) but confirms the menu entry is correct.

### Step 8: Stage and Review Changes

Check what files have changed:

```powershell
cd "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts"
git status
```

You should see:
- Your new script file(s)
- Modified: Menu.ps1

Review the changes if needed:

```powershell
git diff Menu.ps1
```

### Step 9: Commit Changes

Stage all changes:

```powershell
git add -A
```

Commit with a descriptive message:

```powershell
git commit -m "Add: Test-Connectivity script to Utilities"
```

Good commit message formats:
- `Add: Script-Name to Category` - for new scripts
- `Update: Script-Name - description of change` - for modifications  
- `Fix: Script-Name - what was fixed` - for bug fixes
- `Remove: Script-Name` - for deletions

### Step 10: Push to GitHub

```powershell
git push
```

### Step 11: Test from GitHub

Wait a few seconds for GitHub to process, then test:

```powershell
iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Menu.ps1")
```

Navigate to your category and run the script. It should now fetch from GitHub and execute.

### Complete Example: Adding a New Script

Here's the full process for adding a "Get-DiskSpace.ps1" script:

```powershell
# Navigate to repo
cd "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts"

# Pull latest changes first
git pull

# Create subfolder
mkdir "Utils\DiskTools"

# Create the script
code "Utils\DiskTools\Get-DiskSpace.ps1"
```

Paste script content, save file.

```powershell
# Open Menu.ps1
code "Menu.ps1"
```

Add entry to Utilities:

```powershell
"Utilities" = @(
    @{ Name = "Create Backup Folders"; Path = "Utils/BACKUPS/Create_Folders_v2.ps1"; Description = "Create backup folder structure for migrations" }
    @{ Name = "Get Disk Space"; Path = "Utils/DiskTools/Get-DiskSpace.ps1"; Description = "Report disk space on local or remote computers" }
)
```

Save Menu.ps1.

```powershell
# Test locally
& ".\Menu.ps1"

# Stage, commit, push
git add -A
git commit -m "Add: Get-DiskSpace script to Utilities"
git push

# Test from GitHub
iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Menu.ps1")
```

## Adding New Categories

### Step 1: Create Folder

```powershell
cd "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts"
mkdir "Reporting"
```

### Step 2: Add Script(s)

```powershell
mkdir "Reporting\ADReports"
code "Reporting\ADReports\Export-ADUsers.ps1"
```

### Step 3: Update Menu.ps1

Add the new category to `$Script:MenuStructure`. The `[ordered]` keyword preserves the order categories appear:

```powershell
$Script:MenuStructure = [ordered]@{
    "Active Directory" = @(
        # existing entries...
    )
    "Device Setup" = @(
        # existing entries...
    )
    "Reporting" = @(
        @{ Name = "Export AD Users"; Path = "Reporting/ADReports/Export-ADUsers.ps1"; Description = "Export AD users to CSV" }
    )
    "Utilities" = @(
        # existing entries...
    )
}
```

### Step 4: Commit and Push

```powershell
git add -A
git commit -m "Add: Reporting category with Export-ADUsers script"
git push
```

## Git Workflow

### Pull Latest Changes

Always pull before making changes:

```powershell
cd "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts"
git pull
```

### Check Status

```powershell
git status
```

### View Changes

```powershell
git diff
```

### Stage and Commit

```powershell
git add -A
git commit -m "Description of changes"
```

Commit message conventions:
- `Add: New script or feature`
- `Fix: Bug fix`
- `Update: Modify existing script`
- `Remove: Delete script or feature`
- `Docs: Documentation changes`

### Push to GitHub

```powershell
git push
```

### Discard Uncommitted Changes

Single file:

```powershell
git checkout -- Menu.ps1
```

All files:

```powershell
git checkout -- .
```

### View History

```powershell
git log --oneline -10
```

## Running Methods

### Direct Command

```powershell
iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Menu.ps1")
```

### With TLS Override

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Menu.ps1")
```

### PowerShell Profile Alias

```powershell
notepad $PROFILE
```

Add:

```powershell
function IT { iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Menu.ps1") }
```

Type `IT` to launch.

### Desktop Shortcut

```powershell
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\IT-Toolbox.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = '-NoExit -Command "iex (irm https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Menu.ps1)"'
$Shortcut.Save()
```

### Desktop Shortcut (Run as Admin)

```powershell
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\IT-Toolbox-Admin.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = '-NoExit -Command "iex (irm https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Menu.ps1)"'
$Shortcut.Save()

$bytes = [System.IO.File]::ReadAllBytes("$env:USERPROFILE\Desktop\IT-Toolbox-Admin.lnk")
$bytes[0x15] = $bytes[0x15] -bor 0x20
[System.IO.File]::WriteAllBytes("$env:USERPROFILE\Desktop\IT-Toolbox-Admin.lnk", $bytes)
```

### Run Individual Script

```powershell
iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/ActiveDirectory/Rename-UPN/UPN_NameChange.ps1")
```

## Execution Policy and Admin Rights

### Execution Policy

The `iex (irm ...)` pattern bypasses file-based execution policy because no file is written to disk.

Some environments may block via:
- AppLocker
- Constrained Language Mode
- Group Policy restricting Invoke-Expression

### Administrator Requirements

| Script | Admin Required | Reason |
|--------|----------------|--------|
| hwh.ps1 | Yes | WMI hardware access |
| AD scripts | No (AD perms) | Requires AD module and delegation |
| Create_Folders_v2.ps1 | Depends | Write access to target path |

## IEX File Handling - Important Consideration

When scripts are executed via `iex (irm ...)` from the web, certain PowerShell automatic variables behave differently than when running from a local file. This affects scripts that create log files, CSVs, or any output files.

### The Problem

When running a script from a file, `$PSScriptRoot` contains the script's directory path. When running via IEX from the web, `$PSScriptRoot` is empty because there is no physical script file.

This causes issues when scripts try to save files "next to the script" - they may:
- Fail with "Access Denied" (attempting to write to System32)
- Save files to unexpected locations
- Throw errors about invalid paths

### The Solution - Smart Path Detection

Scripts should detect how they are being executed and choose an appropriate output location:

```powershell
# Smart log/output path detection
if ([string]::IsNullOrWhiteSpace($LogPath)) {
    if ($PSScriptRoot) {
        # Running from a physical file - save next to script
        $LogPath = Join-Path -Path $PSScriptRoot -ChildPath "OutputFile.txt"
    }
    else {
        # Running from Web/IEX - save to Desktop to avoid permission errors
        $LogPath = "$env:USERPROFILE\Desktop\OutputFile.txt"
    }
}
```

### Implementation Pattern

For any script that creates output files, use this pattern:

```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath  # Leave empty to allow smart detection
)

Process {
    # Smart path detection at the start of the script
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        if ($PSScriptRoot) {
            $OutputPath = Join-Path -Path $PSScriptRoot -ChildPath "MyOutput.csv"
        }
        else {
            $OutputPath = "$env:USERPROFILE\Desktop\MyOutput.csv"
        }
    }
    
    Write-Host "Output will be saved to: $OutputPath" -ForegroundColor DarkGray
    
    # Rest of script...
}
```

### Common Output Locations for IEX Execution

| Location | Variable | Use Case |
|----------|----------|----------|
| Desktop | `$env:USERPROFILE\Desktop` | User-facing outputs, logs |
| Documents | `$env:USERPROFILE\Documents` | Reports, exports |
| Temp | `$env:TEMP` | Temporary files |
| Current Directory | `$PWD` | If user navigated to specific folder |

### Example: Logging Function with Smart Path

```powershell
function Write-Log {
    param (
        [string]$Message,
        [string]$Color = "White",
        [string]$Type = "INFO" 
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogLine = "[$Timestamp] [$Type] $Message"
    
    # Write to Console
    Write-Host " $Message" -ForegroundColor $Color
    
    # Write to File (with error handling for permission issues)
    try { 
        Add-Content -Path $LogPath -Value $LogLine -ErrorAction SilentlyContinue 
    } catch {}
}
```

### Variables NOT Available in IEX Execution

| Variable | From File | From IEX |
|----------|-----------|----------|
| `$PSScriptRoot` | Script directory | Empty |
| `$PSCommandPath` | Full script path | Empty |
| `$MyInvocation.MyCommand.Path` | Full script path | Empty |

### Testing Your Scripts

Always test scripts both ways:

1. **From file:**
```powershell
& "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts\Utils\MyScript.ps1"
```

2. **From web (after pushing):**
```powershell
iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Utils/MyScript.ps1")
```

Verify output files are created in the expected location for both methods.

## Troubleshooting

### Script Not Found (404)

Test URL in browser:
```
https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Path/To/Script.ps1
```

Check:
- Case sensitivity
- Forward slashes in path
- No leading slash

### Invoke-Expression Errors

"Missing closing '}'" means Menu.ps1 is truncated or has syntax errors. Re-copy complete file and push.

### Changes Not Appearing

GitHub caches raw content. Wait 30-60 seconds or test locally first.

### TLS Errors

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
```

### Module Not Found

```powershell
Install-Module -Name ActiveDirectory -Scope CurrentUser
```

### Menu Entry Not Appearing

Check Menu.ps1 syntax:
- Entry is inside the correct category's `@()` array
- Entry uses `@{ }` wrapper
- Properties separated by semicolons
- No trailing comma after last entry

### Script Runs Locally But Fails from GitHub

- Check path case matches exactly
- Verify no special characters in folder/file names
- Test raw URL directly in browser

## Folder Naming

Avoid spaces - use hyphens:

| Bad | Good |
|-----|------|
| Rename UPN | Rename-UPN |
| Hardware Hash | HWH |
| Backup Tools | Backup-Tools |

## Security

- Keep repository private or restrict write access
- Review changes before pushing
- Consider branch protection rules
- Anyone with push access can modify scripts that execute on client machines

## References

- Invoke-RestMethod: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-restmethod
- Invoke-Expression: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-expression
- GitHub Raw Content: https://docs.github.com/en/repositories/working-with-files/using-files/viewing-a-file
- Git Documentation: https://git-scm.com/doc

## Sources for modifications 

- Official Microsoft Documentation
- Set-ADUser & Attributes: https://learn.microsoft.com/en-us/powershell/module/activedirectory/set-aduser
- Rename-ADObject: https://learn.microsoft.com/en-us/powershell/module/activedirectory/rename-adobject
- Start-Transcript (Logging): https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.host/start-transcript
- Splatting (Hashtables for Parameters): https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_splatting
- Try/Catch/Finally (Error Handling): https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_try_catch_finally

## Technical References & Guides

- SS64 PowerShell Index (Industry Standard Cheat Sheet): https://ss64.com/ps/
- Active Directory Attributes (SMTP vs smtp): https://adamtheautomator.com/powershell-active-directory/
- Handling Proxy Addresses: https://www.powershellisfun.com/2022/07/25/manage-email-addresses-proxyaddresses-in-active-directory-with-powershell/




