# GPU TDR Settings - Read and Interpret

Documents how to read GPU Timeout Detection and Recovery (TDR) settings from the Windows registry, interpret the values, and understand what non-default configurations indicate.

Registry path: `HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers`

## What is TDR

Timeout Detection and Recovery (TDR) is a Windows subsystem that monitors the GPU for hangs. If the GPU fails to respond within the configured timeout, Windows attempts to reset the display driver without requiring a full system reboot. If recovery fails or the hang limit is exceeded, Windows issues a bugcheck (BSOD).

TDR events are logged as Event ID 4101 in the System event log under source `Display`.

Reference: https://learn.microsoft.com/en-us/windows-hardware/drivers/display/tdr-registry-keys

## Read Script

```powershell
$tdrPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"

$tdrKeys = @("TdrLevel", "TdrDelay", "TdrDdiDelay", "TdrLimitTime", "TdrLimitCount")

$tdrLevelMap = @{
    0 = "TdrLevelOff - TDR disabled"
    1 = "TdrLevelBugcheck - Blue screen on timeout (no recovery)"
    2 = "TdrLevelRecover - Recover (default)"
    3 = "TdrLevelRecoverVerbose - Recover with debug logging"
}

Write-Host "`n=== GPU TDR Settings ===" -ForegroundColor Cyan
Write-Host "Registry path: $tdrPath`n" -ForegroundColor DarkGray

foreach ($key in $tdrKeys) {
    $value = (Get-ItemProperty -Path $tdrPath -Name $key -ErrorAction SilentlyContinue).$key

    if ($null -eq $value) {
        Write-Host "${key}: Not set (Windows default applies)" -ForegroundColor Yellow
    } else {
        if ($key -eq "TdrLevel") {
            $desc = $tdrLevelMap[$value]
            Write-Host "${key}: $value  ->  $desc" -ForegroundColor Green
        } else {
            Write-Host "${key}: $value" -ForegroundColor Green
        }
    }
}

Write-Host "`n=== Default Values (if not set) ===" -ForegroundColor Cyan
Write-Host "TdrLevel:      2 (Recover)"
Write-Host "TdrDelay:      2 seconds (GPU hang detection timeout)"
Write-Host "TdrDdiDelay:   5 seconds (DDI call timeout)"
Write-Host "TdrLimitTime:  60 seconds"
Write-Host "TdrLimitCount: 5 (resets per TdrLimitTime before bugcheck)`n"
```

## Registry Keys Reference

| Key | Default | Unit | Purpose |
|-----|---------|------|---------|
| `TdrLevel` | 2 | Enum | Recovery behaviour when GPU hangs |
| `TdrDelay` | 2 | Seconds | How long Windows waits before declaring the GPU hung |
| `TdrDdiDelay` | 5 | Seconds | Timeout for individual DDI (driver interface) calls |
| `TdrLimitTime` | 60 | Seconds | Rolling window for counting TDR events |
| `TdrLimitCount` | 5 | Count | Max recoveries within TdrLimitTime before BSOD |

Keys not present in the registry are not broken — Windows silently applies the defaults listed above.

## TdrLevel Values

| Value | Name | Behaviour |
|-------|------|-----------|
| 0 | TdrLevelOff | TDR entirely disabled. GPU hang causes immediate system freeze. Not recommended in production. |
| 1 | TdrLevelBugcheck | No recovery attempt. GPU hang causes immediate BSOD. Used for driver development. |
| 2 | TdrLevelRecover | Standard behaviour. Windows resets the driver and recovers the desktop silently (default). |
| 3 | TdrLevelRecoverVerbose | Same as level 2 but writes additional debug information to the system log on each event. |

## Example Output and Interpretation

```
TdrLevel: 3  ->  TdrLevelRecoverVerbose - Recover with debug logging
TdrDelay: 10
TdrDdiDelay: Not set (Windows default applies)
TdrLimitTime: Not set (Windows default applies)
TdrLimitCount: Not set (Windows default applies)
```

### TdrLevel 3 (non-default)

Verbose recovery logging is not a standard end-user setting. It is typically configured during active GPU driver troubleshooting or set by installers for GPU-intensive workloads such as machine learning frameworks, rendering software, or cryptocurrency mining tools. If active troubleshooting has concluded, this can be safely reverted to `2` to remove the debug logging overhead.

### TdrDelay 10 (non-default)

The hang detection window has been extended from the default 2 seconds to 10 seconds. This is a well-known manual fix applied after TDR crash events during heavy GPU workloads such as 3D rendering, ML inference, or sustained gaming loads. A longer delay reduces false-positive recoveries where the GPU was still working but had not responded within the short default window. This value is safe to leave in place if the workload warrants it.

### Remaining keys at default

`TdrDdiDelay`, `TdrLimitTime`, and `TdrLimitCount` are absent from the registry, meaning Windows applies its built-in defaults. Recovery limiting behaviour (BSOD after 5 events in 60 seconds) is standard.

## Modifying TDR Values

Run PowerShell as Administrator.

### Set TdrLevel back to standard recovery (remove verbose logging)

```powershell
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "TdrLevel" -Value 2 -Type DWord
```

### Increase TdrDelay for GPU-intensive workloads

```powershell
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "TdrDelay" -Value 10 -Type DWord
```

### Restore a key to Windows default (remove the override)

```powershell
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "TdrDelay" -ErrorAction SilentlyContinue
```

Removing the key causes Windows to apply its compiled-in default on next boot. A reboot is required for any TDR registry changes to take effect.

### Disable TDR entirely (not recommended for general use)

```powershell
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "TdrLevel" -Value 0 -Type DWord
```

With TDR disabled, a GPU hang will cause the system to freeze with no recovery. This is occasionally used for GPU passthrough in virtualisation environments where the host should not interfere with driver resets.

## Common Reasons for Non-Default Values

| Scenario | TdrLevel | TdrDelay | Notes |
|----------|----------|----------|-------|
| Active GPU troubleshooting | 3 | Elevated | Set manually or by support guidance |
| ML framework installer (e.g. CUDA, TensorFlow) | Unchanged | 10-30 | Some installers set TdrDelay automatically |
| Mining software | 0 or unchanged | Elevated | Some tools disable TDR to prevent interrupting long compute jobs |
| Rendering workstation setup guide | Unchanged | 8-10 | Common recommendation to reduce false positives in Blender/DaVinci |
| Never modified | 2 (absent) | 2 (absent) | Both keys absent; pure Windows defaults |

## Viewing TDR Events in Event Viewer

TDR events are recorded in the Windows System log:

```
Source:  Display
Event ID: 4101
Level:   Warning
```

To query via PowerShell:

```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; Id=4101} -MaxEvents 20 |
    Select-Object TimeCreated, Message |
    Format-List
```

## References

- TDR Registry Keys (Microsoft Docs): https://learn.microsoft.com/en-us/windows-hardware/drivers/display/tdr-registry-keys
- Timeout Detection and Recovery Overview: https://learn.microsoft.com/en-us/windows-hardware/drivers/display/timeout-detection-and-recovery
- Set-ItemProperty: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/set-itemproperty
- Get-WinEvent: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-winevent
