# Win11-AppManager

Audits and removes unwanted built-in Windows 11 apps. Runs interactively via the IT-Scripts menu or directly as a script.

---

## Usage

```powershell
iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Utils/Win11-AppManager/Win11-AppManager.ps1")
```

Must be run as Administrator.

---

## Modes

| Mode | Behaviour |
|------|-----------|
| Audit only | Shows what is installed and would be removed. No changes made. |
| Interactive | Prompts for each app individually before removing. |
| Auto-remove | Removes all Safe apps without prompting. Prompts for Review apps. |

---

## Output

A CSV report and a `.log` file are written to the Desktop on completion. The log captures every action including errors, skipped apps, and winget update results.

---

## App Categories

### Safe to Remove

Removed automatically in Auto-remove mode. Prompted in Interactive mode.

| App | Reason |
|-----|--------|
| Mail and Calendar | Deprecated - Microsoft ended support 31 Dec 2024 |
| Windows Maps | Deprecated - removal from Store announced July 2025 |
| Bing News | Consumer news feed |
| Bing Weather | Consumer weather app |
| Phone Link | Android phone integration |
| Edge Game Assist | Gaming overlay for Edge |
| Dev Home | Developer dashboard, separate from Windows Settings |
| Local AI Manager (aimgr) | M365 Copilot+ component |
| Sound Recorder | Consumer audio app |
| Windows Camera | Safe on desktop machines with no camera workflow |
| Widgets Platform Runtime | Only needed if Widgets taskbar panel is in use |
| Windows Web Experience Pack | Only needed if Widgets taskbar panel is in use |
| Get Help | Microsoft virtual support agent |
| Tips / Get Started | Windows onboarding app |
| Office Hub | M365 upsell launcher |
| Skype | Consumer Skype, not relevant in Teams environments |
| Feedback Hub | Microsoft telemetry tool |
| Xbox App | Xbox console companion |
| Xbox Game Bar / Overlay | Gaming overlay |
| Xbox Identity Provider | Xbox sign-in component |
| Groove Music (legacy) | Superseded by Windows Media Player |
| Movies and TV | Storefront deprecated by Microsoft |
| M365 Companion Apps | Auto-installed Files, People, Calendar taskbar apps |
| Cortana | Deprecated in most markets |

### Review Before Removing

Prompted in both Interactive and Auto-remove modes.

| App | Reason |
|-----|--------|
| Microsoft To Do | Remove only if not in use for task management |
| Power Automate Desktop | Remove only if not building automation flows |
| Cross Device Experience Host | Remove if not using Continue on PC features |
| Windows Clock / Alarms | Low risk, remove if not needed |
| People (legacy) | Legacy contacts app |
| Reddit PWA | Progressive Web App, remove if not in use |

### Do Not Remove

These are not in scope for the script and are never touched.

| App | Reason |
|-----|--------|
| App Installer / winget | Removing breaks winget entirely |
| Microsoft Store | Required for Store-based app delivery |
| Windows Security | Defender UI |
| VCLibs / WindowsAppRuntime / UI.Xaml | Runtime dependencies for UWP and MSIX apps |
| Snipping Tool | Active use |
| Windows Terminal | Active use |
| WSL | Active use |
| Microsoft Edge | OS component |

---

## Duplicate Detection

The script checks for common duplicate installs before removing anything:

- Hugo Extended with multiple versions installed
- Notepad++ with both Win32 and MSIX versions present
- Tailscale with both machine-level and User ARP entries

Fixes are reported in the console output and log with the exact command to resolve each one.

---

## M365 Companion Apps

If the M365 Companion apps (Files, People, Calendar) are detected, the script suppresses their auto-startup via registry in addition to removing the package. However they will reinstall on next Windows Update unless the auto-installation toggle is disabled at the tenant level.

To prevent reinstall permanently:

```
Microsoft 365 Admin Center > Settings > Org Settings
> Microsoft 365 on Windows
> Disable: Enable automatic installation of Microsoft 365 companion apps
```

---

## Winget Updates

At the end of each run the script checks for available winget updates and prints a list. To apply all available updates:

```powershell
winget upgrade --all --accept-source-agreements --accept-package-agreements
```

---

## References

- Microsoft - Mail and Calendar deprecation: https://support.microsoft.com/en-us/office/outlook-for-windows-the-future-of-mail-calendar-and-people-on-windows-11-715fc27c-e0f4-4652-9174-47faa751b199
- Microsoft - Windows Maps deprecation: https://support.microsoft.com/en-us/topic/windows-maps-app-deprecation-faq-3e7f59f2-4a8e-4b31-abc4-4d4571f80c0f
- Microsoft - Remove-AppxPackage: https://learn.microsoft.com/en-us/powershell/module/appx/remove-appxpackage
- Microsoft - Remove-AppxProvisionedPackage: https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage
- Windows Latest - M365 Companion Apps: https://www.windowslatest.com/2025/11/07/windows-11-is-auto-installing-people-files-and-calendar-microsoft-365-apps-on-business-pcs/
