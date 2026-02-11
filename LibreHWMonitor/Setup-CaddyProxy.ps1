<#
.SYNOPSIS
    Caddy reverse proxy setup for LibreHardwareMonitor via Tailscale with optional authentication.

.DESCRIPTION
    Installs and configures Caddy as a reverse proxy for LibreHardwareMonitor,
    binding to your Tailscale IP for secure remote access. Supports HTTP Basic
    Authentication using Caddy's built-in bcrypt password hashing.
    
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

.PARAMETER EnableAuth
    Enable HTTP Basic Authentication

.PARAMETER AuthUsername
    Username for basic auth (default: admin)

.PARAMETER FirewallScope
    Firewall rule scope: TailscaleOnly, LAN, or Any (default: TailscaleOnly)

.PARAMETER AllowedAddresses
    Comma-separated list of allowed addresses/subnets for LAN scope

.PARAMETER Force
    Skip confirmation prompts

.EXAMPLE
    .\Setup-CaddyProxy.ps1
    Interactive menu

.EXAMPLE
    .\Setup-CaddyProxy.ps1 -Action Install -Force
    Automated installation with defaults (no auth, Tailscale-only firewall)

.EXAMPLE
    .\Setup-CaddyProxy.ps1 -Action Install -EnableAuth -AuthUsername "monitor"
    Install with authentication enabled (prompts for password)

.EXAMPLE
    .\Setup-CaddyProxy.ps1 -Action Install -FirewallScope LAN -AllowedAddresses "10.1.10.0/24"
    Install with LAN access restricted to specified subnet

.EXAMPLE
    .\Setup-CaddyProxy.ps1 -Action Install -FirewallScope LAN -AllowedAddresses "10.1.10.10,10.1.10.30"
    Install with LAN access restricted to specific hosts

.NOTES
    Author: Andrew Jones
    Version: 5.0
    Date: 2026-02-05
    
    Authentication: Uses Caddy's built-in HTTP Basic Auth with bcrypt hashing
    LibreHardwareMonitor: https://github.com/LibreHardwareMonitor/LibreHardwareMonitor
    Caddy basicauth: https://caddyserver.com/docs/caddyfile/directives/basicauth
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
    [switch]$EnableAuth,

    [Parameter()]
    [string]$AuthUsername = "admin",

    [Parameter()]
    [ValidateSet("TailscaleOnly", "LAN", "Any")]
    [string]$FirewallScope = "TailscaleOnly",

    [Parameter()]
    [string]$AllowedAddresses,

    [Parameter()]
    [switch]$Force
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$Script:Config = @{
    CaddyDownloadUrl   = "https://caddyserver.com/api/download?os=windows&arch=amd64"
    CaddyExe           = "caddy.exe"
    CaddyFile          = "Caddyfile"
    AuthFile           = "auth.json"
    FirewallFile       = "firewall.json"
    ServiceName        = "Caddy"
    FirewallRuleBase   = "Caddy Reverse Proxy"
    TailscaleRange     = "100.64.0.0/10"
    LHMGitHub          = "https://github.com/LibreHardwareMonitor/LibreHardwareMonitor"
    LHMReleases        = "https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases"
}

# Script-scope auth settings
$Script:AuthEnabled = $EnableAuth
$Script:AuthUser = $AuthUsername
$Script:AuthHash = $null

# Script-scope firewall settings
$Script:FWScope = $FirewallScope
$Script:FWAllowedAddresses = $AllowedAddresses

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
# FIREWALL FUNCTIONS
# ============================================================================

function Get-FirewallRules {
    <#
    .SYNOPSIS
        Get all Caddy-related firewall rules
    #>
    $rules = Get-NetFirewallRule -DisplayName "$($Script:Config.FirewallRuleBase)*" -ErrorAction SilentlyContinue
    return $rules
}

