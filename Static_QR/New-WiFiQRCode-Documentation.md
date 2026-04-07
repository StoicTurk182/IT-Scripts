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

### Interactive Mode (Recommended)

```powershell
.\New-WiFiQRCode.ps1
```

The script prompts for SSID (plaintext) and password (masked input via `Read-Host -AsSecureString`). The QR image is saved to the Desktop as `WiFi-QR-<SSID>.png`.

### Parameterised Mode

```powershell
.\New-WiFiQRCode.ps1 -SSID "OfficeGuest" -Password (ConvertTo-SecureString "Welcome2025!" -AsPlainText -Force) -OutputPath "C:\Temp\wifi-qr.png"
```

The `-Password` parameter accepts a `[SecureString]` object. Use `ConvertTo-SecureString` to convert a plaintext string when passing as a parameter.

Note: passing a password on the command line means it is captured in PowerShell session history. Interactive mode avoids this. If using parameterised mode in a script, store the password in a `SecureString` variable rather than inline plaintext where possible.

### All Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| -SSID | String | Prompted | WiFi network name, exact and case-sensitive |
| -Password | SecureString | Prompted (masked) | WiFi password as SecureString |
| -AuthType | String | WPA | Authentication type: `WPA`, `WEP`, or `nopass` |
| -Hidden | Bool | $false | Set to `$true` if the SSID is hidden |
| -OutputPath | String | Desktop\WiFi-QR-\<SSID\>.png | Full path for the output PNG |
| -PixelsPerModule | Int | 20 | Size of each QR module in pixels. Higher values produce larger images |

### iex Execution from IT-Scripts Toolbox

If added to the IT-Scripts repository, the script can be run remotely:

```powershell
iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Utils/WiFi-QR/New-WiFiQRCode.ps1")
```

When executed via `iex`, the script runs in interactive mode and prompts for SSID and password. The password prompt is masked.

## Password Handling

The WiFi URI specification requires the password in plaintext inside the QR string. The QR image itself is inherently the password in visual form, so the final output is always plaintext. What the script controls is how the password is handled on its way there.

| Stage | Protection |
|-------|-----------|
| Interactive input | `Read-Host -AsSecureString` masks console input and prevents capture in PSReadLine history |
| Parameter input | `[SecureString]` type enforced; plaintext string cannot be passed directly |
| Conversion | SecureString is converted to plaintext only at the point of building the WiFi URI string |
| Post-generation | Plaintext password variable is set to `$null` and the SecureString is disposed via `.Dispose()` |
| Console output | All log lines mask the password as `****` |
| WiFi string | Set to `$null` after QR generation is complete |

### Limitations

These are inherent to the WiFi QR code format and cannot be mitigated by the script:

- The QR image contains the password in plaintext. Anyone who scans the QR or decodes the image has the password.
- The WiFi URI specification does not support encrypted or hashed passwords.
- If the password is passed on the command line (parameterised mode), it is captured in the PowerShell session history. Use interactive mode to avoid this.

## What the Script Does

1. Prompts for or accepts SSID and password (SecureString) as parameters
2. Converts the SecureString to plaintext at point of use
3. Builds the WiFi URI string: `WIFI:T:WPA;S:<SSID>;P:<Password>;H:false;;`
4. Clears the plaintext password from memory
5. Installs the QRCoder .NET library via NuGet if not already present
6. Generates a PNG QR code image using QRCoder with high error correction (Level H)
7. Saves the image to the specified output path
8. Clears the WiFi string from memory and disposes the SecureString
9. Optionally opens the image for immediate verification

## Verification After Generation

Scan the generated QR code with a phone camera before printing:

| Check | Expected Result |
|-------|----------------|
| Phone shows WiFi join prompt | Static QR, correct |
| Phone opens a browser URL | Something went wrong, regenerate |
| SSID matches intended network | Case-sensitive match confirmed |
| Tapping Connect/Join works | Password is correct |

## WPA3 Compatibility

The `T:WPA` value in the WiFi URI string is a generic flag that tells the device a passphrase is required. The device negotiates the actual protocol (WPA2-PSK or WPA3-SAE) with the access point during connection. The QR format does not need to distinguish between WPA2 and WPA3.

| Network Type | QR Code Works | Notes |
|-------------|---------------|-------|
| WPA2-Personal (PSK) | Yes | Standard passphrase-based authentication |
| WPA3-Personal (SAE) | Yes | Still uses a passphrase; SAE replaces the 4-way handshake |
| WPA2/WPA3 Transitional | Yes | Device negotiates appropriate protocol |
| WPA2-Enterprise (802.1X) | No | Uses RADIUS/certificates, not a passphrase |
| WPA3-Enterprise (802.1X) | No | Uses RADIUS/certificates, not a passphrase |
| OWE (Enhanced Open) | No | No password; encryption is automatic |

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
| P | Password | Plaintext (required by specification) |
| H | false | true only if SSID is hidden |

Trailing `;;` is required by the specification.

## Change Log

| Version | Date | Change |
|---------|------|--------|
| 1.0 | 2026-04-07 | Initial release |
| 1.1 | 2026-04-07 | Password input changed from plaintext string to SecureString. Interactive prompt uses `Read-Host -AsSecureString`. Plaintext password converted only at point of use and cleared from memory immediately after building WiFi string. SecureString disposed on completion. |

## References

- WiFi URI Scheme Specification (ZXing Project): https://github.com/zxing/zxing/wiki/Barcode-Contents#wi-fi-network-config-wpa
- QRCoder .NET Library (GitHub): https://github.com/codebude/QRCoder
- QRCoder NuGet Package: https://www.nuget.org/packages/QRCoder
- SecureString Best Practices: https://learn.microsoft.com/en-us/dotnet/api/system.security.securestring
- Install-Package Documentation: https://learn.microsoft.com/en-us/powershell/module/packagemanagement/install-package
