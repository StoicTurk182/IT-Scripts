# HWiNFO Installation Guide

Quick reference for installing HWiNFO using Windows Package Manager (winget).

## Installation Command

```powershell
winget install --id REALiX.HWiNFO -e --silent --accept-package-agreements --accept-source-agreements --force
```

## About HWiNFO

HWiNFO (Hardware Information) is a professional system information and diagnostic tool that provides comprehensive hardware analysis, monitoring, and reporting for Windows systems. It is commonly used by IT professionals for hardware diagnostics, temperature monitoring, and system analysis.

Developer: REALiX
Official Website: https://www.hwinfo.com

## Command Parameters Explained

| Parameter | Purpose |
|-----------|---------|
| `--id REALiX.HWiNFO` | Specifies the exact package identifier from winget repository |
| `-e` or `--exact` | Matches the package ID exactly, preventing partial matches |
| `--silent` | Performs silent installation without user interaction |
| `--accept-package-agreements` | Automatically accepts package license agreements |
| `--accept-source-agreements` | Automatically accepts source repository agreements |
| `--force` | Forces installation even if package is already installed (reinstall/repair) |

## Use Cases

HWiNFO is particularly useful for:
- Hardware diagnostics and troubleshooting
- Real-time monitoring of system temperatures, voltages, and fan speeds
- Identifying hardware components and specifications
- Stress testing and system stability analysis
- Generating detailed hardware reports

## Verification

After installation, verify HWiNFO is installed:

```powershell
winget list --id REALiX.HWiNFO
```

## Alternative Installation Methods

If winget is unavailable or fails, HWiNFO can be downloaded directly from the official website:
https://www.hwinfo.com/download/

## Version Information

Winget automatically installs the latest stable version available in the Microsoft winget repository. To check for updates:

```powershell
winget upgrade --id REALiX.HWiNFO
```

## Uninstallation

To remove HWiNFO:

```powershell
winget uninstall --id REALiX.HWiNFO
```

## Notes

HWiNFO offers two editions:
- HWiNFO32 - for 32-bit systems (legacy)
- HWiNFO64 - for 64-bit systems (recommended)

The winget package installs the appropriate version based on system architecture.

## Portable vs Installed Version

The winget installation provides the installed version. For portable deployments, download the portable version from the official website which does not require installation and can run from USB drives.

## References

- HWiNFO Official Website: https://www.hwinfo.com
- Windows Package Manager Documentation: https://learn.microsoft.com/en-us/windows/package-manager/winget/
- Winget Package Repository: https://github.com/microsoft/winget-pkgs
- HWiNFO Package Details: https://winget.run/pkg/REALiX/HWiNFO