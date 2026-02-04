# Caddy Reverse Proxy for LibreHardwareMonitor - Quick Reference

Secure remote access to LibreHardwareMonitor via Tailscale with TLS encryption.

## Environment

| Component | Value |
|-----------|-------|
| Server OS | Windows Server / Windows 10/11 |
| Network | Tailscale (100.x.x.x) |
| Proxy Port | 8086 (HTTPS) |
| Upstream Port | 8085 (HTTP - LibreHardwareMonitor) |
| Features | Internal TLS, Windows Service, Auto-start |

## Directory Structure

```
C:\Caddy\
├── caddy.exe
├── Caddyfile
├── data\
└── logs\
```

## Quick Setup Commands

### 1. Create Directory and Download Caddy

```powershell
New-Item -ItemType Directory -Path "C:\Caddy" -Force
Invoke-WebRequest -Uri "https://caddyserver.com/api/download?os=windows&arch=amd64" -OutFile "C:\Caddy\caddy.exe"
C:\Caddy\caddy.exe version
```

### 2. Create Caddyfile

```powershell
notepad C:\Caddy\Caddyfile
```

Paste (adjust IPs as needed):

```
100.69.66.60:8086 {
    reverse_proxy 10.1.10.30:8085
    tls internal
}
```

### 3. Configure Firewall

```powershell
Remove-NetFirewallRule -DisplayName "Caddy*" -ErrorAction SilentlyContinue

New-NetFirewallRule -DisplayName "Caddy Server" `
    -Direction Inbound `
    -Program "C:\Caddy\caddy.exe" `
    -Action Allow `
    -Profile Any
```

### 4. Test Manually

```powershell
C:\Caddy\caddy.exe run --config C:\Caddy\Caddyfile
```

### 5. Install as Windows Service

```powershell
sc.exe create Caddy start= auto binPath= "C:\Caddy\caddy.exe run --config C:\Caddy\Caddyfile"
sc.exe failure Caddy reset= 86400 actions= restart/60000/restart/60000/restart/60000
Start-Service Caddy
```

## Service Management

| Action | Command |
|--------|---------|
| Start | `Start-Service Caddy` |
| Stop | `Stop-Service Caddy` |
| Restart | `Restart-Service Caddy` |
| Status | `Get-Service Caddy` |
| Delete | `sc.exe delete Caddy` |

## Verification

```powershell
# Service status
Get-Service Caddy

# Port listening
Get-NetTCPConnection -LocalPort 8086 -State Listen

# Firewall rule
Get-NetFirewallRule -DisplayName "Caddy*" | Format-Table DisplayName, Enabled, Action
```

## Access URLs

| Location | URL |
|----------|-----|
| Tailscale | `https://100.69.66.60:8086/` |
| JSON API | `https://100.69.66.60:8086/data.json` |

**Note:** Browser will show certificate warning (self-signed) - click Advanced > Proceed.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Connection Refused | Service not running | `Start-Service Caddy` |
| 502 Bad Gateway | LHM not running or wrong IP | Verify LHM is running on upstream IP |
| Certificate Error | Self-signed cert (expected) | Accept warning or install root CA |
| Blank Page | JavaScript/header issue | Ensure LHM is updated |

## Updating Caddy

```powershell
Stop-Service Caddy
Invoke-WebRequest -Uri "https://caddyserver.com/api/download?os=windows&arch=amd64" -OutFile "C:\Caddy\caddy.exe"
Start-Service Caddy
```

## Uninstall

```powershell
Stop-Service Caddy -ErrorAction SilentlyContinue
sc.exe delete Caddy
Remove-NetFirewallRule -DisplayName "Caddy*"
Remove-Item -Path "C:\Caddy" -Recurse -Force
```

## References

- Caddy Documentation: https://caddyserver.com/docs/
- Caddy Reverse Proxy: https://caddyserver.com/docs/quick-starts/reverse-proxy
- Caddy TLS Directive: https://caddyserver.com/docs/caddyfile/directives/tls
- LibreHardwareMonitor: https://github.com/LibreHardwareMonitor/LibreHardwareMonitor
- Microsoft sc.exe: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/sc-create