function Show-FirewallStatus {
    <#
    .SYNOPSIS
        Display current firewall rules for Caddy
    #>
    $rules = Get-FirewallRules
    
    if (-not $rules) {
        Write-Host "  No Caddy firewall rules found" -ForegroundColor Yellow
        return
    }
    
    foreach ($rule in $rules) {
        $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule
        $addressFilter = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $rule
        
        Write-Host ""
        Write-Host "  Rule: " -NoNewline
        Write-Host $rule.DisplayName -ForegroundColor Cyan
        Write-Host "  Status: " -NoNewline
        if ($rule.Enabled -eq "True") {
            Write-Host "Enabled" -ForegroundColor Green
        }
        else {
            Write-Host "Disabled" -ForegroundColor Red
        }
        Write-Host "  Direction: " -NoNewline
        Write-Host $rule.Direction -ForegroundColor White
        Write-Host "  Action: " -NoNewline
        Write-Host $rule.Action -ForegroundColor White
        Write-Host "  Protocol: " -NoNewline
        Write-Host $portFilter.Protocol -ForegroundColor White
        Write-Host "  Port: " -NoNewline
        Write-Host $portFilter.LocalPort -ForegroundColor White
        Write-Host "  Remote Addresses: " -NoNewline
        Write-Host $addressFilter.RemoteAddress -ForegroundColor White
        Write-Host "  Profile: " -NoNewline
        Write-Host $rule.Profile -ForegroundColor White
    }
}

function Set-FirewallRule {
    <#
    .SYNOPSIS
        Create firewall rule with specified scope
    .PARAMETER Scope
        TailscaleOnly, LAN, or Any
    .PARAMETER Addresses
        For LAN scope: comma-separated addresses/subnets
    #>
    param (
        [ValidateSet("TailscaleOnly", "LAN", "Any")]
        [string]$Scope = "TailscaleOnly",
        
        [string]$Addresses
    )
    
    Write-Log "Configuring firewall rule (Scope: $Scope)..." "INFO"
    
    # Remove existing Caddy rules
    Remove-FirewallRules -Silent
    
    $ruleName = $Script:Config.FirewallRuleBase
    $ruleParams = @{
        DisplayName = $ruleName
        Direction   = "Inbound"
        Protocol    = "TCP"
        LocalPort   = $ProxyPort
        Action      = "Allow"
        Enabled     = "True"
    }
    
    switch ($Scope) {
        "TailscaleOnly" {
            $ruleParams.DisplayName = "$ruleName (Tailscale Only)"
            $ruleParams.RemoteAddress = $Script:Config.TailscaleRange
            $ruleParams.Profile = "Any"
            $ruleParams.Description = "Allow Caddy reverse proxy - Tailscale CGNAT range only (100.64.0.0/10)"
        }
        "LAN" {
            if ([string]::IsNullOrWhiteSpace($Addresses)) {
                Write-Log "LAN scope requires addresses to be specified" "ERROR"
                return $false
            }
            $ruleParams.DisplayName = "$ruleName (LAN Restricted)"
            $ruleParams.RemoteAddress = $Addresses -split ',' | ForEach-Object { $_.Trim() }
            $ruleParams.Profile = "Private,Domain"
            $ruleParams.Description = "Allow Caddy reverse proxy - Restricted to: $Addresses"
        }
        "Any" {
            $ruleParams.DisplayName = "$ruleName (Any)"
            $ruleParams.Profile = "Any"
            $ruleParams.Description = "Allow Caddy reverse proxy - All addresses (least secure)"
        }
    }
    
    try {
        New-NetFirewallRule @ruleParams | Out-Null
        Write-Log "Firewall rule created: $($ruleParams.DisplayName)" "SUCCESS"
        
        # Save config
        Save-FirewallConfig -Scope $Scope -Addresses $Addresses
        
        return $true
    }
    catch {
        Write-Log "Failed to create firewall rule: $_" "ERROR"
        return $false
    }
}

function Remove-FirewallRules {
    <#
    .SYNOPSIS
        Remove all Caddy firewall rules
    #>
    param (
        [switch]$Silent
    )
    
    $rules = Get-FirewallRules
    
    if ($rules) {
        foreach ($rule in $rules) {
            Remove-NetFirewallRule -DisplayName $rule.DisplayName -ErrorAction SilentlyContinue
            if (-not $Silent) {
                Write-Log "Removed rule: $($rule.DisplayName)" "SUCCESS"
            }
        }
        
        # Clear saved config
        $fwConfigPath = Join-Path $InstallPath $Script:Config.FirewallFile
        if (Test-Path $fwConfigPath) {
            Remove-Item $fwConfigPath -Force -ErrorAction SilentlyContinue
        }
        
        return $true
    }
    else {
        if (-not $Silent) {
            Write-Log "No Caddy firewall rules found" "INFO"
        }
        return $false
    }
}

