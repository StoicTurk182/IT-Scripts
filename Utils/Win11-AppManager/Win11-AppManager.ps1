param (
    [switch]$AuditOnly,
    [switch]$AutoRemove,
    [string]$ReportPath = ''
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# ELEVATION CHECK
# ============================================================================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "`nThis script must be run as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as administrator', then try again.`n"
    exit 1
}

# ============================================================================
# INTERACTIVE MODE
# ============================================================================

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Windows 11 App Audit and Removal" -ForegroundColor Cyan
Write-Host "  Running as : $env:USERNAME" -ForegroundColor Cyan
Write-Host "================================================`n" -ForegroundColor Cyan

if (-not $AuditOnly -and -not $AutoRemove) {
    Write-Host "Select mode:"
    Write-Host "  [1] Audit only  - Show what would be removed, no changes made"
    Write-Host "  [2] Interactive - Audit then choose what to remove"
    Write-Host "  [3] Auto-remove - Remove all safe apps automatically (review list first)`n"
    do {
        $modeInput = (Read-Host "  Selection").Trim()
    } until ($modeInput -in '1','2','3')

    switch ($modeInput) {
        '1' { $AuditOnly  = $true }
        '3' { $AutoRemove = $true }
    }
}

if (-not $ReportPath) {
    $def = "$env:USERPROFILE\Desktop\app-audit-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
    Write-Host "`nReport output path"
    Write-Host "  Default    : $def"
    Write-Host "  Running as : $env:USERNAME"
    $i = (Read-Host "  Press Enter for default or paste a different path").Trim()
    $ReportPath = if ($i) { $i } else { $def }
}

Write-Host ""

# ============================================================================
# APP DEFINITIONS
# Safe    = remove without prompting in AutoRemove mode
# Review  = prompt before removing in Interactive mode
# Dead    = confirmed deprecated by Microsoft
# ============================================================================

