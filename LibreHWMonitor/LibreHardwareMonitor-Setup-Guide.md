## Local Scheduled Task setup

# LibreHardwareMonitor Setup Guide

Configuration guide for LibreHardwareMonitor with persistent settings and automatic restart watchdog.

Repository: https://github.com/LibreHardwareMonitor/LibreHardwareMonitor

## Download and Install

1. Download latest release from: https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases
2. Extract ZIP to `C:\LibreHardwareMonitor`
3. Run `LibreHardwareMonitor.exe` as Administrator

Alternatively, install via WinGet:

```powershell
winget install LibreHardwareMonitor.LibreHardwareMonitor
```

## Configure Web Server

1. Open LibreHardwareMonitor
2. **Options** > **Remote Web Server** > **Run** (enable checkbox)
3. **Options** > **Remote Web Server** > **Port**: `8085`
4. **Options** > **Remote Web Server** > **IP**: Select your LAN IP

Avoid selecting Hyper-V virtual switch IPs (172.x.x.x range). Choose your physical NIC IP.

## Configure Startup Behaviour

1. **Options** > **Run On Windows Startup** (if available)
2. **Options** > **Start Minimized**
3. **Options** > **Minimize To Tray**
4. **Options** > **Minimize On Close**

## Verify Web Server

```powershell
Test-NetConnection -ComputerName localhost -Port 8085
```

Browser test:

```
http://localhost:8085/
```

## Watchdog Task

Creates a scheduled task that checks every 5 minutes and restarts LHM if not running.

### Option A: Interactive Mode (Recommended)

Runs in your desktop session with visible tray icon. Use this if you need to access LHM settings or view the GUI.

```powershell
$LHMPath = "C:\LibreHardwareMonitor"

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"if (-not (Get-Process -Name 'LibreHardwareMonitor' -ErrorAction SilentlyContinue)) { Start-Process '$LHMPath\LibreHardwareMonitor.exe' -WorkingDirectory '$LHMPath' }`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 9999)

$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName "LibreHardwareMonitor-Watchdog" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Restarts LHM if not running (interactive)" -Force
```

### Option B: Background Mode (Headless)

Runs as SYSTEM in session 0. No tray icon visible. Use for servers or headless monitoring where GUI access is not required.

```powershell
$LHMPath = "C:\LibreHardwareMonitor"

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"if (-not (Get-Process -Name 'LibreHardwareMonitor' -ErrorAction SilentlyContinue)) { Start-Process '$LHMPath\LibreHardwareMonitor.exe' -WorkingDirectory '$LHMPath' }`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 9999)

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName "LibreHardwareMonitor-Watchdog" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Restarts LHM if not running (background)" -Force
```

### Start Watchdog Immediately

```powershell
Start-ScheduledTask -TaskName "LibreHardwareMonitor-Watchdog"
```

### Test Watchdog

```powershell
# Stop LHM
Stop-Process -Name "LibreHardwareMonitor" -Force -ErrorAction SilentlyContinue

# Trigger watchdog
Start-ScheduledTask -TaskName "LibreHardwareMonitor-Watchdog"

# LHM should restart (check tray for Option A, or process list for Option B)
Get-Process -Name "LibreHardwareMonitor"
```

### Verify Watchdog

```powershell
Get-ScheduledTask -TaskName "LibreHardwareMonitor-Watchdog" | Select-Object TaskName, State
```

### Remove Watchdog

```powershell
Unregister-ScheduledTask -TaskName "LibreHardwareMonitor-Watchdog" -Confirm:$false
```

## Persistent Settings

Settings are stored in `LibreHardwareMonitor.config` in the application folder.

### Lock Settings (Read-Only)

Prevents accidental changes after configuration is complete:

```powershell
Set-ItemProperty -Path "C:\LibreHardwareMonitor\LibreHardwareMonitor.config" -Name IsReadOnly -Value $true
```

### Unlock Settings

Required before making changes:

```powershell
Set-ItemProperty -Path "C:\LibreHardwareMonitor\LibreHardwareMonitor.config" -Name IsReadOnly -Value $false
```

### Backup Settings

```powershell
Copy-Item "C:\LibreHardwareMonitor\LibreHardwareMonitor.config" "C:\LibreHardwareMonitor\LibreHardwareMonitor.config.bak"
```

### Restore Settings

```powershell
Copy-Item "C:\LibreHardwareMonitor\LibreHardwareMonitor.config.bak" "C:\LibreHardwareMonitor\LibreHardwareMonitor.config" -Force
```

## Verification Commands

Check LHM process:

```powershell
Get-Process -Name "LibreHardwareMonitor" -ErrorAction SilentlyContinue
```

Check web server port:

```powershell
Get-NetTCPConnection -LocalPort 8085 -State Listen -ErrorAction SilentlyContinue
```

Check which IP the web server is bound to:

```powershell
Get-NetTCPConnection -LocalPort 8085 -State Listen | Select-Object LocalAddress, LocalPort
```

## Troubleshooting

### Web Server Not Responding

1. Verify LHM is running: `Get-Process -Name "LibreHardwareMonitor"`
2. Check port binding: `Get-NetTCPConnection -LocalPort 8085 -State Listen`
3. Confirm correct IP selected in Options > Remote Web Server > IP
4. Restart LHM after changing web server settings

### Bound to Wrong IP

If bound to Hyper-V IP (172.x.x.x):

1. Options > Remote Web Server > IP > Select correct LAN IP
2. Uncheck then re-check Run to restart web server

### Settings Not Persisting

1. Close LHM properly via tray icon > Exit (not Task Manager kill)
2. Check config file exists: `Test-Path "C:\LibreHardwareMonitor\LibreHardwareMonitor.config"`
3. Check file is not read-only when trying to save

### Watchdog Not Starting LHM

1. Verify path is correct in task
2. Check task is running with correct principal (SYSTEM for background, username for interactive)
3. View task history in Task Scheduler for errors

### LHM Running But No Tray Icon

This occurs when using Background Mode (Option B). The process runs in session 0 (SYSTEM) which is isolated from your desktop. Switch to Interactive Mode (Option A) if you need tray access.

## Directory Structure

```
C:\LibreHardwareMonitor\
├── LibreHardwareMonitor.exe
├── LibreHardwareMonitor.config
├── LibreHardwareMonitorLib.dll
└── [other DLLs]
```

## Integration with Caddy Proxy

After configuring LHM, use the Caddy proxy script for secure Tailscale access:

```powershell
.\Setup-CaddyProxy.ps1 -Action Install -UpstreamIP 127.0.0.1 -Force
```

Access via Tailscale:

```
https://<tailscale-ip>:8086/
```

## References

- LibreHardwareMonitor GitHub: https://github.com/LibreHardwareMonitor/LibreHardwareMonitor
- LibreHardwareMonitor Releases: https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases
- Scheduled Tasks: https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask
- WinGet: https://learn.microsoft.com/en-us/windows/package-manager/winget/
