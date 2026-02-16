# Domain & Email Diagnostic Command Reference
## Information Gathering for Domain Health Reports

## Overview

Comprehensive command list for gathering DNS, email authentication, blacklist, and mail server diagnostic data. Run these against any domain to produce a full baseline report before remediation. All commands are cross-referenced with web-based tool alternatives where available.

---

## Variables

Replace these throughout:

| Variable | Description |
|----------|-------------|
| `{{DOMAIN}}` | Target domain (e.g., signaturerecruitment.london) |
| `{{DNS_SERVER}}` | Public DNS to query against (default: 8.8.8.8) |

---

## Part 1: DNS Record Queries

### PowerShell (Resolve-DnsName)

```powershell
# MX Records — where inbound mail is routed
Resolve-DnsName -Type MX -Name "{{DOMAIN}}" -Server {{DNS_SERVER}}

# SPF Record — authorised senders
Resolve-DnsName -Type TXT -Name "{{DOMAIN}}" -Server {{DNS_SERVER}} | Where-Object { $_.Strings -match "spf1" }

# DMARC Record — policy enforcement
Resolve-DnsName -Type TXT -Name "_dmarc.{{DOMAIN}}" -Server {{DNS_SERVER}}

# DKIM Selectors (Microsoft 365)
Resolve-DnsName -Type CNAME -Name "selector1._domainkey.{{DOMAIN}}" -Server {{DNS_SERVER}} -ErrorAction SilentlyContinue
Resolve-DnsName -Type CNAME -Name "selector2._domainkey.{{DOMAIN}}" -Server {{DNS_SERVER}} -ErrorAction SilentlyContinue

# DKIM Selectors (Google Workspace)
Resolve-DnsName -Type TXT -Name "google._domainkey.{{DOMAIN}}" -Server {{DNS_SERVER}} -ErrorAction SilentlyContinue

# Autodiscover (Outlook client config)
Resolve-DnsName -Type CNAME -Name "autodiscover.{{DOMAIN}}" -Server {{DNS_SERVER}} -ErrorAction SilentlyContinue

# Nameservers
Resolve-DnsName -Type NS -Name "{{DOMAIN}}" -Server {{DNS_SERVER}}

# SOA Record — zone authority and timers
Resolve-DnsName -Type SOA -Name "{{DOMAIN}}" -Server {{DNS_SERVER}}

# A Record — where the domain resolves
Resolve-DnsName -Type A -Name "{{DOMAIN}}" -Server {{DNS_SERVER}}

# AAAA Record — IPv6
Resolve-DnsName -Type AAAA -Name "{{DOMAIN}}" -Server {{DNS_SERVER}} -ErrorAction SilentlyContinue

# All TXT Records — catches SPF, verification, site ownership
Resolve-DnsName -Type TXT -Name "{{DOMAIN}}" -Server {{DNS_SERVER}}

# MTA-STS
Resolve-DnsName -Type TXT -Name "_mta-sts.{{DOMAIN}}" -Server {{DNS_SERVER}} -ErrorAction SilentlyContinue

# TLSRPT
Resolve-DnsName -Type TXT -Name "_smtp._tls.{{DOMAIN}}" -Server {{DNS_SERVER}} -ErrorAction SilentlyContinue

# BIMI
Resolve-DnsName -Type TXT -Name "default._bimi.{{DOMAIN}}" -Server {{DNS_SERVER}} -ErrorAction SilentlyContinue

# DNSSEC
Resolve-DnsName -Type DNSKEY -Name "{{DOMAIN}}" -Server {{DNS_SERVER}} -ErrorAction SilentlyContinue
```

### nslookup Equivalents (CMD / cross-platform)

