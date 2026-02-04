<#
.SYNOPSIS
    Caddy reverse proxy setup for LibreHardwareMonitor via Tailscale.

.DESCRIPTION
    Installs and configures Caddy as a reverse proxy for LibreHardwareMonitor,
    binding to your Tailscale IP for secure remote access.
    
    Prerequisites:
    - Tailscale installed and connected
    - LibreHardwareMonitor installed with web server enabled
    
    LibreHardwareMonitor Setup:
    1. Download from: https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases
    2. Extract and run LibreHardwareMonitor.exe
    3. Options > Remote Web Server > Run (enable)
    4. Options > Remote Web Server > Port: 8085
    5. Options > Remote Web Server > IP: Select your LAN IP (not Hyper-V)

.PARAMETER Action
    Install, Uninstall, Status, Test, or Menu

.PARAMETER InstallPath
    Caddy installation directory (default: C:\Caddy)

.PARAMETER ProxyPort
    Port for Caddy to listen on (default: 8086)

.PARAMETER UpstreamPort
    LibreHardwareMonitor port (default: 8085)

.PARAMETER UpstreamIP
    LibreHardwareMonitor IP (default: 127.0.0.1)

.PARAMETER TailscaleIP
    Tailscale IP to bind to (default: auto-detect)

.PARAMETER Force
    Skip confirmation prompts

.EXAMPLE
    .\Setup-CaddyProxy.ps1
    Interactive menu

.EXAMPLE
    .\Setup-CaddyProxy.ps1 -Action Install -Force
    Automated installation with defaults

.EXAMPLE
    .\Setup-CaddyProxy.ps1 -Action Install -UpstreamIP 10.1.10.20
    Install with custom LHM IP

.NOTES
    Author: Andrew Jones
    Version: 3.0
    Date: 2026-02-04
    
    LibreHardwareMonitor: https://github.com/LibreHardwareMonitor/LibreHardwareMonitor
#>

#Requires -RunAsAdministrator
#Requires -Version 5.1

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateSet("Install", "Uninstall", "Status", "Test", "Menu")]
    [string]$Action = "Menu",

    [Parameter()]
    [string]$InstallPath = "C:\Caddy",

    [Parameter()]
    [int]$ProxyPort = 8086,

    [Parameter()]
    [int]$UpstreamPort = 8085,

    [Parameter()]
    [string]$UpstreamIP = "127.0.0.1",

    [Parameter()]
    [string]$TailscaleIP,

    [Parameter()]
    [switch]$Force
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$Script:Config = @{
    CaddyDownloadUrl  = "https://caddyserver.com/api/download?os=windows&arch=amd64"
    CaddyExe          = "caddy.exe"
    CaddyFile         = "Caddyfile"
    ServiceName       = "Caddy"
    FirewallRule      = "Caddy Reverse Proxy"
    LHMGitHub         = "https://github.com/LibreHardwareMonitor/LibreHardwareMonitor"
    LHMReleases       = "https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases"
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "HEADER")]
        [string]$Level = "INFO"
    )
    $colors = @{
        "INFO"    = "Cyan"
        "SUCCESS" = "Green"
        "WARNING" = "Yellow"
        "ERROR"   = "Red"
        "HEADER"  = "Magenta"
    }
    $prefix = switch ($Level) {
        "HEADER"  { "`n=== " }
        "SUCCESS" { "[+] " }
        "ERROR"   { "[-] " }
        "WARNING" { "[!] " }
        default   { "[*] " }
    }
    $suffix = if ($Level -eq "HEADER") { " ===" } else { "" }
    Write-Host "$prefix$Message$suffix" -ForegroundColor $colors[$Level]
}

function Test-TailscaleInstalled {
    $tailscale = Get-Command tailscale -ErrorAction SilentlyContinue
    return $null -ne $tailscale
}

