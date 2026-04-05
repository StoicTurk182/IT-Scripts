<#
.SYNOPSIS
    Diagnoses page fault pressure and applies or recommends fixes.

.DESCRIPTION
    Collects system memory state, pagefile configuration, counter data,
    and per-process fault counts. Evaluates findings against thresholds,
    flags issues, and where safe to do so applies remediations automatically.
    All other fixes are listed with the exact commands to run.

.PARAMETER SampleSeconds
    Duration in seconds for performance counter sampling. Default: 5

.PARAMETER TopN
    Number of processes to display in the fault table. Default: 15

.PARAMETER AutoFix
    Switch. When present, applies safe automatic remediations:
    - Clears process working sets (trims RAM usage)
    - Enables pagefile if none exists
    Without this switch the script is read-only/diagnostic only.

.EXAMPLE
    .\Resolve-PageFaults.ps1
    Diagnostic mode. No changes made.

.EXAMPLE
    .\Resolve-PageFaults.ps1 -AutoFix
    Diagnostic mode plus safe automatic remediations.

.NOTES
    Author: Andrew Jones
    Version: 1.0
    Date: 2026-04-03
    Requires: Administrator (for counter access and AutoFix actions)
#>

[CmdletBinding()]
param (
    [Parameter()]
    [int]$SampleSeconds = 5,

    [Parameter()]
    [int]$TopN = 15,

    [Parameter()]
    [switch]$AutoFix
)

# ============================================================================
# HELPERS
# ============================================================================

function Write-Section {
    param ([string]$Title)
    Write-Host "`n========================================" -ForegroundColor DarkGray
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor DarkGray
}

function Write-Finding {
    param (
        [string]$Label,
        [string]$Value,
        [ValidateSet("OK","WARN","CRIT","INFO")]
        [string]$Status = "INFO"
    )
    $colours = @{ OK = "Green"; WARN = "Yellow"; CRIT = "Red"; INFO = "White" }
    $tag = switch ($Status) { "OK" { "[OK]  " } "WARN" { "[WARN]" } "CRIT" { "[CRIT]" } default { "[INFO]" } }
    Write-Host "$tag $Label : $Value" -ForegroundColor $colours[$Status]
}

function Write-Fix {
    param ([string]$Description, [string]$Command)
    Write-Host "`n  FIX: $Description" -ForegroundColor Magenta
    if ($Command) {
        Write-Host "  CMD: $Command" -ForegroundColor DarkYellow
    }
}

$script:Issues = @()

function Add-Issue {
    param ([string]$Area, [string]$Detail, [string]$Fix)
    $script:Issues += [PSCustomObject]@{ Area = $Area; Detail = $Detail; Fix = $Fix }
}

# ============================================================================
# ELEVATION CHECK
# ============================================================================

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

Write-Host "`n=== Resolve-PageFaults ===" -ForegroundColor Cyan
Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "AutoFix : $($AutoFix.IsPresent)"
Write-Host "Admin   : $isAdmin"

if (-not $isAdmin) {
    Write-Host "`nWARNING: Not running as Administrator. Counter access and AutoFix will be limited." -ForegroundColor Yellow
}

# ============================================================================
# SECTION 1 - PHYSICAL MEMORY STATE
# ============================================================================

Write-Section "1. Physical Memory State"

$os      = Get-CimInstance Win32_OperatingSystem
$cs      = Get-CimInstance Win32_ComputerSystem
$totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024, 0)
$freeMB  = [math]::Round($os.FreePhysicalMemory / 1024, 0)
$usedMB  = $totalMB - $freeMB
$usedPct = [math]::Round(($usedMB / $totalMB) * 100, 1)
$totalGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)

Write-Finding "Physical RAM installed" "$totalGB GB"
Write-Finding "RAM in use"            "$usedMB MB ($usedPct%)" $(if ($usedPct -gt 90) { "CRIT" } elseif ($usedPct -gt 80) { "WARN" } else { "OK" })
Write-Finding "RAM free"              "$freeMB MB"             $(if ($freeMB -lt 512) { "CRIT" } elseif ($freeMB -lt 1024) { "WARN" } else { "OK" })