```cmd
nslookup -type=MX {{DOMAIN}} 8.8.8.8
nslookup -type=TXT {{DOMAIN}} 8.8.8.8
nslookup -type=TXT _dmarc.{{DOMAIN}} 8.8.8.8
nslookup -type=CNAME selector1._domainkey.{{DOMAIN}} 8.8.8.8
nslookup -type=CNAME selector2._domainkey.{{DOMAIN}} 8.8.8.8
nslookup -type=CNAME autodiscover.{{DOMAIN}} 8.8.8.8
nslookup -type=NS {{DOMAIN}} 8.8.8.8
nslookup -type=SOA {{DOMAIN}} 8.8.8.8
nslookup -type=A {{DOMAIN}} 8.8.8.8
nslookup -type=TXT _mta-sts.{{DOMAIN}} 8.8.8.8
nslookup -type=TXT _smtp._tls.{{DOMAIN}} 8.8.8.8
nslookup -type=TXT default._bimi.{{DOMAIN}} 8.8.8.8
```

### Linux / macOS (dig)

```bash
dig MX {{DOMAIN}} @8.8.8.8
dig TXT {{DOMAIN}} @8.8.8.8
dig TXT _dmarc.{{DOMAIN}} @8.8.8.8
dig CNAME selector1._domainkey.{{DOMAIN}} @8.8.8.8
dig CNAME selector2._domainkey.{{DOMAIN}} @8.8.8.8
dig CNAME autodiscover.{{DOMAIN}} @8.8.8.8
dig NS {{DOMAIN}} @8.8.8.8
dig SOA {{DOMAIN}} @8.8.8.8
dig A {{DOMAIN}} @8.8.8.8
dig TXT _mta-sts.{{DOMAIN}} @8.8.8.8
dig TXT _smtp._tls.{{DOMAIN}} @8.8.8.8
dig TXT default._bimi.{{DOMAIN}} @8.8.8.8
dig DNSKEY {{DOMAIN}} @8.8.8.8
```

---

## Part 2: DomainHealthChecker Module

### Full Domain Scan

```powershell
# Single domain
Invoke-SpfDkimDmarc {{DOMAIN}}

# Multiple domains
Invoke-SpfDkimDmarc {{DOMAIN1}}, {{DOMAIN2}}, {{DOMAIN3}}

# Export to CSV
Invoke-SpfDkimDmarc {{DOMAIN1}}, {{DOMAIN2}} | Export-Csv -Path "DomainHealthReport.csv" -NoTypeInformation

# Against specific DNS server (split DNS environments)
Invoke-SpfDkimDmarc {{DOMAIN}} -Server {{DNS_SERVER}}
```

### Individual Record Checks

```powershell
# SPF only (alias: gspf)
Get-SPFRecord -Name {{DOMAIN}}

# DKIM only (alias: gdkim)
Get-DKIMRecord -Name {{DOMAIN}} -DkimSelector selector1

# DMARC only (alias: gdmarc)
Get-DMARCRecord -Name {{DOMAIN}}

# DNSSEC (alias: gdnssec)
Get-DNSSec -Name {{DOMAIN}}

# BIMI
Get-BIMIRecord -Name {{DOMAIN}}

# MTA-STS
Invoke-MtaSts -Name {{DOMAIN}}
```

Source: https://github.com/T13nn3s/Invoke-SpfDkimDmarc

---

## Part 3: Mail Server Diagnostics

### SMTP Connectivity Test

```powershell
# Test SMTP connection to MX host (port 25)
Test-NetConnection -ComputerName "mx0.123-reg.co.uk" -Port 25

# Test SMTP connection to O365
Test-NetConnection -ComputerName "{{DOMAIN_HYPHENATED}}.mail.protection.outlook.com" -Port 25
```

### SMTP Banner and TLS Check

```powershell
# Telnet-style SMTP banner grab (PowerShell)
$tcp = New-Object System.Net.Sockets.TcpClient("mx0.123-reg.co.uk", 25)
$stream = $tcp.GetStream()
$reader = New-Object System.IO.StreamReader($stream)
$reader.ReadLine()
$tcp.Close()
```