$AppDefinitions = @(

    # --- DEPRECATED / DEAD ---
    [PSCustomObject]@{
        Name        = 'Mail and Calendar'
        Pattern     = '*windowscommunicationsapps*'
        Category    = 'Safe'
        Reason      = 'Deprecated - Microsoft ended support 31 Dec 2024. App is view-only.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Windows Maps'
        Pattern     = '*WindowsMaps*'
        Category    = 'Safe'
        Reason      = 'Deprecated - Microsoft announced removal from Store by July 2025.'
        Method      = 'AppX'
        WingetId    = ''
    }

    # --- SAFE TO REMOVE ---
    [PSCustomObject]@{
        Name        = 'Bing News'
        Pattern     = '*BingNews*'
        Category    = 'Safe'
        Reason      = 'Consumer news feed. No utility in IT/MSP environment.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Phone Link (Your Phone)'
        Pattern     = '*YourPhone*'
        Category    = 'Safe'
        Reason      = 'Android phone integration. Remove if not actively used.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Edge Game Assist'
        Pattern     = '*Edge.GameAssist*'
        Category    = 'Safe'
        Reason      = 'Gaming overlay for Edge. No utility in IT/MSP context.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Dev Home'
        Pattern     = '*DevHome*'
        Category    = 'Safe'
        Reason      = 'Developer dashboard app. Separate from Windows Settings.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Local AI Manager (aimgr)'
        Pattern     = '*aimgr*'
        Category    = 'Safe'
        Reason      = 'M365 Copilot+ AI component. Safe to remove if not using Copilot AI.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Sound Recorder'
        Pattern     = '*WindowsSoundRecorder*'
        Category    = 'Safe'
        Reason      = 'Consumer audio recording app.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Windows Camera'
        Pattern     = '*WindowsCamera*'
        Category    = 'Safe'
        Reason      = 'Desktop machine with no camera workflow. Safe to remove.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Widgets Platform Runtime'
        Pattern     = '*WidgetsPlatformRuntime*'
        Category    = 'Safe'
        Reason      = 'Required only for Widgets taskbar panel. Removing disables Widgets button.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Windows Web Experience Pack (Widgets)'
        Pattern     = '*WebExperience*'
        Category    = 'Safe'
        Reason      = 'Required only for Widgets taskbar panel.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Bing Weather'
        Pattern     = '*BingWeather*'
        Category    = 'Safe'
        Reason      = 'Consumer weather app.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Get Help'
        Pattern     = '*GetHelp*'
        Category    = 'Safe'
        Reason      = 'Microsoft virtual support agent. Not needed on managed devices.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Tips / Get Started'
        Pattern     = '*Getstarted*'
        Category    = 'Safe'
        Reason      = 'Windows onboarding tips app.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Office Hub'
        Pattern     = '*MicrosoftOfficeHub*'
        Category    = 'Safe'
        Reason      = 'M365 upsell launcher. Not needed when M365 apps deployed separately.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Skype'
        Pattern     = '*SkypeApp*'
        Category    = 'Safe'
        Reason      = 'Consumer Skype. Not relevant in Teams-based environments.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Feedback Hub'
        Pattern     = '*WindowsFeedbackHub*'
        Category    = 'Safe'
        Reason      = 'Microsoft telemetry and feedback tool. Safe on managed devices.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Xbox App'
        Pattern     = '*XboxApp*'
        Category    = 'Safe'
        Reason      = 'Xbox console companion. Safe on non-gaming devices.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Xbox Game Bar / Overlay'
        Pattern     = '*XboxGamingOverlay*'
        Category    = 'Safe'
        Reason      = 'Gaming overlay. Safe on non-gaming devices.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Xbox Identity Provider'
        Pattern     = '*XboxIdentityProvider*'
        Category    = 'Safe'
        Reason      = 'Xbox sign-in component. Safe if Xbox services unused.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Groove Music / Media Player (legacy)'
        Pattern     = '*ZuneMusic*'
        Category    = 'Safe'
        Reason      = 'Legacy Groove Music rebranded. Superseded by Windows Media Player.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Movies and TV'
        Pattern     = '*ZuneVideo*'
        Category    = 'Safe'
        Reason      = 'Storefront deprecated by Microsoft.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'M365 Companion Apps (Files, People, Calendar)'
        Pattern     = '*M365Companions*'
        Category    = 'Safe'
        Reason      = 'Auto-installed taskbar companion apps. Reinstall unless Admin Center toggle disabled.'
        Method      = 'AppX'
        WingetId    = ''
    }

    # --- REVIEW BEFORE REMOVING ---
    [PSCustomObject]@{
        Name        = 'Microsoft To Do'
        Pattern     = '*Todos*'
        Category    = 'Review'
        Reason      = 'Task management app. Remove only if not in use.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Power Automate Desktop'
        Pattern     = '*PowerAutomateDesktop*'
        Category    = 'Review'
        Reason      = 'Desktop automation. Remove only if not building flows.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Cross Device Experience Host'
        Pattern     = '*CrossDevice*'
        Category    = 'Review'
        Reason      = 'Continue on PC / phone sync. Remove if not using cross-device features.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'Windows Clock / Alarms'
        Pattern     = '*WindowsAlarms*'
        Category    = 'Review'
        Reason      = 'Alarm and timer app. Low risk.'
        Method      = 'AppX'
        WingetId    = ''
    }
    [PSCustomObject]@{
        Name        = 'People (legacy)'
        Pattern     = '*People*'
        Category    = 'Review'
        Reason      = 'Legacy contacts app. Usually safe to remove.'
        Method      = 'AppX'
        WingetId    = ''
    }

    # --- WINGET REMOVALS ---
    [PSCustomObject]@{
        Name        = 'Cortana'
        Pattern     = '*Cortana*'
        Category    = 'Safe'
        Reason      = 'Microsoft assistant. Deprecated in most markets.'
        Method      = 'Winget'
        WingetId    = 'Cortana'
    }
    [PSCustomObject]@{
        Name        = 'Reddit PWA'
        Pattern     = ''
        Category    = 'Review'
        Reason      = 'Progressive Web App install. Remove if not in use.'
        Method      = 'Winget'
        WingetId    = 'Reddit'
    }
)