function Save-FirewallConfig {
    <#
    .SYNOPSIS
        Save firewall configuration to file
    #>
    param (
        [string]$Scope,
        [string]$Addresses
    )
    
    $fwConfigPath = Join-Path $InstallPath $Script:Config.FirewallFile
    
    $fwConfig = @{
        Scope     = $Scope
        Addresses = $Addresses
        Port      = $ProxyPort
        Updated   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
    
    try {
        $fwConfig | ConvertTo-Json | Out-File -FilePath $fwConfigPath -Encoding UTF8 -Force
        return $true
    }
    catch {
        Write-Log "Failed to save firewall config: $_" "WARNING"
        return $false
    }
}

function Read-FirewallConfig {
    <#
    .SYNOPSIS
        Load firewall configuration from file
    #>
    $fwConfigPath = Join-Path $InstallPath $Script:Config.FirewallFile
    
    if (Test-Path $fwConfigPath) {
        try {
            $fwConfig = Get-Content $fwConfigPath -Raw | ConvertFrom-Json
            $Script:FWScope = $fwConfig.Scope
            $Script:FWAllowedAddresses = $fwConfig.Addresses
            return $true
        }
        catch {
            return $false
        }
    }
    return $false
}

function Show-FirewallMenu {
    <#
    .SYNOPSIS
        Firewall management submenu
    #>
    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host "  ╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "  ║          Firewall Rule Management                     ║" -ForegroundColor Cyan
        Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        
        # Show current rules
        Show-FirewallStatus
        
        Write-Host ""
        Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  [1] Tailscale Only (100.64.0.0/10) - Recommended"
        Write-Host "  [2] LAN Restricted (specify addresses)"
        Write-Host "  [3] Any (all addresses) - Least secure"
        Write-Host "  [4] Remove All Caddy Rules"
        Write-Host "  [5] Refresh Status"
        Write-Host "  [B] Back to Main Menu"
        Write-Host ""
        
        $choice = Read-Host "  Select option"
        
        switch ($choice.ToUpper()) {
            "1" {
                Set-FirewallRule -Scope "TailscaleOnly"
                Read-Host "`n  Press Enter to continue"
            }
            "2" {
                Write-Host ""
                Write-Host "  Enter allowed addresses (comma-separated)" -ForegroundColor Cyan
                Write-Host "  Examples:" -ForegroundColor Gray
                Write-Host "    Single IP:    10.1.10.10" -ForegroundColor Gray
                Write-Host "    Multiple IPs: 10.1.10.10,10.1.10.30" -ForegroundColor Gray
                Write-Host "    Subnet:       10.1.10.0/24" -ForegroundColor Gray
                Write-Host "    Mixed:        10.1.10.10,192.168.1.0/24" -ForegroundColor Gray
                Write-Host ""
                
                $addresses = Read-Host "  Addresses"
                
                if ([string]::IsNullOrWhiteSpace($addresses)) {
                    Write-Log "No addresses specified" "WARNING"
                }
                else {
                    Set-FirewallRule -Scope "LAN" -Addresses $addresses
                }
                Read-Host "`n  Press Enter to continue"
            }
            "3" {
                Write-Host ""
                Write-Log "Warning: This allows connections from any IP address" "WARNING"
                if (Confirm-Action "  Create unrestricted firewall rule?") {
                    Set-FirewallRule -Scope "Any"
                }
                Read-Host "`n  Press Enter to continue"
            }
            "4" {
                if (Confirm-Action "  Remove all Caddy firewall rules?") {
                    Remove-FirewallRules
                }
                Read-Host "`n  Press Enter to continue"
            }
            "5" {
                # Just refresh - loop continues
            }
            "B" {
                return
            }
        }
    }
}

# ============================================================================
# AUTHENTICATION FUNCTIONS
# ============================================================================

function Get-CaddyPasswordHash {
    <#
    .SYNOPSIS
        Generate bcrypt password hash using Caddy's hash-password command
    #>
    param (
        [Parameter(Mandatory)]
        [SecureString]$Password
    )
    
    $exePath = Join-Path $InstallPath $Script:Config.CaddyExe
    
    if (-not (Test-Path $exePath)) {
        Write-Log "Caddy not installed. Install Caddy first." "ERROR"
        return $null
    }
    
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    
    try {
        $hash = $plainPassword | & $exePath hash-password 2>$null
        
        if ($hash -and $hash -match '^\$2[aby]?\$') {
            return $hash.Trim()
        }
        else {
            Write-Log "Failed to generate password hash" "ERROR"
            return $null
        }
    }
    catch {
        Write-Log "Error generating hash: $_" "ERROR"
        return $null
    }
    finally {
        $plainPassword = $null
        [System.GC]::Collect()
    }
}