```bash
# Linux / macOS — OpenSSL STARTTLS test
openssl s_client -starttls smtp -connect mx0.123-reg.co.uk:25 -brief

# Check TLS certificate details
openssl s_client -starttls smtp -connect mx0.123-reg.co.uk:25 </dev/null 2>/dev/null | openssl x509 -noout -subject -dates -issuer
```

### Reverse DNS Check

```powershell
# Get IP of MX host then check rDNS
$ip = (Resolve-DnsName -Type A -Name "mx0.123-reg.co.uk").IPAddress
Resolve-DnsName -Type PTR -Name $ip
```

```cmd
# CMD equivalent
nslookup mx0.123-reg.co.uk
nslookup {{RETURNED_IP}}
```

---

## Part 4: Blacklist Checks

### PowerShell — Common RBLs

```powershell
# Get MX IPs first
$mxHosts = (Resolve-DnsName -Type MX -Name "{{DOMAIN}}").NameExchange
foreach ($mx in $mxHosts) {
    $ip = (Resolve-DnsName -Type A -Name $mx -ErrorAction SilentlyContinue).IPAddress
    Write-Host "`n=== $mx ($ip) ===" -ForegroundColor Cyan

    $rbls = @(
        "zen.spamhaus.org"
        "bl.spamcop.net"
        "b.barracudacentral.org"
        "dnsbl.sorbs.net"
        "spam.dnsbl.sorbs.net"
        "dnsbl-1.uceprotect.net"
        "dnsbl-2.uceprotect.net"
        "dnsbl-3.uceprotect.net"
    )

    $reversedIp = ($ip -split '\.' | ForEach-Object { $_ })
    [array]::Reverse($reversedIp)
    $reversedIp = $reversedIp -join '.'

    foreach ($rbl in $rbls) {
        $lookup = "$reversedIp.$rbl"
        $result = Resolve-DnsName -Name $lookup -Type A -ErrorAction SilentlyContinue
        if ($result) {
            Write-Host "  LISTED on $rbl" -ForegroundColor Red
        } else {
            Write-Host "  Clean on $rbl" -ForegroundColor Green
        }
    }
}
```

### Domain Blacklist Check (SURBL / Spamhaus DBL)

```powershell
$domainRbls = @(
    "multi.surbl.org"
    "dbl.spamhaus.org"
)

foreach ($rbl in $domainRbls) {
    $lookup = "{{DOMAIN}}.$rbl"
    $result = Resolve-DnsName -Name $lookup -Type A -ErrorAction SilentlyContinue
    if ($result) {
        Write-Host "LISTED on $rbl" -ForegroundColor Red
    } else {
        Write-Host "Clean on $rbl" -ForegroundColor Green
    }
}
```

---

## Part 5: Microsoft 365 Tenant Discovery

### Check if Domain is Claimed by a Tenant

```powershell
# Look for MS= verification record
Resolve-DnsName -Type TXT -Name "{{DOMAIN}}" -Server 8.8.8.8 | Where-Object { $_.Strings -match "^MS=" }

# Get tenant ID via OpenID configuration
(Invoke-RestMethod "https://login.microsoftonline.com/{{DOMAIN}}/.well-known/openid-configuration").token_endpoint

# Get tenant ID via Azure AD endpoint
(Invoke-RestMethod "https://login.microsoftonline.com/{{DOMAIN}}/v2.0/.well-known/openid-configuration").issuer
```

### Exchange Online DKIM Status (requires Exchange Online PowerShell)

```powershell
# Connect first
Connect-ExchangeOnline -UserPrincipalName admin@{{TENANT}}.onmicrosoft.com

# Check DKIM signing config
Get-DkimSigningConfig -Identity {{DOMAIN}} | Format-List

# List all DKIM configs
Get-DkimSigningConfig | Format-Table Domain, Enabled, Status