# ============================================================================
# DUPLICATE / ANOMALY CHECKS
# ============================================================================

function Get-DuplicateCheck {
    Write-Host "=== Duplicate and Anomaly Check ===" -ForegroundColor Cyan

    $anomalies = [System.Collections.Generic.List[PSObject]]::new()

    # Hugo duplicate versions
    $hugo = winget list --id Hugo.Hugo.Extended 2>$null | Select-String "Hugo"
    if (($hugo | Measure-Object).Count -gt 1) {
        $anomalies.Add([PSCustomObject]@{
            Issue  = 'Duplicate Hugo Extended'
            Detail = 'Multiple versions installed. Remove older with: winget uninstall --id Hugo.Hugo.Extended --version 0.152.2'
            Action = 'winget uninstall --id Hugo.Hugo.Extended --version 0.152.2'
        })
    }

    # Notepad++ MSIX alongside Win32
    $nppMsix = Get-AppxPackage -Name "*NotepadPlusPlus*" -ErrorAction SilentlyContinue
    $nppWin32 = winget list --name "Notepad++" 2>$null | Select-String "Notepad\+\+"
    if ($nppMsix -and ($nppWin32 | Measure-Object).Count -gt 0) {
        $anomalies.Add([PSCustomObject]@{
            Issue  = 'Duplicate Notepad++'
            Detail = 'Win32 and MSIX versions both installed. Remove MSIX, keep Win32.'
            Action = 'Get-AppxPackage -Name "*NotepadPlusPlus*" | Remove-AppxPackage'
        })
    }

    # Tailscale dual install
    $tailscale = winget list --name "Tailscale" 2>$null | Select-String "Tailscale"
    if (($tailscale | Measure-Object).Count -gt 1) {
        $anomalies.Add([PSCustomObject]@{
            Issue  = 'Duplicate Tailscale'
            Detail = 'Machine-level and User\X64 ARP entries both present. Likely an older install remnant.'
            Action = 'Investigate via Settings > Apps > Installed apps'
        })
    }

    if ($anomalies.Count -gt 0) {
        Write-Host "Anomalies found: $($anomalies.Count)`n" -ForegroundColor Yellow
        $anomalies | ForEach-Object {
            Write-Host "  Issue  : $($_.Issue)" -ForegroundColor Yellow
            Write-Host "  Detail : $($_.Detail)"
            Write-Host "  Fix    : $($_.Action)`n"
        }
    } else {
        Write-Host "No duplicates or anomalies detected.`n" -ForegroundColor Green
    }

    return $anomalies
}

# ============================================================================
# AUDIT - CHECK WHAT IS INSTALLED
# ============================================================================

function Get-InstalledStatus {
    param ([PSCustomObject]$AppDef)

    if ($AppDef.Method -eq 'AppX' -and $AppDef.Pattern) {
        $pkg = Get-AppxPackage -Name $AppDef.Pattern -ErrorAction SilentlyContinue
        $prv = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
               Where-Object { $_.DisplayName -like $AppDef.Pattern }
        return [PSCustomObject]@{
            Installed    = ($null -ne $pkg)
            Provisioned  = ($null -ne $prv)
            PackageName  = if ($pkg) { $pkg.Name } else { '' }
        }
    }

    if ($AppDef.Method -eq 'Winget' -and $AppDef.WingetId) {
        $result = winget list --name $AppDef.WingetId 2>$null | Select-String $AppDef.WingetId
        return [PSCustomObject]@{
            Installed   = ($null -ne $result)
            Provisioned = $false
            PackageName = $AppDef.WingetId
        }
    }

    return [PSCustomObject]@{ Installed=$false; Provisioned=$false; PackageName='' }
}

# ============================================================================
# REMOVAL
# ============================================================================

