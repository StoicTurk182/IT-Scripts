<#
.SYNOPSIS
    Comprehensive domain health diagnostic tool for email and DNS.

.DESCRIPTION
    Runs a full diagnostic sweep against a domain covering DNS records,
    email authentication (SPF, DKIM, DMARC), mail server connectivity,
    blacklist checks, TLS capability, reverse DNS, and M365 tenant discovery.
    Outputs results to console and optionally exports to a timestamped report file.

.PARAMETER Domain
    The target domain to diagnose (e.g., signaturerecruitment.london)

.PARAMETER DnsServer
    DNS server to query against. Default: 8.8.8.8 (Google Public DNS)

.PARAMETER DkimSelectors
    Array of DKIM selectors to check. Default: selector1, selector2, google

.PARAMETER ExportPath
    Optional path to export the report. Default: current directory.

.PARAMETER NoExport
    Switch to skip file export and only output to console.

.EXAMPLE
    .\Get-DomainHealth.ps1 -Domain "ENTER DOMAIN NAME"
    Runs full diagnostic with defaults and exports report.

.EXAMPLE
    .\Get-DomainHealth.ps1 -Domain "ajolnet.com" -DkimSelectors "selector1","selector2" -NoExport
    Runs diagnostic with custom selectors, console output only.

.EXAMPLE
    .\Get-DomainHealth.ps1 -Domain "example.com" -DnsServer "1.1.1.1" -ExportPath "C:\Reports"
    Runs diagnostic against Cloudflare DNS and exports to specified path.

.NOTES
    Author: Informal IT Ltd
    Version: 1.0
    Date: 2026-02-13
    Requires: PowerShell 5.1+
    Optional: DomainHealthChecker module (Install-Module DomainHealthChecker)
#>

#Requires -Version 5.1

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$Domain,

    [Parameter()]
    [string]$DnsServer = "8.8.8.8",

    [Parameter()]
    [string[]]$DkimSelectors = @("selector1", "selector2", "google"),

    [Parameter()]
    [string]$ExportPath = (Get-Location).Path,

    [Parameter()]
    [switch]$NoExport
)

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "HEADER", "SUBHEADER")]
        [string]$Level = "INFO"
    )
    $colors = @{
        "INFO"      = "Cyan"
        "SUCCESS"   = "Green"
        "WARNING"   = "Yellow"
        "ERROR"     = "Red"
        "HEADER"    = "Magenta"
        "SUBHEADER" = "White"
    }
    $timestamp = Get-Date -Format "HH:mm:ss"
    $prefix = switch ($Level) {
        "HEADER"    { "`n{'='*70}`n" }
        "SUBHEADER" { "`n---" }
        default     { "[$timestamp] [$Level]" }
    }

    if ($Level -eq "HEADER") {
        Write-Host "`n$('=' * 70)" -ForegroundColor $colors[$Level]
        Write-Host "  $Message" -ForegroundColor $colors[$Level]
        Write-Host "$('=' * 70)" -ForegroundColor $colors[$Level]
    } elseif ($Level -eq "SUBHEADER") {
        Write-Host "`n--- $Message ---" -ForegroundColor $colors[$Level]
    } else {
        Write-Host "$prefix $Message" -ForegroundColor $colors[$Level]
    }
}

function Test-DnsRecord {
    param (
        [string]$Name,
        [string]$Type,
        [string]$Server,
        [string]$Label
    )

    try {
        $result = Resolve-DnsName -Name $Name -Type $Type -Server $Server -ErrorAction Stop
        return $result
    } catch {
        Write-Log "$Label : NOT FOUND" -Level "WARNING"
        return $null
    }
}

function Get-ReversedIp {
    param ([string]$Ip)
    $octets = $Ip -split '\.'
    [array]::Reverse($octets)
    return ($octets -join '.')
}

# ============================================================================
# REPORT COLLECTION
# ============================================================================

$report = [System.Collections.ArrayList]::new()

function Add-ReportLine {
    param ([string]$Line)
    [void]$report.Add($Line)
}

function Add-ReportSection {
    param ([string]$Title)
    Add-ReportLine ""
    Add-ReportLine "## $Title"
    Add-ReportLine ""
}