function Request-AuthCredentials {
    <#
    .SYNOPSIS
        Prompt user for authentication credentials
    #>
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║           Authentication Setup                        ║" -ForegroundColor Cyan
    Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    $defaultUser = $Script:AuthUser
    $inputUser = Read-Host "  Username [$defaultUser]"
    if ([string]::IsNullOrWhiteSpace($inputUser)) {
        $Script:AuthUser = $defaultUser
    }
    else {
        $Script:AuthUser = $inputUser.Trim()
    }
    
    $passwordMatch = $false
    $attempts = 0
    
    while (-not $passwordMatch -and $attempts -lt 3) {
        Write-Host ""
        $password1 = Read-Host "  Password" -AsSecureString
        $password2 = Read-Host "  Confirm Password" -AsSecureString
        
        $BSTR1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password1)
        $BSTR2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password2)
        $plain1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR1)
        $plain2 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR2)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR1)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR2)
        
        if ($plain1 -eq $plain2) {
            if ($plain1.Length -lt 8) {
                Write-Log "Password must be at least 8 characters" "WARNING"
                $attempts++
            }
            else {
                $passwordMatch = $true
                
                Write-Host ""
                Write-Log "Generating password hash..." "INFO"
                $Script:AuthHash = Get-CaddyPasswordHash -Password $password1
                
                if ($Script:AuthHash) {
                    Write-Log "Password hash generated" "SUCCESS"
                    $Script:AuthEnabled = $true
                    return $true
                }
                else {
                    return $false
                }
            }
        }
        else {
            Write-Log "Passwords do not match" "WARNING"
            $attempts++
        }
        
        $plain1 = $null
        $plain2 = $null
        [System.GC]::Collect()
    }
    
    if (-not $passwordMatch) {
        Write-Log "Too many failed attempts" "ERROR"
        return $false
    }
    
    return $false
}

function Save-AuthConfig {
    <#
    .SYNOPSIS
        Save authentication configuration to file
    #>
    $authPath = Join-Path $InstallPath $Script:Config.AuthFile
    
    $authConfig = @{
        Enabled  = $Script:AuthEnabled
        Username = $Script:AuthUser
        Hash     = $Script:AuthHash
        Updated  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
    
    try {
        $authConfig | ConvertTo-Json | Out-File -FilePath $authPath -Encoding UTF8 -Force
        
        $acl = Get-Acl $authPath
        $acl.SetAccessRuleProtection($true, $false)
        $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "BUILTIN\Administrators", "FullControl", "Allow"
        )
        $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "NT AUTHORITY\SYSTEM", "FullControl", "Allow"
        )
        $acl.SetAccessRule($adminRule)
        $acl.SetAccessRule($systemRule)
        Set-Acl -Path $authPath -AclObject $acl
        
        Write-Log "Auth config saved: $authPath" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to save auth config: $_" "ERROR"
        return $false
    }
}

function Read-AuthConfig {
    <#
    .SYNOPSIS
        Load authentication configuration from file
    #>
    $authPath = Join-Path $InstallPath $Script:Config.AuthFile
    
    if (Test-Path $authPath) {
        try {
            $authConfig = Get-Content $authPath -Raw | ConvertFrom-Json
            $Script:AuthEnabled = $authConfig.Enabled
            $Script:AuthUser = $authConfig.Username
            $Script:AuthHash = $authConfig.Hash
            return $true
        }
        catch {
            Write-Log "Failed to read auth config: $_" "WARNING"
            return $false
        }
    }
    return $false
}