if ($usedPct -gt 90) {
    Add-Issue -Area "Physical RAM" `
              -Detail "RAM usage at $usedPct% ($usedMB MB of $totalMB MB used)" `
              -Fix    "Close non-essential applications or add physical RAM. Run with -AutoFix to trim process working sets."
}

# ============================================================================
# SECTION 2 - PAGEFILE CONFIGURATION
# ============================================================================

Write-Section "2. Pagefile Configuration"

$pagefiles = Get-CimInstance Win32_PageFileUsage
$pagefileSetting = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue

if (-not $pagefiles) {
    Write-Finding "Pagefile" "NONE DETECTED" "CRIT"
    Add-Issue -Area "Pagefile" `
              -Detail "No pagefile found. Windows cannot handle memory overflow." `
              -Fix    "Enable pagefile: System Properties > Advanced > Performance > Virtual Memory > System managed size. Or run with -AutoFix."

    if ($AutoFix) {
        Write-Host "`n  AUTOFIX: Enabling system-managed pagefile on C:..." -ForegroundColor Magenta
        try {
            $pf = New-CimInstance -ClassName Win32_PageFileSetting -Property @{ Name = "C:\pagefile.sys" } -ErrorAction Stop
            Write-Host "  Pagefile created. Reboot required." -ForegroundColor Green
        } catch {
            Write-Host "  Failed to create pagefile: $_" -ForegroundColor Red
        }
    }
} else {
    foreach ($pf in $pagefiles) {
        $allocMB  = $pf.AllocatedBaseSize
        $currentMB = $pf.CurrentUsage
        $peakMB   = $pf.PeakUsage
        $usedPfPct = if ($allocMB -gt 0) { [math]::Round(($currentMB / $allocMB) * 100, 1) } else { 0 }

        Write-Finding "Pagefile path"     $pf.Name
        Write-Finding "Allocated size"    "$allocMB MB"
        Write-Finding "Current usage"     "$currentMB MB ($usedPfPct%)" $(if ($usedPfPct -gt 80) { "WARN" } else { "OK" })
        Write-Finding "Peak usage"        "$peakMB MB"

        if ($peakMB -ge ($allocMB * 0.9)) {
            Add-Issue -Area "Pagefile size" `
                      -Detail "Peak pagefile usage ($peakMB MB) reached $usedPfPct% of allocated size ($allocMB MB)" `
                      -Fix    "Increase pagefile: System Properties > Advanced > Performance > Virtual Memory. Recommended initial: 1.5x RAM ($([math]::Round($totalMB * 1.5, 0)) MB), max: 3x RAM ($([math]::Round($totalMB * 3, 0)) MB)."
        }

        if ($pf.Name -like "C:\*") {
            Write-Finding "Pagefile location" "System drive (C:) - acceptable but not optimal" "INFO"
        }
    }
}

# ============================================================================
# SECTION 3 - PERFORMANCE COUNTERS
# ============================================================================

Write-Section "3. Performance Counters (${SampleSeconds}s sample)"

$counterResults = @{}

