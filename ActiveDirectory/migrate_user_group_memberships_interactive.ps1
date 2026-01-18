# 1. Prompt for input
Write-Host "--- Copy AD Group Memberships ---" -ForegroundColor Cyan
$SourceUser = (Read-Host "Enter the SOURCE username (Copy FROM)").Trim()
$TargetUser = (Read-Host "Enter the TARGET username (Copy TO)").Trim()

# 2. Check if the user actually typed something
if ([string]::IsNullOrWhiteSpace($SourceUser) -or [string]::IsNullOrWhiteSpace($TargetUser)) {
    Write-Warning "You must provide both usernames. Script aborted."
    Exit
}

# 3. Validate users exist in AD
Try {
    Write-Host "Verifying users..." -NoNewline
    $SourceObj = Get-ADUser -Identity $SourceUser -Properties MemberOf -ErrorAction Stop
    $TargetObj = Get-ADUser -Identity $TargetUser -ErrorAction Stop
    Write-Host " OK." -ForegroundColor Green
}
Catch {
    Write-Host "" # New line
    Write-Warning "Could not find one of the users. Please check the spelling."
    Write-Host "Error Details: $($_.Exception.Message)"
    Break
}

# 4. Get the groups
$Groups = @($SourceObj | Select-Object -ExpandProperty MemberOf)

if ($Groups.Count -eq 0) {
    Write-Warning "$SourceUser is not a member of any groups (other than Domain Users)."
    Exit
}

Write-Host "Found $( $Groups.Count ) groups for $SourceUser. Copying to $TargetUser..." -ForegroundColor Cyan

# 5. Loop through and add
foreach ($Group in $Groups) {
    # Extract a friendly name for the log (e.g., "CN=VPN Users,OU=..." becomes "VPN Users")
    $GroupName = ($Group -split ",")[0] -replace "CN=",""

    Try {
        Add-ADGroupMember -Identity $Group -Members $TargetUser -ErrorAction Stop
        Write-Host " [SUCCESS] Added to $GroupName" -ForegroundColor Green
    }
    Catch {
        if ($_.Exception.Message -like "*already a member*") {
            Write-Host " [SKIP]   Already in $GroupName" -ForegroundColor Gray
        }
        else {
            Write-Host " [ERROR]  Failed to add to $GroupName : $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host "--- Operation Complete ---"