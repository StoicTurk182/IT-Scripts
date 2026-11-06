---
title: "dnscheck PowerShell Function"
created: 2026-11-06T09:14:42
updated: 2026-11-06T14:04:37


---
# dnscheck PowerShell Function

**Table of Contents**

1. [Overview](#overview)
2. [Requirements](#requirements)
3. [Full Function](#full-function)
4. [Parameters](#parameters)
5. [Records Checked](#records-checked)
6. [Status Values](#status-values)
7. [How It Works](#how-it-works)
	1. [Input Handling](#input-handling)
	2. [Helper Functions](#helper-functions)
	3. [Answer Section Filtering](#answer-section-filtering)
	4. [DKIM Two-Step Lookup](#dkim-two-step-lookup)
	5. [Duplicate SPF and DMARC Detection](#duplicate-spf-and-dmarc-detection)
8. [Usage Examples](#usage-examples)
9. [Example Output](#example-output)
10. [Reading the Output](#reading-the-output)
	1. [A Record Shows NONE](#a-record-shows-none)
	2. [DKIM CNAME Found but No Key at Target](#dkim-cname-found-but-no-key-at-target)
	3. [Other Findings](#other-findings)
11. [Installation](#installation)
	1. [Step 1: Save the Function File](#step-1-save-the-function-file)
	2. [Step 2: Dot-Source from the Profile](#step-2-dot-source-from-the-profile)
	3. [Step 3: Add to Show-Help](#step-3-add-to-show-help)
	4. [Step 4: Reload and Verify](#step-4-reload-and-verify)
	5. [Chris Titus Tech Profile Notes](#chris-titus-tech-profile-notes)
12. [Function Management](#function-management)
	1. [How Functions Persist](#how-functions-persist)
	2. [List Functions](#list-functions)
	3. [View a Function](#view-a-function)
	4. [Remove a Function](#remove-a-function)
	5. [Profile Management](#profile-management)
	6. [Verifying the Running Version](#verifying-the-running-version)
	7. [Copying Code Safely](#copying-code-safely)
	8. [Display Differences Between Systems](#display-differences-between-systems)
	9. [Quick Reference](#quick-reference)
13. [Minimal Version (mailcheck)](#minimal-version-mailcheck)
14. [Limitations](#limitations)
15. [Troubleshooting](#troubleshooting)
16. [References](#references)

## Overview

`dnscheck` is a PowerShell function that queries the common DNS records for a domain and shows them in grouped sections with colour-coded statuses. It covers web, zone, mail routing, email authentication (SPF, DMARC, DKIM) and the optional mail security records (MTA-STS, TLS-RPT, BIMI).

It accepts a domain or a full email address, queries a public resolver by default, and runs the DKIM CNAME and key lookups as separate steps. That way it can tell whether a DKIM failure is in your own zone or at the provider.

## Requirements

| Requirement | Detail |
|-------------|--------|
| OS | Windows. `Resolve-DnsName` is part of the DnsClient module, which only exists on Windows. |
| PowerShell | Windows PowerShell 5.1 or PowerShell 7+ |
| Network | Outbound UDP/TCP 53 to the resolver (default `1.1.1.1`) |
| Admin rights | Not required |

## Full Function

```powershell
function dnscheck {
<#
.SYNOPSIS
    Queries common DNS records for a domain and outputs a grouped, colour-coded report.

.DESCRIPTION
    Checks web (A, AAAA, www), zone (NS, SOA), mail routing (MX, Autodiscover),
    email authentication (SPF, DMARC, DKIM) and optional records (MTA-STS,
    TLS-RPT, BIMI). Accepts a domain or an email address. DKIM is checked in
    two steps (CNAME, then key at target) to show where a failure sits.

.PARAMETER Domain
    Domain name or email address. Anything up to and including the @ is removed.

.PARAMETER Server
    DNS resolver to query. Default 1.1.1.1.

.PARAMETER Selectors
    DKIM selectors to check. Default selector1, selector2 (Microsoft 365).

.EXAMPLE
    dnscheck yourdomain.com

.EXAMPLE
    dnscheck user@yourdomain.com -Server 8.8.8.8

.EXAMPLE
    dnscheck yourdomain.com -Selectors selector1,selector2,google

.NOTES
    Author: Andrew Jones
    Version: 2.0
    Date: 2026-11-06
    Requires: Windows (DnsClient module / Resolve-DnsName)
#>
    param(
        [Parameter(Mandatory)][string]$Domain,
        [string]$Server = '1.1.1.1',
        [string[]]$Selectors = @('selector1','selector2')
    )
    $d = $Domain -replace '.*@'

    function Q($n, $t) {
        Resolve-DnsName $n -Type $t -Server $Server -DnsOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.Section -eq 'Answer' -and "$($_.Type)" -eq $t }
    }
    function Row($label, $status, $value) {
        $c = @{ OK='Green'; WARN='Yellow'; MISSING='Red'; NONE='DarkGray' }[$status]
        if (-not $c) { $c = 'Gray' }
        Write-Host ('  {0,-18}' -f $label) -NoNewline
        Write-Host ('{0,-9}' -f $status) -ForegroundColor $c -NoNewline
        Write-Host $value
    }
    function Show($label, $vals, $miss = 'MISSING', $note = 'not found') {
        $vals = @($vals | Where-Object { $_ })
        if (-not $vals) { Row $label $miss $note; return }
        Row $label 'OK' $vals[0]
        $vals | Select-Object -Skip 1 | ForEach-Object { Row '' '' $_ }
    }
    function Head($t) { Write-Host "`n$t" -ForegroundColor Cyan }

    Write-Host "`nDNS check: $d  (resolver $Server)"

    Head 'Web'
    Show 'A'    (Q $d A).IPAddress 'NONE' 'not set'
    Show 'AAAA' (Q $d AAAA).IPAddress 'NONE' 'not set'
    Show 'WWW'  (@((Q ('www.' + $d) CNAME) | ForEach-Object { "CNAME -> $($_.NameHost)" }) + @((Q ('www.' + $d) A).IPAddress)) 'NONE' 'not set'

    Head 'DNS zone'
    Show 'NS'  ((Q $d NS).NameHost | Sort-Object)
    Show 'SOA' ((Q $d SOA) | ForEach-Object { "$($_.PrimaryServer)  serial $($_.SerialNumber)" })

    Head 'Mail routing'
    Show 'MX'               ((Q $d MX) | Sort-Object Preference | ForEach-Object { "$($_.Preference)  $($_.NameExchange)" })
    Show 'Autodiscover'     ((Q "autodiscover.$d" CNAME) | ForEach-Object { "CNAME -> $($_.NameHost)" }) 'NONE' 'not set'
    Show 'Autodiscover SRV' ((Q "_autodiscover._tcp.$d" SRV) | ForEach-Object { "$($_.Port)  $($_.NameTarget)" }) 'NONE' 'not set'

    Head 'Email authentication'
    $txt   = @((Q $d TXT) | ForEach-Object { $_.Strings -join '' })
    $spf   = @($txt | Where-Object { $_ -match '^v=spf1' })
    $dmarc = @((Q "_dmarc.$d" TXT) | ForEach-Object { $_.Strings -join '' } | Where-Object { $_ -match '^v=DMARC1' })
    if ($spf.Count -gt 1)   { Row 'SPF' 'WARN' "$($spf.Count) records - only one allowed"; $spf | ForEach-Object { Row '' '' $_ } } else { Show 'SPF' $spf }
    if ($dmarc.Count -gt 1) { Row 'DMARC' 'WARN' "$($dmarc.Count) records - only one allowed"; $dmarc | ForEach-Object { Row '' '' $_ } } else { Show 'DMARC' $dmarc }

    foreach ($s in $Selectors) {
        $n   = "$s._domainkey.$d"
        $cn  = (Q $n CNAME).NameHost | Select-Object -First 1
        $key = (Q $(if ($cn) { $cn } else { $n }) TXT) | ForEach-Object { $_.Strings -join '' } |
               Where-Object { $_ -match 'p=' } | Select-Object -First 1
        $label = "DKIM $s"
        if ($key) {
            $p = [regex]::Match($key, 'p=([^;\s]*)').Groups[1].Value
            if (-not $p) { Row $label 'WARN' 'key revoked (empty p=)' }
            else {
                $bits = if ($p.Length -lt 300) { '~1024-bit' } elseif ($p.Length -lt 600) { '~2048-bit' } else { '~4096-bit' }
                Row $label 'OK' "key published ($bits)"
            }
        }
        elseif ($cn) { Row $label 'WARN' 'CNAME found but no key at target' }
        else         { Row $label 'MISSING' 'no CNAME or TXT record' }
        if ($cn) { Row '' '' "CNAME -> $cn" }
    }

    Head 'Optional'
    Show 'MTA-STS' ((Q "_mta-sts.$d" TXT)        | ForEach-Object { $_.Strings -join '' }) 'NONE' 'not set'
    Show 'TLS-RPT' ((Q "_smtp._tls.$d" TXT)      | ForEach-Object { $_.Strings -join '' }) 'NONE' 'not set'
    Show 'BIMI'    ((Q "default._bimi.$d" TXT)   | ForEach-Object { $_.Strings -join '' }) 'NONE' 'not set'

    Head 'Other TXT'
    Show 'TXT' @($txt | Where-Object { $_ -notmatch '^v=spf1' }) 'NONE' 'none'
    Write-Host ''
}
```

## Parameters

| Parameter | Type | Required | Default | Purpose |
|-----------|------|----------|---------|---------|
| `-Domain` | String | Yes (positional) | None | Domain or email address to check |
| `-Server` | String | No | `1.1.1.1` | Resolver to query |
| `-Selectors` | String array | No | `selector1`, `selector2` | DKIM selectors to check |

## Records Checked

| Section | Check | Query Name | Type |
|---------|-------|------------|------|
| Web | A | `domain` | A |
| Web | AAAA | `domain` | AAAA |
| Web | WWW | `www.domain` | CNAME + A |
| DNS zone | NS | `domain` | NS |
| DNS zone | SOA | `domain` | SOA |
| Mail routing | MX | `domain` | MX |
| Mail routing | Autodiscover | `autodiscover.domain` | CNAME |
| Mail routing | Autodiscover SRV | `_autodiscover._tcp.domain` | SRV |
| Email authentication | SPF | `domain` | TXT (`v=spf1`) |
| Email authentication | DMARC | `_dmarc.domain` | TXT (`v=DMARC1`) |
| Email authentication | DKIM | `<selector>._domainkey.domain` | CNAME, then TXT at target |
| Optional | MTA-STS | `_mta-sts.domain` | TXT (RFC 8461) |
| Optional | TLS-RPT | `_smtp._tls.domain` | TXT (RFC 8460) |
| Optional | BIMI | `default._bimi.domain` | TXT |
| Other TXT | TXT | `domain` | TXT, excluding SPF |

## Status Values

| Status | Colour | Meaning |
|--------|--------|---------|
| OK | Green | Record found |
| WARN | Yellow | Record found, but there's a problem (duplicate SPF or DMARC, revoked DKIM key, CNAME with no key behind it) |
| MISSING | Red | A required record wasn't found (NS, SOA, MX, SPF, DMARC, DKIM) |
| NONE | Grey | An optional record isn't set. This is normal for many domains. |

## How It Works

### Input Handling

```powershell
$d = $Domain -replace '.*@'
```

Removes everything up to and including the `@`, so `user@yourdomain.com` becomes `yourdomain.com`. A bare domain passes through unchanged. Without this, `Resolve-DnsName` returns "DNS name contains an invalid character".

### Helper Functions

The helpers are defined inside `dnscheck`, so they only exist while it runs and don't clutter the session:

| Helper | Purpose |
|--------|---------|
| `Q` | Runs `Resolve-DnsName` and returns only Answer-section records of the requested type |
| `Row` | Writes one aligned, colour-coded line |
| `Show` | Writes a label and status with the first value, then any further values indented below it, or the "missing" status if there are none |
| `Head` | Writes a section header |

The `www` query name is built as `('www.' + $d)` and not as `"www.$d"`. Both give the same result, but Markdown renderers such as Obsidian, chat clients and Hugo can auto-link `www.$d` into `[www.$d](https://www.$d)` when the code is copied from a rendered view. That would break the query. See [Copying Code Safely](#copying-code-safely).

### Answer Section Filtering

```powershell
Where-Object { $_.Section -eq 'Answer' -and "$($_.Type)" -eq $t }
```

| Filter | Reason |
|--------|--------|
| `Section -eq 'Answer'` | When a name has no record of the requested type, the server returns the zone SOA in the Authority section (a NODATA response, RFC 2308). Without this filter, the SOA would look like a result. |
| `Type -eq $t` | A query that follows a CNAME returns the CNAME and the target record. This keeps only the type that was asked for. |
| `-DnsOnly` | Stops Windows falling back to LLMNR or NetBIOS |
| `-Server` | Bypasses local DNS cache |

### DKIM Two-Step Lookup

```powershell
$cn  = (Q $n CNAME).NameHost
$key = (Q $(if ($cn) { $cn } else { $n }) TXT) ...
```

1. Query the selector for a CNAME, which is the record in your own zone.
2. Query the TXT key at the CNAME target (provider-hosted), or at the selector itself if there's no CNAME (self-hosted or Google-style TXT DKIM).

A single TXT query can't separate the two cases. When the CNAME exists but its target has no key, `Resolve-DnsName` errors and returns nothing, including the CNAME. The two-step lookup reports which part is missing.

The key size is estimated from the length of the `p=` base64 value. Treat it as approximate.

### Duplicate SPF and DMARC Detection

More than one SPF record makes SPF return a permanent error (RFC 7208 section 4.5). More than one DMARC record causes DMARC processing to be skipped (RFC 7489 section 6.6.3). Both show as WARN, with every record listed.

## Usage Examples

```powershell
dnscheck yourdomain.com
dnscheck user@yourdomain.com
dnscheck yourdomain.com -Server 8.8.8.8
dnscheck yourdomain.com -Selectors selector1,selector2,google
```

To query the authoritative nameserver directly, which bypasses all caching:

```powershell
dnscheck yourdomain.com -Server ns1.bdm.microsoftonline.com
```

Common DKIM selectors:

| Provider | Selector(s) | Record Type |
|----------|-------------|-------------|
| Microsoft 365 | `selector1`, `selector2` | CNAME |
| Google Workspace | `google` | TXT |
| Mailchimp / Mandrill | `k1`, `k2`, `k3` | CNAME |
| SendGrid | `s1`, `s2` | CNAME |

Selectors are set by each provider and can change. Confirm them against the provider's dashboard, or against the `s=` value in a received message's `DKIM-Signature` header.

## Example Output

Real output for a Microsoft 365 domain hosted on Azure DNS:

```
DNS check: ajolnet.com  (resolver 1.1.1.1)

Web
  A                 NONE     not set
  AAAA              NONE     not set
  WWW               NONE     not set

DNS zone
  NS                OK       ns1.bdm.microsoftonline.com
                             ns2.bdm.microsoftonline.com
                             ns3.bdm.microsoftonline.com
                             ns4.bdm.microsoftonline.com
  SOA               OK       ns1.bdm.microsoftonline.com  serial 1

Mail routing
  MX                OK       0  ajolnet-com.mail.protection.outlook.com
  Autodiscover      OK       CNAME -> autodiscover.outlook.com
  Autodiscover SRV  NONE     not set

Email authentication
  SPF               OK       v=spf1 include:spf.protection.outlook.com ip4:37.59.98.223 ip4:37.59.96.34 ip6:2001:41d0:305:2100::b259 -all
  DMARC             OK       v=DMARC1; p=quarantine; pct=100; rua=mailto:dmarc@ajolnet.com; aspf=r; adkim=r; fo=1
  DKIM selector1    OK       key published (~2048-bit)
                             CNAME -> selector1-ajolnet-com._domainkey.andrewjitlabs.w-v1.dkim.mail.microsoft
  DKIM selector2    OK       key published (~2048-bit)
                             CNAME -> selector2-ajolnet-com._domainkey.andrewjitlabs.w-v1.dkim.mail.microsoft

Optional
  MTA-STS           NONE     not set
  TLS-RPT           NONE     not set
  BIMI              NONE     not set

Other TXT
  TXT               OK       mscid=KbF+JjrB...
```

## Reading the Output

### A Record Shows NONE

`A NONE not set` means the domain has no A record at the root. This is normal when nothing is hosted on the bare domain, for example when the website is on a subdomain.

To confirm by hand:

```powershell
Resolve-DnsName yourdomain.com -Type A
```

| Raw Result | Meaning |
|------------|---------|
| A record in the Answer section | An A record exists |
| Only SOA, in the Authority section | NODATA. The name exists but has no A record (RFC 2308). |
| "DNS name does not exist" | NXDOMAIN. The name doesn't exist at all. |

`dnscheck` only checks the root and `www`. Check subdomains directly:

```powershell
Resolve-DnsName blog.yourdomain.com -Type A -Server 1.1.1.1
```

### DKIM CNAME Found but No Key at Target

```
DKIM selector2    WARN     CNAME found but no key at target
                           CNAME -> selector2-yourdomain-com._domainkey.tenant.w-v1.dkim.mail.microsoft
```

Your zone is correct, but the provider isn't publishing the key at the target. With Microsoft 365, selector2 often has no key published until a key rotation is triggered. Mail isn't affected while signing uses selector1.

Check the signing configuration:

```powershell
Connect-ExchangeOnline
Get-DkimSigningConfig -Identity yourdomain.com | Format-List Status,Enabled,Selector1CNAME,Selector2CNAME,RotateOnDate
```

Trigger a rotation:

```powershell
Rotate-DkimSigningConfig -Identity yourdomain.com
```

Or in the Defender portal:

```
security.microsoft.com > Email & collaboration > Policies & rules > Threat policies > Email authentication settings > DKIM > [domain] > Rotate DKIM keys
```

`RotateOnDate` shows when the switch is scheduled, and it follows the session's regional date format (UK `dd/MM/yyyy`). Don't rotate again before that date. Re-run `dnscheck` once it has passed.

If the key still doesn't appear, users have reported (not verified) that disabling and re-enabling DKIM for the domain fixes it.

Mixed case in Microsoft's CNAME values, such as `AndrewJITLabs`, doesn't matter. DNS names aren't case-sensitive (RFC 4343).

### Other Findings

| Finding | Meaning | Action |
|---------|---------|--------|
| SPF WARN, more than one record | SPF returns a permanent error | Merge into a single `v=spf1` record |
| DMARC WARN, more than one record | DMARC is not processed | Delete the extra records |
| DKIM MISSING | No CNAME or TXT at the selector | Publish the provider's records, or check the selector name |
| DKIM WARN, key revoked | The `p=` value is empty (RFC 6376 section 3.6.1) | Expected after a key has been retired, otherwise republish the key |
| NS not at the expected provider | Records are being edited in the wrong DNS panel | Make the changes at the provider shown in NS |

## Installation

The function file goes in the IT-Scripts repo and is dot-sourced from the profile. This keeps it version-controlled, synced through OneDrive, and safe from profile overwrites.

### Step 1: Save the Function File

```powershell
New-Item -Path 'C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\Utils\DNS-Tools' -ItemType Directory -Force
notepad 'C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\Utils\DNS-Tools\dnscheck.ps1'
```

Paste the [full function](#full-function) and save.

### Step 2: Dot-Source from the Profile

```powershell
notepad $PROFILE
```

Add this block after the `Show-Help` function and before the oh-my-posh and zoxide init block. Init commands should stay at the end of the profile.

```powershell
# region Custom: dnscheck
$dnscheck = 'C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\Utils\DNS-Tools\dnscheck.ps1'
if (Test-Path $dnscheck) { . $dnscheck } else { Write-Warning "dnscheck not found at $dnscheck" }
# endregion Custom: dnscheck
```

The leading `. ` (dot-source) runs the file in the current scope, so the function stays available after the file has run. If you run the file without the dot, the function is discarded when the script ends.

### Step 3: Add to Show-Help

Add this line inside the `Show-Help` here-string (between `@"` and `"@`), at the top of the System Shortcuts section:

```powershell
  ${command}dnscheck <domain>${reset}  ${accent}→${reset} ${desc}DNS / mail auth check${reset}
```

The line must go inside the here-string. The `${command}`, `${reset}` and related variables are only defined inside `Show-Help`. Placed anywhere else in the profile, the line causes a parse error. The variables are `$PSStyle` colour codes, which need PowerShell 7.2 or later.

### Step 4: Reload and Verify

```powershell
. $PROFILE
Show-Help
Get-Command dnscheck | Select-Object Name, @{n='File';e={$_.ScriptBlock.File}}
dnscheck yourdomain.com
```

`File` should show the `dnscheck.ps1` path.

### Chris Titus Tech Profile Notes

| Issue | Detail | Fix |
|-------|--------|-----|
| `Update-Profile` overwrites `$PROFILE` | Downloads the upstream profile and saves it over the local file, removing all custom edits | Keep custom functions in separate files and dot-source them. After an update, re-add only the dot-source lines. |
| oh-my-posh initialised twice | The `$shouldInitPosh` block loads the configured theme, and the trailing `oh-my-posh init ... tokyo.omp.json` line loads it again with no Warp check | Delete the trailing line and set `$poshTheme` to `Join-Path $env:POSH_THEMES_PATH 'tokyo.omp.json'` |
| Profile load time | The double init adds load time | Check with `Measure-Command { . $PROFILE }` |

## Function Management

### How Functions Persist

| Defined By | Lifetime |
|------------|----------|
| Pasted into the console | Current session only. Gone when the window closes. |
| Script run normally (`.\script.ps1`) | Discarded when the script ends |
| Script dot-sourced (`. .\script.ps1`) | Current session |
| In `$PROFILE`, or dot-sourced from it | Every new session |

PowerShell 7 (`pwsh.exe`) and Windows PowerShell 5.1 (`powershell.exe`) use separate profile files. Run `$PROFILE` in each to see its path. To have a function in both, dot-source the same `.ps1` from both profiles.

### List Functions

All functions in the session, including built-ins:

```powershell
Get-ChildItem Function:
```

Only the functions you added, compared against a clean `-NoProfile` session, with module functions excluded:

```powershell
$base = & (Get-Process -Id $PID).Path -NoProfile -Command '(Get-ChildItem Function:).Name'
Get-ChildItem Function: | Where-Object { $_.Name -notin $base -and -not $_.Source } |
    Select-Object Name, @{n='DefinedIn';e={ if ($_.ScriptBlock.File) { $_.ScriptBlock.File } else { 'console (pasted)' } }}
```

| DefinedIn | Meaning |
|-----------|---------|
| `$PROFILE` path | Loads in every session from the profile |
| Script path | Dot-sourced from that file |
| `console (pasted)` | Current session only |

### View a Function

```powershell
${function:dnscheck}
Get-Command dnscheck | Select-Object Name, CommandType, @{n='File';e={$_.ScriptBlock.File}}
Get-Help dnscheck -Full
```

`Get-Help` reads the comment-based help block in the function.

### Remove a Function

From the current session:

```powershell
Remove-Item Function:\dnscheck -ErrorAction SilentlyContinue
```

Several at once:

```powershell
Remove-Item Function:\dnscheck, Function:\mailcheck -ErrorAction SilentlyContinue
```

Check they've gone (this should return nothing):

```powershell
Get-Command dnscheck, mailcheck -ErrorAction SilentlyContinue
```

To remove a function permanently, also take it out of the profile, or out of the file the profile dot-sources. Otherwise the next session loads it again:

```powershell
Select-String -Path $PROFILE -Pattern 'function (dnscheck|mailcheck)|dnscheck\.ps1'
notepad $PROFILE
```

### Profile Management

Create the profile if it doesn't exist:

```powershell
if (-not (Test-Path $PROFILE)) { New-Item -Path $PROFILE -ItemType File -Force }
```

Edit and reload:

```powershell
notepad $PROFILE
. $PROFILE
```

Back up before major edits or before running `Update-Profile`:

```powershell
Copy-Item $PROFILE "$PROFILE.$(Get-Date -Format yyyyMMdd-HHmm).bak"
```

Measure load time:

```powershell
Measure-Command { . $PROFILE } | Select-Object TotalMilliseconds
```

Fix the execution policy if the profile won't load ("running scripts is disabled"):

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Quick Reference

| Task | Command |
|------|---------|
| List all functions | `Get-ChildItem Function:` |
| View function code | `${function:Name}` |
| Where a function is defined | `(Get-Command Name).ScriptBlock.File` |
| Remove from session | `Remove-Item Function:\Name` |
| Profile path | `$PROFILE` |
| Edit profile | `notepad $PROFILE` |
| Reload profile | `. $PROFILE` |
| Back up profile | `Copy-Item $PROFILE "$PROFILE.bak"` |
| Load a function file | `. 'C:\path\file.ps1'` |

## Minimal Version (mailcheck)

A single-line check of SPF, DMARC and the Microsoft 365 DKIM CNAMEs only:

```powershell
function mailcheck($d){$d=$d -replace '.*@';(Resolve-DnsName $d -Type TXT).Strings -match 'v=spf1';(Resolve-DnsName "_dmarc.$d" -Type TXT).Strings;'selector1','selector2'|%{(Resolve-DnsName "$_._domainkey.$d" -Type CNAME).NameHost}}
```

```powershell
mailcheck yourdomain.com
```

It outputs four lines in order: SPF, DMARC, selector1, selector2. It uses the local resolver.

## Limitations

| Limitation | Detail |
|------------|--------|
| Windows only | Use `dig` on macOS and Linux |
| On-screen output only | `Write-Host` output can't be piped to `Export-Csv` or other cmdlets |
| No CAA | CAA isn't in the `Resolve-DnsName` record type list |
| No DNSSEC validation | Records are shown but not validated |
| No PTR | Reverse DNS for mail hosts isn't checked |
| Root and `www` only | Other subdomains have to be queried separately |
| Selectors must be known | DKIM selectors can't be listed from DNS |
| Key size approximate | Estimated from the length of the `p=` value |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "DNS name contains an invalid character" | An email address was passed to a version without `-replace '.*@'` | Use v2 or pass the domain only |
| Everything shows NONE or MISSING | The resolver is unreachable | `Test-NetConnection 1.1.1.1 -Port 53`, or use `-Server` with your local resolver |
| `dnscheck` not recognised in a new window | The function was pasted, not added to the profile | Follow [Installation](#installation) |
| "dnscheck not found at ..." warning on startup | The dot-source path is wrong, or OneDrive hasn't synced the file | Check with `Test-Path` on the path |
| Parse error on profile load | A `Show-Help` line was placed outside the here-string | Move it between `@"` and `"@` |
| Results differ from the DNS panel | Propagation or cache, or the panel isn't the authoritative provider | Query with `-Server` set to an NS host, and check the NS records |
| DKIM WARN, CNAME but no key | The provider isn't publishing the key at the target | See [DKIM CNAME Found but No Key at Target](#dkim-cname-found-but-no-key-at-target) |

## References

- Microsoft - Resolve-DnsName: https://learn.microsoft.com/en-us/powershell/module/dnsclient/resolve-dnsname
- Microsoft - Write-Host: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/write-host
- Microsoft - about_Functions: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_functions
- Microsoft - about_Function_Provider: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_function_provider
- Microsoft - about_Profiles: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles
- Microsoft - about_Scripts (dot sourcing): https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scripts
- Microsoft - about_Comment_Based_Help: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_comment_based_help
- Microsoft - about_Quoting_Rules (here-strings): https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_quoting_rules
- Microsoft - about_ANSI_Terminals ($PSStyle): https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_ansi_terminals
- Microsoft - about_Execution_Policies: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies
- Microsoft - Configure DKIM for Microsoft 365: https://learn.microsoft.com/en-us/defender-office-365/email-authentication-dkim-configure
- Ali Tajran - DKIM selector2 not working for Microsoft 365: https://www.alitajran.com/dkim-selector2-not-working/
- PowerDMARC - DKIM selector2 not working for Microsoft 365: https://powerdmarc.com/o365-dkim-selector2-not-working/
- Chris Titus Tech - powershell-profile: https://github.com/ChrisTitusTech/powershell-profile
- RFC 2308 - Negative Caching of DNS Queries (NODATA): https://datatracker.ietf.org/doc/html/rfc2308
- RFC 4343 - DNS Case Insensitivity: https://datatracker.ietf.org/doc/html/rfc4343
- RFC 6376 - DKIM Signatures: https://datatracker.ietf.org/doc/html/rfc6376
- RFC 7208 - SPF: https://datatracker.ietf.org/doc/html/rfc7208
- RFC 7489 - DMARC: https://datatracker.ietf.org/doc/html/rfc7489
- RFC 8460 - SMTP TLS Reporting: https://datatracker.ietf.org/doc/html/rfc8460
- RFC 8461 - MTA-STS: https://datatracker.ietf.org/doc/html/rfc8461