function Add-ReportEntry {
    param (
        [string]$Label,
        [string]$Value,
        [string]$Status = "INFO"
    )
    Add-ReportLine "| $Label | $Value | $Status |"
}

# ============================================================================
# MAIN
# ============================================================================

$startTime = Get-Date

Write-Log "Domain Health Diagnostic: $Domain" -Level "HEADER"
Write-Log "DNS Server: $DnsServer" -Level "INFO"
Write-Log "DKIM Selectors: $($DkimSelectors -join ', ')" -Level "INFO"
Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level "INFO"

# Report header
Add-ReportLine "# Domain Health Report: $Domain"
Add-ReportLine "**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Add-ReportLine "**DNS Server:** $DnsServer"
Add-ReportLine "**Tool:** Get-DomainHealth.ps1 v1.0"
Add-ReportLine ""
Add-ReportLine "---"

# --------------------------------------------------
# 1. NAMESERVERS
# --------------------------------------------------
Write-Log "Nameservers" -Level "SUBHEADER"
Add-ReportSection "1. Nameservers"
Add-ReportLine "| Record | Value | Status |"
Add-ReportLine "|--------|-------|--------|"

$ns = Test-DnsRecord -Name $Domain -Type NS -Server $DnsServer -Label "NS"
if ($ns) {
    foreach ($record in ($ns | Where-Object { $_.QueryType -eq 'NS' })) {
        $nsHost = $record.NameHost
        Write-Log "NS: $nsHost" -Level "SUCCESS"
        Add-ReportEntry -Label "NS" -Value $nsHost -Status "FOUND"
    }
} else {
    Add-ReportEntry -Label "NS" -Value "No NS records found" -Status "ERROR"
}

# --------------------------------------------------
# 2. SOA RECORD
# --------------------------------------------------
Write-Log "SOA Record" -Level "SUBHEADER"
Add-ReportSection "2. SOA Record"
Add-ReportLine "| Field | Value | Status |"
Add-ReportLine "|-------|-------|--------|"

$soa = Test-DnsRecord -Name $Domain -Type SOA -Server $DnsServer -Label "SOA"
if ($soa) {
    $soaRecord = $soa | Where-Object { $_.QueryType -eq 'SOA' }
    if ($soaRecord) {
        Write-Log "Primary: $($soaRecord.PrimaryServer)" -Level "INFO"
        Write-Log "Admin: $($soaRecord.NameAdministrator)" -Level "INFO"
        Write-Log "Serial: $($soaRecord.SerialNumber)" -Level "INFO"
        Write-Log "Refresh: $($soaRecord.RefreshInterval)" -Level "INFO"
        Write-Log "Retry: $($soaRecord.RetryDelay)" -Level "INFO"
        Write-Log "Expire: $($soaRecord.ExpireLimit)" -Level "INFO"
        Write-Log "Min TTL: $($soaRecord.DefaultTTL)" -Level "INFO"

        Add-ReportEntry -Label "Primary Server" -Value $soaRecord.PrimaryServer -Status "FOUND"
        Add-ReportEntry -Label "Admin" -Value $soaRecord.NameAdministrator -Status "INFO"
        Add-ReportEntry -Label "Serial" -Value $soaRecord.SerialNumber -Status "INFO"
        Add-ReportEntry -Label "Refresh" -Value $soaRecord.RefreshInterval -Status "INFO"
        Add-ReportEntry -Label "Retry" -Value $soaRecord.RetryDelay -Status "INFO"
        Add-ReportEntry -Label "Expire" -Value $soaRecord.ExpireLimit -Status $(if ($soaRecord.ExpireLimit -lt 604800 -or $soaRecord.ExpireLimit -gt 2419200) { "WARNING" } else { "OK" })
        Add-ReportEntry -Label "Min TTL" -Value $soaRecord.DefaultTTL -Status "INFO"
    }
} else {
    Add-ReportEntry -Label "SOA" -Value "No SOA record found" -Status "ERROR"
}

# --------------------------------------------------
# 3. A / AAAA RECORDS
# --------------------------------------------------
Write-Log "A / AAAA Records" -Level "SUBHEADER"
Add-ReportSection "3. A / AAAA Records"
Add-ReportLine "| Type | Value | Status |"
Add-ReportLine "|------|-------|--------|"

