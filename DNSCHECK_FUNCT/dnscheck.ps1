function dnscheck {
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