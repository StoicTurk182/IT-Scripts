# Windows 11 - Removing Built-In and Auto-Installed Apps

Guide covering removal of Windows 11 built-in apps and the M365 Companion suite (Files, People, Calendar) auto-installed from late 2025 onward.

---

## Background

Windows 11 ships with a range of built-in Microsoft Store apps, many of which have no relevance in MSP or enterprise environments. From October 2025, Microsoft began a further rollout of three **M365 Companion apps** — Files, People, and Calendar — automatically installed and pinned to the taskbar on business PCs without user consent. These are distinct from the legacy Mail, Calendar, and People apps.

Removal approaches differ depending on:

- Whether the app is provisioned (installs for all new users) or just installed for the current user
- Whether the device is managed via Intune/GPO or is standalone
- Whether the Windows 11 build is 25H2 or earlier

---

## The M365 Companion Apps (Files, People, Calendar)

### What They Are

Microsoft's M365 Companion apps are lightweight taskbar flyout apps tied to Microsoft 365 services. They share a single package:

```
Microsoft.M365Companions_8wekyb3d8bbwe
```

The three companions installed by default are:

| App | Function |
|-----|----------|
| Files | Quick access to OneDrive and recent files from the taskbar |
| People | Contact cards and org details pulled from Entra/M365 |
| Calendar | Taskbar calendar flyout linked to Exchange/Outlook |

### Why They Keep Coming Back

The apps reinstall unless the auto-installation setting is disabled at the tenant level. The toggle is:

**Microsoft 365 Admin Center > Settings > Org Settings > Microsoft 365 on Windows > Enable automatic installation of Microsoft 365 companion apps (preview)**

Disabling this prevents re-deployment. Without disabling it first, removal at the device level is temporary.

### Suppressing Startup Without Removing

This script disables auto-start for all three companions by modifying per-user registry keys. The apps remain installed but will not launch.

```powershell
$baseKey = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\Microsoft.M365Companions_8wekyb3d8bbwe"

$startupKeys = @("CalendarStartupId", "FilesStartupId", "PeopleStartupId")

foreach ($key in $startupKeys) {
    $fullPath = Join-Path $baseKey $key
    if (Test-Path $fullPath) {
        Set-ItemProperty -Path $fullPath -Name "State" -Value 1 -ErrorAction SilentlyContinue
        Write-Host "Disabled startup for: $key"
    } else {
        Write-Host "Key not found (app may not be installed): $key"
    }
}
```

### Removing the Companion Package

```powershell
# Remove for current user
Get-AppxPackage -Name "*M365Companions*" | Remove-AppxPackage

# Remove provisioned (prevents install for new user profiles)
Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*M365Companions*" } | Remove-AppxProvisionedPackage -Online
```

If the provisioned package cannot be removed due to policy, the apps will reinstall. Disable the Admin Center toggle first.

---

## General Built-In App Removal

### Method 1 - Settings UI

For apps that expose an Uninstall button:

1. Open Settings (`Win + I`)
2. Navigate to **Apps > Installed apps**
3. Find the app, click the three-dot menu, select **Uninstall**

Note: Many built-in apps do not show an Uninstall option here. System components moved to **Settings > System > System Components** in recent Windows 11 builds.

### Method 2 - PowerShell (Current User)

Removes the app for the currently signed-in user only. Does not affect other profiles or new users.

```powershell
# Syntax
Get-AppxPackage -Name "PackageName" | Remove-AppxPackage

# Examples
Get-AppxPackage -Name "*BingWeather*" | Remove-AppxPackage
Get-AppxPackage -Name "*XboxApp*" | Remove-AppxPackage
Get-AppxPackage -Name "*WindowsFeedbackHub*" | Remove-AppxPackage
Get-AppxPackage -Name "*SkypeApp*" | Remove-AppxPackage
Get-AppxPackage -Name "*ZuneMusic*" | Remove-AppxPackage
Get-AppxPackage -Name "*ZuneVideo*" | Remove-AppxPackage
Get-AppxPackage -Name "*People*" | Remove-AppxPackage
Get-AppxPackage -Name "*MicrosoftOfficeHub*" | Remove-AppxPackage
Get-AppxPackage -Name "*GetHelp*" | Remove-AppxPackage
Get-AppxPackage -Name "*Getstarted*" | Remove-AppxPackage
```

