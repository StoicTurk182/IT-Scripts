#Requires -Modules ActiveDirectory

Function Rename-ADUserSmart {
    param (
        [Parameter(Mandatory=$true, HelpMessage="Enter either the Short Login ID (SamAccountName) OR the Full Email (UPN)")]
        [string]$Identity
    )

    Write-Host "Searching for '$Identity'..." -NoNewline

    # 1. SMART SEARCH
    Try {
        $User = Get-ADUser -Filter "UserPrincipalName -eq '$Identity' -or SamAccountName -eq '$Identity'" -Properties proxyAddresses, DisplayName, EmailAddress, UserPrincipalName -ErrorAction Stop
    }
    Catch {
        Write-Warning "`nError contacting Active Directory. Check your connection."
        Return
    }

    if (-not $User) {
        Write-Host " FAILED." -ForegroundColor Red
        Write-Warning "User '$Identity' was not found."
        Return
    }
    
    Write-Host " FOUND!" -ForegroundColor Green
    Write-Host "   Name:  $($User.Name)"
    
    # 2. Auto-Detect Domain
    if ($User.UserPrincipalName -match "@") {
        $DomainSuffix = ($User.UserPrincipalName -split "@")[1]
    }
    else {
        $DomainSuffix = Read-Host "Could not detect domain. Please type it (e.g. orionad.lab)"
    }

    # 3. Gather New Details
    Write-Host "`n--- Enter New Identity Details ---" -ForegroundColor Yellow
    
    $NewNamePrefix = Read-Host "New Username (e.g. bob.jones)" 
    
    if ($NewNamePrefix -match "@") {
        Write-Warning "Stop! Only enter the username part, not the '@' symbol."
        return
    }

    $NewFirstName = Read-Host "New First Name"
    $NewLastName  = Read-Host "New Last Name"
    
    $NewUPN = "$NewNamePrefix@$DomainSuffix"
    $NewDisplayName = "$NewFirstName $NewLastName"
    $NewSamAccount = $NewNamePrefix 

    Write-Host "--------------------------------"
    Write-Host "PROPOSED CHANGES:"
    Write-Host "   Name:  $NewDisplayName"
    Write-Host "   UPN:   $NewUPN" 
    Write-Host "--------------------------------"
    
    $Confirm = Read-Host "Type 'Y' to proceed"
    if ($Confirm -ne 'Y') { Write-Warning "Cancelled."; return }

    # 4. Handle Proxy Addresses (THE FIX IS HERE)
    $CurrentProxy = $User.proxyAddresses
    $OldPrimary = $CurrentProxy | Where-Object { $_ -cmatch '^SMTP:' } | Select-Object -First 1
    
    # Explicitly define these as String Arrays [string[]] so they aren't PSObjects
    [string[]]$ProxyRemove = @()
    [string[]]$ProxyAdd    = @()
    
    if ($OldPrimary) {
        $OldEmail = $OldPrimary -replace "^SMTP:", ""
        
        # Force raw string
        $ProxyRemove += "$OldPrimary"
        
        # Add new as Primary, Old as Alias
        $ProxyAdd += "SMTP:$NewUPN"
        $ProxyAdd += "smtp:$OldEmail"
    }
    else {
        $ProxyAdd += "SMTP:$NewUPN"
    }

    # 5. Execute Changes
    Try {
        Write-Host "Updating Identity attributes..." -NoNewline
        
        # We create a hashtable for the changes to keep the command clean
        $UserChanges = @{
            GivenName = $NewFirstName
            Surname = $NewLastName
            DisplayName = $NewDisplayName
            SamAccountName = $NewSamAccount
            UserPrincipalName = $NewUPN
        }

        # Handle Proxy Addresses logic for the -Add/-Remove parameters
        # If arrays are empty, we shouldn't pass them, so we do specific logic here
        
        if ($ProxyRemove.Count -gt 0) {
            Set-ADUser -Identity $User @UserChanges -Remove @{proxyAddresses = $ProxyRemove} -Add @{proxyAddresses = $ProxyAdd} -ErrorAction Stop
        }
        else {
            Set-ADUser -Identity $User @UserChanges -Add @{proxyAddresses = $ProxyAdd} -ErrorAction Stop
        }
        
        Write-Host " Done." -ForegroundColor Green
    }
    Catch {
        Write-Error "`nFailed to update attributes: $($_.Exception.Message)"
        Return
    }

    # 6. Rename the Object (CN)
    Try {
        Write-Host "Renaming AD Object..." -NoNewline
        Rename-ADObject -Identity $User -NewName $NewDisplayName -ErrorAction Stop
        Write-Host " Done." -ForegroundColor Green
    }
    Catch {
        Write-Warning "`nAttributes updated, but failed to rename the object CN."
        Write-Error $_.Exception.Message
    }
    
    Write-Host "`nCOMPLETE." -ForegroundColor Cyan
}

# Run it
$InputUser = Read-Host "Enter the Username or Email"
Rename-ADUserSmart -Identity $InputUser