function Get-TailscaleIP {
    if (-not (Test-TailscaleInstalled)) { return $null }
    try {
        $ip = & tailscale ip -4 2>$null
        if ($ip -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
            return $ip.Trim()
        }
    }
    catch { return $null }
    return $null
}

function Test-PortOpen {
    param (
        [string]$ComputerName,
        [int]$Port
    )
    try {
        # Using Test-NetConnection is reliable for localhost/loopback
        $result = Test-NetConnection -ComputerName $ComputerName -Port $Port -WarningAction SilentlyContinue -InformationLevel Quiet
        return $result
    }
    catch { 
        return $false 
    }
}

function Confirm-Action {
    param ([string]$Message)
    if ($Force) { return $true }
    $response = Read-Host "$Message (Y/N)"
    return $response -match '^[Yy]'
}

# ============================================================================
# CADDY FUNCTIONS
# ============================================================================

function Install-Caddy {
    Write-Log "Installing Caddy..." "HEADER"
    
    # Create directory
    if (-not (Test-Path $InstallPath)) {
        New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
        Write-Log "Created directory: $InstallPath" "SUCCESS"
    }
    
    # Create subdirectories
    @("data", "logs") | ForEach-Object {
        $subDir = Join-Path $InstallPath $_
        if (-not (Test-Path $subDir)) {
            New-Item -ItemType Directory -Path $subDir -Force | Out-Null
        }
    }
    
    # Download
    $exePath = Join-Path $InstallPath $Script:Config.CaddyExe
    Write-Log "Downloading Caddy..." "INFO"
    try {
        Invoke-WebRequest -Uri $Script:Config.CaddyDownloadUrl -OutFile $exePath -UseBasicParsing
        Write-Log "Download complete" "SUCCESS"
    }
    catch {
        Write-Log "Download failed: $_" "ERROR"
        return $false
    }
    
    # Verify
    $version = & $exePath version 2>$null
    if ($version) {
        Write-Log "Caddy version: $version" "SUCCESS"
    }
    else {
        Write-Log "Could not verify Caddy" "ERROR"
        return $false
    }
    
    return $true
}

function New-Caddyfile {
    Write-Log "Creating Caddyfile..." "HEADER"
    
    $caddyfilePath = Join-Path $InstallPath $Script:Config.CaddyFile
    
    $caddyfileContent = @"
# Caddy Reverse Proxy for LibreHardwareMonitor
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# Tailscale IP: $($Script:TailscaleIP)
# Upstream: $($UpstreamIP):$($UpstreamPort)

$($Script:TailscaleIP):$ProxyPort {
    reverse_proxy $($UpstreamIP):$($UpstreamPort)
    tls internal
}
"@
    
    try {
        $caddyfileContent | Out-File -FilePath $caddyfilePath -Encoding UTF8 -Force
        Write-Log "Created Caddyfile: $caddyfilePath" "SUCCESS"
        
        Write-Host "`n--- Caddyfile Contents ---" -ForegroundColor DarkGray
        Get-Content $caddyfilePath | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        Write-Host "--- End Caddyfile ---`n" -ForegroundColor DarkGray
        
        return $true
    }
    catch {
        Write-Log "Failed to create Caddyfile: $_" "ERROR"
        return $false
    }
}