function Remove-AuthConfig {
    <#
    .SYNOPSIS
        Remove authentication and regenerate Caddyfile without auth
    #>
    $Script:AuthEnabled = $false
    $Script:AuthUser = "admin"
    $Script:AuthHash = $null
    
    $authPath = Join-Path $InstallPath $Script:Config.AuthFile
    if (Test-Path $authPath) {
        Remove-Item $authPath -Force -ErrorAction SilentlyContinue
    }
    
    New-Caddyfile
    
    $service = Get-Service -Name $Script:Config.ServiceName -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        Restart-Service -Name $Script:Config.ServiceName -Force
        Write-Log "Authentication disabled and service restarted" "SUCCESS"
    }
    else {
        Write-Log "Authentication disabled" "SUCCESS"
    }
}

# ============================================================================
# CADDY FUNCTIONS
# ============================================================================

function Install-Caddy {
    Write-Log "Installing Caddy..." "HEADER"
    
    if (-not (Test-Path $InstallPath)) {
        New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
        Write-Log "Created directory: $InstallPath" "SUCCESS"
    }
    
    @("data", "logs") | ForEach-Object {
        $subDir = Join-Path $InstallPath $_
        if (-not (Test-Path $subDir)) {
            New-Item -ItemType Directory -Path $subDir -Force | Out-Null
        }
    }
    
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
    
    $authBlock = ""
    if ($Script:AuthEnabled -and $Script:AuthHash) {
        $authBlock = @"

    # HTTP Basic Authentication
    basicauth {
        $($Script:AuthUser) $($Script:AuthHash)
    }
"@
    }
    
    $authStatus = if ($Script:AuthEnabled) { "Enabled (User: $($Script:AuthUser))" } else { "Disabled" }
    
    $caddyfileContent = @"
# Caddy Reverse Proxy for LibreHardwareMonitor
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# Tailscale IP: $($Script:TailscaleIP)
# Upstream: $($UpstreamIP):$($UpstreamPort)
# Authentication: $authStatus

$($Script:TailscaleIP):$ProxyPort {$authBlock
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
    
    $existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-Log "Removing existing service..." "INFO"
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        & sc.exe delete $serviceName 2>$null | Out-Null
        Start-Sleep -Seconds 2
    }
    
    $binPath = "`"$exePath`" run --config `"$configPath`""
    
    $result = & sc.exe create $serviceName start= auto binPath= $binPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to create service: $result" "ERROR"
        return $false
    }
    Write-Log "Created service: $serviceName" "SUCCESS"
    
    & sc.exe failure $serviceName reset= 86400 actions= restart/60000/restart/60000/restart/60000 2>$null | Out-Null
    & sc.exe description $serviceName "Caddy reverse proxy for LibreHardwareMonitor via Tailscale" 2>$null | Out-Null
    Write-Log "Configured auto-restart on failure" "SUCCESS"
    
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

    $ipList = @("127.0.0.1")
    try {
        $adapters = Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" }
        $ipList += $adapters.IPAddress
    }
    catch {
        Write-Log "Could not enumerate network adapters." "WARNING"
    }

    $validOptions = @()
    for ($i = 0; $i -lt $ipList.Count; $i++) {
        $currentIP = $ipList[$i]
        $isResponsive = Test-PortOpen -ComputerName $currentIP -Port $UpstreamPort
        
        $indexTag = "  [$($i+1)]".PadRight(7)
        $ipTag = "$currentIP".PadRight(18)
        
        if ($isResponsive) { 
            Write-Host "$indexTag$ipTag" -NoNewline -ForegroundColor White
            Write-Host " [FOUND LHM!] " -ForegroundColor Green
            $validOptions += $currentIP
        }
        else {
            Write-Host "$indexTag$ipTag" -NoNewline -ForegroundColor Gray
            Write-Host " [No Response] " -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    if ($validOptions.Count -gt 0) {
        Write-Host "  LHM was detected on $($validOptions.Count) interface(s)." -ForegroundColor Green
    }
    else {
        Write-Host "  LHM was not detected on any interface." -ForegroundColor Red
        Write-Host "  Ensure LHM is running and the Web Server is enabled." -ForegroundColor Yellow
    }

    $choice = Read-Host "  Select IP number to use [1-$($ipList.Count)] or Enter to cancel"

    if ($choice -match '^\d+$' -and $choice -ge 1 -and $choice -le $ipList.Count) {
        $selected = $ipList[$choice - 1]
        $Script:UpstreamIP = $selected
        Write-Host ""
        Write-Log "Upstream IP updated to: $selected" "SUCCESS"
        Start-Sleep -Seconds 2
    }
}

function Select-FirewallScope {
    <#
    .SYNOPSIS
        Interactive firewall scope selection during install
    #>
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║           Firewall Scope Selection                    ║" -ForegroundColor Cyan
    Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] Tailscale Only (100.64.0.0/10)" -ForegroundColor Green
    Write-Host "      Recommended - Only Tailscale devices can connect" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [2] LAN Restricted (specify addresses)"
    Write-Host "      Allow specific IPs or subnets" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [3] Any (all addresses)" -ForegroundColor Yellow
    Write-Host "      Least secure - allows all connections" -ForegroundColor Gray
    Write-Host ""
    
    $choice = Read-Host "  Select scope [1]"
    
    switch ($choice) {
        "2" {
            Write-Host ""
            Write-Host "  Enter allowed addresses (comma-separated)" -ForegroundColor Cyan
            Write-Host "  Example: 10.1.10.0/24 or 10.1.10.10,10.1.10.30" -ForegroundColor Gray
            $addresses = Read-Host "  Addresses"
            
            if ([string]::IsNullOrWhiteSpace($addresses)) {
                Write-Log "No addresses specified, defaulting to Tailscale Only" "WARNING"
                $Script:FWScope = "TailscaleOnly"
                $Script:FWAllowedAddresses = $null
            }
            else {
                $Script:FWScope = "LAN"
                $Script:FWAllowedAddresses = $addresses
            }
        }
        "3" {
            $Script:FWScope = "Any"
            $Script:FWAllowedAddresses = $null
        }
        default {
            $Script:FWScope = "TailscaleOnly"
            $Script:FWAllowedAddresses = $null
        }
    }
}