$aRecords = Test-DnsRecord -Name $Domain -Type A -Server $DnsServer -Label "A Record"
if ($aRecords) {
    foreach ($a in ($aRecords | Where-Object { $_.QueryType -eq 'A' })) {
        Write-Log "A: $($a.IPAddress)" -Level "SUCCESS"
        Add-ReportEntry -Label "A" -Value $a.IPAddress -Status "FOUND"
    }
} else {
    Add-ReportEntry -Label "A" -Value "No A record found" -Status "WARNING"
}

$aaaaRecords = Test-DnsRecord -Name $Domain -Type AAAA -Server $DnsServer -Label "AAAA Record"
if ($aaaaRecords) {
    foreach ($aaaa in ($aaaaRecords | Where-Object { $_.QueryType -eq 'AAAA' })) {
        Write-Log "AAAA: $($aaaa.IPAddress)" -Level "SUCCESS"
        Add-ReportEntry -Label "AAAA" -Value $aaaa.IPAddress -Status "FOUND"
    }
} else {
    Write-Log "AAAA: None (IPv6 not configured)" -Level "INFO"
    Add-ReportEntry -Label "AAAA" -Value "Not configured" -Status "INFO"
}

# --------------------------------------------------
# 4. MX RECORDS
# --------------------------------------------------
Write-Log "MX Records" -Level "SUBHEADER"
Add-ReportSection "4. MX Records"
Add-ReportLine "| Host | Priority | Status |"
Add-ReportLine "|------|----------|--------|"

$mx = Test-DnsRecord -Name $Domain -Type MX -Server $DnsServer -Label "MX"
$mxHosts = @()
if ($mx) {
    foreach ($record in ($mx | Where-Object { $_.QueryType -eq 'MX' } | Sort-Object Preference)) {
        $mxHosts += $record.NameExchange
        Write-Log "MX: $($record.NameExchange) (Priority: $($record.Preference))" -Level "SUCCESS"
        Add-ReportEntry -Label $record.NameExchange -Value $record.Preference -Status "FOUND"
    }
} else {
    Add-ReportEntry -Label "MX" -Value "No MX records found" -Status "ERROR"
}

# --------------------------------------------------
# 5. SPF RECORD
# --------------------------------------------------
Write-Log "SPF Record" -Level "SUBHEADER"
Add-ReportSection "5. SPF Record"
Add-ReportLine "| Check | Value | Status |"
Add-ReportLine "|-------|-------|--------|"

$txtRecords = Test-DnsRecord -Name $Domain -Type TXT -Server $DnsServer -Label "TXT"
$spfRecords = @()
if ($txtRecords) {
    $spfRecords = $txtRecords | Where-Object { $_.Strings -match "v=spf1" }
}