# Disconnect
Disconnect-ExchangeOnline -Confirm:$false
```

---

## Part 6: Web-Based Tool Reference

Run these in parallel with command-line checks for cross-validation.

| Tool | URL | Checks |
|------|-----|--------|
| MXToolbox SuperTool | `mxtoolbox.com/SuperTool.aspx` | MX, SPF, DKIM, DMARC, blacklist, SMTP, rDNS |
| MXToolbox Blacklist | `mxtoolbox.com/blacklists.aspx` | IP/domain blacklist scan (100+ lists) |
| Mail-Tester | `mail-tester.com` | Send a test email, get score out of 10 |
| Google Admin Toolbox | `toolbox.googleapps.com/apps/checkmx/` | MX, SPF, DKIM, DMARC for Google domains |
| Microsoft Remote Connectivity | `testconnectivity.microsoft.com` | Autodiscover, Exchange, O365 connectivity |
| dmarcian Domain Checker | `dmarcian.com/domain-checker/` | SPF, DKIM, DMARC with advisory |
| DMARC Inspector (dmarcian) | `dmarcian.com/dmarc-inspector/` | Detailed DMARC record parsing |
| Red Sift Investigate | `redsift.com/tools/investigate` | Dynamic SPF/DKIM/DMARC/BIMI check (requires test email send) |
| Google Public DNS | `dns.google` | Quick propagation check |
| Spamhaus Lookup | `check.spamhaus.org` | IP and domain lookup against Spamhaus lists |
| SURBL Lookup | `surbl.org/surbl-analysis` | Domain reputation check |
| SSL Labs | `ssllabs.com/ssltest/` | TLS/SSL certificate analysis (web, not SMTP) |
| CheckTLS | `checktls.com` | SMTP TLS testing |
| Hardenize | `hardenize.com` | Comprehensive domain security (DNS, email, web, TLS) |

---

## Recommended Execution Order

For a full domain health report, run in this sequence:

```
1. Nameservers and SOA         — confirms DNS authority and zone health
2. A / AAAA records            — confirms where domain resolves
3. MX records                  — confirms mail routing
4. SPF record                  — confirms sender authorisation
5. DKIM selectors              — confirms signing capability
6. DMARC record                — confirms policy and reporting
7. Autodiscover CNAME          — confirms client auto-config
8. MTA-STS / TLSRPT / BIMI    — confirms advanced email security
9. DNSSEC                      — confirms zone signing
10. SMTP connectivity + banner — confirms MX servers are reachable and identify correctly
11. TLS check on SMTP          — confirms encryption in transit
12. Reverse DNS on MX IPs      — confirms rDNS matches
13. IP blacklist scan           — confirms MX IPs are clean
14. Domain blacklist scan       — confirms domain is clean
15. Tenant discovery            — confirms O365/Azure AD claim status
```

---

## References

- DomainHealthChecker module: https://github.com/T13nn3s/Invoke-SpfDkimDmarc
- Resolve-DnsName: https://learn.microsoft.com/en-us/powershell/module/dnsclient/resolve-dnsname
- Spamhaus blocklist FAQ: https://www.spamhaus.org/faq/section/Spamhaus%20DBL
- SURBL documentation: https://surbl.org/guidelines
- UCEPROTECT listing policy: http://www.uceprotect.net/en/index.php?m=3&s=0
- MXToolbox: https://mxtoolbox.com
- Microsoft Remote Connectivity Analyzer: https://testconnectivity.microsoft.com
- Exchange Online PowerShell: https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-online-powershell
- OpenSSL STARTTLS: https://www.openssl.org/docs/man1.1.1/man1/openssl-s_client.html

---

## Document Information

| Field | Value |
|-------|-------|
| **Guide Type** | Domain Diagnostic Command Reference |
| **Scope** | DNS, email authentication, blacklist, mail server, tenant discovery |
| **Compatible With** | Obsidian, Hugo, Standard Markdown Viewers |
| **Classification** | Technical Reference Documentation |
| **Format** | Markdown |

---

**End of Reference**