function Test-Prerequisites {
    Write-Log "Checking prerequisites..." "HEADER"
    
    $passed = $true
    
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
    
    # Handle authentication setup
    if ($EnableAuth -or $Script:AuthEnabled) {
        if (-not $Script:AuthHash) {
            if (-not (Request-AuthCredentials)) {
                Write-Log "Authentication setup cancelled. Proceeding without auth." "WARNING"
                $Script:AuthEnabled = $false
            }
        }
        
        if ($Script:AuthEnabled) {
            Save-AuthConfig
        }
    }
    
    if (-not (New-Caddyfile)) { return $false }
    
    # Handle firewall setup
    if (-not (Set-FirewallRule -Scope $Script:FWScope -Addresses $Script:FWAllowedAddresses)) {
        Write-Log "Firewall rule creation failed - continuing anyway" "WARNING"
    }
    
    if (-not (Install-CaddyService)) { return $false }
    
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
    
    $service = Get-Service -Name $Script:Config.ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        Write-Log "Removing service..." "INFO"
        Stop-Service -Name $Script:Config.ServiceName -Force -ErrorAction SilentlyContinue
        & sc.exe delete $Script:Config.ServiceName 2>$null | Out-Null
        Write-Log "Service removed" "SUCCESS"
    }
    
    Remove-FirewallRules
    
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
    
    $service = Get-Service -Name $Script:Config.ServiceName -ErrorAction SilentlyContinue
    Write-Host "  Caddy Service:   " -NoNewline
    if ($service -and $service.Status -eq "Running") {
        Write-Host "Running" -ForegroundColor Green
    }
    else {
        Write-Host "Not Running" -ForegroundColor Red
        $allPassed = $false
    }
    
    Write-Host "  Proxy Port:      " -NoNewline
    if ($Script:TailscaleIP -and (Test-PortOpen -ComputerName $Script:TailscaleIP -Port $ProxyPort)) {
        Write-Host "Listening ($($Script:TailscaleIP):$ProxyPort)" -ForegroundColor Green
    }
    else {
        Write-Host "Not Responding" -ForegroundColor Red
        $allPassed = $false
    }
    
    Write-Host "  LHM Upstream:    " -NoNewline
    if (Test-PortOpen -ComputerName $UpstreamIP -Port $UpstreamPort) {
        Write-Host "Responding ($($UpstreamIP):$($UpstreamPort))" -ForegroundColor Green
    }
    else {
        Write-Host "Not Responding" -ForegroundColor Yellow
    }
    
    Write-Host "  Authentication:  " -NoNewline
    if ($Script:AuthEnabled) {
        Write-Host "Enabled (User: $($Script:AuthUser))" -ForegroundColor Green
    }
    else {
        Write-Host "Disabled" -ForegroundColor Yellow
    }
    
    # Firewall status
    Write-Host "  Firewall:        " -NoNewline
    $fwRules = Get-FirewallRules
    if ($fwRules) {
        $ruleName = ($fwRules | Select-Object -First 1).DisplayName
        Write-Host $ruleName -ForegroundColor Green
    }
    else {
        Write-Host "No rules configured" -ForegroundColor Yellow
    }
    
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
        if ($Script:AuthEnabled) {
            Write-Host "  Login: $($Script:AuthUser) / [your password]" -ForegroundColor Yellow
        }
    }
    else {
        Write-Log "Some components failed verification" "WARNING"
    }
    
    return $allPassed
}

