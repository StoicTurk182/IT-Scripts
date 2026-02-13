# DNS Record Export One-Liner

Prompts for a domain name, queries A, MX, TXT, CNAME, and SOA records for the root domain and common subdomains via `Resolve-DnsName`, formats as a table, and copies to clipboard. Also prompts for additional custom subdomains.

## One-Liner

```powershell
$d=Read-Host "Enter domain name";$extra=Read-Host "Additional subdomains (comma-separated, or leave blank)";$subs=@("www","mail","blog","ftp","vpn","remote","autodiscover","sip","lyncdiscover","enterpriseregistration","enterpriseenrollment","_dmarc");if($extra){$subs+=$extra.Split(",").Trim()};$hosts=@($d)+($subs|ForEach-Object{"$_.$d"});$results=@();foreach($h in $hosts){foreach($t in @("A","AAAA","CNAME","MX","TXT","SRV","SOA")){$types=if($h-eq$d){@("A","AAAA","MX","TXT","SRV","SOA")}else{@("A","AAAA","CNAME")};if($t-notin$types){continue};try{$r=Resolve-DnsName -Name $h -Type $t -ErrorAction Stop|Where-Object{$_.QueryType-ne'SOA'-or$t-eq'SOA'};if($r){$results+=$r|Select-Object @{N='Host';E={$h}},@{N='Type';E={$t}},@{N='Value';E={if($_.IPAddress){$_.IPAddress}elseif($_.NameExchange){$_.NameExchange+" (Pri: "+$_.Preference+")"}elseif($_.Strings){$_.Strings-join" "}elseif($_.NameHost){$_.NameHost}elseif($_.PrimaryServer){$_.PrimaryServer+" | Serial: "+$_.SerialNumber}else{$_.ToString()}}}}}catch{}}};$results|Format-Table -AutoSize|Out-String|Set-Clipboard;$results|Format-Table -AutoSize;Write-Host "`nDNS records copied to clipboard. $($results.Count) records found.`n" -ForegroundColor Green
```

## Readable Version

```powershell
$d = Read-Host "Enter domain name"
$extra = Read-Host "Additional subdomains (comma-separated, or leave blank)"

# Common subdomains to check
$subs = @(
    "www", "mail", "blog", "ftp", "vpn", "remote",
    "autodiscover", "sip", "lyncdiscover",
    "enterpriseregistration", "enterpriseenrollment",
    "_dmarc"
)

# Append any user-specified subdomains
if ($extra) { $subs += $extra.Split(",").Trim() }

# Build full host list: root domain + all subdomains
$hosts = @($d) + ($subs | ForEach-Object { "$_.$d" })

$results = @()

foreach ($h in $hosts) {
    # Root domain: query A, AAAA, MX, TXT, SRV, SOA
    # Subdomains: query A, AAAA, CNAME only
    $types = if ($h -eq $d) {
        @("A", "AAAA", "MX", "TXT", "SRV", "SOA")
    } else {
        @("A", "AAAA", "CNAME")
    }

    foreach ($t in $types) {
        try {
            $r = Resolve-DnsName -Name $h -Type $t -ErrorAction Stop |
                 Where-Object { $_.QueryType -ne 'SOA' -or $t -eq 'SOA' }

            if ($r) {
                $results += $r | Select-Object @{N='Host';E={$h}},
                                               @{N='Type';E={$t}},
                                               @{N='Value';E={
                                                   if ($_.IPAddress) { $_.IPAddress }
                                                   elseif ($_.NameExchange) { $_.NameExchange + " (Pri: " + $_.Preference + ")" }
                                                   elseif ($_.Strings) { $_.Strings -join " " }
                                                   elseif ($_.NameHost) { $_.NameHost }
                                                   elseif ($_.PrimaryServer) { $_.PrimaryServer + " | Serial: " + $_.SerialNumber }
                                                   else { $_.ToString() }
                                               }}
            }
        } catch {
            # No record exists - skip silently
        }
    }
}

$results | Format-Table -AutoSize | Out-String | Set-Clipboard
$results | Format-Table -AutoSize
Write-Host "`nDNS records copied to clipboard. $($results.Count) records found.`n" -ForegroundColor Green
```

## Example Output

```
Host                                    Type  Value
----                                    ----  -----
ajolnet.com                             MX    ajolnet-com.mail.protection.outlook.com (Pri: 0)
ajolnet.com                             TXT   mscid=KbF+JjrBDtvkNentBiB6M+fp255sgMl...
ajolnet.com                             TXT   v=spf1 include:spf.protection.outlook.com ip4:37.59.98.223...
ajolnet.com                             SOA   ns1.bdm.microsoftonline.com | Serial: 1
blog.ajolnet.com                        A     37.59.98.223
autodiscover.ajolnet.com                CNAME autodiscover.outlook.com
enterpriseregistration.ajolnet.com      CNAME enterpriseregistration.windows.net
enterpriseenrollment.ajolnet.com        CNAME enterpriseenrollment.manage.microsoft.com
_dmarc.ajolnet.com                      TXT   v=DMARC1; p=none;
```

## Default Subdomains Checked

| Subdomain | Reason |
|---|---|
| www | Standard web alias |
| mail | Mail server |
| blog | Blog / CMS hosting |
| ftp | File transfer |
| vpn | VPN gateway |
| remote | Remote access (RDP gateway, etc.) |
| autodiscover | Exchange / M365 email client autoconfiguration |
| sip | Skype for Business / Teams SIP |
| lyncdiscover | Skype for Business / Teams discovery |
| enterpriseregistration | Microsoft Entra device registration |
| enterpriseenrollment | Intune MDM enrolment |
| _dmarc | DMARC email authentication policy |

These cover the most common records for a typical SMB environment running Microsoft 365. The prompt for additional subdomains lets you add anything domain-specific (e.g. `portal`, `api`, `staging`, `dev`).

## Design Decisions

- Subdomains only query A, AAAA, and CNAME since MX/TXT/SRV/SOA records are almost always on the root domain. This keeps the output clean and the query count reasonable
- Records that do not exist are silently skipped rather than showing "No record found" rows, as the subdomain list is speculative and most will not exist
- AAAA (IPv6) is included alongside A records
- SRV is queried on the root to catch Teams/SIP service records
- The table prints to console as well as clipboard so you can review before pasting
- DNS cannot enumerate subdomains. This script checks common ones but is not exhaustive. If the source domain has unusual subdomains, add them via the prompt or check the Fasthosts Advanced DNS panel directly

## Notes

- Uses `Resolve-DnsName` (built into Windows 8.1+ / Server 2012 R2+, no module install required)
- Filter uses `Where-Object { $_.QueryType -ne 'SOA' -or $t -eq 'SOA' }` to strip SOA authority bleed from other record types
- Multiple records of the same type each get their own row
- Clipboard content is plain text table, paste directly into Obsidian, ticketing systems, or documentation

## References

- Resolve-DnsName: https://learn.microsoft.com/en-us/powershell/module/dnsclient/resolve-dnsname
- Set-Clipboard: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/set-clipboard
- Microsoft 365 DNS Records Required: https://learn.microsoft.com/en-us/microsoft-365/enterprise/external-domain-name-system-records
