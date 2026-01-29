#Requires -Modules ActiveDirectory

# --- 1. SETUP LOGGING ---
$LogDir = "$env:TEMP\ADRenameLogs"
if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$LogFile = "$LogDir\Log_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"

Start-Transcript -Path $LogFile -Append | Out-Null

Function Rename-ADUserSmart {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Identity
    )

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "             AD IDENTITY UPDATE WIZARD                  " -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan

    # --- SECTION: SEARCH ---
    Try {
        $User = Get-ADUser -Filter "UserPrincipalName -eq '$Identity' -or SamAccountName -eq '$Identity'" `
                           -Properties proxyAddresses, DisplayName, EmailAddress, UserPrincipalName, ProtectedFromAccidentalDeletion, GivenName, Surname `
                           -ErrorAction Stop
    }
    Catch {
        Write-Warning "Error contacting Active Directory: $($_.Exception.Message)"
        return
    }

    if (-not $User) {
        Write-Host "Status: NOT FOUND" -ForegroundColor Red
        return
    }
    
    Write-Host "Status: FOUND" -ForegroundColor Green
    Write-Host "Current Name: $($User.DisplayName)"
    Write-Host "Current UPN:  $($User.UserPrincipalName)"

    # --- SECTION: INPUT & VALIDATION ---
    $DomainSuffix = if ($User.UserPrincipalName -match "@") { ($User.UserPrincipalName -split "@")[1] } else { Read-Host "Enter Domain (e.g. corp.com)" }

    $NewNamePrefix = Read-Host "New Username (prefix only)" 
    if ($NewNamePrefix -match "@" -or [string]::IsNullOrWhiteSpace($NewNamePrefix)) {
        Write-Warning "Invalid Input: Prefix cannot be empty or contain '@'."
        return
    }

    $NewFirstName = Read-Host "New First Name (Leave blank to keep current)"
    $NewLastName  = Read-Host "New Last Name (Leave blank to keep current)"
    
    # Defaults
    if ([string]::IsNullOrWhiteSpace($NewFirstName)) { $NewFirstName = $User.GivenName }
    if ([string]::IsNullOrWhiteSpace($NewLastName)) { $NewLastName = $User.Surname }

    $NewUPN = "$NewNamePrefix@$DomainSuffix"
    $NewDisplayName = "$NewFirstName $NewLastName"
    $NewSamAccount = $NewNamePrefix 

    # Forest-wide uniqueness check
    $Conflict = Get-ADUser -Filter "SamAccountName -eq '$NewSamAccount' -or UserPrincipalName -eq '$NewUPN'" -ErrorAction SilentlyContinue
    if ($Conflict) {
        Write-Warning "CONFLICT: The proposed username or UPN already exists for user: $($Conflict.Name)"
        return
    }

    Write-Host "`n[ PROPOSED CHANGES ]" -ForegroundColor Magenta
    Write-Host "--------------------------------------------------------"
    Write-Host "Display Name:  $($User.DisplayName) -> $NewDisplayName"
    Write-Host "SamAccount:    $($User.SamAccountName) -> $NewSamAccount"
    Write-Host "UserPrincipal: $($User.UserPrincipalName) -> $NewUPN"
    Write-Host "--------------------------------------------------------"
    
    if ((Read-Host "Type 'Y' to apply these changes") -ne 'Y') { 
        Write-Host "Aborted." -ForegroundColor Yellow
        return 
    }

    # --- SECTION: PROXY CALCULATION ---
    # HashSet ensures zero duplicates and handles case-insensitivity automatically
    $EmailSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    
    # 1. Capture all existing addresses and normalize
    foreach ($addr in $User.proxyAddresses) {
        $EmailSet.Add(($addr -replace '^(SMTP|smtp):', '')) | Out-Null
    }
    
    # 2. Add the old "mail" attribute if it wasn't in proxyAddresses for some reason
    if ($User.EmailAddress) { $EmailSet.Add($User.EmailAddress) | Out-Null }
    
    # 3. Ensure the new primary UPN is not in the alias set (we add it as uppercase SMTP later)
    $EmailSet.Remove($NewUPN) | Out-Null
    
    # 4. Build the final list
    $FinalProxies = [System.Collections.Generic.List[string]]::new()
    $FinalProxies.Add("SMTP:$NewUPN") # The new primary
    foreach ($email in $EmailSet) {
        $FinalProxies.Add("smtp:$email") # All others demoted to aliases
    }

    # --- SECTION: EXECUTION ---
    Try {
        # Check and temporarily disable Accidental Deletion Protection
        $WasProtected = $User.ProtectedFromAccidentalDeletion
        if ($WasProtected) {
            Write-Host "Unlocking object for structural changes..."
            Set-ADObject -Identity $User.DistinguishedName -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
        }

        $UserChanges = @{
            GivenName = $NewFirstName
            Surname = $NewLastName
            DisplayName = $NewDisplayName
            SamAccountName = $NewSamAccount
            UserPrincipalName = $NewUPN
            EmailAddress = $NewUPN
        }
        
        Write-Host "Updating attributes..." -NoNewline
        Set-ADUser -Identity $User @UserChanges -Replace @{proxyAddresses = $FinalProxies.ToArray()} -ErrorAction Stop
        Write-Host "[ OK ]" -ForegroundColor Green

        Write-Host "Renaming AD Object..." -NoNewline
        Rename-ADObject -Identity $User -NewName $NewDisplayName -ErrorAction Stop
        Write-Host "[ OK ]" -ForegroundColor Green

        # Restore Protection if it was there
        if ($WasProtected) {
            Write-Host "Restoring protection flag..."
            # Query by new SamAccount because the DN changed after rename
            $NewObj = Get-ADUser -Identity $NewSamAccount
            Set-ADObject -Identity $NewObj.DistinguishedName -ProtectedFromAccidentalDeletion $true -ErrorAction Stop
        }
        
        Write-Host "`n Changes finalized successfully." -ForegroundColor Cyan
    }
    Catch {
        Write-Host "[ FAIL ]" -ForegroundColor Red
        Write-Error "Error: $($_.Exception.Message)"
    }
}

# --- MAIN EXECUTION ---
Try {
    $InputUser = Read-Host "`nENTER USERNAME OR EMAIL TO START"
    if (![string]::IsNullOrWhiteSpace($InputUser)) {
        Rename-ADUserSmart -Identity $InputUser
    }
}
Finally {
    Stop-Transcript | Out-Null
    Write-Host "`nLOG FILE: $LogFile" -ForegroundColor Yellow
}