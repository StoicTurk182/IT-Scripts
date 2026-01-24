# Windows 11 Feature Manager

Interactive PowerShell tool to check, enable, and disable common Windows 11 features via registry and service commands. Works via `iex (irm)` or locally.

Repository: https://github.com/StoicTurk182/IT-Scripts

Location: `Utils/Windows mgmt/Win11-FeatureManager.ps1`

## Quick Start

Run from IT-Scripts Toolbox menu:

```powershell
iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Menu.ps1")
```

Select: Utilities > Windows mgmt

Run directly:

```powershell
iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Utils/Windows%20mgmt/Win11-FeatureManager.ps1")
```

Run locally:

```powershell
.\Win11-FeatureManager.ps1
```

With TLS override for older systems:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Utils/Windows%20mgmt/Win11-FeatureManager.ps1")
```

Note: Spaces in URLs must be encoded as `%20`.

## Requirements

Requires Administrator rights for most operations. The script will warn if running without elevation but will still allow read-only status checks where possible.

## Features

### Capability Access Manager (Privacy Settings)

Manage Windows privacy toggles found in Settings > Privacy & Security:

| Feature | Registry Key |
|---------|--------------|
| Location Services | location |
| Camera Access | webcam |
| Microphone Access | microphone |
| Notifications | userNotificationListener |
| Contacts Access | contacts |
| Calendar Access | appointments |
| Phone Calls | phoneCall |
| Call History | phoneCallHistory |
| Email Access | email |
| Messaging (SMS/MMS) | chat |
| Bluetooth/Radios | radios |
| Background Apps | appCompatibility |
| App Diagnostics | appDiagnostics |
| Documents Library | documentsLibrary |
| Pictures Library | picturesLibrary |
| Videos Library | videosLibrary |
| Broad File System | broadFileSystemAccess |
| Screenshot Capture | graphicsCaptureProgrammatic |

Includes bulk Enable All / Disable All options.

### System Settings

Toggle common system settings:

| Setting | Registry Path |
|---------|---------------|
| Remote Desktop | HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server |
| RDP Network Level Auth | HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp |
| User Account Control | HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System |
| SmartScreen Filter | HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer |
| Fast Startup | HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power |
| Clipboard History | HKCU:\SOFTWARE\Microsoft\Clipboard |
| Storage Sense | HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense |
| Advertising ID | HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo |

### Windows Services

Manage key Windows services with Start/Stop/Auto/Disable options:

| Service | Service Name |
|---------|--------------|
| Windows Update | wuauserv |
| Windows Search | WSearch |
| Windows Time | w32time |
| Remote Desktop Services | TermService |
| Windows Remote Management | WinRM |
| Windows Defender | WinDefend |
| Print Spooler | Spooler |
| BITS | BITS |

### Windows Firewall

| Option | Action |
|--------|--------|
| Enable All Profiles | netsh advfirewall set allprofiles state on |
| Disable All Profiles | netsh advfirewall set allprofiles state off |
| Enable Network Discovery | Enable firewall rule group |
| Disable Network Discovery | Disable firewall rule group |
| Enable File and Printer Sharing | Enable firewall rule group |
| Disable File and Printer Sharing | Disable firewall rule group |
| Enable Remote Desktop Rule | Enable firewall rule group |
| Disable Remote Desktop Rule | Disable firewall rule group |

### Quick Commands

Common admin commands available with one keystroke:

| Command | Action |
|---------|--------|
| Force Time Sync | w32tm /resync /force |
| Flush DNS | ipconfig /flushdns |
| Release/Renew IP | ipconfig /release + /renew |
| Reset Winsock | netsh winsock reset |
| Enable Hibernate | powercfg /hibernate on |
| Disable Hibernate | powercfg /hibernate off |
| SFC Scan | sfc /scannow |
| DISM Health Check | DISM /Online /Cleanup-Image /CheckHealth |
| Clear Update Cache | Stops wuauserv, clears SoftwareDistribution, restarts |

### Full Status Report

Generates a complete status report of all monitored settings, services, and firewall profiles in one view.

## Menu Structure

```
Main Menu
├── [1] Capability Access Manager (Privacy Settings)
│   ├── Individual feature toggle
│   ├── [A] Enable ALL
│   ├── [D] Disable ALL
│   └── [R] Refresh Status
├── [2] System Settings (RDP, UAC, SmartScreen, etc.)
│   └── Individual setting toggle
├── [3] Windows Services
│   └── [S]tart / s[T]op / [A]uto / [D]isable
├── [4] Windows Firewall
│   ├── Profile enable/disable
│   └── Rule group enable/disable
├── [5] Quick Commands
│   └── One-shot admin commands
├── [S] Full Status Report
└── [0] Exit
```

## Menu.ps1 Entry

The script is registered in Menu.ps1 under Utilities:

```powershell
@{ Name = "Windows mgmt"; Path = "Utils/Windows mgmt/Win11-FeatureManager.ps1"; Description = "Manage Windows 11 features and settings" }
```

## How It Works

The script uses two primary methods to modify settings:

### Registry Commands

Uses `reg.exe add` for registry modifications to ensure compatibility when running via `iex`:

```powershell
reg add "HKLM\Path\To\Key" /v ValueName /t REG_DWORD /d 1 /f
```

The `/f` flag forces overwrite without confirmation.

### Service Commands

Uses PowerShell cmdlets for service management:

```powershell
Start-Service -Name ServiceName
Stop-Service -Name ServiceName -Force
Set-Service -Name ServiceName -StartupType Automatic
```

### Firewall Commands

Uses netsh for firewall management:

```powershell
netsh advfirewall set allprofiles state on
netsh advfirewall firewall set rule group="Group Name" new enable=yes
```

## Colour Coding

The interface uses consistent colour coding:

| Colour | Meaning |
|--------|---------|
| Green | Enabled / Running / OK |
| Red | Disabled / Stopped / Failed |
| Yellow | Warning / Partial / Requires attention |
| Gray | Not configured / Unknown |
| Cyan | Information / Headers |
| Magenta | Section headers |

## Limitations

- Requires Administrator rights for HKLM registry changes
- Some settings require restart to take effect (UAC, Winsock reset)
- Group Policy may override registry settings in managed environments
- Tamper Protection may block Defender changes
- Services protected by anti-malware may resist changes

## Security Notes

- Script does not write to disk when run via iex
- All changes use standard Windows commands
- No external dependencies or network calls (except initial download)
- Review changes in domain/enterprise environments before deployment

## References

- Microsoft Privacy Settings: https://learn.microsoft.com/en-us/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services
- Capability Access Manager: https://learn.microsoft.com/en-us/windows/privacy/
- Service Management: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/set-service
- Netsh Firewall Commands: https://learn.microsoft.com/en-us/windows-server/networking/technologies/netsh/netsh-contexts