#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Renames an AD User, updates UPN/Mail, and demotes old Primary SMTP to an Alias.
    
.EXAMPLE
    .\Rename-ADUserSmart_v3.ps1 -Identity "j.doe" -NewPrefix "john.smith" -FirstName "John" -LastName "Smith"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)][string]$Identity,
    [Parameter(Mandatory=$false)][string]$NewPrefix,
    [Parameter(Mandatory=$false)][string]$FirstName,
    [Parameter(Mandatory=$false)][string]$LastName
)

# --- 1. SETUP LOGGING ---
$LogDir = "$env:TEMP\ADRenameLogs"
if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$LogFile = "$LogDir\Log_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"

Start-Transcript -Path $LogFile -Append | Out-Null

Function Rename-ADUserSmart {
    param ($Id, $Prefix, $FName, $LName)

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "             AD IDENTITY UPDATE WIZARD                  " -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan

    # --- SEARCH ---
    if ([string]::IsNullOrWhiteSpace($Id)) {
        $Id = Read-Host "ENTER USERNAME OR EMAIL TO START"
    }

    Try {
        $User = Get-ADUser -Filter "UserPrincipalName -eq '$Id' -or SamAccountName -eq '$Id'" `
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

    # --- INPUTS (Handles Pasting Issues) ---
    $DomainSuffix = if ($User.UserPrincipalName -match "@") { ($User.UserPrincipalName -split "@")[1] } else { Read-Host "Enter Domain (e.g. corp.com)" }

    if ([string]::IsNullOrWhiteSpace($Prefix)) {
        Write-Host "`n[TIP: Right-click to paste in most PowerShell windows]" -ForegroundColor Gray
        $Prefix = Read-Host "New Username (prefix only)" 
    }
    
    if ($Prefix -match "@") {
        Write-Warning "Invalid Input: Prefix cannot contain '@'."
        return
    }

    $NewFirstName = if ([string]::IsNullOrWhiteSpace($FName)) { Read-Host "New First Name (Enter to keep current)" } else { $FName }
    $NewLastName  = if ([string]::IsNullOrWhiteSpace($LName)) { Read-Host "New Last Name (Enter to keep current)"  } else { $LName }
    
    # Apply Defaults
    $NewFirstName = if ([string]::IsNullOrWhiteSpace($NewFirstName)) { $User.GivenName } else { $NewFirstName }
    $NewLastName  = if ([string]::IsNullOrWhiteSpace($NewLastName)) { $User.Surname } else { $NewLastName }

    $NewUPN = "$Prefix@$DomainSuffix"
    $NewDisplayName = "$NewFirstName $NewLastName"
    $NewSamAccount = $Prefix 

    # Forest-wide uniqueness check
    $Conflict = Get-ADUser -Filter "SamAccountName -eq '$NewSamAccount' -or UserPrincipalName -eq '$NewUPN'" -ErrorAction SilentlyContinue
    if ($Conflict -and $Conflict.ObjectGUID -ne $User.ObjectGUID) {
        Write-Warning "CONFLICT: The proposed username or UPN already exists for user: $($Conflict.Name)"
        return
    }

    # --- PROXY CALCULATION ---
    $EmailSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($User.proxyAddresses) {
        foreach ($addr in $User.proxyAddresses) {
            $EmailSet.Add(($addr -replace '^(SMTP|smtp):', '')) | Out-Null
        }
    }
    if ($User.EmailAddress) { $EmailSet.Add($User.EmailAddress) | Out-Null }
    
    $EmailSet.Remove($NewUPN) | Out-Null # Ensure new UPN isn't in alias list
    
    $FinalProxies = [System.Collections.Generic.List[string]]::new()
    $FinalProxies.Add("SMTP:$NewUPN") 
    foreach ($email in $EmailSet) { $FinalProxies.Add("smtp:$email") }

    # --- CONFIRMATION ---
    Write-Host "`n[ PROPOSED CHANGES ]" -ForegroundColor Magenta
    Write-Host "--------------------------------------------------------"
    Write-Host "Display Name:  $($User.DisplayName) -> $NewDisplayName"
    Write-Host "SamAccount:    $($User.SamAccountName) -> $NewSamAccount"
    Write-Host "UserPrincipal: $($User.UserPrincipalName) -> $NewUPN"
    Write-Host "Primary SMTP:  $NewUPN"
    Write-Host "Aliases:       $($EmailSet.Count) addresses preserved."
    Write-Host "--------------------------------------------------------"
    
    if ((Read-Host "Type 'Y' to apply") -ne 'Y') { return }

    # --- EXECUTION ---
    Try {
        $WasProtected = $User.ProtectedFromAccidentalDeletion
        if ($WasProtected) {
            Write-Host "Unlocking object..."
            Set-ADObject -Identity $User.DistinguishedName -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
        }

        $UserChanges = @{
            GivenName = $NewFirstName; Surname = $NewLastName; DisplayName = $NewDisplayName;
            SamAccountName = $NewSamAccount; UserPrincipalName = $NewUPN; EmailAddress = $NewUPN
        }
        
        Write-Host "Updating attributes..." -NoNewline
        Set-ADUser -Identity $User @UserChanges -Replace @{proxyAddresses = $FinalProxies.ToArray()} -ErrorAction Stop
        Write-Host "[ OK ]" -ForegroundColor Green

        Write-Host "Renaming AD Object..." -NoNewline
        Rename-ADObject -Identity $User -NewName $NewDisplayName -ErrorAction Stop
        Write-Host "[ OK ]" -ForegroundColor Green

        if ($WasProtected) {
            Write-Host "Relocking object..."
            $NewObj = Get-ADUser -Identity $NewSamAccount
            Set-ADObject -Identity $NewObj.DistinguishedName -ProtectedFromAccidentalDeletion $true -ErrorAction Stop
        }
        Write-Host "`n Success." -ForegroundColor Cyan
    }
    Catch {
        Write-Error "Error: $($_.Exception.Message)"
    }
}

# --- MAIN ---
Try {
    Rename-ADUserSmart -Id $Identity -Prefix $NewPrefix -FName $FirstName -LName $LastName
}
Finally {
    Stop-Transcript | Out-Null
    Write-Host "`nOpening Log: $LogFile" -ForegroundColor Yellow
    # AUTO-OPEN THE LOG FILE DIRECTLY
    Start-Process notepad.exe -ArgumentList $LogFile
}