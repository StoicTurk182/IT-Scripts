# Get-PageFaults

PowerShell script to pull system-level and per-process page fault information on Windows.

## Script

```powershell
<#
.SYNOPSIS
    Pulls page fault statistics at system and per-process level.

.DESCRIPTION
    Queries Windows performance counters and WMI for page fault data.
    Reports system-wide page faults per second, memory pressure indicators,
    and the top offending processes by page fault count.

.PARAMETER TopN
    Number of top processes to display by page fault count. Default: 15

.PARAMETER SampleSeconds
    Duration in seconds to sample performance counters. Default: 3

.EXAMPLE
    .\Get-PageFaults.ps1
    Runs with defaults - top 15 processes, 3 second sample.

.EXAMPLE
    .\Get-PageFaults.ps1 -TopN 25 -SampleSeconds 5
    Returns top 25 processes over a 5 second counter sample.

.NOTES
    Author: Andrew Jones
    Version: 1.0
    Date: 2026-04-03
    Requires: Run as Administrator for full counter access
#>

[CmdletBinding()]
param (
    [Parameter()]
    [int]$TopN = 15,

    [Parameter()]
    [int]$SampleSeconds = 3
)

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Header {
    param ([string]$Title)
    Write-Host "`n--- $Title ---" -ForegroundColor Cyan
}

# ============================================================================
# SYSTEM MEMORY OVERVIEW
# ============================================================================

Write-Host "`n=== Page Fault Report ===" -ForegroundColor Cyan
Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"

Write-Header "System Memory"

$mem = Get-CimInstance Win32_OperatingSystem
$totalMB = [math]::Round($mem.TotalVisibleMemorySize / 1024, 0)
$freeMB  = [math]::Round($mem.FreePhysicalMemory / 1024, 0)
$usedMB  = $totalMB - $freeMB
$usedPct = [math]::Round(($usedMB / $totalMB) * 100, 1)

Write-Host "Total RAM : $totalMB MB"
Write-Host "Used      : $usedMB MB ($usedPct%)"
Write-Host "Free      : $freeMB MB"

# ============================================================================
# SYSTEM PAGE FAULT COUNTER
# ============================================================================

Write-Header "System Page Faults/sec (${SampleSeconds}s sample)"

try {
    $counterPath = "\Memory\Page Faults/sec"
    $samples = Get-Counter -Counter $counterPath -SampleInterval 1 -MaxSamples $SampleSeconds -ErrorAction Stop
    $values  = $samples.CounterSamples | Select-Object -ExpandProperty CookedValue
    $avg     = [math]::Round(($values | Measure-Object -Average).Average, 2)
    $peak    = [math]::Round(($values | Measure-Object -Maximum).Maximum, 2)

    Write-Host "Average : $avg faults/sec"
    Write-Host "Peak    : $peak faults/sec"

    if ($avg -gt 1000) {
        Write-Host "WARNING: High page fault rate detected - possible memory pressure." -ForegroundColor Yellow
    }
} catch {
    Write-Host "Could not read performance counter: $_" -ForegroundColor Red
    Write-Host "Try running as Administrator." -ForegroundColor Yellow
}

# ============================================================================
# ADDITIONAL MEMORY PRESSURE COUNTERS
# ============================================================================

Write-Header "Memory Pressure Indicators"

try {
    $pressureCounters = @(
        "\Memory\Pages/sec",
        "\Memory\Page Reads/sec",
        "\Memory\Page Writes/sec",
        "\Memory\Pool Nonpaged Bytes"
    )

    $snap = Get-Counter -Counter $pressureCounters -SampleInterval 1 -MaxSamples 2 -ErrorAction Stop
    $snap.CounterSamples | ForEach-Object {
        $label = ($_.Path -split '\\')[-1]
        $val   = [math]::Round($_.CookedValue, 2)
        Write-Host "$label : $val"
    }
} catch {
    Write-Host "Could not read pressure counters: $_" -ForegroundColor Yellow
}

# ============================================================================
# PER-PROCESS PAGE FAULTS
# ============================================================================

Write-Header "Top $TopN Processes by Page Fault Count"

Get-Process |
    Where-Object { $_.PageFaults -gt 0 } |
    Sort-Object PageFaults -Descending |
    Select-Object -First $TopN |
    Format-Table -AutoSize @(
        @{ Label = "PID";         Expression = { $_.Id }; Width = 8 },
        @{ Label = "Process";     Expression = { $_.ProcessName }; Width = 30 },
        @{ Label = "PageFaults";  Expression = { $_.PageFaults }; Width = 14 },
        @{ Label = "WorkingSet(MB)"; Expression = { [math]::Round($_.WorkingSet64 / 1MB, 1) }; Width = 16 },
        @{ Label = "CPU(s)";      Expression = { [math]::Round($_.CPU, 1) }; Width = 10 }
    )

Write-Host "`nDone.`n" -ForegroundColor Green
```

## Key Metrics Explained

| Metric | Source | What It Indicates |
|--------|--------|-------------------|
| Page Faults/sec | `\Memory\Page Faults/sec` | Total soft + hard faults per second system-wide |
| Pages/sec | `\Memory\Pages/sec` | Hard faults resolved via disk read/write; sustained values above 20 indicate pressure |
| Page Reads/sec | `\Memory\Page Reads/sec` | Disk reads caused by hard page faults |
| Page Writes/sec | `\Memory\Page Writes/sec` | Pages written to pagefile to free physical RAM |
| Pool Nonpaged Bytes | `\Memory\Pool Nonpaged Bytes` | Kernel memory that cannot be paged out |
| PageFaults (per process) | `Get-Process` | Cumulative count since process start; soft and hard combined |

### Soft vs Hard Page Faults

A soft fault is resolved in RAM (page found in standby list or shared memory). A hard fault requires a disk read from the pagefile or a mapped file. Hard faults are the expensive ones.

`Get-Counter` and `\Memory\Page Faults/sec` report both combined. `\Memory\Pages/sec` is the best single indicator of hard fault activity.

## Usage Examples

Run with defaults:

```powershell
.\Get-PageFaults.ps1
```

Extend sample window and show more processes:

```powershell
.\Get-PageFaults.ps1 -TopN 25 -SampleSeconds 10
```

Run from GitHub (IT-Scripts toolbox pattern):

```powershell
iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Utils/Diagnostics/Get-PageFaults.ps1")
```

## Threshold Reference

These are general guidance values. Baselines vary by workload.

| Metric | Normal | Investigate |
|--------|--------|-------------|
| Page Faults/sec | < 1000 | > 5000 sustained |
| Pages/sec | < 5 | > 20 sustained |
| RAM used | < 80% | > 90% |

## References

- Get-Counter: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-counter
- Win32_OperatingSystem: https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-operatingsystem
- Memory performance counters: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/typeperf
- Page fault explanation (Windows Internals): https://learn.microsoft.com/en-us/windows/win32/memory/working-set