function Remove-App {
    param ([PSCustomObject]$AppDef)

    $removed = $false

    if ($AppDef.Method -eq 'AppX') {
        try {
            $pkg = Get-AppxPackage -Name $AppDef.Pattern -ErrorAction SilentlyContinue
            if ($pkg) {
                $pkg | Remove-AppxPackage -ErrorAction Stop
                Write-Host "  Removed (user)       : $($AppDef.Name)" -ForegroundColor Green
                $removed = $true
            }
            $prv = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                   Where-Object { $_.DisplayName -like $AppDef.Pattern }
            if ($prv) {
                $prv | Remove-AppxProvisionedPackage -Online -ErrorAction Stop
                Write-Host "  Removed (provisioned): $($AppDef.Name)" -ForegroundColor Green
                $removed = $true
            }
            if (-not $removed) {
                Write-Host "  Not installed        : $($AppDef.Name)" -ForegroundColor DarkGray
            }
        }
        catch {
            Write-Warning "  Failed: $($AppDef.Name) - $($_.Exception.Message)"
        }
    }

    if ($AppDef.Method -eq 'Winget') {
        try {
            $result = winget uninstall --name $AppDef.WingetId --silent 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Removed (winget)     : $($AppDef.Name)" -ForegroundColor Green
                $removed = $true
            } else {
                Write-Host "  Not found (winget)   : $($AppDef.Name)" -ForegroundColor DarkGray
            }
        }
        catch {
            Write-Warning "  Failed: $($AppDef.Name) - $($_.Exception.Message)"
        }
    }

    return $removed
}

# ============================================================================
# MAIN
# ============================================================================

# Step 1 - Duplicate check
$anomalies = Get-DuplicateCheck

# Step 2 - Audit installed state
Write-Host "=== Auditing Installed Apps ===" -ForegroundColor Cyan
Write-Host "Checking $($AppDefinitions.Count) app definitions...`n"

$auditResults = [System.Collections.Generic.List[PSObject]]::new()

foreach ($app in $AppDefinitions) {
    $status = Get-InstalledStatus -AppDef $app
    $auditResults.Add([PSCustomObject]@{
        Name        = $app.Name
        Category    = $app.Category
        Reason      = $app.Reason
        Method      = $app.Method
        Pattern     = $app.Pattern
        WingetId    = $app.WingetId
        Installed   = $status.Installed
        Provisioned = $status.Provisioned
        PackageName = $status.PackageName
        Removed     = $false
        AppDef      = $app
    })
}

$installed     = $auditResults | Where-Object { $_.Installed -or $_.Provisioned }
$safeApps      = $installed    | Where-Object { $_.Category -eq 'Safe' }
$reviewApps    = $installed    | Where-Object { $_.Category -eq 'Review' }
$notInstalled  = $auditResults | Where-Object { -not $_.Installed -and -not $_.Provisioned }

Write-Host "Results:"
Write-Host "  Installed - Safe to remove   : $($safeApps.Count)" -ForegroundColor Red
Write-Host "  Installed - Review first     : $($reviewApps.Count)" -ForegroundColor Yellow
Write-Host "  Not installed (already clean): $($notInstalled.Count)" -ForegroundColor Green
Write-Host ""

if ($safeApps.Count -gt 0) {
    Write-Host "Safe to remove:" -ForegroundColor Red
    $safeApps | ForEach-Object {
        $provTag = if ($_.Provisioned) { ' [provisioned]' } else { '' }
        Write-Host ("  {0,-45} {1}{2}" -f $_.Name, $_.Reason, $provTag)
    }
    Write-Host ""
}

if ($reviewApps.Count -gt 0) {
    Write-Host "Review before removing:" -ForegroundColor Yellow
    $reviewApps | ForEach-Object {
        Write-Host ("  {0,-45} {1}" -f $_.Name, $_.Reason)
    }
    Write-Host ""
}

# Step 3 - Export audit CSV
$auditResults | Select-Object Name, Category, Installed, Provisioned, Reason, Method, PackageName |
    Export-Csv $ReportPath -NoTypeInformation
Write-Host "Audit report : $ReportPath`n"