function Show-Status {
    $Script:TailscaleIP = if ($TailscaleIP) { $TailscaleIP } else { Get-TailscaleIP }
    
    Read-AuthConfig | Out-Null
    Read-FirewallConfig | Out-Null
    
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║          Caddy Proxy Status                           ║" -ForegroundColor Cyan
    Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "  Tailscale IP:    " -NoNewline
    if ($Script:TailscaleIP) {
        Write-Host $Script:TailscaleIP -ForegroundColor Green
    }
    else {
        Write-Host "Not Connected" -ForegroundColor Red
    }
    
    $service = Get-Service -Name $Script:Config.ServiceName -ErrorAction SilentlyContinue
    Write-Host "  Caddy Service:   " -NoNewline
    if ($service) {
        $color = if ($service.Status -eq "Running") { "Green" } else { "Yellow" }
        Write-Host $service.Status -ForegroundColor $color
    }
    else {
        Write-Host "Not Installed" -ForegroundColor Red
    }
    
    Write-Host "  Proxy Port:      " -NoNewline
    if ($Script:TailscaleIP -and (Test-PortOpen -ComputerName $Script:TailscaleIP -Port $ProxyPort)) {
        Write-Host "Listening (:$ProxyPort)" -ForegroundColor Green
    }
    else {
        Write-Host "Not Responding" -ForegroundColor Red
    }
    
    Write-Host "  LHM Upstream:    " -NoNewline
    if (Test-PortOpen -ComputerName $UpstreamIP -Port $UpstreamPort) {
        Write-Host "Responding ($($UpstreamIP):$($UpstreamPort))" -ForegroundColor Green
    }
    else {
        Write-Host "Not Responding" -ForegroundColor Yellow
    }
    
    Write-Host "  Authentication:  " -NoNewline
    if ($Script:AuthEnabled) {
        Write-Host "Enabled (User: $($Script:AuthUser))" -ForegroundColor Green
    }
    else {
        Write-Host "Disabled" -ForegroundColor Yellow
    }
    
    # Firewall status
    Write-Host "  Firewall:        " -NoNewline
    $fwRules = Get-FirewallRules
    if ($fwRules) {
        $ruleName = ($fwRules | Select-Object -First 1).DisplayName
        $shortName = $ruleName -replace "^Caddy Reverse Proxy ", ""
        Write-Host $shortName -ForegroundColor Green
    }
    else {
        Write-Host "No rules" -ForegroundColor Yellow
    }
    
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
    Write-Host "  6. (Optional) Disable LHM Authentication:" -ForegroundColor White
    Write-Host "     Caddy + Tailscale + basicauth provides security" -ForegroundColor Gray
    Write-Host ""
}

