# Get-TenantSecurityPosture.ps1

Generates a comprehensive Microsoft 365 tenant security posture report in markdown format.

## Requirements

```powershell
Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser -Force
```

## Usage

```powershell
.\Get-TenantSecurityPosture.ps1 -TenantDomain "domain.com" -UPN "admin@domain.com"
```

With custom output path:

```powershell
.\Get-TenantSecurityPosture.ps1 -TenantDomain "domain.com" -UPN "admin@domain.com" -OutputPath "C:\Reports"
```

## What It Checks

| Section | Description |
|---------|-------------|
| Security Defaults | Enabled or disabled |
| Conditional Access | All policies, state, conditions, and grant controls |
| Named Locations | All configured named/trusted locations |
| MFA Registration | Per-user MFA registration and capability status |
| Privileged Roles | All privileged role assignments, flags excessive assignments |
| Managed Devices | Intune device compliance state and last sync |
| SSPR | Registration campaign state and targets |
| DKIM | Signing config status per domain |
| SPF | Record presence and policy strength |
| DMARC | Record presence, policy, pct, and reporting address |
| Safe Links | Policy configuration per rule |
| Safe Attachments | Policy configuration per rule |
| Anti-Phishing | Policy configuration including impersonation protection |

## Output

Produces a timestamped markdown file:

```
Security-Posture-2026-03-29-1430.md
```

Each check is flagged as:

- `[OK]` - Correct configuration
- `[WARN]` - Needs review
- `[FAIL]` - Misconfigured or missing

A summary count of OK/WARN/FAIL is included at the end of the report.

## Required Graph Scopes

The script will request the following scopes on connect:

- Policy.Read.All
- Policy.ReadWrite.ConditionalAccess
- Directory.Read.All
- DeviceManagementManagedDevices.Read.All
- Reports.Read.All
- AuditLog.Read.All
- UserAuthenticationMethod.Read.All

## Notes

- Exchange Online connection is optional. MDO sections (Safe Links, Safe Attachments, Anti-Phishing, DKIM) will be skipped if the connection fails.
- Always run with an account that has at least Security Reader and Exchange View-Only Administrator roles for full output.
- Output is compatible with Obsidian and Hugo.
