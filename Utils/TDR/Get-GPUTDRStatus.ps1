<#
.SYNOPSIS
    GPU TDR Diagnostic Script

.DESCRIPTION
    Checks Event Viewer, WER reports, minidumps, and registry TDR settings
    to determine whether GPU timeout/recovery events are present and whether
    they indicate an ongoing issue.

.NOTES
    Author: Andrew Jones
    Version: 1.0
    Run as Administrator for full access to all log locations.
#>

#Requires -Version 5.1

# ============================================================================
# CONFIG
# ============================================================================

$LookbackDays   = 7     # How many days back to check events
$TDRThreshold   = 3     # Number of TDR events considered "an issue"
$ExportResults  = $false # Set to $true to export CSV to Desktop

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Header {
    param([string]$Title)
    Write-Host "`n$('=' * 60)" -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "$('=' * 60)" -ForegroundColor DarkGray
}

function Write-Status {
    param([string]$Label, [string]$Value, [string]$Color = "White")
    Write-Host "  $Label" -ForegroundColor Gray -NoNewline
    Write-Host " $Value" -ForegroundColor $Color
}

function Get-TDREventViewerEvents {
    param([int]$Days)
    $since = (Get-Date).AddDays(-$Days)
    try {
        $events = Get-WinEvent -LogName System -ErrorAction Stop | Where-Object {
            $_.TimeCreated -ge $since -and
            $_.ProviderName -match "display|nvlddmkm|amdkmdag|igfx|dxgkrnl"
        }
        return $events
    } catch {
        return @()
    }
}

function Get-WERTDRReports {
    $werPath = "$env:ProgramData\Microsoft\Windows\WER\ReportArchive"
    if (-not (Test-Path $werPath)) { return @() }
    return Get-ChildItem $werPath -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "0x116|0x117|0x119|nvlddmkm|amdkmdag|igfx|video_tdr" } |
        Sort-Object LastWriteTime -Descending
}

function Get-Minidumps {
    $dumpPath = "C:\Windows\Minidump"
    if (-not (Test-Path $dumpPath)) { return @() }
    return Get-ChildItem $dumpPath -Filter "*.dmp" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
}

function Get-TDRRegistrySettings {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
    try {
        return Get-ItemProperty $regPath -ErrorAction Stop
    } catch {
        return $null
    }
}

function Get-InstalledGPUs {
    try {
        return Get-CimInstance Win32_VideoController -ErrorAction Stop |
            Select-Object Name, DriverVersion, Status, AdapterRAM
    } catch {
        return @()
    }
}

# ============================================================================
# MAIN
# ============================================================================

Write-Host "`n  GPU TDR Diagnostic" -ForegroundColor White
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  |  Lookback: $LookbackDays days  |  Issue threshold: $TDRThreshold events" -ForegroundColor DarkGray

$allEvents   = @()
$issueFlags  = @()
$exportRows  = @()

# ---- GPU Info ----
Write-Header "Installed GPU(s)"
$gpus = Get-InstalledGPUs
if ($gpus) {
    foreach ($gpu in $gpus) {
        $ramGB = if ($gpu.AdapterRAM -gt 0) { "{0:N1} GB" -f ($gpu.AdapterRAM / 1GB) } else { "Unknown" }
        Write-Status "Name    :" $gpu.Name White
        Write-Status "Driver  :" $gpu.DriverVersion White
        Write-Status "RAM     :" $ramGB White
        Write-Status "Status  :" $gpu.Status $(if ($gpu.Status -eq "OK") { "Green" } else { "Red" })
        Write-Host ""
        if ($gpu.Status -ne "OK") {
            $issueFlags += "GPU '$($gpu.Name)' reports status: $($gpu.Status)"
        }
    }
} else {
    Write-Host "  Could not retrieve GPU info." -ForegroundColor Yellow
}

# ---- Event Viewer ----
Write-Header "Event Viewer - System Log (Last $LookbackDays days)"
$evtEvents = Get-TDREventViewerEvents -Days $LookbackDays

