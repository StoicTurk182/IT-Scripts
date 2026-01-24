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
│   │   └── migrate_user_group_memberships_param.ps1
│   └── Rename-UPN/
│       └── UPN_NameChange.ps1
├── Setup/
│   └── HWH/
│       └── hwh.ps1
├── Utils/
│   ├── BACKUPS/
│   │   └── Create_Folders_v2.ps1
│   ├── Install-standard-apps/
│   │   └── Install-StandardApps.ps1
│   ├── Set Screen Lock/
│   │   └── Set-AutoLock.ps1
│   ├── Export App JSON/
│   │   └── App Export_JSON.ps1
│   └── Windows mgmt/
│       └── Win11-FeatureManager.ps1
└── Windows Autopilot Deployment_WINhome/
    ├── Create_Bypass.ps1
    └── Install_AnyBurn.ps1
```

## Menu Categories

### Active Directory (2 scripts)

| Script | File | Description |
|--------|------|-------------|
| Copy User Groups | migrate_user_group_memberships_param.ps1 | Copy groups from Source to Target user |
| UPN Name Change | UPN_NameChange.ps1 | Change user UPN and display name |

### Device Setup (1 script)

| Script | File | Description |
|--------|------|-------------|
| Get Hardware Hash | hwh.ps1 | Collect Autopilot hardware hash |

### Utilities (5 scripts)

| Script | File | Description |
|--------|------|-------------|
| Create Backup Folders | Create_Folders_v2.ps1 | Create backup folder structure for migrations |
| Install Standard Apps | Install-StandardApps.ps1 | Auto-installs Winget, 7-Zip, and Notepad++ |
| Set Screen Lock | Set-AutoLock.ps1 | Set Windows Auto-Lock timeout for user and machine |
| Export App JSON | App Export_JSON.ps1 | Export list of installed applications to a text file |
| Windows mgmt | Win11-FeatureManager.ps1 | Manage Windows 11 features and settings |

### Windows Autopilot Deployment_WINhome (2 scripts)

| Script | File | Description |
|--------|------|-------------|
| Create_Bypass | Create_Bypass.ps1 | Create files for Windows ISO modification to prep for Home Edition |
| Install_AnyBurn | Install_AnyBurn.ps1 | Install AnyBurn for ISO editing |

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

## Menu Navigation

```
Main Menu
├── [1] Active Directory (2 scripts)
├── [2] Device Setup (1 script)
├── [3] Utilities (5 scripts)
├── [4] Windows Autopilot Deployment_WINhome (2 scripts)
├── [R] Reload Menu
└── [Q] Quit

Category Menu
├── [1-n] Select script to run
├── [B] Back to main menu
└── [Q] Quit
```

## Adding New Scripts

### Step 1: Create Subfolder

```powershell
cd "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts"
mkdir "Utils\NewScript"
```

### Step 2: Add Script File

```powershell
Copy-Item "C:\Source\NewScript.ps1" -Destination ".\Utils\NewScript\"
```

Or create new:

```powershell
code "Utils\NewScript\NewScript.ps1"
```

### Step 3: Update Menu.ps1

Open Menu.ps1 and add entry to the appropriate category in `$Script:MenuStructure`:

```powershell
"Utilities" = @(
    @{ Name = "Create Backup Folders"; Path = "Utils/BACKUPS/Create_Folders_v2.ps1"; Description = "Create backup folder structure for migrations" }
    @{ Name = "Install Standard Apps"; Path = "Utils/Install-standard-apps/Install-StandardApps.ps1"; Description = "Auto-installs Winget, 7-Zip, and Notepad++" }
    @{ Name = "Set Screen Lock"; Path = "Utils/Set Screen Lock/Set-AutoLock.ps1"; Description = "Set Windows Auto-Lock timeout for user and machine" }
    @{ Name = "Export App JSON"; Path = "Utils/Export App JSON/App Export_JSON.ps1"; Description = "Export list of installed applications to a text file" }
    @{ Name = "Windows mgmt"; Path = "Utils/Windows mgmt/Win11-FeatureManager.ps1"; Description = "Manage Windows 11 features and settings" }
    @{ Name = "New Script"; Path = "Utils/NewScript/NewScript.ps1"; Description = "Description of new script" }
)
```

### Step 4: Commit and Push

```powershell
git add -A
git commit -m "Add: NewScript to Utilities"
git push
```

## Adding New Categories

Add a new ordered entry to `$Script:MenuStructure` in Menu.ps1:

```powershell
$Script:MenuStructure = [ordered]@{
    "Active Directory" = @(
        # existing entries
    )
    "Device Setup" = @(
        # existing entries
    )
    "Utilities" = @(
        # existing entries
    )
    "Windows Autopilot Deployment_WINhome" = @(
        # existing entries
    )
    "New Category" = @(
        @{ Name = "Script Name"; Path = "NewCategory/Script.ps1"; Description = "Script description" }
    )
}
```

The `[ordered]` keyword preserves the display order of categories in the menu.

## Menu Entry Format

Each script entry requires three properties:

| Property | Purpose | Example |
|----------|---------|---------|
| Name | Display name in menu | `"Copy User Groups"` |
| Path | Relative path from repo root | `"ActiveDirectory/migrate_groups/migrate_user_group_memberships_param.ps1"` |
| Description | Brief description shown below name | `"Copy groups from Source to Target user"` |

Path rules:
- Use forward slashes `/` not backslashes
- No leading slash
- Case-sensitive (must match actual filename)
- Spaces in folder names are allowed but not recommended

## Git Workflow

Pull before changes:
```powershell
git pull
```

Check status:
```powershell
git status
```

Stage, commit, push:
```powershell
git add -A
git commit -m "Add: Description of changes"
git push
```

## Running Methods

### Direct Execution

```powershell
iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Menu.ps1")
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

