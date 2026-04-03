# Configuration
$DNSServer = "8.8.8.8"

# Define the list of records to verify
$Checks = @(
    [PSCustomObject]@{ Name = "toast-group.com";                       Type = "TXT"   }
    [PSCustomObject]@{ Name = "toast-group.com";                       Type = "MX"    }
    [PSCustomObject]@{ Name = "toast-group.com";                       Type = "CNAME" }
    [PSCustomObject]@{ Name = "toast-group.com";                       Type = "CNAME" }
    [PSCustomObject]@{ Name = "toast-group.com";                       Type = "TXT"   }
    [PSCustomObject]@{ Name = "toast-group.com";                       Type = "NS"    }
)

Write-Host "Starting DNS Verification using Server: $DNSServer" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------" -ForegroundColor Gray

$Results = foreach ($Check in $Checks) {
    try {
        # Perform the lookup
        $Records = Resolve-DnsName -Name $Check.Name -Type $Check.Type -Server $DNSServer -ErrorAction Stop
        
        # Process each record returned (sometimes one query returns multiple records)
        foreach ($Record in $Records) {
            # Extract the 'Value' based on record type for cleaner output
            $Value = switch ($Record.Type) {
                "MX"    { "$($Record.NameExchange) (Pref: $($Record.Preference))" }
                "CNAME" { $Record.NameHost }
                "TXT"   { $Record.Strings -join " " }
                "NS"    { $Record.NameHost }
                Default { "Complex Data/Other" }
            }

            [PSCustomObject]@{
                Status      = "OK"
                RecordType  = $Record.Type
                Hostname    = $Record.Name
                Result      = $Value
            }
        }
    }
    catch {
        # Handle cases where the record is missing or DNS fails
        [PSCustomObject]@{
            Status      = "MISSING/ERROR"
            RecordType  = $Check.Type
            Hostname    = $Check.Name
            Result      = $_.Exception.Message
        }
    }
}

# Output the results in a formatted table
$Results | Format-Table -AutoSize -Property Status, RecordType, Hostname, Result

Write-Host "--------------------------------------------------------" -ForegroundColor Gray
Write-Host "Verification Complete." -ForegroundColor Cyan