function Show-AuthMenu {
    <#
    .SYNOPSIS
        Authentication management submenu
    #>
    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host "  ╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "  ║          Authentication Management                    ║" -ForegroundColor Cyan
        Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Host "  Current Status:  " -NoNewline
        if ($Script:AuthEnabled) {
            Write-Host "Enabled" -ForegroundColor Green
            Write-Host "  Username:        " -NoNewline
            Write-Host $Script:AuthUser -ForegroundColor Cyan
        }
        else {
            Write-Host "Disabled" -ForegroundColor Yellow
        }
        
        Write-Host ""
        Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  [1] Enable/Update Authentication"
        Write-Host "  [2] Change Password"
        Write-Host "  [3] Disable Authentication"
        Write-Host "  [B] Back to Main Menu"
        Write-Host ""
        
        $choice = Read-Host "  Select option"
        
        switch ($choice.ToUpper()) {
            "1" {
                $exePath = Join-Path $InstallPath $Script:Config.CaddyExe
                if (-not (Test-Path $exePath)) {
                    Write-Log "Caddy not installed. Install Caddy first." "ERROR"
                    Read-Host "`n  Press Enter to continue"
                    continue
                }
                
                if (Request-AuthCredentials) {
                    Save-AuthConfig
                    New-Caddyfile
                    
                    $service = Get-Service -Name $Script:Config.ServiceName -ErrorAction SilentlyContinue
                    if ($service -and $service.Status -eq "Running") {
                        Restart-Service -Name $Script:Config.ServiceName -Force
                        Write-Log "Service restarted with new auth settings" "SUCCESS"
                    }
                }
                Read-Host "`n  Press Enter to continue"
            }
            "2" {
                if (-not $Script:AuthEnabled) {
                    Write-Log "Authentication not enabled" "WARNING"
                    Read-Host "`n  Press Enter to continue"
                    continue
                }
                
                $exePath = Join-Path $InstallPath $Script:Config.CaddyExe
                if (-not (Test-Path $exePath)) {
                    Write-Log "Caddy not installed" "ERROR"
                    Read-Host "`n  Press Enter to continue"
                    continue
                }
                
                Write-Host ""
                Write-Host "  Changing password for user: $($Script:AuthUser)" -ForegroundColor Cyan
                
                $passwordMatch = $false
                $attempts = 0
                
                while (-not $passwordMatch -and $attempts -lt 3) {
                    Write-Host ""
                    $password1 = Read-Host "  New Password" -AsSecureString
                    $password2 = Read-Host "  Confirm Password" -AsSecureString
                    
                    $BSTR1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password1)
                    $BSTR2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password2)
                    $plain1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR1)
                    $plain2 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR2)
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR1)
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR2)
                    
                    if ($plain1 -eq $plain2) {
                        if ($plain1.Length -lt 8) {
                            Write-Log "Password must be at least 8 characters" "WARNING"
                            $attempts++
                        }
                        else {
                            $passwordMatch = $true
                            Write-Host ""
                            Write-Log "Generating password hash..." "INFO"
                            $Script:AuthHash = Get-CaddyPasswordHash -Password $password1
                            
                            if ($Script:AuthHash) {
                                Save-AuthConfig
                                New-Caddyfile
                                
                                $service = Get-Service -Name $Script:Config.ServiceName -ErrorAction SilentlyContinue
                                if ($service -and $service.Status -eq "Running") {
                                    Restart-Service -Name $Script:Config.ServiceName -Force
                                    Write-Log "Password changed and service restarted" "SUCCESS"
                                }
                                else {
                                    Write-Log "Password changed" "SUCCESS"
                                }
                            }
                        }
                    }
                    else {
                        Write-Log "Passwords do not match" "WARNING"
                        $attempts++
                    }
                    
                    $plain1 = $null
                    $plain2 = $null
                    [System.GC]::Collect()
                }
                
                Read-Host "`n  Press Enter to continue"
            }
            "3" {
                if (-not $Script:AuthEnabled) {
                    Write-Log "Authentication already disabled" "INFO"
                    Read-Host "`n  Press Enter to continue"
                    continue
                }
                
                if (Confirm-Action "Disable authentication?") {
                    Remove-AuthConfig
                }
                Read-Host "`n  Press Enter to continue"
            }
            "B" {
                return
            }
        }
    }
}

function Show-InteractiveMenu {
    Read-AuthConfig | Out-Null
    Read-FirewallConfig | Out-Null
    
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
        Write-Host "  [A] Authentication Settings"
        Write-Host "  [F] Firewall Settings"
        Write-Host "  [S] Scan/Select Upstream IP"
        Write-Host "  [Q] Quit"
        Write-Host ""
        
        $choice = Read-Host "  Select option"
        
        switch ($choice.ToUpper()) {
            "1" {
                # Ask about auth during install
                Write-Host ""
                $enableAuthChoice = Read-Host "  Enable password authentication? (Y/N)"
                if ($enableAuthChoice -match '^[Yy]') {
                    $Script:AuthEnabled = $true
                }
                else {
                    $Script:AuthEnabled = $false
                }
                
                # Ask about firewall scope
                Select-FirewallScope
                
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
            "A" {
                Show-AuthMenu
            }
            "F" {
                Show-FirewallMenu
            }
            "S" {
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
