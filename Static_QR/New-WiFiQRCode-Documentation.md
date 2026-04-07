# New-WiFiQRCode.ps1

PowerShell script to generate static WiFi QR codes on Windows. The QR image is self-contained, has no dependency on external services, and does not expire.

## Problem

Many online QR generators produce dynamic QR codes that encode a redirect URL to their server instead of encoding the WiFi credentials directly into the image. When the link expires, the QR code stops working even though the WiFi password has not changed.

This script generates a static QR code where the WiFi connection string is embedded directly in the QR pattern using the QRCoder .NET library. No external service is involved.

## Requirements

| Requirement | Detail |
|-------------|--------|
| PowerShell | 5.1 or later (built into Windows 10/11) |
| Internet | Required on first run only to download the QRCoder NuGet package |
| Admin rights | Not required |

The script automatically installs the QRCoder NuGet package on first run. Subsequent runs use the cached package.

## Usage

### Interactive Mode

```powershell
.\New-WiFiQRCode.ps1
```

The script prompts for SSID and password. The QR image is saved to the Desktop as `WiFi-QR-<SSID>.png`.

### Parameterised Mode

```powershell
.\New-WiFiQRCode.ps1 -SSID "OfficeGuest" -Password "Welcome2025!" -OutputPath "C:\Temp\wifi-qr.png"
```

### All Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| -SSID | String | Prompted | WiFi network name, exact and case-sensitive |
| -Password | String | Prompted | WiFi password in plaintext |
| -AuthType | String | WPA | Authentication type: `WPA`, `WEP`, or `nopass` |
| -Hidden | Bool | $false | Set to `$true` if the SSID is hidden |
| -OutputPath | String | Desktop\WiFi-QR-\<SSID\>.png | Full path for the output PNG |
| -PixelsPerModule | Int | 20 | Size of each QR module in pixels. Higher values produce larger images |

### iex Execution from IT-Scripts Toolbox

If added to the IT-Scripts repository, the script can be run remotely:

```powershell
iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Utils/WiFi-QR/New-WiFiQRCode.ps1")
```

## What the Script Does

1. Prompts for or accepts SSID and password as parameters
2. Builds the WiFi URI string: `WIFI:T:WPA;S:<SSID>;P:<Password>;H:false;;`
3. Installs the QRCoder .NET library via NuGet if not already present
4. Generates a PNG QR code image using QRCoder with high error correction (Level H)
5. Saves the image to the specified output path
6. Optionally opens the image for immediate verification

## Verification After Generation

Scan the generated QR code with a phone camera before printing:

| Check | Expected Result |
|-------|----------------|
| Phone shows WiFi join prompt | Static QR, correct |
| Phone opens a browser URL | Something went wrong, regenerate |
| SSID matches intended network | Case-sensitive match confirmed |
| Tapping Connect/Join works | Password is correct |

## Adding to IT-Scripts Toolbox

### Step 1: Create Folder

```powershell
cd "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts"
mkdir "Utils\WiFi-QR"
```

### Step 2: Copy Script

```powershell
Copy-Item ".\New-WiFiQRCode.ps1" -Destination ".\Utils\WiFi-QR\"
```

### Step 3: Update Menu.ps1

Add to the Utilities category in `$Script:MenuStructure`:

```powershell
@{ Name = "Generate WiFi QR Code"; Path = "Utils/WiFi-QR/New-WiFiQRCode.ps1"; Description = "Generate a static WiFi QR code PNG from SSID and password" }
```

### Step 4: Commit and Push

```powershell
git add -A
git commit -m "Add: WiFi QR code generator to Utilities"
git push
```

## How QRCoder is Installed

The script uses the QRCoder .NET library (MIT licensed) to generate QR codes without any external web service.

On first run:

1. Registers the NuGet package source if not present
2. Installs the NuGet package provider if not present
3. Installs the QRCoder package via `Install-Package`
4. Locates and loads the `QRCoder.dll` from the package directory

On subsequent runs, the package is already installed and the DLL is loaded directly.

No admin rights are required. The package installs to the current user's package directory.

## WiFi URI Format Reference

```
WIFI:T:WPA;S:OfficeGuest;P:Welcome2025!;H:false;;
```

| Field | Value | Notes |
|-------|-------|-------|
| T | WPA | Use WPA for both WPA2 and WPA3 |
| S | SSID | Exact, case-sensitive |
| P | Password | Plaintext |
| H | false | true only if SSID is hidden |

Trailing `;;` is required by the specification.

## References

- WiFi URI Scheme Specification (ZXing Project): https://github.com/zxing/zxing/wiki/Barcode-Contents#wi-fi-network-config-wpa
- QRCoder .NET Library (GitHub): https://github.com/codebude/QRCoder
- QRCoder NuGet Package: https://www.nuget.org/packages/QRCoder
- Install-Package Documentation: https://learn.microsoft.com/en-us/powershell/module/packagemanagement/install-package