function Install-CaddyService {
    Write-Log "Installing Caddy service..." "HEADER"
    
    $exePath = Join-Path $InstallPath $Script:Config.CaddyExe
    $configPath = Join-Path $InstallPath $Script:Config.CaddyFile
    $serviceName = $Script:Config.ServiceName
    
    # Remove existing
    $existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-Log "Removing existing service..." "INFO"
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        & sc.exe delete $serviceName 2>$null | Out-Null
        Start-Sleep -Seconds 2
    }
    
    # Create service
    $binPath = "`"$exePath`" run --config `"$configPath`""
    
    $result = & sc.exe create $serviceName start= auto binPath= $binPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to create service: $result" "ERROR"
        return $false
    }
    Write-Log "Created service: $serviceName" "SUCCESS"
    
    # Configure recovery
    & sc.exe failure $serviceName reset= 86400 actions= restart/60000/restart/60000/restart/60000 2>$null | Out-Null
    & sc.exe description $serviceName "Caddy reverse proxy for LibreHardwareMonitor via Tailscale" 2>$null | Out-Null
    Write-Log "Configured auto-restart on failure" "SUCCESS"
    
    # Start service
    Write-Log "Starting service..." "INFO"
    try {
        Start-Service -Name $serviceName -ErrorAction Stop
        Start-Sleep -Seconds 2
        $service = Get-Service -Name $serviceName
        if ($service.Status -eq "Running") {
            Write-Log "Service started" "SUCCESS"
            return $true
        }
        else {
            Write-Log "Service status: $($service.Status)" "WARNING"
            return $false
        }
    }
    catch {
        Write-Log "Failed to start service: $_" "ERROR"
        return $false
    }
}

