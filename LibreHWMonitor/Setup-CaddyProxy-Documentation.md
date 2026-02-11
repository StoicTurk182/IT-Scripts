# Caddy Reverse Proxy for LibreHardwareMonitor

PowerShell script to deploy Caddy as a reverse proxy for LibreHardwareMonitor, binding to Tailscale for secure remote access with optional HTTP Basic Authentication and configurable firewall rules.

## Overview

This script automates the installation and configuration of Caddy as a reverse proxy, enabling secure HTTPS access to LibreHardwareMonitor via Tailscale. Version 5.0 adds granular firewall rule management with Tailscale-only, LAN-restricted, and removal options.

| Component | Purpose |
|-----------|---------|
| Caddy | Reverse proxy with automatic TLS |
| Tailscale | Secure mesh VPN binding |
| LibreHardwareMonitor | Hardware monitoring backend |
| basicauth | HTTP Basic Authentication layer |
| Windows Firewall | Network access control |

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Windows PowerShell 5.1+ | Script uses modern cmdlets |
| Administrator privileges | Required for service and firewall rules |
| Tailscale | Installed and connected |
| LibreHardwareMonitor | Web server enabled on port 8085 |

## Quick Start

### Interactive Menu

```powershell
.\Setup-CaddyProxy.ps1
```

### Automated Install (Tailscale Only)

```powershell
.\Setup-CaddyProxy.ps1 -Action Install -Force
```

### Automated Install (LAN Restricted)

```powershell
.\Setup-CaddyProxy.ps1 -Action Install -FirewallScope LAN -AllowedAddresses "10.1.10.0/24" -Force
```

### Automated Install (With Auth + LAN)

```powershell
.\Setup-CaddyProxy.ps1 -Action Install -EnableAuth -FirewallScope LAN -AllowedAddresses "10.1.10.10,10.1.10.30"
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Action` | String | Menu | Install, Uninstall, Status, Test, or Menu |
| `-InstallPath` | String | C:\Caddy | Caddy installation directory |
| `-ProxyPort` | Int | 8086 | Port Caddy listens on |
| `-UpstreamPort` | Int | 8085 | LibreHardwareMonitor port |
| `-UpstreamIP` | String | 127.0.0.1 | LibreHardwareMonitor IP |
| `-TailscaleIP` | String | Auto-detect | Tailscale IP to bind |
| `-EnableAuth` | Switch | False | Enable HTTP Basic Authentication |
| `-AuthUsername` | String | admin | Username for basic auth |
| `-FirewallScope` | String | TailscaleOnly | TailscaleOnly, LAN, or Any |
| `-AllowedAddresses` | String | - | Comma-separated addresses for LAN scope |
| `-Force` | Switch | False | Skip confirmation prompts |

## Firewall Management

### Scope Options

| Scope | Remote Address | Profile | Security Level |
|-------|----------------|---------|----------------|
| TailscaleOnly | 100.64.0.0/10 | Any | Highest - Only Tailscale CGNAT range |
| LAN | User-specified | Private,Domain | Medium - Restricted to specified addresses |
| Any | Any | Any | Lowest - All addresses allowed |

### Tailscale Only (Recommended)

Restricts access to the Tailscale CGNAT range (100.64.0.0/10). Only devices on your Tailnet can connect.

```powershell
.\Setup-CaddyProxy.ps1 -Action Install -FirewallScope TailscaleOnly
```

Or via menu: `[F] Firewall Settings` > `[1] Tailscale Only`

### LAN Restricted

Allows specific IP addresses or subnets. Useful for local network access without Tailscale.

```powershell
# Single subnet
.\Setup-CaddyProxy.ps1 -Action Install -FirewallScope LAN -AllowedAddresses "10.1.10.0/24"

# Multiple specific IPs
.\Setup-CaddyProxy.ps1 -Action Install -FirewallScope LAN -AllowedAddresses "10.1.10.10,10.1.10.30"

# Mixed (subnet + specific IPs)
.\Setup-CaddyProxy.ps1 -Action Install -FirewallScope LAN -AllowedAddresses "10.1.10.0/24,192.168.1.50"
```

Or via menu: `[F] Firewall Settings` > `[2] LAN Restricted`

### Any (Least Secure)

Allows connections from any IP address. Not recommended for production use.

```powershell
.\Setup-CaddyProxy.ps1 -Action Install -FirewallScope Any
```

### Remove Firewall Rules

Remove all Caddy-related firewall rules:

Via menu: `[F] Firewall Settings` > `[4] Remove All Caddy Rules`

Or manually:

```powershell
Get-NetFirewallRule -DisplayName "Caddy Reverse Proxy*" | Remove-NetFirewallRule
```

### View Current Rules

Via menu: `[F] Firewall Settings` > `[5] Refresh Status`

Or manually:

```powershell
Get-NetFirewallRule -DisplayName "Caddy Reverse Proxy*" | ForEach-Object {
    $port = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $_
    $addr = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $_
    [PSCustomObject]@{
        Name = $_.DisplayName
        Enabled = $_.Enabled
        Port = $port.LocalPort
        RemoteAddress = $addr.RemoteAddress
        Profile = $_.Profile
    }
} | Format-Table -AutoSize
```

## Authentication

### How It Works

Caddy's `basicauth` directive provides HTTP Basic Authentication with bcrypt-hashed passwords. The script uses Caddy's built-in `hash-password` command to generate secure hashes.

### Generated Caddyfile (With Auth)