### Method 3 - PowerShell (All Users + Provisioned)

Removes the app from all existing user profiles and prevents it from being installed for new users. Requires an elevated PowerShell session.

```powershell
# Remove for all current user profiles
Get-AppxPackage -AllUsers -Name "*PackageName*" | Remove-AppxPackage

# Remove provisioned package (new user prevention)
Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*PackageName*" } | Remove-AppxProvisionedPackage -Online
```

Both commands should be run together for a complete removal.

### Bulk Removal Script

```powershell
#Requires -RunAsAdministrator

$AppsToRemove = @(
    "Microsoft.BingWeather",
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.People",
    "Microsoft.SkypeApp",
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.XboxApp",
    "Microsoft.XboxGameOverlay",
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxIdentityProvider",
    "Microsoft.ZuneMusic",
    "Microsoft.ZuneVideo",
    "Microsoft.M365Companions"
)

foreach ($App in $AppsToRemove) {
    Write-Host "Processing: $App"

    # Remove for all current users
    Get-AppxPackage -AllUsers -Name $App -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue

    # Remove provisioned package
    Get-AppxProvisionedPackage -Online |
        Where-Object { $_.DisplayName -eq $App } |
        Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

    Write-Host "Done: $App" -ForegroundColor Green
}
```

### Method 4 - winget

winget can remove some built-in apps using their display name. Useful for one-off removals without needing to know the AppX package name.

```powershell
# List all installed apps
winget list

# Remove by name
winget uninstall "Microsoft To Do"
winget uninstall "Cortana"
winget uninstall "Xbox"
```

winget operates on the current user by default and may not remove provisioned packages.

### Method 5 - Group Policy (Windows 11 25H2, Enterprise/Education Only)

Windows 11 25H2 introduced a native Group Policy setting for removing built-in Store apps. This is the most reliable managed method as it does not require scripts and prevents reinstallation.

Path:

```
Computer Configuration > Administrative Templates > Windows Components > App Package Deployment > Remove Default Microsoft Store packages from the system
```

Steps:

1. Open `gpedit.msc` as administrator
2. Navigate to the path above
3. Enable the policy
4. Check the boxes for each app to remove
5. Log off and back on to apply

This policy is only available on:
- Windows 11 25H2 and later
- Enterprise and Education SKUs

The equivalent registry key written by this policy:

```
HKLM:\Software\Policies\Microsoft\Windows\Appx\RemoveDefaultMicrosoftStorePackages
```

### Method 6 - Intune (Settings Catalog, 25H2+)

For managed device environments:

1. Navigate to **Intune > Devices > Configuration > Create policy**
2. Platform: **Windows 10 and later**
3. Profile type: **Settings Catalog**
4. Search for: `Remove Default Microsoft Store packages from the system`
5. Enable the setting and select the apps to remove
6. Assign to device groups

This policy blocks reinstallation via the Microsoft Store (error `0x80073D3F`) and prevents user-initiated reinstall as long as the policy remains applied.

---

## App Reference - Safe to Remove

These apps are commonly removed in enterprise/MSP environments with minimal risk:

| Package Name | Display Name | Notes |
|-------------|--------------|-------|
| Microsoft.BingWeather | Weather | Safe to remove |
| Microsoft.GetHelp | Get Help | Safe to remove |
| Microsoft.Getstarted | Tips / Get Started | Safe to remove |
| Microsoft.MicrosoftOfficeHub | Office Hub | Safe if M365 apps deployed separately |
| Microsoft.People | People (legacy) | Safe to remove |
| Microsoft.SkypeApp | Skype | Safe to remove |
| Microsoft.WindowsFeedbackHub | Feedback Hub | Safe on managed devices |
| Microsoft.XboxApp | Xbox | Safe on non-gaming devices |
| Microsoft.XboxGameOverlay | Xbox Game Bar Overlay | Safe on non-gaming devices |
| Microsoft.XboxGamingOverlay | Xbox Game Bar | Safe on non-gaming devices |
| Microsoft.XboxIdentityProvider | Xbox Identity Provider | Safe if Xbox services unused |
| Microsoft.ZuneMusic | Media Player (legacy Groove) | Safe to remove |
| Microsoft.ZuneVideo | Movies & TV | Safe to remove; storefront deprecated |
| Microsoft.M365Companions | Files, People, Calendar companions | Safe to remove if not using companion features |