# Step 4 - Remove based on mode
if ($AuditOnly) {
    Write-Host "Audit-only mode. No changes made." -ForegroundColor Cyan
    Write-Host "Re-run without -AuditOnly to perform removals.`n"
    exit 0
}

$removedCount = 0

if ($AutoRemove) {
    # Remove all safe apps without prompting
    Write-Host "=== Auto-Removing Safe Apps ===" -ForegroundColor Cyan
    foreach ($app in $safeApps) {
        $result = Remove-App -AppDef $app.AppDef
        if ($result) { $removedCount++ }
    }

    # Prompt for review apps
    if ($reviewApps.Count -gt 0) {
        Write-Host "`n=== Review Apps - Confirm Each ===" -ForegroundColor Yellow
        foreach ($app in $reviewApps) {
            $confirm = (Read-Host "  Remove '$($app.Name)'? ($($app.Reason)) [Y/N]").Trim()
            if ($confirm -match '^(Y|yes)$') {
                $result = Remove-App -AppDef $app.AppDef
                if ($result) { $removedCount++ }
            } else {
                Write-Host "  Skipped: $($app.Name)" -ForegroundColor DarkGray
            }
        }
    }
} else {
    # Interactive mode - prompt for each safe app too
    Write-Host "=== Interactive Removal ===" -ForegroundColor Cyan
    Write-Host "You will be prompted for each installed app.`n"

    foreach ($app in ($safeApps + $reviewApps)) {
        $tag = if ($app.Category -eq 'Safe') { '[SAFE]' } else { '[REVIEW]' }
        $confirm = (Read-Host "  $tag Remove '$($app.Name)'? ($($app.Reason)) [Y/N]").Trim()
        if ($confirm -match '^(Y|yes)$') {
            $result = Remove-App -AppDef $app.AppDef
            if ($result) { $removedCount++ }
        } else {
            Write-Host "  Skipped: $($app.Name)" -ForegroundColor DarkGray
        }
    }
}

# ============================================================================
# M365 COMPANION STARTUP SUPPRESSION
# ============================================================================

$m365 = $auditResults | Where-Object { $_.Name -like '*M365 Companion*' -and $_.Installed }
if ($m365) {
    Write-Host "`nM365 Companion apps detected. Disabling auto-startup..." -ForegroundColor Cyan
    $baseKey    = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\Microsoft.M365Companions_8wekyb3d8bbwe"
    $startupKeys = @("CalendarStartupId", "FilesStartupId", "PeopleStartupId")
    foreach ($key in $startupKeys) {
        $fullPath = Join-Path $baseKey $key
        if (Test-Path $fullPath) {
            Set-ItemProperty -Path $fullPath -Name "State" -Value 1 -ErrorAction SilentlyContinue
            Write-Host "  Startup disabled: $key" -ForegroundColor Green
        }
    }
    Write-Host "  Note: Apps will reinstall unless disabled in M365 Admin Center > Settings > Org Settings > Microsoft 365 on Windows" -ForegroundColor Yellow
}

# ============================================================================
# WINGET UPDATES AVAILABLE
# ============================================================================

Write-Host "`n=== Checking Winget Updates ===" -ForegroundColor Cyan
Write-Host "Running winget upgrade check...`n"
winget upgrade 2>$null | Select-String -NotMatch "^-|^Name|^$|winget" | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
Write-Host "`nTo apply all updates:"
Write-Host "  winget upgrade --all --accept-source-agreements --accept-package-agreements`n"

# ============================================================================
# SUMMARY
# ============================================================================

Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Apps audited      : $($AppDefinitions.Count)"
Write-Host "Installed found   : $($installed.Count)"
Write-Host "Safe to remove    : $($safeApps.Count)"
Write-Host "Review items      : $($reviewApps.Count)"
Write-Host "Removed this run  : $removedCount"
Write-Host "Anomalies found   : $($anomalies.Count)"
Write-Host "Report saved      : $ReportPath"
if ($m365) { Write-Host "M365 Companions   : startup suppressed - disable Admin Center toggle to prevent reinstall" -ForegroundColor Yellow }
Write-Host ""