### Run Individual Script Directly

```powershell
iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Utils/Windows%20mgmt/Win11-FeatureManager.ps1")
```

Note: Spaces in URLs must be encoded as `%20`.

### Desktop Shortcut

```powershell
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\IT-Toolbox.lnk")
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = '-NoExit -Command "iex (irm https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Menu.ps1)"'
$Shortcut.Save()
```

## Script Descriptions

### Copy User Groups

Copies Active Directory group memberships from a source user to a target user. Accepts parameters for source and target usernames.

Requirements: Active Directory PowerShell module, appropriate AD permissions.

### UPN Name Change

Changes user UPN (User Principal Name) and display name in Active Directory.

Requirements: Active Directory PowerShell module, appropriate AD permissions.

### Get Hardware Hash

Collects Windows Autopilot hardware hash for device enrollment. Exports to CSV for upload to Intune/Autopilot.

Requirements: Administrator rights, WMI access.

### Create Backup Folders

Creates standardised backup folder structure for user data migrations.

### Install Standard Apps

Automatically installs common applications using Winget: 7-Zip and Notepad++. Installs Winget if not present.

Requirements: Administrator rights, internet access.

### Set Screen Lock

Configures Windows auto-lock timeout settings for both user and machine policies.

Requirements: Administrator rights for machine-level settings.

### Export App JSON

Exports a list of all installed applications to a text/JSON file for documentation or migration planning.

### Windows mgmt (Win11-FeatureManager)

Interactive menu-driven tool to manage Windows 11 features, privacy settings, services, and firewall rules. Includes capability access manager toggles, system settings, service management, and quick admin commands.

Requirements: Administrator rights for most operations.

### Create_Bypass

Creates necessary files for Windows ISO modification to prepare for Windows Home Edition Autopilot deployment.

### Install_AnyBurn

Downloads and installs AnyBurn, a lightweight ISO editing tool used for Windows ISO customisation.

## Troubleshooting

### Script Not Found (404)

Test the URL in a browser:
```
https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Path/To/Script.ps1
```

Check for:
- Case sensitivity mismatches
- Missing or extra slashes
- Spaces not encoded as %20 in direct URLs

### TLS Errors

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
```

### Menu Entry Not Appearing

Verify in Menu.ps1:
- Entry is inside correct category's `@()` array
- Uses `@{ }` wrapper with semicolon separators
- Path uses forward slashes

### Changes Not Appearing After Push

GitHub caches raw content for approximately 5 minutes. Wait and retry, or use `[R]` Reload Menu option.

## References

- Invoke-RestMethod: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-restmethod
- Invoke-Expression: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-expression
- GitHub Raw Content: https://docs.github.com/en/repositories/working-with-files/using-files/viewing-a-file
- Git Documentation: https://git-scm.com/doc