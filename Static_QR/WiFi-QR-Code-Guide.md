# WiFi QR Code Guide

Generate a scannable QR code that allows visitors to join a WiFi network without manually entering credentials. The QR code is a static image encoding a standard URI string and does not expire.

1. [WiFi URI Format](#wifi-uri-format)
2. [Example](#example)
3. [Generating the QR Code](#generating-the-qr-code)
	1. [Python (qrcode library)](#python-qrcode-library)
	2. [PowerShell (QRCoder .NET library)](#powershell-qrcoder-net-library)
	3. [LibreOffice / Word](#libreoffice--word)
4. [Printing and Deployment](#printing-and-deployment)
5. [Why a Static Password Still Matters](#why-a-static-password-still-matters)
6. [QR Code Expiry](#qr-code-expiry)
7. [Alternative Approaches](#alternative-approaches)
8. [References](#references)


## WiFi URI Format

The WiFi QR code uses an open URI scheme recognised natively by iOS (Camera app) and Android (Camera or WiFi settings). The string to encode is:

```
WIFI:T:WPA;S:YourSSID;P:YourPassword;H:false;;
```

| Field | Value | Notes |
|-------|-------|-------|
| T | WPA, WEP, nopass, or blank | Use `WPA` for both WPA2 and WPA3 |
| S | SSID name | Exact match, case-sensitive |
| P | Password | Plaintext passphrase |
| H | true / false | Whether the SSID is hidden |

The trailing double semicolon `;;` is required by the specification.

## Example

For a guest network with SSID `CompanyGuest` and password `Welcome2025!`:

```
WIFI:T:WPA;S:CompanyGuest;P:Welcome2025!;H:false;;
```

For a hidden network:

```
WIFI:T:WPA;S:CompanyGuest;P:Welcome2025!;H:true;;
```

## Generating the QR Code

Use an offline method to avoid exposing the WiFi password to third-party websites.

### Python (qrcode library)

Install:

```bash
pip install qrcode[pil]
```

Generate from command line:

```bash
qr "WIFI:T:WPA;S:CompanyGuest;P:Welcome2025!;H:false;;" > wifi-qr.png
```

Generate from script with more control:

```python
import qrcode

wifi_string = "WIFI:T:WPA;S:CompanyGuest;P:Welcome2025!;H:false;;"

img = qrcode.make(wifi_string)
img.save("wifi-qr.png")
```

### PowerShell (QRCoder .NET library)

```powershell
Install-Module -Name QRCodeGenerator -Scope CurrentUser

New-QRCodeURI -URI "WIFI:T:WPA;S:CompanyGuest;P:Welcome2025!;H:false;;" -OutPath "wifi-qr.png"
```

### LibreOffice / Word

Generate the QR image using one of the methods above, then insert the image into a document for printing.

## Printing and Deployment

- Print the QR code on a card or laminated sign for reception desks, meeting rooms, or communal areas.
- Include the SSID and password in plain text below the QR code for devices that cannot scan (older laptops, devices without cameras).
- Size the QR code at a minimum of 3cm x 3cm for reliable scanning at arm's length.

## Why a Static Password Still Matters

A WiFi QR code encodes the password in plaintext, which is functionally identical to printing it on a card. The password is not there to restrict access — it is there to encrypt traffic over the air.

| Configuration | Encryption | Risk |
|---------------|------------|------|
| Open network (no password) | None | All traffic between client and AP is unencrypted and can be captured with a packet sniffer |
| Static PSK (WPA2/3) | Per-session pairwise keys derived during 4-way handshake | Traffic is encrypted even though the PSK is shared publicly |
| Captive portal on open network | None (portal is layer 3, not layer 2) | Traffic is still unencrypted despite the portal |

A static PSK on a visitor network that is VLAN-isolated from internal resources is the pragmatic approach for most environments.

## QR Code Expiry

QR codes do not expire. A QR code is a static image encoding a fixed string. If the QR code stops working after a period of time, the cause is one of the following:

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| QR scans but fails to connect after 24-48 hours | PSK auto-rotation is enabled on the wireless controller | Disable password rotation on the guest SSID |
| QR scans but network not found | SSID has been renamed or disabled | Regenerate the QR with the correct SSID |
| QR does not scan at all | Print quality or size too small | Reprint at minimum 3cm x 3cm, high contrast black on white |

## Alternative Approaches

If per-user access control or logging is required rather than a shared password:

| Method | How It Works | Requires |
|--------|-------------|----------|
| Captive portal with voucher codes | Each visitor gets a unique time-limited code | Wireless controller with hotspot/voucher support (UniFi Hotspot Manager, Meraki Splash, Aruba Guest) |
| Enhanced Open (OWE) | Encrypts traffic without any password, no user interaction | Wi-Fi 6 / OWE-capable clients and APs |
| Private PSK (PPSK) | Unique per-user pre-shared key | Aruba, Ruckus, or third-party RADIUS with PPSK support |

## References

- WiFi URI Scheme Specification (ZXing Project): https://github.com/zxing/zxing/wiki/Barcode-Contents#wi-fi-network-config-wpa
- Python qrcode Library: https://pypi.org/project/qrcode/
- WPA2 4-Way Handshake (IEEE 802.11i): https://standards.ieee.org/standard/802_11i-2004.html
- Enhanced Open / OWE (RFC 8110): https://datatracker.ietf.org/doc/html/rfc8110
