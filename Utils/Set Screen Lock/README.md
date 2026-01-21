# Windows Auto-Lock Not Working - Troubleshooting Guide

Troubleshooting steps when Windows 10/11 fails to automatically lock the screen after a period of inactivity.

## Overview

Windows auto-lock functionality depends on multiple settings working together. If any of these are misconfigured, the screen will not lock automatically. This guide covers GUI settings, Group Policy, Registry, and PowerShell verification methods.

## Priority Fix: Legacy Screen Saver Settings (Master Switch)

Since "Default" in Windows is actually scattered across three different menus, the simplest, most direct way to force standard auto-lock behaviour is to use the Legacy Screen Saver Settings. This acts as a "master switch" that overrides most other power glitches.

### Method A: The Magic Command (Fastest Manual Way)

This method bypasses the confusing modern Settings menus and goes straight to the control panel logic that forces the lock.

1. Press `Win + R` to open the Run box
2. Paste this exact command and press Enter:

```
control desk.cpl,,@screensaver
```

Note: Include the two commas.

3. In the window that opens, set these 3 standard defaults:

| Setting | Value | Notes |
|---------|-------|-------|
| Screen saver | "(None)" or any option | The selection does not affect lock behaviour |
| Wait | 5 minutes | Standard default timeout |
| On resume, display logon screen | Checked | Critical setting - this forces the lock |

4. Click **OK**

### Method B: PowerShell Force Standard Script (Per-User)

Sets the current user's screensaver configuration to the standard 5-minute lock without menu navigation.

1. Right-click Start button and select **Terminal** or **PowerShell**
2. Paste the following block and press Enter:

```powershell
# Force "On resume, display logon screen" to ON (1)
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name ScreenSaverIsSecure -Value 1

# Set the inactivity timer to 5 minutes (300 seconds)
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name ScreenSaveTimeOut -Value 300

# Ensure the screensaver logic is Active (even if set to None)
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name ScreenSaveActive -Value 1

# Apply changes immediately (forces Windows to read the new registry keys)
rundll32.exe user32.dll, UpdatePerUserSystemParameters
Write-Host "Auto-Lock set to standard 5-minute default." -ForegroundColor Green
```

### Method C: PowerShell Security Policy Script (Machine-Wide)

Sets the machine-level "Interactive Logon: Machine Inactivity Limit" security policy. Requires administrator privileges and a restart.

1. Right-click Start button and select **Terminal (Admin)** or **PowerShell (Admin)**
2. Paste the following block and press Enter:

```powershell
# Set the "Interactive Logon: Machine Inactivity Limit" to 5 minutes (300 seconds)
$Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$Name = "InactivityTimeoutSecs"
$Value = 300 # Change this number for different seconds (e.g. 600 for 10 mins)
if (!(Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force
Write-Host "Success: Security Lock Timer set to 5 minutes." -ForegroundColor Green
Write-Host "Please RESTART your computer for this security policy to take effect." -ForegroundColor Yellow
```

| Method | Scope | Requires Admin | Requires Restart |
|--------|-------|----------------|------------------|
| Method B (Per-User) | Current user only | No | No |
| Method C (Machine-Wide) | All users on device | Yes | Yes |

### Method D: Combined Script (User + Machine)

This script configures both the per-user screensaver settings and the machine-wide security policy in a single execution. It automatically detects admin privileges and applies machine settings only when elevated.

Save as `Set-AutoLock.ps1`:

