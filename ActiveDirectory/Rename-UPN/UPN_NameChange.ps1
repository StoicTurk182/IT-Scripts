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
    # Retrieve core naming, messaging, and security attributes [6]
    Try {
        $User = Get-ADUser -Filter "UserPrincipalName -eq '$Identity' -or SamAccountName -eq '$Identity'" `
                           -Properties proxyAddresses, DisplayName, EmailAddress, UserPrincipalName, ProtectedFromAccidentalDeletion `
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
    Write-Host "Current Name: $($User.Name)"
    Write-Host "Current UPN:  $($User.UserPrincipalName)"

    # --- SECTION: INPUT & VALIDATION ---
    if ($User.UserPrincipalName -match "@") {
        $DomainSuffix = ($User.UserPrincipalName -split "@")[1]
    }
    else {
        $DomainSuffix = Read-Host "Enter Domain (e.g. corp.com)"
    }

    $NewNamePrefix = Read-Host "New Username (prefix only)" 
    if ($NewNamePrefix -match "@") {
        Write-Warning "Invalid Input: Do not include the '@' symbol."
        return
    }

    $NewFirstName = Read-Host "New First Name"
    $NewLastName  = Read-Host "New Last Name"
    
    $NewUPN = "$NewNamePrefix@$DomainSuffix"
    $NewDisplayName = "$NewFirstName $NewLastName"
    $NewSamAccount = $NewNamePrefix 

    # Forest-wide uniqueness check to prevent downstream sync failures [7, 3]
    $Conflict = Get-ADUser -Filter "SamAccountName -eq '$NewSamAccount' -or UserPrincipalName -eq '$NewUPN'"
    if ($Conflict) {
        Write-Warning "CONFLICT: The proposed username or UPN already exists in the directory."
        return
    }

    Write-Host "`n" -ForegroundColor Magenta
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
    # Using HashSet with OrdinalIgnoreCase to handle case-insensitive deduplication [2, 8]
    $EmailSet =]::new(::OrdinalIgnoreCase)
    
    # 1. Capture all existing addresses and normalize (remove SMTP: prefixes)
    foreach ($addr in $User.proxyAddresses) {
        $EmailSet.Add(($addr -replace '^(SMTP|smtp):', '')) | Out-Null
    }
    
    # 2. Ensure the new primary UPN is not in the alias set (it will be added as SMTP:)
    $EmailSet.Remove($NewUPN) | Out-Null
    
    # 3. Build the final array using -Replace best practices [2, 3]
    $FinalProxies =]::new()
    $FinalProxies.Add("SMTP:$NewUPN") # The new primary address
    foreach ($email in $EmailSet) {
        $FinalProxies.Add("smtp:$email") # All former addresses (including old primary) demoted to aliases
    }

    # --- SECTION: EXECUTION ---
    Try {
        # Check and temporarily disable Accidental Deletion Protection if set [4, 5]
        $WasProtected = $User.ProtectedFromAccidentalDeletion
        if ($WasProtected) {
            Write-Host "Unlocking object for structural changes..."
            Set-ADObject -Identity $User.DistinguishedName -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
        }

        # Update Naming and Messaging Attributes in a single transaction [2, 3]
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

        # Structural Rename of the AD Object [9]
        Write-Host "Renaming AD Object..." -NoNewline
        Rename-ADObject -Identity $User -NewName $NewDisplayName -ErrorAction Stop
        Write-Host "[ OK ]" -ForegroundColor Green

        # Restore Accidental Deletion Protection [10]
        if ($WasProtected) {
            Write-Host "Restoring protection flag..."
            # Note: We query by the new SamAccountName as the DistinguishedName has changed
            Set-ADObject -Identity (Get-ADUser -Identity $NewSamAccount).DistinguishedName `
                         -ProtectedFromAccidentalDeletion $true -ErrorAction Stop
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
    $InputUser = Read-Host "ENTER USERNAME OR EMAIL"
    Rename-ADUserSmart -Identity $InputUser
}
Finally {
    Stop-Transcript | Out-Null
    Write-Host "`nLOG FILE: $LogFile" -ForegroundColor Yellow
    Invoke-Item $LogDir
}