```caddyfile
# Caddy Reverse Proxy for LibreHardwareMonitor
# Authentication: Enabled (User: admin)

100.x.x.x:8086 {
    # HTTP Basic Authentication
    basicauth {
        admin $2a$14$hashedpassword...
    }
    reverse_proxy 127.0.0.1:8085
    tls internal
}
```

### Password Requirements

| Requirement | Value |
|-------------|-------|
| Minimum length | 8 characters |
| Hash algorithm | bcrypt (Caddy default) |
| Storage | auth.json (admin-only ACL) |

### Managing Authentication

From the interactive menu, select `[A] Authentication Settings`:

| Option | Action |
|--------|--------|
| Enable/Update Authentication | Set username and password |
| Change Password | Update password for existing user |
| Disable Authentication | Remove auth and regenerate Caddyfile |

## Menu Options

| Key | Option | Description |
|-----|--------|-------------|
| 1 | Install Caddy Proxy | Full installation with auth and firewall prompts |
| 2 | Uninstall Caddy | Remove service, files, firewall rules |
| 3 | Test Installation | Verify all components |
| 4 | Restart Caddy Service | Restart after config changes |
| 5 | View Caddyfile | Display current configuration |
| 6 | Edit Caddyfile | Open in Notepad |
| 7 | LHM Setup Instructions | Display setup guide |
| 8 | Open Install Folder | Open C:\Caddy in Explorer |
| A | Authentication Settings | Manage auth credentials |
| F | Firewall Settings | Manage firewall rules |
| S | Scan/Select Upstream IP | Find LHM on local interfaces |
| Q | Quit | Exit menu |

## File Structure

```
C:\Caddy\
├── caddy.exe        # Caddy binary
├── Caddyfile        # Proxy configuration
├── auth.json        # Authentication config (restricted ACL)
├── firewall.json    # Firewall config
├── data\            # Caddy data directory
└── logs\            # Log files
```

### firewall.json Structure

```json
{
    "Scope": "LAN",
    "Addresses": "10.1.10.0/24",
    "Port": 8086,
    "Updated": "2026-02-05 10:30:00"
}
```

## Security Considerations

### Defence in Depth

| Layer | Protection |
|-------|------------|
| Windows Firewall | Network-level access control |
| Tailscale | Mesh VPN / zero-trust network |
| TLS | Encrypted transport (self-signed) |
| basicauth | Credential-based access control |

### Recommended Configuration

For maximum security, combine multiple layers:

```powershell
.\Setup-CaddyProxy.ps1 -Action Install -EnableAuth -FirewallScope TailscaleOnly
```

This provides:

1. Firewall blocks all non-Tailscale traffic
2. Tailscale provides authenticated mesh network access
3. TLS encrypts all traffic
4. basicauth requires username/password

### LAN-Only Access (No Tailscale)

If Tailscale is not available on all devices:

```powershell
.\Setup-CaddyProxy.ps1 -Action Install -EnableAuth -FirewallScope LAN -AllowedAddresses "10.1.10.0/24"
```

Ensure you enable authentication when using LAN scope.

## Troubleshooting

### Firewall Rule Not Working

Check the rule was created:

```powershell
Get-NetFirewallRule -DisplayName "Caddy Reverse Proxy*"
```

Check remote address filter:

```powershell
Get-NetFirewallRule -DisplayName "Caddy Reverse Proxy*" | 
    Get-NetFirewallAddressFilter | 
    Select-Object RemoteAddress
```

### Cannot Connect from LAN

Verify source IP is in allowed range:

```powershell
# On the client machine
(Invoke-WebRequest -Uri "https://api.ipify.org" -UseBasicParsing).Content
# Or for local IP
Get-NetIPAddress -AddressFamily IPv4 | Select-Object IPAddress, InterfaceAlias
```

Verify firewall rule includes that address:

```powershell
Get-NetFirewallRule -DisplayName "Caddy Reverse Proxy*" | 
    Get-NetFirewallAddressFilter
```

### Connection Refused

Check if Caddy is listening:

```powershell
Get-NetTCPConnection -LocalPort 8086 -ErrorAction SilentlyContinue
```

Check service status:

```powershell
Get-Service Caddy
```

### Authentication Not Prompting

Verify Caddyfile contains basicauth block:

```powershell
Get-Content C:\Caddy\Caddyfile | Select-String "basicauth" -Context 0,3
```

## Uninstallation

### Interactive

Run menu and select `[2] Uninstall Caddy`.

### Command Line

```powershell
.\Setup-CaddyProxy.ps1 -Action Uninstall -Force
```

Removes:

- Caddy Windows service
- All Caddy firewall rules
- C:\Caddy directory (including auth.json and firewall.json)

## References

| Resource | URL |
|----------|-----|
| Caddy Documentation | https://caddyserver.com/docs/ |
| Caddy basicauth Directive | https://caddyserver.com/docs/caddyfile/directives/basicauth |
| Caddy hash-password Command | https://caddyserver.com/docs/command-line#caddy-hash-password |
| LibreHardwareMonitor | https://github.com/LibreHardwareMonitor/LibreHardwareMonitor |
| Tailscale Documentation | https://tailscale.com/kb/ |
| Tailscale CGNAT Range | https://tailscale.com/kb/1015/100.x-addresses |
| Windows Firewall PowerShell | https://learn.microsoft.com/en-us/powershell/module/netsecurity/ |
| New-NetFirewallRule | https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule |
