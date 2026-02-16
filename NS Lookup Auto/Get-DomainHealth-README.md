# Get-DomainHealth.ps1

PowerShell script that runs a full DNS and email authentication diagnostic against any domain. Enter the domain, get a report.

## What It Checks

- Nameservers, SOA, A/AAAA records
- MX records
- SPF (record, policy, DNS lookup count)
- DKIM (selector1, selector2, google — or custom selectors)
- DMARC (policy, percentage, reporting address)
- Autodiscover CNAME
- MTA-STS, TLSRPT, BIMI, DNSSEC
- SMTP connectivity and banner on all MX hosts
- Reverse DNS on MX IPs
- IP blacklist scan (Spamhaus, SpamCop, Barracuda, SORBS, UCEPROTECT L1-L3)
- Domain blacklist scan (SURBL, Spamhaus DBL)
- Microsoft 365 tenant discovery (MS= verification record, tenant ID)

## Requirements

- PowerShell 5.1 or later
- Internet connectivity for DNS queries and tenant discovery
- Optional: DomainHealthChecker module (`Install-Module DomainHealthChecker`)

## Usage

```powershell
# Basic — runs all checks, exports .md report to current directory
.\Get-DomainHealth.ps1 -Domain "example.com"

# Custom DNS server
.\Get-DomainHealth.ps1 -Domain "example.com" -DnsServer "1.1.1.1"

# Custom DKIM selectors
.\Get-DomainHealth.ps1 -Domain "example.com" -DkimSelectors "selector1","selector2","mimecast"

# Export to specific path
.\Get-DomainHealth.ps1 -Domain "example.com" -ExportPath "C:\Reports"

# Console output only, no file
.\Get-DomainHealth.ps1 -Domain "example.com" -NoExport
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-Domain` | Yes | — | Target domain to diagnose |
| `-DnsServer` | No | `8.8.8.8` | DNS server to query |
| `-DkimSelectors` | No | `selector1, selector2, google` | DKIM selectors to check |
| `-ExportPath` | No | Current directory | Where to save the report |
| `-NoExport` | No | `$false` | Skip file export |

## Output

Console output is colour-coded by severity. A timestamped markdown report is saved as:

```
DomainHealth_example-com_20260213_143022.md
```

## References

- Resolve-DnsName: https://learn.microsoft.com/en-us/powershell/module/dnsclient/resolve-dnsname
- DomainHealthChecker module: https://github.com/T13nn3s/Invoke-SpfDkimDmarc
- Spamhaus: https://www.spamhaus.org
- MXToolbox: https://mxtoolbox.com