## App Reference - Remove With Caution

| Package Name | Display Name | Risk |
|-------------|--------------|------|
| Microsoft.WindowsStore | Microsoft Store | Removing breaks Store-based app delivery and winget |
| Microsoft.DesktopAppInstaller | App Installer / winget | Removing breaks winget entirely |
| Microsoft.WindowsCalculator | Calculator | Low risk but restore is simple |
| Microsoft.WindowsCamera | Camera | Required if device has camera workflows |
| Microsoft.MicrosoftStickyNotes | Sticky Notes | Low risk |
| Microsoft.Windows.Photos | Photos | Default image handler — test before removing |
| Microsoft.WindowsNotepad | Notepad | Default text handler — test before removing |

Do not remove Microsoft Edge, Settings, or any package prefixed `Windows.` rather than `Microsoft.` — these are OS components, not Store apps.

---

## Auditing Installed Packages

### List All Installed AppX Packages

```powershell
# Current user
Get-AppxPackage | Select-Object Name, PackageFullName, Version | Sort-Object Name

# All users
Get-AppxPackage -AllUsers | Select-Object Name, PackageFullName, PackageUserInformation | Sort-Object Name
```

### List Provisioned Packages (New User Template)

```powershell
Get-AppxProvisionedPackage -Online | Select-Object DisplayName, PackageName | Sort-Object DisplayName
```

### Export to CSV

```powershell
Get-AppxPackage | Export-Csv -Path "C:\Temp\InstalledApps.csv" -NoTypeInformation
Get-AppxProvisionedPackage -Online | Export-Csv -Path "C:\Temp\ProvisionedApps.csv" -NoTypeInformation
```

### Find a Specific App

```powershell
# Search by partial name
Get-AppxPackage -Name "*Teams*" | Select-Object Name, PackageFullName

# Check if a specific package is provisioned
Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*Teams*" }
```

---

## Restoring Removed Apps

If an app needs to be restored:

```powershell
# Reinstall via Microsoft Store - search for the app by name

# Or restore all default AppX packages (use with caution - reinstalls everything)
Get-AppxPackage -AllUsers | ForEach-Object {
    Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue
}
```

Most removed built-in apps are available for reinstall from the Microsoft Store directly.

---

## Key Differences: Remove-AppxPackage vs Remove-AppxProvisionedPackage

| Cmdlet | Scope | Affects New Users | Use Case |
|--------|-------|-------------------|----------|
| `Remove-AppxPackage` | Current user (or `-AllUsers` for all existing) | No | Single machine cleanup |
| `Remove-AppxProvisionedPackage -Online` | Windows image / new user template | Yes | Prevents reinstall on new profiles |

For a clean state on a managed device, both should be run.

---

## References

- Microsoft - Remove-AppxPackage: https://learn.microsoft.com/en-us/powershell/module/appx/remove-appxpackage
- Microsoft - Remove-AppxProvisionedPackage: https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage
- Microsoft - Policy-Based Removal of Pre-installed Store Apps: https://support.microsoft.com/en-us/topic/policy-based-removal-of-pre-installed-microsoft-store-apps-e1d41a92-b658-4511-95a6-0fbcc02b4e9c
- MSEndpointMgr - Remove Built-in Apps for Windows 11 25H2: https://msendpointmgr.com/2025/10/29/how-to-remove-built-in-apps-for-windows-11-25h2/
- Windows Latest - M365 Companion Apps Auto-Installing on Business PCs: https://www.windowslatest.com/2025/11/07/windows-11-is-auto-installing-people-files-and-calendar-microsoft-365-apps-on-business-pcs/
- Patch My PC - Remove Built-In Windows Apps: https://patchmypc.com/blog/remove-built-windows-apps-powershell/
- Patch My PC - Remove Default Store Packages 25H2: https://patchmypc.com/blog/remove-default-microsoft-store-app-packages-windows11-25h2/
- Ben Whitmore - Remove-Appx-AllUsers.ps1 (GitHub): https://github.com/byteben/Win32App-Migration-Tool
