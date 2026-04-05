# Windows 11 App Audit - Removal Recommendations

Analysis of installed applications from `winget list` output. Apps are categorised by removal risk with PowerShell removal commands provided.

---

## Anomalies and Duplicates

Before any removals, the following duplicates and oddities are worth addressing:

| Issue | Details | Action |
|-------|---------|--------|
| Duplicate Hugo | `Hugo.Hugo.Extended` at both 0.154.5 and 0.152.2 | Remove older 0.152.2 |
| Duplicate Notepad++ | Win32 install (8.8.8) and MSIX version both present | Remove MSIX version, keep Win32 |
| Duplicate Tailscale | Machine-level install and a `User\X64` ARP entry both present | Investigate; likely a leftover from an older install |
| Duplicate Microsoft To Do | Only one entry visible but flagged for review | Keep if in use |

Remove the older Hugo:

```powershell
winget uninstall --id Hugo.Hugo.Extended --version 0.152.2
```

Remove the MSIX Notepad++:

```powershell
Get-AppxPackage -Name "*NotepadPlusPlus*" | Remove-AppxPackage
```

---

## Safe to Remove

These apps have no likely role in your environment and carry low removal risk.

### Mail and Calendar (deprecated)

Microsoft ended support for the classic Mail, Calendar and People apps on 31 December 2024. The app is now view-only and cannot send or receive mail.

```powershell
Get-AppxPackage -Name "*windowscommunicationsapps*" | Remove-AppxPackage
Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*windowscommunicationsapps*" } | Remove-AppxProvisionedPackage -Online
```

### Microsoft Bing News

```powershell
Get-AppxPackage -Name "*BingNews*" | Remove-AppxPackage
Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*BingNews*" } | Remove-AppxProvisionedPackage -Online
```

### Windows Maps (deprecated)

Microsoft deprecated the Maps app and announced removal from the Microsoft Store by July 2025.

```powershell
Get-AppxPackage -Name "*WindowsMaps*" | Remove-AppxPackage
Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*WindowsMaps*" } | Remove-AppxProvisionedPackage -Online
```

### Phone Link

Only relevant if actively using the Android phone integration feature.

```powershell
Get-AppxPackage -Name "*YourPhone*" | Remove-AppxPackage
Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*YourPhone*" } | Remove-AppxProvisionedPackage -Online
```

### Microsoft Edge Game Assist

A gaming overlay for Edge. No utility in an IT/MSP context.

```powershell
Get-AppxPackage -Name "*Edge.GameAssist*" | Remove-AppxPackage
```

### Windows Advanced Settings / Dev Home

Dev Home is a developer dashboard app. Separate from actual Windows settings. Safe to remove.

```powershell
Get-AppxPackage -Name "*DevHome*" | Remove-AppxPackage
Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*DevHome*" } | Remove-AppxProvisionedPackage -Online
```

### Local AI Manager for Microsoft 365 (aimgr)

The `aimgr` package is Microsoft's Local AI Manager, part of the Copilot+/M365 AI feature set. Safe to remove if not using Copilot AI features.

```powershell
Get-AppxPackage -Name "*aimgr*" | Remove-AppxPackage
```

### Windows Sound Recorder

```powershell
Get-AppxPackage -Name "*WindowsSoundRecorder*" | Remove-AppxPackage
Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*WindowsSoundRecorder*" } | Remove-AppxProvisionedPackage -Online
```

### Windows Camera

Desktop machine with no camera use case. Safe to remove.

```powershell
Get-AppxPackage -Name "*WindowsCamera*" | Remove-AppxPackage
Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*WindowsCamera*" } | Remove-AppxProvisionedPackage -Online
```

### Reddit PWA

Installed as a Progressive Web App via Edge/Chrome. Can be removed from the browser's app management or:

```powershell
# Find and remove the ARP entry
winget uninstall --name "Reddit"
```

If winget doesn't resolve it, remove via **Settings > Apps > Installed apps** and search "Reddit".

### HydraHD

Listed as a User\X64 ARP entry with version 1.0. This appears to be a PWA install (likely a video streaming service app). Check the publisher and remove via Settings > Apps > Installed apps if not in use.

### Widgets Platform Runtime + Windows Web Experience Pack

Only needed if using the Widgets panel on the taskbar. If Widgets is disabled:

```powershell
Get-AppxPackage -Name "*WidgetsPlatformRuntime*" | Remove-AppxPackage
Get-AppxPackage -Name "*WebExperience*" | Remove-AppxPackage
```

Note: Removing these will disable the Widgets button on the taskbar. This is a cosmetic functional change only.

---

## Review Before Removing

These apps may have a use case depending on workflow.

| App | Package | Remove If |
|-----|---------|-----------|
| Microsoft To Do | `Microsoft.Todos` | Not using it for task management |
| Power Automate Desktop | `Microsoft.PowerAutomateDesktop` | Not building desktop automation flows |
| Cross Device Experience Host | `MicrosoftWindows.CrossDevice` | Not using Continue on PC / phone sync features |
| Windows Clock / Alarms | `Microsoft.WindowsAlarms` | No alarm or timer use case |
| Quick Assist | `MicrosoftCorporationII.QuickAssist` | Keep — useful for MSP remote support |

Removal commands (run individually after confirming):

