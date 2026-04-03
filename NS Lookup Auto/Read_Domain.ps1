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