function Set-FirewallRule {
    Write-Log "Configuring firewall rule..." "INFO"
    
    $exePath = Join-Path $InstallPath $Script:Config.CaddyExe
    $ruleName = $Script:Config.FirewallRule
    
    # Remove existing
    Remove-NetFirewallRule -DisplayName "$ruleName*" -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName "Caddy*" -ErrorAction SilentlyContinue
    
    try {
        New-NetFirewallRule -DisplayName $ruleName `
            -Direction Inbound `
            -Program $exePath `
            -Action Allow `
            -Profile Any `
            -Description "Allow Caddy reverse proxy for Tailscale access" | Out-Null
        
        Write-Log "Firewall rule created" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to create firewall rule: $_" "ERROR"
        return $false
    }
}

# ============================================================================
# WORKFLOW FUNCTIONS
# ============================================================================

function Select-UpstreamIP {
    Clear-Host
    Write-Host "`n  ╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║           LHM Upstream IP Scanner                     ║" -ForegroundColor Cyan
    Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Scanning local interfaces for Port $UpstreamPort..." -ForegroundColor Gray
    Write-Host ""

    # 1. Gather all potential IPs (Localhost + LAN IPs)
    $ipList = @("127.0.0.1")
    try {
        $adapters = Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" }
        $ipList += $adapters.IPAddress
    } catch {
        Write-Log "Could not enumerate network adapters." "WARNING"
    }

    # 2. Test each IP and display status
    $validOptions = @()
    for ($i = 0; $i -lt $ipList.Count; $i++) {
        $currentIP = $ipList[$i]
        
        # Test connection immediately
        $isResponsive = Test-PortOpen -ComputerName $currentIP -Port $UpstreamPort
        
        # Format the output
        $indexTag = "  [$($i+1)]".PadRight(7)
        $ipTag    = "$currentIP".PadRight(18)
        
        if ($isResponsive) { 
            Write-Host "$indexTag$ipTag" -NoNewline -ForegroundColor White
            Write-Host " [FOUND LHM!] " -ForegroundColor Green
            $validOptions += $currentIP
        } else {
            Write-Host "$indexTag$ipTag" -NoNewline -ForegroundColor Gray
            Write-Host " [No Response] " -ForegroundColor DarkGray
        }
    }

    # 3. Handle Selection
    Write-Host ""
    if ($validOptions.Count -gt 0) {
        Write-Host "  LHM was detected on $($validOptions.Count) interface(s)." -ForegroundColor Green
    } else {
        Write-Host "  LHM was not detected on any interface." -ForegroundColor Red
        Write-Host "  Ensure LHM is running and the Web Server is enabled." -ForegroundColor Yellow
    }

    $choice = Read-Host "  Select IP number to use [1-$($ipList.Count)] or Enter to cancel"

    if ($choice -match '^\d+$' -and $choice -ge 1 -and $choice -le $ipList.Count) {
        $selected = $ipList[$choice-1]
        
        # Update the Script-Scope variable so the rest of the script uses it
        $Script:UpstreamIP = $selected
        
        Write-Host ""
        Write-Log "Upstream IP updated to: $selected" "SUCCESS"
        Start-Sleep -Seconds 2
    }
}

function Test-Prerequisites {
    Write-Log "Checking prerequisites..." "HEADER"
    
    $passed = $true
    
    # Check Tailscale
    if (Test-TailscaleInstalled) {
        $Script:TailscaleIP = if ($TailscaleIP) { $TailscaleIP } else { Get-TailscaleIP }
        if ($Script:TailscaleIP) {
            Write-Log "Tailscale IP: $($Script:TailscaleIP)" "SUCCESS"
        }
        else {
            Write-Log "Tailscale not connected" "ERROR"
            $passed = $false
        }
    }
    else {
        Write-Log "Tailscale not installed" "ERROR"
        $passed = $false
    }
    
    # Check LHM upstream
    Write-Log "Checking LibreHardwareMonitor at $($UpstreamIP):$($UpstreamPort)..." "INFO"
    if (Test-PortOpen -ComputerName $UpstreamIP -Port $UpstreamPort) {
        Write-Log "LibreHardwareMonitor responding" "SUCCESS"
    }
    else {
        Write-Log "LibreHardwareMonitor not responding on $($UpstreamIP):$($UpstreamPort)" "WARNING"
        Write-Log "Make sure LHM is running with web server enabled" "WARNING"
        Write-Log "Download: $($Script:Config.LHMReleases)" "INFO"
    }
    
    return $passed
}

function Invoke-Installation {
    Write-Log "Starting Caddy Installation" "HEADER"
    
    if (-not (Test-Prerequisites)) {
        Write-Log "Prerequisites check failed" "ERROR"
        return $false
    }
    
    if (-not (Install-Caddy)) { return $false }
    if (-not (New-Caddyfile)) { return $false }
    if (-not (Set-FirewallRule)) { return $false }
    if (-not (Install-CaddyService)) { return $false }
    
    # Final verification
    Test-Installation
    
    return $true
}

function Invoke-Uninstall {
    Write-Log "Uninstalling Caddy..." "HEADER"
    
    if (-not $Force) {
        if (-not (Confirm-Action "This will remove Caddy. Continue?")) {
            Write-Log "Uninstall cancelled" "INFO"
            return $false
        }
    }
    
    # Stop and remove service
    $service = Get-Service -Name $Script:Config.ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        Write-Log "Removing service..." "INFO"
        Stop-Service -Name $Script:Config.ServiceName -Force -ErrorAction SilentlyContinue
        & sc.exe delete $Script:Config.ServiceName 2>$null | Out-Null
        Write-Log "Service removed" "SUCCESS"
    }
    
    # Remove firewall rules
    Remove-NetFirewallRule -DisplayName "$($Script:Config.FirewallRule)*" -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName "Caddy*" -ErrorAction SilentlyContinue
    Write-Log "Firewall rules removed" "SUCCESS"
    
    # Remove files
    if (Test-Path $InstallPath) {
        Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Removed directory: $InstallPath" "SUCCESS"
    }
    
    Write-Log "Uninstall complete" "SUCCESS"
    return $true
}