if ($spfRecords.Count -eq 0) {
    Write-Log "SPF: NOT FOUND" -Level "ERROR"
    Add-ReportEntry -Label "SPF Record" -Value "NOT FOUND" -Status "ERROR"
} elseif ($spfRecords.Count -gt 1) {
    Write-Log "SPF: MULTIPLE RECORDS FOUND (invalid per RFC 7208)" -Level "ERROR"
    Add-ReportEntry -Label "SPF Record" -Value "MULTIPLE RECORDS (invalid)" -Status "ERROR"
    foreach ($spf in $spfRecords) {
        $spfString = ($spf.Strings -join '')
        Add-ReportEntry -Label "SPF Value" -Value $spfString -Status "ERROR"
    }
} else {
    $spfString = ($spfRecords[0].Strings -join '')
    Write-Log "SPF: $spfString" -Level "SUCCESS"
    Add-ReportEntry -Label "SPF Record" -Value $spfString -Status "FOUND"
    Add-ReportEntry -Label "Length" -Value "$($spfString.Length) chars" -Status $(if ($spfString.Length -gt 255) { "WARNING" } else { "OK" })

    # Count DNS lookups
    $lookups = ([regex]::Matches($spfString, '(include:|a:|mx:|redirect=|exists:)')).Count
    $lookupStatus = if ($lookups -gt 10) { "ERROR" } elseif ($lookups -gt 7) { "WARNING" } else { "OK" }
    Write-Log "SPF DNS Lookups: $lookups/10" -Level $(if ($lookups -gt 10) { "ERROR" } elseif ($lookups -gt 7) { "WARNING" } else { "SUCCESS" })
    Add-ReportEntry -Label "DNS Lookups" -Value "$lookups/10" -Status $lookupStatus

    # Check policy
    if ($spfString -match '-all$') {
        Write-Log "SPF Policy: Hard Fail (-all)" -Level "SUCCESS"
        Add-ReportEntry -Label "Policy" -Value "Hard Fail (-all)" -Status "OK"
    } elseif ($spfString -match '~all$') {
        Write-Log "SPF Policy: Soft Fail (~all)" -Level "WARNING"
        Add-ReportEntry -Label "Policy" -Value "Soft Fail (~all)" -Status "WARNING"
    } elseif ($spfString -match '\+all$') {
        Write-Log "SPF Policy: Pass All (+all) — INSECURE" -Level "ERROR"
        Add-ReportEntry -Label "Policy" -Value "Pass All (+all) — INSECURE" -Status "ERROR"
    } elseif ($spfString -match '\?all$') {
        Write-Log "SPF Policy: Neutral (?all)" -Level "WARNING"
        Add-ReportEntry -Label "Policy" -Value "Neutral (?all)" -Status "WARNING"
    }
}

# --------------------------------------------------
# 6. DKIM RECORDS
# --------------------------------------------------
Write-Log "DKIM Records" -Level "SUBHEADER"
Add-ReportSection "6. DKIM Records"
Add-ReportLine "| Selector | Value | Status |"
Add-ReportLine "|----------|-------|--------|"

foreach ($selector in $DkimSelectors) {
    $dkimName = "$selector._domainkey.$Domain"

    # Check CNAME first (M365 style)
    $dkimCname = Test-DnsRecord -Name $dkimName -Type CNAME -Server $DnsServer -Label "DKIM ($selector) CNAME"
    if ($dkimCname) {
        $cnameTarget = ($dkimCname | Where-Object { $_.QueryType -eq 'CNAME' }).NameHost
        if ($cnameTarget) {
            Write-Log "DKIM ($selector): CNAME -> $cnameTarget" -Level "SUCCESS"
            Add-ReportEntry -Label $selector -Value "CNAME: $cnameTarget" -Status "FOUND"
            continue
        }
    }

    # Check TXT (direct key style)
    $dkimTxt = Test-DnsRecord -Name $dkimName -Type TXT -Server $DnsServer -Label "DKIM ($selector) TXT"
    if ($dkimTxt) {
        $dkimString = ($dkimTxt | Where-Object { $_.Strings -match "v=DKIM1" }).Strings -join ''
        if ($dkimString) {
            $keyLength = if ($dkimString -match 'p=([A-Za-z0-9+/=]+)') {
                $keyBytes = [System.Convert]::FromBase64String($Matches[1])
                "$($keyBytes.Length * 8)-bit"
            } else { "Unknown" }
            Write-Log "DKIM ($selector): TXT record found ($keyLength)" -Level "SUCCESS"
            Add-ReportEntry -Label $selector -Value "TXT: $keyLength key" -Status "FOUND"
            continue
        }
    }

    Write-Log "DKIM ($selector): NOT FOUND" -Level "WARNING"
    Add-ReportEntry -Label $selector -Value "NOT FOUND" -Status "WARNING"
}

# --------------------------------------------------
# 7. DMARC RECORD
# --------------------------------------------------
Write-Log "DMARC Record" -Level "SUBHEADER"
Add-ReportSection "7. DMARC Record"
Add-ReportLine "| Check | Value | Status |"
Add-ReportLine "|-------|-------|--------|"

