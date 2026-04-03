# Domain Health Report: toast-group.com
**Generated:** 2026-03-27 17:08:50
**DNS Server:** 8.8.8.8
**Tool:** Get-DomainHealth.ps1 v1.0

---

## 1. Nameservers

| Record | Value | Status |
|--------|-------|--------|
| NS | ns60.domaincontrol.com | FOUND |
| NS | ns59.domaincontrol.com | FOUND |

## 2. SOA Record

| Field | Value | Status |
|-------|-------|--------|
| Primary Server | ns59.domaincontrol.com | FOUND |
| Admin | dns.jomax.net | INFO |
| Serial | 2026032400 | INFO |
| Refresh |  | INFO |
| Retry |  | INFO |
| Expire |  | WARNING |
| Min TTL | 600 | INFO |

## 3. A / AAAA Records

| Type | Value | Status |
|------|-------|--------|
| A | 3.33.130.190 | FOUND |
| A | 15.197.148.33 | FOUND |

## 4. MX Records

| Host | Priority | Status |
|------|----------|--------|
| toastgroup-com01c.mail.protection.outlook.com | 0 | FOUND |

## 5. SPF Record

| Check | Value | Status |
|-------|-------|--------|
| SPF Record | v=spf1 include:spf.protection.outlook.com -all | FOUND |
| Length | 46 chars | OK |
| DNS Lookups | 1/10 | OK |
| Policy | Hard Fail (-all) | OK |

## 6. DKIM Records

| Selector | Value | Status |
|----------|-------|--------|
| selector1 | CNAME: selector1-toastgroup-com01c._domainkey.netorgft8590772.y-v1.dkim.mail.microsoft | FOUND |
| selector2 | CNAME: selector2-toastgroup-com01c._domainkey.netorgft8590772.y-v1.dkim.mail.microsoft | FOUND |
| google | NOT FOUND | WARNING |

## 7. DMARC Record

| Check | Value | Status |
|-------|-------|--------|
| DMARC Record | v=DMARC1; p=none; adkim=r; aspf=r; rua=dmarcalerts@informal-it.co.uk; | FOUND |
| Policy | p=none | WARNING |

## 8. Autodiscover

| Type | Value | Status |
|------|-------|--------|
| CNAME | autodiscover.outlook.com | FOUND |

## 9. Advanced Email Security

| Record | Value | Status |
|--------|-------|--------|
| MTA-STS | Not configured | INFO |
| TLSRPT | Not configured | INFO |
| BIMI | Not configured | INFO |
| DNSSEC | Enabled | FOUND |

## 10. Mail Server Connectivity

| Host | Port 25 | Banner | Status |
|------|---------|--------|--------|
| toastgroup-com01c.mail.protection.outlook.com | OPEN | 220 LN2PEPF000100CA.mail.protection.outlook.com Microsoft ESMTP MAIL Service ready at Fri, 27 Mar 2026 17:08:50 +0000 [08DE8A01A0B45E1B] |

## 11. Reverse DNS (MX Hosts)

| MX Host | IP | rDNS | Match |
|---------|-----|------|-------|
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.0 | mail-lo2p265cu02300.inbound.protection.outlook.com | MISMATCH |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.1 | mail-lo0p265cu00201.inbound.protection.outlook.com | MISMATCH |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.2 | mail-lo3p265cu00302.inbound.protection.outlook.com | MISMATCH |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.99.0 | mail-cwxp265cu00600.inbound.protection.outlook.com | MISMATCH |

## 12. Blacklist Checks

### IP Blacklists (MX Hosts)

| MX Host | IP | RBL | Status |
|---------|-----|-----|--------|
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.0 | zen.spamhaus.org | LISTED |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.0 | bl.spamcop.net | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.0 | b.barracudacentral.org | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.0 | dnsbl.sorbs.net | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.0 | dnsbl-1.uceprotect.net | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.0 | dnsbl-2.uceprotect.net | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.0 | dnsbl-3.uceprotect.net | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.1 | zen.spamhaus.org | LISTED |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.1 | bl.spamcop.net | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.1 | b.barracudacentral.org | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.1 | dnsbl.sorbs.net | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.1 | dnsbl-1.uceprotect.net | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.1 | dnsbl-2.uceprotect.net | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.1 | dnsbl-3.uceprotect.net | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.2 | zen.spamhaus.org | LISTED |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.2 | bl.spamcop.net | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.2 | b.barracudacentral.org | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.2 | dnsbl.sorbs.net | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.2 | dnsbl-1.uceprotect.net | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.2 | dnsbl-2.uceprotect.net | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.89.2 | dnsbl-3.uceprotect.net | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.99.0 | zen.spamhaus.org | LISTED |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.99.0 | bl.spamcop.net | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.99.0 | b.barracudacentral.org | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.99.0 | dnsbl.sorbs.net | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.99.0 | dnsbl-1.uceprotect.net | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.99.0 | dnsbl-2.uceprotect.net | Clean |
| toastgroup-com01c.mail.protection.outlook.com | 52.101.99.0 | dnsbl-3.uceprotect.net | Clean |

### Domain Blacklists

| Domain | RBL | Status |
|--------|-----|--------|
| toast-group.com | multi.surbl.org | Clean |
| toast-group.com | dbl.spamhaus.org | LISTED |

## 13. Microsoft 365 Tenant Discovery

| Check | Value | Status |
|-------|-------|--------|
| MS Verification Record | Not found | INFO |
| Tenant ID | bb50fad4-0c10-442a-89c7-2e3ee4e941e9 | CLAIMED |

## 14. Summary

| Component | Status |
|-----------|--------|
| A Record | FOUND |
| Autodiscover | FOUND |
| DKIM | See section 6 |
| DMARC | FOUND |
| DNSSEC | ENABLED |
| M365 Tenant | CLAIMED |
| MTA-STS | NOT CONFIGURED |
| MX Records | FOUND |
| Nameservers | FOUND |
| SPF | FOUND |

---
**Completed:** 2026-03-27 17:09:12 (Duration: 21.7s)
