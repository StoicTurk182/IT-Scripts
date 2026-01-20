#Requires -Modules ActiveDirectory

# --- 1. SETUP LOGGING (Universal) ---
$LogDir = "$env:TEMP\ADRenameLogs"
if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$LogFile = "$LogDir\Log_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"

# Start Transcript (Captures the aesthetic output perfectly)
Start-Transcript -Path $LogFile -Append | Out-Null

Function Rename-ADUserSmart {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Identity
    )

    # --- HEADER ---
    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "            AD IDENTITY UPDATE WIZARD                   " -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan

    # --- SECTION: SEARCH ---
    Write-Host "`n[ SEARCH ]" -ForegroundColor Magenta
    Write-Host "   Target Identity    : " -NoNewline
    Write-Host "$Identity" -ForegroundColor White

    Try {
        $User = Get-ADUser -Filter "UserPrincipalName -eq '$Identity' -or SamAccountName -eq '$Identity'" -Properties proxyAddresses, DisplayName, EmailAddress, UserPrincipalName, Title, Department -ErrorAction Stop
    }
    Catch {
        Write-Warning "`n   [!] Error contacting Active Directory."
        Return
    }

    if (-not $User) {
        Write-Host "   Status             : " -NoNewline
        Write-Host "NOT FOUND" -ForegroundColor Red
        Write-Warning "   The user '$Identity' could not be located."
        Return
    }
    
    Write-Host "   Status             : " -NoNewline
    Write-Host "FOUND" -ForegroundColor Green
    Write-Host "   Current Name       : $($User.Name)"
    Write-Host "   Current UPN        : $($User.UserPrincipalName)"

    # --- SECTION: INPUT ---
    Write-Host "`n[ INPUT DETAILS ]" -ForegroundColor Magenta
    
    # Auto-Detect Domain
    if ($User.UserPrincipalName -match "@") {
        $DomainSuffix = ($User.UserPrincipalName -split "@")[1]
    }
    else {
        Write-Host "   [!] Domain not detected." -ForegroundColor Yellow
        $DomainSuffix = Read-Host "   > Enter Domain (e.g. corp.com)"
    }

    # Better input handling with spacing
    $NewNamePrefix = Read-Host "   > New Username (e.g. j.doe)   " 
    if ($NewNamePrefix -match "@") {
        Write-Warning "   [!] Invalid Input: Do not include the '@' symbol."
        return
    }

    $NewFirstName = Read-Host "   > New First Name              "
    $NewLastName  = Read-Host "   > New Last Name               "
    
    $NewUPN = "$NewNamePrefix@$DomainSuffix"
    $NewDisplayName = "$NewFirstName $NewLastName"
    $NewSamAccount = $NewNamePrefix 

    # --- SECTION: CONFIRMATION ---
    Write-Host "`n[ PROPOSED CHANGES ]" -ForegroundColor Magenta
    Write-Host "--------------------------------------------------------" -ForegroundColor Gray
    Write-Host "   ATTRIBUTE        CURRENT VALUE           NEW VALUE" -ForegroundColor Gray
    Write-Host "   ---------        -------------           ---------" -ForegroundColor Gray
    Write-Host "   Display Name     $($User.DisplayName)    $NewDisplayName"
    Write-Host "   SamAccount       $($User.SamAccountName) $NewSamAccount"
    Write-Host "   UserPrincipal    $($User.UserPrincipalName) $NewUPN"
    Write-Host "   Email (Gen Tab)  $($User.EmailAddress)   $NewUPN"
    Write-Host "--------------------------------------------------------" -ForegroundColor Gray
    
    Write-Host ""
    $Confirm = Read-Host "   >>> Type 'Y' to APPLY these changes"
    if ($Confirm -ne 'Y') { 
        Write-Host "`n   [ ABORTED ] Operation cancelled by user." -ForegroundColor Yellow
        return 
    }

    # --- SECTION: EXECUTION ---
    Write-Host "`n[ EXECUTION ]" -ForegroundColor Magenta

    # 1. Proxy Address Logic
    $CurrentProxy = $User.proxyAddresses
    $OldPrimary = $CurrentProxy | Where-Object { $_ -cmatch '^SMTP:' } | Select-Object -First 1
    
    [string[]]$ProxyRemove = @()
    [string[]]$ProxyAdd    = @()
    
    if ($OldPrimary) {
        $OldEmail = $OldPrimary -replace "^SMTP:", ""
        $ProxyRemove += "$OldPrimary"
        $ProxyAdd += "SMTP:$NewUPN"
        $ProxyAdd += "smtp:$OldEmail"
    }
    else {
        $ProxyAdd += "SMTP:$NewUPN"
    }

    # 2. Update Attributes
    Try {
        Write-Host "   Updating Attributes ... " -NoNewline
        
        $UserChanges = @{
            GivenName = $NewFirstName
            Surname = $NewLastName
            DisplayName = $NewDisplayName
            SamAccountName = $NewSamAccount
            UserPrincipalName = $NewUPN
            EmailAddress = $NewUPN
        }

        if ($ProxyRemove.Count -gt 0) {
            Set-ADUser -Identity $User @UserChanges -Remove @{proxyAddresses = $ProxyRemove} -Add @{proxyAddresses = $ProxyAdd} -ErrorAction Stop
        }
        else {
            Set-ADUser -Identity $User @UserChanges -Add @{proxyAddresses = $ProxyAdd} -ErrorAction Stop
        }
        
        Write-Host "[ OK ]" -ForegroundColor Green
    }
    Catch {
        Write-Host "[ FAIL ]" -ForegroundColor Red
        Write-Error "   Error: $($_.Exception.Message)"
        Return
    }

    # 3. Rename Object
    Try {
        Write-Host "   Renaming AD Object  ... " -NoNewline
        Rename-ADObject -Identity $User -NewName $NewDisplayName -ErrorAction Stop
        Write-Host "[ OK ]" -ForegroundColor Green
    }
    Catch {
        Write-Host "[ WARN ]" -ForegroundColor Yellow
        Write-Warning "   Attributes updated, but object rename failed: $($_.Exception.Message)"
    }
    
    Write-Host "`n   [ COMPLETE ] All operations finished." -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan
}

# --- MAIN EXECUTION ---
Try {
    # Clear visual noise if possible (Optional)
    # Clear-Host 

    Write-Host "`n"
    $InputUser = Read-Host "ENTER USERNAME OR EMAIL TO START"
    Rename-ADUserSmart -Identity $InputUser
}
Finally {
    Stop-Transcript | Out-Null
    
    Write-Host "`n--------------------------------------------------" -ForegroundColor Gray
    Write-Host " LOG FILE: $LogFile" -ForegroundColor Yellow
    Write-Host " Opening log folder..." -ForegroundColor Gray
    Write-Host "--------------------------------------------------" -ForegroundColor Gray
    
    # Open folder
    Invoke-Item $LogDir
}