```powershell
# Microsoft To Do
Get-AppxPackage -Name "*Todos*" | Remove-AppxPackage

# Power Automate Desktop
Get-AppxPackage -Name "*PowerAutomateDesktop*" | Remove-AppxPackage

# Cross Device Experience Host
Get-AppxPackage -Name "*CrossDevice*" | Remove-AppxPackage

# Windows Clock / Alarms
Get-AppxPackage -Name "*WindowsAlarms*" | Remove-AppxPackage
```

---

## Do Not Remove

These packages are either dependencies for other installed apps, system components, or tools you actively use. Removal would cause breakage.

| App | Reason |
|-----|--------|
| App Installer (`Microsoft.AppInstaller`) | winget dependency — removing this breaks winget entirely |
| Microsoft Store | Required for Store-based app delivery and many MSIX app updates |
| Windows Security (`Microsoft.SecHealthUI`) | Defender UI — do not remove |
| All `Microsoft.VCLibs.*` entries | Runtime dependency for UWP/MSIX apps |
| All `Microsoft.WindowsAppRuntime.*` entries | Runtime dependency for modern apps |
| All `Microsoft.UI.Xaml.*` entries | UI framework dependency |
| All `Microsoft.NET.*` entries | .NET runtime dependencies |
| Snipping Tool | In active use for screenshots |
| Paint | Updated with AI features; low overhead |
| Windows Notepad | Default text handler |
| Windows Calculator | Default calculator handler |
| Windows Terminal | In active use |
| WSL | In active use for lab work |
| Windows Package Manager Source (winget) | winget source index |
| Start Experiences App | Tied to Start menu — do not remove |
| Store Experience Host | Required for Store purchases |
| Microsoft Engagement Framework | Store dependency — leave alone |
| HEIF / HEVC / AV1 / VP9 / WebP / MPEG-2 extensions | Codec support — useful for media files encountered in work |
| Microsoft.Office.ActionsServer | M365 component — leave alone |
| OfficePushNotificationsUtility | M365 component — leave alone |
| English (UK) Language Experience Pack | Required for locale |
| Ink Handwriting packages | Input system component |

---

## Batch Removal Script

Run as Administrator. Review the list before executing — comment out any line you are unsure about.

```powershell
#Requires -RunAsAdministrator

$AppsToRemove = @(
    "*windowscommunicationsapps*",  # Mail and Calendar (deprecated)
    "*BingNews*",                   # News
    "*WindowsMaps*",                # Maps (deprecated)
    "*YourPhone*",                  # Phone Link
    "*Edge.GameAssist*",            # Edge Game Assist
    "*DevHome*",                    # Windows Advanced Settings / Dev Home
    "*aimgr*",                      # Local AI Manager (M365 Copilot)
    "*WindowsSoundRecorder*",       # Sound Recorder
    "*WindowsCamera*",              # Camera
    "*WidgetsPlatformRuntime*",     # Widgets runtime
    "*WebExperience*"               # Windows Web Experience Pack
)

foreach ($App in $AppsToRemove) {
    Write-Host "Removing: $App" -ForegroundColor Cyan

    Get-AppxPackage -Name $App -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue

    Get-AppxProvisionedPackage -Online |
        Where-Object { $_.DisplayName -like $App } |
        Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

    Write-Host "Done: $App" -ForegroundColor Green
}

Write-Host "`nBatch removal complete." -ForegroundColor Cyan
```

---

## Winget Updates Available

The following apps have updates available via winget and are worth running on the next maintenance window:

```powershell
winget upgrade --all --accept-source-agreements --accept-package-agreements
```

Apps with available updates from the audit:

| App | Current | Available |
|-----|---------|-----------|
| Koodo Reader | 2.2.6 | 2.3.1 |
| 7-Zip | 25.01 | 26.00 |
| CPUID HWMonitor | 1.61 | 1.63 |
| CrystalDiskMark | 9.0.1 | 9.0.2 |
| Docker Desktop | 4.49.0 | 4.67.0 |
| Notepad++ | 8.8.8 | 8.9.3 |
| Oh My Posh | 26.14.3 | 29.9.2 |
| Adobe Acrobat Reader | 25.001.20531 | 26.001.21346 |
| GitHub CLI | 2.83.1 | 2.89.0 |
| GitHub Desktop | 3.5.6 | 3.5.7 |
| Hugo Extended | 0.154.5 | 0.159.2 |
| pyfa | 2.65.4 | 2.66.1 |
| VS Code | 1.101.2 | 1.114.0 |
| WinSCP | 6.5.5 | 6.5.6 |
| Microsoft Teams | current | update available |
| Oracle VirtualBox | 7.2.4 | 7.2.6 |
| PowerShell | 7.5.5 | 7.6.0 |
| PawnIO | 2.0.1.0 | 2.2.0 |

---

## References

- Microsoft - Windows Maps Deprecation: https://support.microsoft.com/en-us/topic/windows-maps-app-deprecation-faq-3e7f59f2-4a8e-4b31-abc4-4d4571f80c0f
- Microsoft - Mail and Calendar End of Support: https://support.microsoft.com/en-us/office/outlook-for-windows-the-future-of-mail-calendar-and-people-on-windows-11-715fc27c-e0f4-4652-9174-47faa751b199
- Microsoft - Remove-AppxPackage: https://learn.microsoft.com/en-us/powershell/module/appx/remove-appxpackage
- Windows Latest - M365 Companion Apps: https://www.windowslatest.com/2025/11/07/windows-11-is-auto-installing-people-files-and-calendar-microsoft-365-apps-on-business-pcs/