if ($isAdmin) {
    $counters = @(
        "\Memory\Page Faults/sec",
        "\Memory\Pages/sec",
        "\Memory\Page Reads/sec",
        "\Memory\Page Writes/sec",
        "\Memory\Available MBytes",
        "\Memory\Committed Bytes",
        "\Memory\Commit Limit",
        "\Memory\Pool Nonpaged Bytes"
    )

    try {
        $samples = Get-Counter -Counter $counters -SampleInterval 1 -MaxSamples $SampleSeconds -ErrorAction Stop

        foreach ($counter in $counters) {
            $label = ($counter -split '\\')[-1]
            $vals  = $samples.CounterSamples | Where-Object { $_.Path -like "*$label*" } | Select-Object -ExpandProperty CookedValue
            $counterResults[$label] = @{
                Avg = [math]::Round(($vals | Measure-Object -Average).Average, 2)
                Max = [math]::Round(($vals | Measure-Object -Maximum).Maximum, 2)
            }
        }

        $pfSec    = $counterResults["Page Faults/sec"].Avg
        $pagesSec = $counterResults["Pages/sec"].Avg
        $avail    = $counterResults["Available MBytes"].Avg
        $committed = [math]::Round($counterResults["Committed Bytes"].Avg / 1MB, 0)
        $limit     = [math]::Round($counterResults["Commit Limit"].Avg / 1MB, 0)
        $commitPct = [math]::Round(($committed / $limit) * 100, 1)

        Write-Finding "Page Faults/sec (avg)"  "$pfSec"    $(if ($pfSec -gt 5000) { "CRIT" } elseif ($pfSec -gt 1000) { "WARN" } else { "OK" })
        Write-Finding "Pages/sec (avg)"         "$pagesSec" $(if ($pagesSec -gt 20) { "CRIT" } elseif ($pagesSec -gt 5) { "WARN" } else { "OK" })
        Write-Finding "Page Reads/sec (avg)"    "$($counterResults["Page Reads/sec"].Avg)"
        Write-Finding "Page Writes/sec (avg)"   "$($counterResults["Page Writes/sec"].Avg)"
        Write-Finding "Available MBytes (avg)"  "$avail MB" $(if ($avail -lt 100) { "CRIT" } elseif ($avail -lt 300) { "WARN" } else { "OK" })
        Write-Finding "Commit charge"           "$committed MB / $limit MB ($commitPct%)" $(if ($commitPct -gt 90) { "CRIT" } elseif ($commitPct -gt 75) { "WARN" } else { "OK" })

        if ($pagesSec -gt 20) {
            Add-Issue -Area "Hard page faults" `
                      -Detail "Pages/sec averaging $pagesSec - disk is actively being used to resolve memory faults" `
                      -Fix    "Immediate: close applications. Medium term: add RAM. Check top fault processes below."
        }

        if ($commitPct -gt 90) {
            Add-Issue -Area "Commit charge" `
                      -Detail "Virtual memory commit at $commitPct% ($committed MB of $limit MB)" `
                      -Fix    "Increase pagefile size or add RAM. System is close to running out of addressable virtual memory."
        }

    } catch {
        Write-Host "Counter error: $_" -ForegroundColor Red
    }
} else {
    Write-Host "Skipped - Administrator required for performance counters." -ForegroundColor Yellow
}

# ============================================================================
# SECTION 4 - TOP OFFENDING PROCESSES
# ============================================================================

Write-Section "4. Top $TopN Processes by Page Fault Count"

$procs = Get-Process |
    Where-Object { $_.PageFaults -gt 0 } |
    Sort-Object PageFaults -Descending |
    Select-Object -First $TopN

$procs | Format-Table -AutoSize @(
    @{ Label = "PID";          Expression = { $_.Id };                                               Width = 8 },
    @{ Label = "Process";      Expression = { $_.ProcessName };                                      Width = 28 },
    @{ Label = "PageFaults";   Expression = { $_.PageFaults };                                       Width = 14 },
    @{ Label = "WS(MB)";       Expression = { [math]::Round($_.WorkingSet64 / 1MB, 1) };            Width = 10 },
    @{ Label = "VM(MB)";       Expression = { [math]::Round($_.VirtualMemorySize64 / 1MB, 1) };     Width = 10 },
    @{ Label = "CPU(s)";       Expression = { [math]::Round($_.CPU, 1) };                            Width = 10 },
    @{ Label = "StartTime";    Expression = { if ($_.StartTime) { $_.StartTime.ToString("HH:mm") } else { "N/A" } }; Width = 10 }
)