$dmarc = Test-DnsRecord -Name "_dmarc.$Domain" -Type TXT -Server $DnsServer -Label "DMARC"
if ($dmarc) {
    $dmarcString = ($dmarc | Where-Object { $_.Strings -match "v=DMARC1" }).Strings -join ''
    if ($dmarcString) {
        Write-Log "DMARC: $dmarcString" -Level "SUCCESS"
        Add-ReportEntry -Label "DMARC Record" -Value $dmarcString -Status "FOUND"

        # Parse policy
        if ($dmarcString -match 'p=(\w+)') {
            $policy = $Matches[1]
            $policyStatus = switch ($policy) {
                "reject"     { "OK" }
                "quarantine" { "WARNING" }
                "none"       { "WARNING" }
                default      { "ERROR" }
            }
            Write-Log "DMARC Policy: $policy" -Level $(if ($policy -eq "reject") { "SUCCESS" } else { "WARNING" })
            Add-ReportEntry -Label "Policy" -Value "p=$policy" -Status $policyStatus
        }

        # Parse pct
        if ($dmarcString -match 'pct=(\d+)') {
            $pct = $Matches[1]
            Write-Log "DMARC Percentage: $pct%" -Level $(if ($pct -eq "100") { "SUCCESS" } else { "WARNING" })
            Add-ReportEntry -Label "Percentage" -Value "pct=$pct" -Status $(if ($pct -eq "100") { "OK" } else { "WARNING" })
        }

        # Parse rua
        if ($dmarcString -match 'rua=mailto:([^\s;]+)') {
            Write-Log "DMARC Reports: $($Matches[1])" -Level "INFO"
            Add-ReportEntry -Label "Aggregate Reports" -Value $Matches[1] -Status "INFO"
        }
    } else {
        Write-Log "DMARC: NOT FOUND" -Level "ERROR"
        Add-ReportEntry -Label "DMARC Record" -Value "NOT FOUND" -Status "ERROR"
    }
} else {
    Add-ReportEntry -Label "DMARC Record" -Value "NOT FOUND" -Status "ERROR"
}

# --------------------------------------------------
# 8. AUTODISCOVER
# --------------------------------------------------
Write-Log "Autodiscover" -Level "SUBHEADER"
Add-ReportSection "8. Autodiscover"
Add-ReportLine "| Type | Value | Status |"
Add-ReportLine "|------|-------|--------|"

$autodiscover = Test-DnsRecord -Name "autodiscover.$Domain" -Type CNAME -Server $DnsServer -Label "Autodiscover CNAME"
if ($autodiscover) {
    $adTarget = ($autodiscover | Where-Object { $_.QueryType -eq 'CNAME' }).NameHost
    if ($adTarget) {
        Write-Log "Autodiscover: $adTarget" -Level "SUCCESS"
        Add-ReportEntry -Label "CNAME" -Value $adTarget -Status "FOUND"
    }
} else {
    # Check A record fallback
    $autodiscoverA = Test-DnsRecord -Name "autodiscover.$Domain" -Type A -Server $DnsServer -Label "Autodiscover A"
    if ($autodiscoverA) {
        $adIp = ($autodiscoverA | Where-Object { $_.QueryType -eq 'A' }).IPAddress
        Write-Log "Autodiscover: A record -> $adIp (CNAME preferred)" -Level "WARNING"
        Add-ReportEntry -Label "A Record" -Value $adIp -Status "WARNING — CNAME preferred"
    } else {
        Add-ReportEntry -Label "Autodiscover" -Value "NOT FOUND" -Status "WARNING"
    }
}

# --------------------------------------------------
# 9. ADVANCED RECORDS (MTA-STS, TLSRPT, BIMI)
# --------------------------------------------------
Write-Log "Advanced Email Security Records" -Level "SUBHEADER"
Add-ReportSection "9. Advanced Email Security"
Add-ReportLine "| Record | Value | Status |"
Add-ReportLine "|--------|-------|--------|"

# MTA-STS
$mtasts = Test-DnsRecord -Name "_mta-sts.$Domain" -Type TXT -Server $DnsServer -Label "MTA-STS"
if ($mtasts) {
    $mtaString = ($mtasts | Where-Object { $_.Strings -match "v=STSv1" }).Strings -join ''
    if ($mtaString) {
        Write-Log "MTA-STS: $mtaString" -Level "SUCCESS"
        Add-ReportEntry -Label "MTA-STS" -Value $mtaString -Status "FOUND"
    } else {
        Add-ReportEntry -Label "MTA-STS" -Value "Not configured" -Status "INFO"
    }
} else {
    Add-ReportEntry -Label "MTA-STS" -Value "Not configured" -Status "INFO"
}

# TLSRPT
$tlsrpt = Test-DnsRecord -Name "_smtp._tls.$Domain" -Type TXT -Server $DnsServer -Label "TLSRPT"
if ($tlsrpt) {
    $tlsString = ($tlsrpt | Where-Object { $_.Strings -match "v=TLSRPTv1" }).Strings -join ''
    if ($tlsString) {
        Write-Log "TLSRPT: $tlsString" -Level "SUCCESS"
        Add-ReportEntry -Label "TLSRPT" -Value $tlsString -Status "FOUND"
    } else {
        Add-ReportEntry -Label "TLSRPT" -Value "Not configured" -Status "INFO"
    }
} else {
    Add-ReportEntry -Label "TLSRPT" -Value "Not configured" -Status "INFO"
}

# BIMI
$bimi = Test-DnsRecord -Name "default._bimi.$Domain" -Type TXT -Server $DnsServer -Label "BIMI"
if ($bimi) {
    $bimiString = ($bimi | Where-Object { $_.Strings -match "v=BIMI1" }).Strings -join ''
    if ($bimiString) {
        Write-Log "BIMI: $bimiString" -Level "SUCCESS"
        Add-ReportEntry -Label "BIMI" -Value $bimiString -Status "FOUND"
    } else {
        Add-ReportEntry -Label "BIMI" -Value "Not configured" -Status "INFO"
    }
} else {
    Add-ReportEntry -Label "BIMI" -Value "Not configured" -Status "INFO"
}

# DNSSEC
$dnssec = Test-DnsRecord -Name $Domain -Type DNSKEY -Server $DnsServer -Label "DNSSEC"
if ($dnssec) {
    Write-Log "DNSSEC: Enabled" -Level "SUCCESS"
    Add-ReportEntry -Label "DNSSEC" -Value "Enabled" -Status "FOUND"
} else {
    Add-ReportEntry -Label "DNSSEC" -Value "Not enabled" -Status "INFO"
}

# --------------------------------------------------
# 10. SMTP CONNECTIVITY & TLS
# --------------------------------------------------
Write-Log "Mail Server Connectivity" -Level "SUBHEADER"
Add-ReportSection "10. Mail Server Connectivity"
Add-ReportLine "| Host | Port 25 | Banner | Status |"
Add-ReportLine "|------|---------|--------|--------|"

foreach ($mxHost in $mxHosts) {
    # Port 25 connectivity
    $smtpTest = Test-NetConnection -ComputerName $mxHost -Port 25 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    $portStatus = if ($smtpTest.TcpTestSucceeded) { "OPEN" } else { "CLOSED" }

    # SMTP banner grab
    $banner = "Unable to retrieve"
    if ($smtpTest.TcpTestSucceeded) {
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient($mxHost, 25)
            $tcp.ReceiveTimeout = 5000
            $stream = $tcp.GetStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $banner = $reader.ReadLine()
            $tcp.Close()
        } catch {
            $banner = "Connection failed: $($_.Exception.Message)"
        }
    }

    $statusLevel = if ($smtpTest.TcpTestSucceeded) { "SUCCESS" } else { "ERROR" }
    Write-Log "$mxHost — Port 25: $portStatus — Banner: $banner" -Level $statusLevel
    Add-ReportEntry -Label $mxHost -Value $portStatus -Status $banner
}

# --------------------------------------------------
# 11. REVERSE DNS ON MX IPs
# --------------------------------------------------
Write-Log "Reverse DNS" -Level "SUBHEADER"
Add-ReportSection "11. Reverse DNS (MX Hosts)"
Add-ReportLine "| MX Host | IP | rDNS | Match |"
Add-ReportLine "|---------|-----|------|-------|"

