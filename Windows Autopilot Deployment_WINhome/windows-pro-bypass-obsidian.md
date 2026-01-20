

1. [Problem Overview](#problem-overview)
2. [Solution Methods](#solution-methods)
3. [Method 1: ISO Modification (Recommended)](#method-1-iso-modification-recommended)
	1. [Why Both Files Are Required (Windows 11 24H2+)](#why-both-files-are-required-windows-11-24h2)
	2. [Step 1: Create Configuration Files](#step-1-create-configuration-files)
	3. [Step 2: Install Required Tools](#step-2-install-required-tools)
	4. [Step 3: Inject Files Using AnyBurn](#step-3-inject-files-using-anyburn)
	5. [Step 4: Verify (Optional)](#step-4-verify-optional)
	6. [Alternative: Ventoy Injection](#alternative-ventoy-injection)
4. [Method 2: Post-Install Upgrade (Workaround)](#method-2-post-install-upgrade-workaround)
	1. [Step 1: Bypass Network Requirement](#step-1-bypass-network-requirement)
	2. [Step 2: Complete OOBE with Local Account](#step-2-complete-oobe-with-local-account)
	3. [Step 3: Upgrade to Pro](#step-3-upgrade-to-pro)
	4. [Step 4: Configure Regional Settings](#step-4-configure-regional-settings)
	5. [Step 5: Run Windows Update (Optional but Recommended)](#step-5-run-windows-update-optional-but-recommended)
	6. [Step 6: Reset to OOBE](#step-6-reset-to-oobe)
5. [Configuration File Reference](#configuration-file-reference)
	1. [ei.cfg Options](#eicfg-options)
	2. [pid.txt Format](#pidtxt-format)
	3. [Generic Windows 11 Keys (Installation Only)](#generic-windows-11-keys-installation-only)
6. [BIOS Options (If Available)](#bios-options-if-available)
7. [Post-Reset Behaviour](#post-reset-behaviour)
8. [Troubleshooting](#troubleshooting)
	1. [ei.cfg/pid.txt Not Working](#eicfgpidtxt-not-working)
	2. [Autopilot Still Fails After Pro Upgrade](#autopilot-still-fails-after-pro-upgrade)
	3. ["This account can't be used with this edition"](#this-account-cant-be-used-with-this-edition)
9. [References](#references)

# Windows 11 Pro Installation - Bypassing BIOS Embedded Home Key

Guide for installing Windows 11 Pro on devices with OEM Home edition keys embedded in BIOS/UEFI firmware.

## Problem Overview

Many OEM devices (Dell, HP, Lenovo, etc.) have Windows Home product keys embedded in the BIOS MSDM table. During Windows Setup, this key is detected automatically and forces Home edition installation, bypassing edition selection entirely.

This causes issues for:
- Autopilot deployments (Home cannot join Entra ID)
- Enterprise environments requiring Pro features
- Domain join scenarios

## Solution Methods

| Method | Best For | Requires |
|--------|----------|----------|
| ISO Modification | Future deployments, multiple devices | AnyBurn or 7-Zip, ISO access |
| Post-Install Upgrade | Immediate need, single device | Time for reset cycle |

---

## Method 1: ISO Modification (Recommended)

Inject ei.cfg and pid.txt into the Windows ISO to force Pro edition selection.

### Why Both Files Are Required (Windows 11 24H2+)

| Windows Version | Requirement |
|-----------------|-------------|
| Pre-24H2 | ei.cfg alone worked |
| 24H2+ | ei.cfg + pid.txt required |

The "Modern Setup" in 24H2 treats clean installs like upgrades, checking BIOS keys first. The pid.txt forces the installer to use the specified key instead.

### Step 1: Create Configuration Files

Run in PowerShell:

```powershell
# ei.cfg - Forces Pro edition
@"
[EditionID]
Pro
[Channel]
_Default
[VL]
0
"@ | Out-File "$env:USERPROFILE\Desktop\ei.cfg" -Encoding ASCII

# pid.txt - Generic Pro installer key
@"
[PID]
Value=VK7JG-NPHTM-C97JM-9MPGT-3V66T
"@ | Out-File "$env:USERPROFILE\Desktop\pid.txt" -Encoding ASCII

Write-Host "Files created on Desktop" -ForegroundColor Green
```

### Step 2: Install Required Tools

7-Zip (for viewing) and AnyBurn (for editing):

```powershell

# Install Anyburn

winget install --id PowerSoftware.AnyBurn

# Install 7-Zip
$url = "https://www.7-zip.org/a/7z2408-x64.exe"
$output = "$env:USERPROFILE\Desktop\7z-setup.exe"
Invoke-WebRequest -Uri $url -OutFile $output
Start-Process -FilePath $output -ArgumentList "/S" -Wait

# Install AnyBurn
winget install AnyBurn.AnyBurn
```

### Step 3: Inject Files Using AnyBurn

1. Open AnyBurn
2. Click "Edit image file"
3. Browse to Windows ISO (e.g., `Win11_25H2_English_x64.iso`)
4. Navigate to `sources` folder
5. Click Add > select `ei.cfg` from Desktop > Open
6. Click Add > select `pid.txt` from Desktop > Open
7. Click Next
8. Select "Save as a new file" or "Overwrite original"
9. Click "Create Now"
10. Wait for completion

### Step 4: Verify (Optional)

Using 7-Zip:

1. Right-click modified ISO > 7-Zip > Open archive
2. Navigate to `sources`
3. Confirm `ei.cfg` and `pid.txt` are present

### Alternative: Ventoy Injection

If using Ventoy USB boot, create injection folder structure:

```powershell
$usbDrive = "E:"  # Your Ventoy USB letter
$isoName = "Win11_25H2_English_x64"  # ISO name without .iso

$path = "$usbDrive\ventoy\injection\$isoName\sources"
New-Item -ItemType Directory -Path $path -Force

@"
[EditionID]
Pro
[Channel]
_Default
[VL]
0
"@ | Out-File "$path\ei.cfg" -Encoding ASCII

@"
[PID]
Value=VK7JG-NPHTM-C97JM-9MPGT-3V66T
"@ | Out-File "$path\pid.txt" -Encoding ASCII

Write-Host "Ventoy injection files created" -ForegroundColor Green
```

Note: YUMI's Ventoy integration may not support injection. Standard Ventoy does.

---

## Method 2: Post-Install Upgrade (Workaround)

Install Windows Home, bypass OOBE, upgrade to Pro, then reset.

### Step 1: Bypass Network Requirement

At OOBE network screen, press Shift+F10 to open Command Prompt:

```cmd
start ms-cxh:localonly
```

This immediately triggers the local account creation flow without requiring a reboot.

Note: The older `oobe\bypassnro` command no longer works on recent Windows 11 builds.

### Step 2: Complete OOBE with Local Account

1. Local account creation screen appears
2. Create local account (any name/password)
3. Complete remaining OOBE screens
4. Reach desktop

### Step 3: Upgrade to Pro

Open PowerShell as Administrator:

```powershell
slmgr /ipk VK7JG-NPHTM-C97JM-9MPGT-3V66T
```

Wait for confirmation dialog. Device is now Pro (unactivated).

### Step 4: Configure Regional Settings

```powershell
# Set timezone to GMT/UK
Set-TimeZone -Id "GMT Standard Time"

# Set system locale to UK English
Set-WinSystemLocale -SystemLocale en-GB

# Set region to UK
Set-WinHomeLocation -GeoId 242

# Set culture
Set-Culture -CultureInfo en-GB

# Set display language override
Set-WinUILanguageOverride -Language en-GB
```

Restart required for locale changes.

### Step 5: Run Windows Update (Optional but Recommended)

Apply all updates before reset. These will be preserved with local reinstall.

```powershell
# Check for updates
winget upgrade --all --accept-package-agreements --accept-source-agreements
```

Or via Settings > Windows Update.

### Step 6: Reset to OOBE

1. Settings > System > Recovery
2. Reset this PC
3. Select "Remove everything"
4. Select "Local reinstall" (preserves Pro + updates)
5. Select "Just remove my files"
6. Confirm and reset

Device reboots into OOBE with Pro edition. Autopilot will now detect and work.

---

## Configuration File Reference

### ei.cfg Options

```ini
[EditionID]
Pro
[Channel]
_Default
[VL]
0
```

| Field | Options | Notes |
|-------|---------|-------|
| EditionID | Pro, Home, Education, Enterprise, or blank | Blank shows selection screen |
| Channel | Retail, _Default, OEM, Volume | _Default recommended |
| VL | 0 or 1 | 0 = not volume license |

### pid.txt Format

```ini
[PID]
Value=XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
```

### Generic Windows 11 Keys (Installation Only)

| Edition | Key |
|---------|-----|
| Pro | VK7JG-NPHTM-C97JM-9MPGT-3V66T |
| Home | YTMG3-N6DKC-DKB77-7M9GH-8HVX7 |
| Enterprise | NPPR9-FWDCX-D2C8J-H872K-2YT43 |
| Education | NW6C2-QMPVW-D7KKK-3GKT6-VCFB2 |

These keys select edition only - do not activate Windows. Activation occurs via actual license, digital entitlement, or Intune policy.

---

## BIOS Options (If Available)

Some BIOS/UEFI have option to disable embedded key:

| Manufacturer | Location | Setting Name |
|--------------|----------|--------------|
| Dell | Advanced > System Configuration | OS Key Provisioning |
| HP | Advanced > System Options | Windows OS License Key |
| Lenovo | Security or Advanced | OS Optimized Defaults |
| ASUS | Advanced > Windows OS Configuration | Windows License / MSDM |

If disabled, edition selection appears without needing ei.cfg/pid.txt.

Note: Consumer devices often lock this setting. Business-class machines (OptiPlex, ProDesk, ThinkCentre) more likely to expose it.

---

## Post-Reset Behaviour

| Reset Type | Pro Preserved | Updates Preserved |
|------------|---------------|-------------------|
| Local reinstall | Yes | Yes |
| Cloud download | May revert to Home | No |
| Fresh USB install | Reverts to Home | No |

To permanently preserve Pro after any reset, link to Microsoft account:

1. Settings > Accounts > Sign in with Microsoft account
2. Settings > System > Activation
3. Confirm "Windows is activated with a digital license linked to your Microsoft account"

---

## Troubleshooting

### ei.cfg/pid.txt Not Working

- Verify files are in `sources` folder (not root)
- Check file encoding is ASCII (not UTF-8 with BOM)
- Confirm exact filename (case-sensitive on some systems)
- For 24H2+, both files required

### Autopilot Still Fails After Pro Upgrade

- Reset was not "Local reinstall" (used Cloud download)
- Pro upgrade didn't complete before reset
- Profile not assigned in Intune

### "This account can't be used with this edition"

- Windows Home cannot join Entra ID
- Must upgrade to Pro before Autopilot enrolment

---

## References

- Microsoft Learn - ei.cfg and pid.txt: https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-edition-configuration-and-product-id-files--eicfg-and-pidtxt
- Windows 11 Forum - ei.cfg with 24H2: https://www.elevenforum.com/t/windows-11-pro-install-defaults-to-home-hp-te01-5364-sk-hynix-ssd-ei-cfg-ignored.39116/
- WinReflection - Edition Force Guide: https://www.winreflection.com/windows-11-24h2-edition-force-gpos-repair/