```powershell
<#
.SYNOPSIS
    Sets the Windows Auto-Lock timeout for both Current User and Local Machine.
    Compatible with IEX (Invoke-Expression) and local execution.
.PARAMETER Minutes
    The number of minutes to wait before locking. Default is 5.
#>
param (
    [int]$Minutes = 5
)

# Convert Minutes to Seconds
$Seconds = $Minutes * 60

Write-Host "----------------------------------------------------" -ForegroundColor Cyan
Write-Host " Config using: $Minutes Minutes ($Seconds Seconds)" -ForegroundColor Cyan
Write-Host "----------------------------------------------------" -ForegroundColor Gray

# --- PART 1: Current User Settings (The "Soft" Lock) ---
# This sets the screensaver timeout and forces the password requirement on resume.
try {
    Write-Host "Setting Current User (Screensaver) config..." -NoNewline
    $UserPath = "HKCU:\Control Panel\Desktop"
    
    # 1. Enable Screensaver logic (even if set to "None", this activates the timer)
    Set-ItemProperty -Path $UserPath -Name "ScreenSaveActive" -Value "1" -Type String -Force
    # 2. Force 'On resume, display logon screen'
    Set-ItemProperty -Path $UserPath -Name "ScreenSaverIsSecure" -Value "1" -Type String -Force
    # 3. Set the timeout duration
    Set-ItemProperty -Path $UserPath -Name "ScreenSaveTimeOut" -Value "$Seconds" -Type String -Force
    
    # Refresh user parameters immediately
    [void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
    rundll32.exe user32.dll, UpdatePerUserSystemParameters
    Write-Host " [OK]" -ForegroundColor Green
}
catch {
    Write-Host " [FAILED] - $_" -ForegroundColor Red
}

# --- PART 2: Local Machine Security Policy (The "Hard" Lock) ---
# This sets the 'Interactive logon: Machine inactivity limit'.
# Requires ADMIN privileges.
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if ($IsAdmin) {
    try {
        Write-Host "Setting Machine Policy (Inactivity Limit)..." -NoNewline
        $MachinePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        
        if (!(Test-Path $MachinePath)) { New-Item -Path $MachinePath -Force | Out-Null }
        
        # Set InactivityTimeoutSecs
        Set-ItemProperty -Path $MachinePath -Name "InactivityTimeoutSecs" -Value $Seconds -Type DWord -Force
        Write-Host " [OK]" -ForegroundColor Green
    }
    catch {
        Write-Host " [FAILED] - $_" -ForegroundColor Red
    }
}
else {
    Write-Host "Skipping Machine Policy (Requires 'Run as Administrator')" -ForegroundColor Yellow
}

Write-Host "----------------------------------------------------" -ForegroundColor Gray
Write-Host "Done. Auto-lock set to $Minutes minutes." -ForegroundColor Cyan
```

#### Running the Combined Script

**Option 1: Run Local File**

Set to 10 minutes:

```powershell
.\Set-AutoLock.ps1 -Minutes 10
```

Use the default (5 minutes):

```powershell
.\Set-AutoLock.ps1
```

**Option 2: Run via IEX (Web/Remote)**

If hosting the script on GitHub or an internal server, run directly into memory.

Method A - Uses default 5 minutes:

```powershell
irm http://your-server/Set-AutoLock.ps1 | iex
```

Method B - Pass specific minutes (e.g., 15):

```powershell
# Define the arg, then download and invoke
$script = irm http://your-server/Set-AutoLock.ps1
Invoke-Command -ScriptBlock ([ScriptBlock]::Create($script)) -ArgumentList 15
```

Note: For `ArgumentList` to work with IEX, the script uses a `param` block. For more complex IEX scenarios, wrap the logic in a function inside the script and call the function after IEX.

### Method D: Combined Auto-Lock Script (Recommended)

This script sets both current user and machine-wide settings in one execution. It automatically detects admin privileges and applies machine policy only when running elevated.

Save as `Set-AutoLock.ps1`:

```powershell
<#
.SYNOPSIS
    Sets the Windows Auto-Lock timeout for both Current User and Local Machine.
    Compatible with IEX (Invoke-Expression) and local execution.
.PARAMETER Minutes
    The number of minutes to wait before locking. Default is 5.
#>
param (
    [int]$Minutes = 5
)

# Convert Minutes to Seconds
$Seconds = $Minutes * 60

Write-Host "----------------------------------------------------" -ForegroundColor Cyan
Write-Host " Config using: $Minutes Minutes ($Seconds Seconds)" -ForegroundColor Cyan
Write-Host "----------------------------------------------------" -ForegroundColor Gray

# --- PART 1: Current User Settings (The "Soft" Lock) ---
# This sets the screensaver timeout and forces the password requirement on resume.
try {
    Write-Host "Setting Current User (Screensaver) config..." -NoNewline
    $UserPath = "HKCU:\Control Panel\Desktop"
    
    # 1. Enable Screensaver logic (even if set to "None", this activates the timer)
    Set-ItemProperty -Path $UserPath -Name "ScreenSaveActive" -Value "1" -Type String -Force
    # 2. Force 'On resume, display logon screen'
    Set-ItemProperty -Path $UserPath -Name "ScreenSaverIsSecure" -Value "1" -Type String -Force
    # 3. Set the timeout duration
    Set-ItemProperty -Path $UserPath -Name "ScreenSaveTimeOut" -Value "$Seconds" -Type String -Force
    
    # Refresh user parameters immediately
    [void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
    rundll32.exe user32.dll, UpdatePerUserSystemParameters
    Write-Host " [OK]" -ForegroundColor Green
}
catch {
    Write-Host " [FAILED] - $_" -ForegroundColor Red
}

# --- PART 2: Local Machine Security Policy (The "Hard" Lock) ---
# This sets the 'Interactive logon: Machine inactivity limit'.
# Requires ADMIN privileges.
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if ($IsAdmin) {
    try {
        Write-Host "Setting Machine Policy (Inactivity Limit)..." -NoNewline
        $MachinePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        
        if (!(Test-Path $MachinePath)) { New-Item -Path $MachinePath -Force | Out-Null }
        
        # Set InactivityTimeoutSecs
        Set-ItemProperty -Path $MachinePath -Name "InactivityTimeoutSecs" -Value $Seconds -Type DWord -Force
        Write-Host " [OK]" -ForegroundColor Green
    }
    catch {
        Write-Host " [FAILED] - $_" -ForegroundColor Red
    }
}
else {
    Write-Host "Skipping Machine Policy (Requires 'Run as Administrator')" -ForegroundColor Yellow
}

Write-Host "----------------------------------------------------" -ForegroundColor Gray
Write-Host "Done. Auto-lock set to $Minutes minutes." -ForegroundColor Cyan
```