foreach ($mxHost in $mxHosts) {
    try {
        $mxIps = (Resolve-DnsName -Type A -Name $mxHost -Server $DnsServer -ErrorAction Stop | Where-Object { $_.QueryType -eq 'A' }).IPAddress
        foreach ($ip in $mxIps) {
            try {
                $ptr = (Resolve-DnsName -Name $ip -Type PTR -ErrorAction Stop).NameHost
                $match = if ($ptr -match [regex]::Escape($mxHost)) { "MATCH" } else { "MISMATCH" }
                $matchLevel = if ($match -eq "MATCH") { "SUCCESS" } else { "WARNING" }
                Write-Log "$mxHost ($ip) -> rDNS: $ptr [$match]" -Level $matchLevel
                Add-ReportLine "| $mxHost | $ip | $ptr | $match |"
            } catch {
                Write-Log "$mxHost ($ip) -> rDNS: NOT FOUND" -Level "WARNING"
                Add-ReportLine "| $mxHost | $ip | NOT FOUND | ERROR |"
            }
        }
    } catch {
        Write-Log "$mxHost -> Could not resolve IP" -Level "ERROR"
        Add-ReportLine "| $mxHost | UNRESOLVABLE | - | ERROR |"
    }
}

# --------------------------------------------------
# 12. BLACKLIST CHECKS
# --------------------------------------------------
Write-Log "Blacklist Checks" -Level "SUBHEADER"
Add-ReportSection "12. Blacklist Checks"

# IP-based RBLs
Add-ReportLine "### IP Blacklists (MX Hosts)"
Add-ReportLine ""
Add-ReportLine "| MX Host | IP | RBL | Status |"
Add-ReportLine "|---------|-----|-----|--------|"

$rbls = @(
    "zen.spamhaus.org"
    "bl.spamcop.net"
    "b.barracudacentral.org"
    "dnsbl.sorbs.net"
    "dnsbl-1.uceprotect.net"
    "dnsbl-2.uceprotect.net"
    "dnsbl-3.uceprotect.net"
)

foreach ($mxHost in $mxHosts) {
    try {
        $mxIps = (Resolve-DnsName -Type A -Name $mxHost -Server $DnsServer -ErrorAction Stop | Where-Object { $_.QueryType -eq 'A' }).IPAddress
        foreach ($ip in $mxIps) {
            $reversedIp = Get-ReversedIp -Ip $ip
            foreach ($rbl in $rbls) {
                $lookup = "$reversedIp.$rbl"
                $rblResult = Resolve-DnsName -Name $lookup -Type A -ErrorAction SilentlyContinue
                if ($rblResult) {
                    Write-Log "$mxHost ($ip) LISTED on $rbl" -Level "ERROR"
                    Add-ReportLine "| $mxHost | $ip | $rbl | LISTED |"
                } else {
                    Add-ReportLine "| $mxHost | $ip | $rbl | Clean |"
                }
            }
        }
    } catch {
        Write-Log "$mxHost -> Could not resolve for blacklist check" -Level "WARNING"
    }
}

# Domain-based blacklists
Add-ReportLine ""
Add-ReportLine "### Domain Blacklists"
Add-ReportLine ""
Add-ReportLine "| Domain | RBL | Status |"
Add-ReportLine "|--------|-----|--------|"

$domainRbls = @(
    "multi.surbl.org"
    "dbl.spamhaus.org"
)

foreach ($rbl in $domainRbls) {
    $lookup = "$Domain.$rbl"
    $rblResult = Resolve-DnsName -Name $lookup -Type A -ErrorAction SilentlyContinue
    if ($rblResult) {
        Write-Log "$Domain LISTED on $rbl" -Level "ERROR"
        Add-ReportLine "| $Domain | $rbl | LISTED |"
    } else {
        Write-Log "$Domain Clean on $rbl" -Level "SUCCESS"
        Add-ReportLine "| $Domain | $rbl | Clean |"
    }
}

# --------------------------------------------------
# 13. M365 TENANT DISCOVERY
# --------------------------------------------------
Write-Log "Microsoft 365 Tenant Discovery" -Level "SUBHEADER"
Add-ReportSection "13. Microsoft 365 Tenant Discovery"
Add-ReportLine "| Check | Value | Status |"
Add-ReportLine "|-------|-------|--------|"