if ($evtEvents.Count -gt 0) {
    $color = if ($evtEvents.Count -ge $TDRThreshold) { "Red" } else { "Yellow" }
    Write-Status "Events found :" "$($evtEvents.Count)" $color

    $evtEvents | Sort-Object TimeCreated -Descending | ForEach-Object {
        $row = [PSCustomObject]@{
            Source    = "EventViewer"
            Time      = $_.TimeCreated
            Level     = $_.LevelDisplayName
            Provider  = $_.ProviderName
            Message   = ($_.Message -split "`n")[0]  # First line only
        }
        $allEvents  += $row
        $exportRows += $row
        $lvlColor = switch ($_.LevelDisplayName) {
            "Error"       { "Red" }
            "Warning"     { "Yellow" }
            default       { "Gray" }
        }
        Write-Host "  [$($_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))]" -ForegroundColor DarkGray -NoNewline
        Write-Host " [$($_.LevelDisplayName)]" -ForegroundColor $lvlColor -NoNewline
        Write-Host " $($_.ProviderName)" -ForegroundColor White
        Write-Host "    $( ($_.Message -split "`n")[0] )" -ForegroundColor Gray
    }

    if ($evtEvents.Count -ge $TDRThreshold) {
        $issueFlags += "$($evtEvents.Count) GPU-related System events in the last $LookbackDays days"
    }
} else {
    Write-Status "Events found :" "0" Green
}

# ---- WER Reports ----
Write-Header "Windows Error Reporting - TDR Reports"
$werReports = Get-WERTDRReports

if ($werReports.Count -gt 0) {
    $color = if ($werReports.Count -ge $TDRThreshold) { "Red" } else { "Yellow" }
    Write-Status "WER reports found :" "$($werReports.Count)" $color
    $werReports | Select-Object -First 10 | ForEach-Object {
        Write-Host "  [$($_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))]" -ForegroundColor DarkGray -NoNewline
        Write-Host " $($_.Name)" -ForegroundColor Yellow
        $exportRows += [PSCustomObject]@{
            Source   = "WER"
            Time     = $_.LastWriteTime
            Level    = "Report"
            Provider = "WER"
            Message  = $_.Name
        }
    }
    if ($werReports.Count -ge $TDRThreshold) {
        $issueFlags += "$($werReports.Count) TDR-related WER reports found"
    }
} else {
    Write-Status "WER reports found :" "0" Green
}

# ---- Minidumps ----
Write-Header "Minidumps (C:\Windows\Minidump)"
$dumps = Get-Minidumps

if ($dumps.Count -gt 0) {
    $recentDumps = $dumps | Where-Object { $_.LastWriteTime -ge (Get-Date).AddDays(-$LookbackDays) }
    $color = if ($recentDumps.Count -gt 0) { "Red" } else { "Yellow" }
    Write-Status "Total dumps  :" "$($dumps.Count)" Yellow
    Write-Status "Last $LookbackDays days :" "$($recentDumps.Count)" $color
    $dumps | Select-Object -First 5 | ForEach-Object {
        Write-Host "  [$($_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))]" -ForegroundColor DarkGray -NoNewline
        Write-Host " $($_.Name)  ($([math]::Round($_.Length/1KB)) KB)" -ForegroundColor $(if ($_.LastWriteTime -ge (Get-Date).AddDays(-$LookbackDays)) {"Red"} else {"Gray"})
        $exportRows += [PSCustomObject]@{
            Source   = "Minidump"
            Time     = $_.LastWriteTime
            Level    = "Crash"
            Provider = "BugCheck"
            Message  = $_.Name
        }
    }
    if ($recentDumps.Count -gt 0) {
        $issueFlags += "$($recentDumps.Count) minidump(s) written in the last $LookbackDays days - BSOD(s) occurred"
    }
} else {
    Write-Status "Minidumps found :" "0" Green
}

# ---- Registry TDR Settings ----
Write-Header "TDR Registry Settings"
$reg = Get-TDRRegistrySettings

if ($reg) {
    $tdrDelay  = if ($reg.TdrDelay)      { $reg.TdrDelay }      else { "2 (default)" }
    $tdrLevel  = if ($null -ne $reg.TdrLevel) { $reg.TdrLevel } else { "3 (default)" }
    $tdrLimit  = if ($reg.TdrLimitCount) { $reg.TdrLimitCount }  else { "5 (default)" }
    $tdrWindow = if ($reg.TdrLimitTime)  { $reg.TdrLimitTime }   else { "60 (default)" }

    Write-Status "TdrDelay      :" "$tdrDelay seconds" White
    Write-Status "TdrLevel      :" "$tdrLevel  (3=recover, 0=disable, 1=bugcheck)" White
    Write-Status "TdrLimitCount :" "$tdrLimit events" White
    Write-Status "TdrLimitTime  :" "$tdrWindow seconds" White

    if ($tdrLevel -eq 0) {
        Write-Host "`n  TDR recovery is DISABLED - system will BSOD on any GPU hang." -ForegroundColor Yellow
    }
} else {
    Write-Host "  Registry key not accessible (run as Administrator)." -ForegroundColor Yellow
}

# ---- Verdict ----
Write-Header "Verdict"

if ($issueFlags.Count -eq 0) {
    Write-Host "  No TDR issues detected in the last $LookbackDays days." -ForegroundColor Green
    Write-Host "  GPU appears stable." -ForegroundColor Green
} else {
    Write-Host "  ISSUE DETECTED - Review the following:" -ForegroundColor Red
    foreach ($flag in $issueFlags) {
        Write-Host "    - $flag" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  Recommended next steps:" -ForegroundColor Cyan
    Write-Host "    1. Update or rollback GPU driver" -ForegroundColor White
    Write-Host "    2. Open WER reports for bucket ID and driver name" -ForegroundColor White
    Write-Host "    3. Run WinDbg !analyze -v on any minidumps" -ForegroundColor White
    Write-Host "    4. Check GPU thermals and power delivery" -ForegroundColor White
    Write-Host "    5. Test with DDU clean driver reinstall" -ForegroundColor White
}

# ---- Export ----
if ($ExportResults -and $exportRows.Count -gt 0) {
    $exportPath = "$env:USERPROFILE\Desktop\TDR-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    $exportRows | Export-Csv $exportPath -NoTypeInformation
    Write-Host "`n  Report exported to: $exportPath" -ForegroundColor Cyan
}

Write-Host "`n$('=' * 60)`n" -ForegroundColor DarkGray