#### Running the Combined Script

**Option 1: Run Local File**

Set to 10 minutes:

```powershell
.\Set-AutoLock.ps1 -Minutes 10
```

Use default (5 minutes):

```powershell
.\Set-AutoLock.ps1
```

**Option 2: Run via IEX (Web/Remote)**

If hosting the script on GitHub or an internal server, run directly into memory.

Method A - Uses default 5 minutes:

```powershell
irm http://your-server/Set-AutoLock.ps1 | iex
```

Method B - Pass specific minutes (e.g., 15):

```powershell
# Define the arg, then download and invoke
$script = irm http://your-server/Set-AutoLock.ps1
Invoke-Command -ScriptBlock ([ScriptBlock]::Create($script)) -ArgumentList 15
```

Note: For `ArgumentList` to work with IEX, the script uses the `param` block. Alternatively, wrap the script in a function and call it after IEX.

### Fresh Windows Installation Defaults

For reference, these are the standard values on a fresh Windows installation:

| Setting | Battery | Plugged In |
|---------|---------|------------|
| Screen Off | 5 minutes | 10 minutes |
| Sleep | 15 minutes | 30 minutes |
| Lock Screen | Enabled | Enabled |
| Require Sign-in | When PC wakes from sleep | When PC wakes from sleep |

## Common Causes

| Cause | Description |
|-------|-------------|
| Sign-in options | "When should Windows require sign-in" set to Never |
| Dynamic Lock disabled | Bluetooth-based locking not configured or paired device in range |
| Screensaver settings | "On resume, display logon screen" unchecked |
| Group Policy | Machine inactivity limit not configured or set to 0 |
| Power settings | Screen/sleep timeouts not triggering lock |
| Presence Sensing | Modern devices may override lock based on proximity detection |
| Third-party apps | Applications preventing system idle state |

## Method 1: GUI Settings Verification

### Check Sign-in Options

1. Press `Win + I` to open Settings
2. Navigate to **Accounts** > **Sign-in options**
3. Under **Additional settings**, locate "If you've been away, when should Windows require you to sign in again?"
4. Set to **When PC wakes up from sleep** (not "Never")

### Disable Dynamic Lock (If Causing Issues)

Dynamic Lock automatically locks when a paired Bluetooth device leaves range. If enabled without a paired device, it can interfere with other lock mechanisms.

1. Settings > **Accounts** > **Sign-in options**
2. Scroll to **Dynamic lock**
3. Uncheck "Allow Windows to automatically lock your device when you're away"

### Configure Screensaver Lock

1. Press `Win + R`, type `control desk.cpl,,@screensaver` and press Enter
2. Select a screensaver or leave as "(None)"
3. Set **Wait** time (e.g., 5 minutes)
4. Check **On resume, display logon screen**
5. Click **Apply** > **OK**

### Verify Power Settings

1. Settings > **System** > **Power & battery** (Win11) or **Power & sleep** (Win10)
2. Set **Screen** timeout to desired value (e.g., 5 minutes)
3. Set **Sleep** timeout to desired value or "Never" if only screen lock is needed

### Presence Sensing (Windows 11 Compatible Devices Only)

Some modern devices with presence sensors can override lock behaviour.

1. Settings > **Privacy & security** > **Presence sensing**
2. Adjust or disable "Turn off my screen when I leave"
3. Adjust "Lock my device when I leave"

## Method 2: Group Policy Configuration

Requires Windows Pro, Enterprise, or Education editions. This is the most reliable method for enforcing auto-lock.

### Configure Machine Inactivity Limit

1. Press `Win + R`, type `gpedit.msc` and press Enter
2. Navigate to:

```
Computer Configuration > Windows Settings > Security Settings > Local Policies > Security Options
```

