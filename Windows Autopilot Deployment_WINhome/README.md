# Windows 11 Pro Bypass - Quick Reference

**Date:** 20/01/2026

---

## Pre-Requisites

Check manufacturer website for specific NVME and Network drivers - missing drivers can significantly extend deployment time.

---

## Method 1: ISO Modification

### AnyBurn Process

1. Select **Edit ISO**
2. Navigate to `sources` folder
3. Click **Add Items** > select `ei.cfg` and `pid.txt`
4. Click **Burn**
5. Select **Overwrite**
6. Confirm **YES**

### Create Files via PowerShell

```powershell
# Load function into memory
iex (irm https://your-repo/script.ps1)

# Run targeting USB drive
New-WinConfig -TargetPath "D:\sources"
```

---

## Method 2: OOBE Bypass (If ISO Method Fails)

### Step 1: Open Terminal

Press **Shift + F10** at OOBE screen

### Step 2: Bypass Network Requirement

```cmd
start ms-cxh:localonly
```

### Step 3: Create Local User

Complete local account setup

### Step 4: Upgrade to Pro

```powershell
slmgr /ipk VK7JG-NPHTM-C97JM-9MPGT-3V66T
```

### Step 5: Run Updates

```powershell
winget upgrade --all
```

### Step 6: Fix Regional Settings

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

### Step 7: Reset to OOBE

Settings > System > Recovery > Reset this PC > Remove everything > **Local reinstall**

---

## Result

Device boots to OOBE with Pro edition - Autopilot will detect and work.

---

## Reference

See `windows-pro-bypass-obsidian.md` for detailed instructions.