# MS verification record
$msRecord = $null
if ($txtRecords) {
    $msRecord = $txtRecords | Where-Object { $_.Strings -match "^MS=" }
}
if ($msRecord) {
    $msValue = ($msRecord.Strings | Where-Object { $_ -match "^MS=" })
    Write-Log "MS Verification: $msValue (domain claimed by a tenant)" -Level "WARNING"
    Add-ReportEntry -Label "MS Verification" -Value $msValue -Status "CLAIMED"
} else {
    Write-Log "MS Verification: No MS= record found" -Level "INFO"
    Add-ReportEntry -Label "MS Verification" -Value "Not found" -Status "UNCLAIMED"
}

# Tenant ID via OpenID
try {
    $openId = Invoke-RestMethod "https://login.microsoftonline.com/$Domain/.well-known/openid-configuration" -ErrorAction Stop
    if ($openId.token_endpoint -match '/([a-f0-9-]{36})/') {
        $tenantId = $Matches[1]
        Write-Log "Tenant ID: $tenantId" -Level "INFO"
        Add-ReportEntry -Label "Tenant ID" -Value $tenantId -Status "FOUND"
    }
} catch {
    Write-Log "Tenant ID: Could not retrieve (domain may not be in Azure AD)" -Level "INFO"
    Add-ReportEntry -Label "Tenant ID" -Value "Not found" -Status "INFO"
}

# --------------------------------------------------
# SUMMARY
# --------------------------------------------------
Write-Log "Diagnostic Summary" -Level "HEADER"
Add-ReportSection "14. Summary"
Add-ReportLine "| Component | Status |"
Add-ReportLine "|-----------|--------|"

$summary = @{
    "Nameservers"  = if ($ns) { "FOUND" } else { "MISSING" }
    "A Record"     = if ($aRecords) { "FOUND" } else { "MISSING" }
    "MX Records"   = if ($mx) { "FOUND" } else { "MISSING" }
    "SPF"          = if ($spfRecords.Count -eq 1) { "FOUND" } elseif ($spfRecords.Count -gt 1) { "MULTIPLE (ERROR)" } else { "MISSING" }
    "DKIM"         = "See section 6"
    "DMARC"        = if ($dmarcString) { "FOUND" } else { "MISSING" }
    "Autodiscover" = if ($autodiscover) { "FOUND" } else { "MISSING" }
    "MTA-STS"      = if ($mtasts -and ($mtasts | Where-Object { $_.Strings -match "v=STSv1" })) { "FOUND" } else { "NOT CONFIGURED" }
    "DNSSEC"       = if ($dnssec) { "ENABLED" } else { "NOT ENABLED" }
    "M365 Tenant"  = if ($msRecord) { "CLAIMED" } else { "UNCLAIMED" }
}

foreach ($item in $summary.GetEnumerator() | Sort-Object Name) {
    $statusColor = switch -Regex ($item.Value) {
        "FOUND|ENABLED"         { "SUCCESS" }
        "MISSING|ERROR"         { "ERROR" }
        "CLAIMED"               { "WARNING" }
        default                 { "INFO" }
    }
    Write-Log "$($item.Name): $($item.Value)" -Level $statusColor
    Add-ReportLine "| $($item.Name) | $($item.Value) |"
}

$endTime = Get-Date
$duration = $endTime - $startTime
Write-Log "Completed in $([math]::Round($duration.TotalSeconds, 1)) seconds" -Level "INFO"

Add-ReportLine ""
Add-ReportLine "---"
Add-ReportLine "**Completed:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') (Duration: $([math]::Round($duration.TotalSeconds, 1))s)"

# --------------------------------------------------
# EXPORT
# --------------------------------------------------
if (-not $NoExport) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $sanitizedDomain = $Domain -replace '\.', '-'
    $fileName = "DomainHealth_${sanitizedDomain}_${timestamp}.md"
    $filePath = Join-Path $ExportPath $fileName

    $report | Out-File -FilePath $filePath -Encoding UTF8
    Write-Log "Report exported: $filePath" -Level "SUCCESS"
} else {
    Write-Log "Export skipped (-NoExport specified)" -Level "INFO"
}

Write-Host "`nDiagnostic complete.`n" -ForegroundColor Green