3. Double-click **Interactive logon: Machine inactivity limit**
4. Set value in seconds (e.g., 300 for 5 minutes, 600 for 10 minutes)
5. Click **OK**
6. Run `gpupdate /force` in elevated Command Prompt or restart

Valid range: 0 to 599940 seconds. Setting 0 disables the policy.

### Verify Screensaver GPO (Optional)

1. In Group Policy Editor, navigate to:

```
User Configuration > Administrative Templates > Control Panel > Personalization
```

2. Enable **Enable screen saver**
3. Enable **Password protect the screen saver**
4. Set **Screen saver timeout** to desired seconds

## Method 3: Registry Configuration

Use when Group Policy Editor is unavailable (Windows Home edition).

### Set Inactivity Timeout via Registry

1. Press `Win + R`, type `regedit` and press Enter
2. Navigate to:

```
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System
```

3. Look for DWORD value **InactivityTimeoutSecs**
4. If it does not exist, right-click > **New** > **DWORD (32-bit) Value**
5. Name it `InactivityTimeoutSecs`
6. Double-click, select **Decimal**, enter value in seconds (e.g., 600 for 10 minutes)
7. Restart computer

### Disable Lock Screen Completely (If Troubleshooting)

To verify whether the lock screen itself is disabled:

```
HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Personalization
```

Check for DWORD **NoLockScreen**:
- Value 1 = Lock screen disabled
- Value 0 or absent = Lock screen enabled

## Method 4: PowerShell Verification Commands

### Check Current Inactivity Timeout Registry Value

```powershell
Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "InactivityTimeoutSecs" -ErrorAction SilentlyContinue | Select-Object InactivityTimeoutSecs
```

### Set Inactivity Timeout (Requires Admin)

```powershell
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "InactivityTimeoutSecs" -Value 600 -Type DWord
```

### Check if Lock Screen is Disabled

```powershell
Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoLockScreen" -ErrorAction SilentlyContinue | Select-Object NoLockScreen
```

### Export Current Power Settings

```powershell
powercfg /query SCHEME_CURRENT
```

### Check Screensaver Settings

```powershell
Get-ItemProperty -Path "HKCU:\Control Panel\Desktop" | Select-Object ScreenSaveActive, ScreenSaverIsSecure, ScreenSaveTimeOut
```

### Force Group Policy Update

```powershell
gpupdate /force
```

## Method 5: Check for Interfering Applications

Some applications prevent Windows from entering idle state, which can block auto-lock.

### Check Power Requests

Run in elevated Command Prompt or PowerShell:

```powershell
powercfg /requests
```

This displays applications currently preventing sleep or display timeout. Look for entries under:
- DISPLAY
- SYSTEM
- AWAYMODE

### Common Culprits

| Application Type | Examples |
|-----------------|----------|
| Media players | VLC, Windows Media Player during playback |
| Video conferencing | Teams, Zoom when in meeting |
| Remote desktop | RDP sessions, TeamViewer |
| Presentation mode | PowerPoint slideshow |
| Download managers | Large file downloads |
| Backup software | Running backup operations |

## Troubleshooting Decision Tree

```
Screen not auto-locking?
│
├─ Check Settings > Accounts > Sign-in options
│  └─ "When should Windows require sign-in" = When PC wakes from sleep
│
├─ Check Screensaver settings
│  └─ "On resume, display logon screen" = Checked
│
├─ Check Group Policy (Pro/Enterprise)
│  └─ Interactive logon: Machine inactivity limit > 0
│
├─ Check Registry
│  └─ InactivityTimeoutSecs exists and > 0
│
├─ Run powercfg /requests
│  └─ Identify and close blocking applications
│
└─ Restart and test
```

## Enterprise Deployment Considerations

When deploying via Group Policy or Intune:

| Setting | Recommended Value | Notes |
|---------|-------------------|-------|
| Machine inactivity limit | 600-900 seconds | Balance security and productivity |
| Screensaver timeout | Match inactivity limit | Provides visual indication |
| Require sign-in on wake | Enabled | Enforces credential prompt |

For Intune deployments, note that the "Interactive Logon Machine Inactivity Limit" setting has known issues where it may be interpreted as boolean rather than integer, causing immediate lockouts. Use "Minutes of lock screen inactivity until screen saver activates" under Endpoint Protection as an alternative.

## References

- Microsoft Learn - Interactive logon: Machine inactivity limit: https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/interactive-logon-machine-inactivity-limit
- Microsoft Learn - Windows 11 Sign-in Options: https://learn.microsoft.com/en-us/windows/security/identity-protection/configure-s-mode
- Microsoft PowerCfg Documentation: https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options