function Test-Installation {
    Write-Log "Verifying Installation" "HEADER"
    
    $allPassed = $true
    
    # Check Caddy Service
    $service = Get-Service -Name $Script:Config.ServiceName -ErrorAction SilentlyContinue
    Write-Host "  Caddy Service:   " -NoNewline
    if ($service -and $service.Status -eq "Running") {
        Write-Host "Running" -ForegroundColor Green
    }
    else {
        Write-Host "Not Running" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Check Caddy Port
    Write-Host "  Proxy Port:      " -NoNewline
    if ($Script:TailscaleIP -and (Test-PortOpen -ComputerName $Script:TailscaleIP -Port $ProxyPort)) {
        Write-Host "Listening ($($Script:TailscaleIP):$ProxyPort)" -ForegroundColor Green
    }
    else {
        Write-Host "Not Responding" -ForegroundColor Red
        $allPassed = $false
    }
    
    # Check LHM Upstream
    Write-Host "  LHM Upstream:    " -NoNewline
    if (Test-PortOpen -ComputerName $UpstreamIP -Port $UpstreamPort) {
        Write-Host "Responding ($($UpstreamIP):$($UpstreamPort))" -ForegroundColor Green
    }
    else {
        Write-Host "Not Responding" -ForegroundColor Yellow
    }
    
    # Summary
    if ($allPassed) {
        Write-Host ""
        Write-Log "Installation verified!" "SUCCESS"
        Write-Host ""
        Write-Host "  ╔═══════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "  ║                    ACCESS URL                         ║" -ForegroundColor Green
        Write-Host "  ╠═══════════════════════════════════════════════════════╣" -ForegroundColor Green
        Write-Host "  ║  " -ForegroundColor Green -NoNewline
        Write-Host "https://$($Script:TailscaleIP):$ProxyPort/" -ForegroundColor Cyan -NoNewline
        $padding = 55 - "https://$($Script:TailscaleIP):$ProxyPort/".Length - 2
        Write-Host (" " * $padding) -NoNewline
        Write-Host "║" -ForegroundColor Green
        Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Note: Accept the self-signed certificate warning" -ForegroundColor Yellow
    }
    else {
        Write-Log "Some components failed verification" "WARNING"
    }
    
    return $allPassed
}

function Show-Status {
    $Script:TailscaleIP = if ($TailscaleIP) { $TailscaleIP } else { Get-TailscaleIP }
    
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║          Caddy Proxy Status                           ║" -ForegroundColor Cyan
    Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    # Tailscale
    Write-Host "  Tailscale IP:    " -NoNewline
    if ($Script:TailscaleIP) {
        Write-Host $Script:TailscaleIP -ForegroundColor Green
    }
    else {
        Write-Host "Not Connected" -ForegroundColor Red
    }
    
    # Caddy Service
    $service = Get-Service -Name $Script:Config.ServiceName -ErrorAction SilentlyContinue
    Write-Host "  Caddy Service:   " -NoNewline
    if ($service) {
        $color = if ($service.Status -eq "Running") { "Green" } else { "Yellow" }
        Write-Host $service.Status -ForegroundColor $color
    }
    else {
        Write-Host "Not Installed" -ForegroundColor Red
    }
    
    # Caddy Port
    Write-Host "  Proxy Port:      " -NoNewline
    if ($Script:TailscaleIP -and (Test-PortOpen -ComputerName $Script:TailscaleIP -Port $ProxyPort)) {
        Write-Host "Listening (:$ProxyPort)" -ForegroundColor Green
    }
    else {
        Write-Host "Not Responding" -ForegroundColor Red
    }
    
    # LHM Upstream
    Write-Host "  LHM Upstream:    " -NoNewline
    if (Test-PortOpen -ComputerName $UpstreamIP -Port $UpstreamPort) {
        Write-Host "Responding ($($UpstreamIP):$($UpstreamPort))" -ForegroundColor Green
    }
    else {
        Write-Host "Not Responding" -ForegroundColor Yellow
    }
    
    # Access URL
    if ($Script:TailscaleIP -and $service -and $service.Status -eq "Running") {
        Write-Host ""
        Write-Host "  Access URL:      " -NoNewline
        Write-Host "https://$($Script:TailscaleIP):$ProxyPort/" -ForegroundColor Cyan
    }
}

function Show-LHMSetup {
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "  ║     LibreHardwareMonitor Setup Instructions           ║" -ForegroundColor Magenta
    Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  1. Download LibreHardwareMonitor:" -ForegroundColor White
    Write-Host "     $($Script:Config.LHMReleases)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  2. Extract and run " -NoNewline -ForegroundColor White
    Write-Host "LibreHardwareMonitor.exe" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  3. Enable Web Server:" -ForegroundColor White
    Write-Host "     Options > Remote Web Server > Run (check)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  4. Configure Port:" -ForegroundColor White
    Write-Host "     Options > Remote Web Server > Port: " -NoNewline -ForegroundColor Gray
    Write-Host "$UpstreamPort" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  5. Select correct IP (important!):" -ForegroundColor White
    Write-Host "     Options > Remote Web Server > IP: " -NoNewline -ForegroundColor Gray
    Write-Host "Your LAN IP" -ForegroundColor Yellow
    Write-Host "     (Avoid Hyper-V IPs like 172.x.x.x)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  6. (Optional) Disable Authentication:" -ForegroundColor White
    Write-Host "     Caddy + Tailscale provides security layer" -ForegroundColor Gray
    Write-Host ""
}

function Show-InteractiveMenu {
    while ($true) {
        Clear-Host
        Show-Status
        
        Write-Host ""
        Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  [1] Install Caddy Proxy"
        Write-Host "  [2] Uninstall Caddy"
        Write-Host "  [3] Test Installation"
        Write-Host "  [4] Restart Caddy Service"
        Write-Host "  [5] View Caddyfile"
        Write-Host "  [6] Edit Caddyfile"
        Write-Host "  [7] LHM Setup Instructions"
        Write-Host "  [8] Open Install Folder"
        Write-Host "  [S] Scan/Select Upstream IP"  # <--- NEW OPTION
        Write-Host "  [Q] Quit"
        Write-Host ""
        
        $choice = Read-Host "  Select option"
        
        switch ($choice.ToUpper()) {
            "1" {
                Invoke-Installation
                Read-Host "`n  Press Enter to continue"
            }
            "2" {
                Invoke-Uninstall
                Read-Host "`n  Press Enter to continue"
            }
            "3" {
                Test-Installation
                Read-Host "`n  Press Enter to continue"
            }
            "4" {
                Write-Log "Restarting Caddy service..." "INFO"
                Restart-Service -Name $Script:Config.ServiceName -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                $svc = Get-Service -Name $Script:Config.ServiceName -ErrorAction SilentlyContinue
                if ($svc -and $svc.Status -eq "Running") {
                    Write-Log "Service restarted" "SUCCESS"
                }
                else {
                    Write-Log "Service restart failed" "ERROR"
                }
                Read-Host "`n  Press Enter to continue"
            }
            "5" {
                $caddyfilePath = Join-Path $InstallPath $Script:Config.CaddyFile
                if (Test-Path $caddyfilePath) {
                    Write-Host ""
                    Get-Content $caddyfilePath
                }
                else {
                    Write-Log "Caddyfile not found" "ERROR"
                }
                Read-Host "`n  Press Enter to continue"
            }
            "6" {
                $caddyfilePath = Join-Path $InstallPath $Script:Config.CaddyFile
                if (Test-Path $caddyfilePath) {
                    notepad $caddyfilePath
                    Write-Log "Remember to restart Caddy after editing" "WARNING"
                }
                else {
                    Write-Log "Caddyfile not found" "ERROR"
                }
                Read-Host "`n  Press Enter to continue"
            }
            "7" {
                Show-LHMSetup
                Read-Host "`n  Press Enter to continue"
            }
            "8" {
                if (Test-Path $InstallPath) {
                    explorer.exe $InstallPath
                }
                else {
                    Write-Log "Install path does not exist" "ERROR"
                    Read-Host "`n  Press Enter to continue"
                }
            }
            "S" {  # <--- NEW SWITCH CASE
                Select-UpstreamIP
            } 
            "Q" {
                return
            }
        }
    }
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

$Script:TailscaleIP = if ($TailscaleIP) { $TailscaleIP } else { Get-TailscaleIP }

switch ($Action) {
    "Menu" {
        Show-InteractiveMenu
    }
    "Install" {
        Invoke-Installation
    }
    "Uninstall" {
        Invoke-Uninstall
    }
    "Status" {
        Show-Status
    }
    "Test" {
        Test-Installation
    }
}