# Flag any process consuming more than 25% of total RAM
$highMemProcs = Get-Process | Where-Object { ($_.WorkingSet64 / 1MB) -gt ($totalMB * 0.25) }
foreach ($p in $highMemProcs) {
    $wsMB = [math]::Round($p.WorkingSet64 / 1MB, 0)
    Add-Issue -Area "High memory process" `
              -Detail "$($p.ProcessName) (PID $($p.Id)) using $wsMB MB working set ($([math]::Round($wsMB/$totalMB*100,1))% of RAM)" `
              -Fix    "Investigate $($p.ProcessName): check for memory leaks, restart the process, or check vendor guidance."
}

# ============================================================================
# SECTION 5 - AUTOFIX: TRIM WORKING SETS
# ============================================================================

if ($AutoFix -and $isAdmin) {
    Write-Section "5. AutoFix - Trim Process Working Sets"
    Write-Host "Requesting Windows to trim working sets for top fault processes..." -ForegroundColor Magenta

    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("kernel32.dll")]
    public static extern bool SetProcessWorkingSetSize(IntPtr hProcess, IntPtr dwMinimumWorkingSetSize, IntPtr dwMaximumWorkingSetSize);
}
"@

    $trimmed = 0
    foreach ($proc in $procs | Select-Object -First 10) {
        try {
            $handle = $proc.Handle
            [WinAPI]::SetProcessWorkingSetSize($handle, [IntPtr](-1), [IntPtr](-1)) | Out-Null
            $trimmed++
        } catch { }
    }

    Write-Host "Trim requested for $trimmed processes. Windows will page out idle memory over the next few seconds." -ForegroundColor Green
    Write-Host "Note: This is a soft hint to the memory manager, not a forceful eviction." -ForegroundColor DarkGray
}

# ============================================================================
# SECTION 6 - FINDINGS SUMMARY AND FIX LIST
# ============================================================================

Write-Section "6. Findings Summary"

if ($script:Issues.Count -eq 0) {
    Write-Host "No significant issues detected." -ForegroundColor Green
} else {
    Write-Host "$($script:Issues.Count) issue(s) found:`n" -ForegroundColor Yellow
    $i = 1
    foreach ($issue in $script:Issues) {
        Write-Host "  [$i] $($issue.Area)" -ForegroundColor Yellow
        Write-Host "      $($issue.Detail)" -ForegroundColor White
        Write-Fix -Description $issue.Fix -Command ""
        $i++
    }
}

# ============================================================================
# SECTION 7 - MANUAL REMEDIATION REFERENCE
# ============================================================================

Write-Section "7. Manual Remediation Commands"

Write-Host @"

PAGEFILE - Set system-managed (run as admin, reboot required):
  wmic computersystem set AutomaticManagedPagefile=True

PAGEFILE - Set custom size on C: (initial 8192 MB, max 16384 MB):
  wmic pagefileset where name="C:\\pagefile.sys" set InitialSize=8192,MaximumSize=16384

PAGEFILE - View current settings:
  wmic pagefileset list full

WORKING SET TRIM - Force all process trim via RAMMap or:
  Get-Process | ForEach-Object { `$_.MinWorkingSet = 1024 }

IDENTIFY LEAK - Watch a process working set over time (PID required):
  while (`$true) { (Get-Process -Id <PID>).WorkingSet64 / 1MB; Start-Sleep 10 }

COMMIT CHARGE - Check virtual memory totals:
  Get-CimInstance Win32_OperatingSystem | Select-Object TotalVirtualMemorySize, FreeVirtualMemory

CLEAR STANDBY LIST - Requires SysinternalsSuite RAMMap (GUI):
  https://learn.microsoft.com/en-us/sysinternals/downloads/rammap

CHECK DRIVER POOL USAGE - Non-paged pool leak detection:
  poolmon.exe (Windows Driver Kit) or via Resource Monitor > Memory > Drivers
"@ -ForegroundColor Gray

Write-Host "`nDone.`n" -ForegroundColor Green