#Requires -Version 5.1
#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Renames an AD User, updates UPN/Mail, and demotes old Primary SMTP to an Alias.

.DESCRIPTION
    Performs a full identity rename on an Active Directory user object.
    Updates: DisplayName, SamAccountName, UserPrincipalName, EmailAddress, proxyAddresses.
    Preserves existing SMTP aliases. Handles ProtectedFromAccidentalDeletion automatically.
    Logs all actions to $env:TEMP\ADRenameLogs\ via Start-Transcript.

.PARAMETER Identity
    The SamAccountName or UserPrincipalName of the user to rename.

.PARAMETER NewPrefix
    The new username prefix (the part before the @ symbol). Maximum 20 characters.

.PARAMETER FirstName
    The new given name. If omitted, the existing value is preserved.

.PARAMETER LastName
    The new surname. If omitted, the existing value is preserved.

.EXAMPLE
    .\Rename-ADUserSmart_v4.ps1 -Identity "j.doe" -NewPrefix "john.smith" -FirstName "John" -LastName "Smith"

.EXAMPLE
    .\Rename-ADUserSmart_v4.ps1
    Runs interactively, prompting for all required values.

.NOTES
    Author:  Andrew Jones
    Version: 4.0
    Changes from v3:
      - Get-ADUser uses script block filter to prevent injection on special characters
      - SamAccountName length validated before conflict check (AD 20-char limit)
      - SamAccountName character set validated against AD-prohibited characters
      - All user inputs trimmed of leading/trailing whitespace before use
      - OriginalDN captured before Set-ADUser; passed by string to Rename-ADObject
      - Entra Connect Sync warning added to confirmation block
      - Comment added on alias removal logic to explain intentional Remove($NewUPN)
      - Inner function param names aligned with outer script param names
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)][string]$Identity,
    [Parameter(Mandatory=$false)][string]$NewPrefix,
    [Parameter(Mandatory=$false)][string]$FirstName,
    [Parameter(Mandatory=$false)][string]$LastName
)

# --- SETUP LOGGING ---
$LogDir = "$env:TEMP\ADRenameLogs"
if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$LogFile = "$LogDir\Log_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"
Start-Transcript -Path $LogFile -Append | Out-Null

# AD SamAccountName prohibited characters
# Reference: https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/naming-conventions-for-computer-domain-site-ou
$SamInvalidChars = '["/\\[\]:;|=,+*?<>@\s]'

Function Invoke-ADUserRename {
    param (
        [string]$Identity,
        [string]$NewPrefix,
        [string]$FirstName,
        [string]$LastName
    )

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "             AD IDENTITY UPDATE WIZARD                  " -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan

    # --- SEARCH ---
    if ([string]::IsNullOrWhiteSpace($Identity)) {
        $Identity = Read-Host "ENTER USERNAME OR EMAIL TO START"
    }
    $Identity = $Identity.Trim()

    # FIX: Script block filter prevents unexpected behaviour if $Identity contains single quotes
    # (e.g. Irish names: o'brien). String interpolation in AD filter breaks on apostrophes.
    # Reference: https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-aduser
    Try {
        $User = Get-ADUser -Filter { UserPrincipalName -eq $Identity -or SamAccountName -eq $Identity } `
                           -Properties proxyAddresses, DisplayName, EmailAddress, UserPrincipalName,
                                       ProtectedFromAccidentalDeletion, GivenName, Surname `
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

    # --- COLLECT INPUTS ---
    $DomainSuffix = if ($User.UserPrincipalName -match "@") {
        ($User.UserPrincipalName -split "@")[1]
    } else {
        Read-Host "Enter Domain (e.g. corp.com)"
    }

    if ([string]::IsNullOrWhiteSpace($NewPrefix)) {
        Write-Host "`n[TIP: Right-click to paste in most PowerShell windows]" -ForegroundColor Gray
        $NewPrefix = Read-Host "New Username (prefix only, no @ symbol)"
    }

    $NewFirstName = if ([string]::IsNullOrWhiteSpace($FirstName)) {
        Read-Host "New First Name (Enter to keep: $($User.GivenName))"
    } else { $FirstName }

    $NewLastName = if ([string]::IsNullOrWhiteSpace($LastName)) {
        Read-Host "New Last Name (Enter to keep: $($User.Surname))"
    } else { $LastName }

    # --- FIX: Trim all inputs before use ---
    $NewPrefix    = $NewPrefix.Trim()
    $NewFirstName = $NewFirstName.Trim()
    $NewLastName  = $NewLastName.Trim()

    # Apply defaults for empty name fields
    $NewFirstName = if ([string]::IsNullOrWhiteSpace($NewFirstName)) { $User.GivenName  } else { $NewFirstName }
    $NewLastName  = if ([string]::IsNullOrWhiteSpace($NewLastName))  { $User.Surname    } else { $NewLastName  }

    # --- INPUT VALIDATION ---

    # Guard: prefix must not contain @
    if ($NewPrefix -match "@") {
        Write-Warning "Invalid Input: Prefix cannot contain '@'. Enter only the part before the @ symbol."
        return
    }

    # FIX: SamAccountName length check — AD enforces a hard 20-character maximum.
    # Set-ADUser will throw a cryptic LDAP constraint violation without this guard.
    # Reference: https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/naming-conventions-for-computer-domain-site-ou
    if ($NewPrefix.Length -gt 20) {
        Write-Warning "Prefix '$NewPrefix' is $($NewPrefix.Length) characters. SamAccountName maximum is 20."
        return
    }

    # FIX: SamAccountName character validation.
    # AD rejects ", /, \, [, ], :, ;, |, =, ,, +, *, ?, <, >, @, and whitespace.
    if ($NewPrefix -match $SamInvalidChars) {
        Write-Warning "Prefix '$NewPrefix' contains characters not permitted in SamAccountName."
        Write-Warning "Prohibited: `" / \ [ ] : ; | = , + * ? < > @ and whitespace."
        return
    }

    $NewUPN         = "$NewPrefix@$DomainSuffix"
    $NewDisplayName = "$NewFirstName $NewLastName"
    $NewSamAccount  = $NewPrefix

    # --- CONFLICT CHECK ---
    $Conflict = Get-ADUser -Filter { SamAccountName -eq $NewSamAccount -or UserPrincipalName -eq $NewUPN } `
                           -ErrorAction SilentlyContinue
    if ($Conflict -and $Conflict.ObjectGUID -ne $User.ObjectGUID) {
        Write-Warning "CONFLICT: The proposed username or UPN already exists for user: $($Conflict.Name)"
        return
    }

    # --- PROXY ADDRESS CALCULATION ---
    $EmailSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if ($User.proxyAddresses) {
        foreach ($addr in $User.proxyAddresses) {
            $EmailSet.Add(($addr -replace '^(SMTP|smtp):', '')) | Out-Null
        }
    }
    if ($User.EmailAddress) { $EmailSet.Add($User.EmailAddress) | Out-Null }

    # FIX: Remove the new primary UPN from the alias set before building proxyAddresses.
    # This prevents the new primary being added twice (once as SMTP: and once as smtp:).
    # If the new UPN already existed as an alias it is promoted; if it did not exist it is
    # added fresh as the primary. Either way, the intent is correct.
    $EmailSet.Remove($NewUPN) | Out-Null

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
    Write-Host "Aliases:       $($EmailSet.Count) address(es) preserved as secondary SMTP."
    Write-Host "--------------------------------------------------------"

    # FIX: Entra Connect Sync warning.
    # proxyAddresses changes replicate to Exchange Online. If the new domain is not an accepted
    # domain in the M365 tenant, the sync will reject or silently drop the address update.
    Write-Host ""
    Write-Host "[SYNC NOTE] If Entra Connect Sync is active, proxyAddresses changes will replicate" `
               -ForegroundColor Yellow
    Write-Host "            to Exchange Online. Confirm '$DomainSuffix' is an accepted domain in" `
               -ForegroundColor Yellow
    Write-Host "            the M365 tenant before proceeding." -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------"

    if ((Read-Host "`nType 'Y' to apply") -ne 'Y') { return }

    # --- EXECUTION ---
    Try {
        # FIX: Capture the DN as a string before any changes.
        # Passing the original ADUser object to Rename-ADObject after Set-ADUser runs means
        # the in-memory object's DN is stale if the module ever updates it post-Set-ADUser.
        # Using the captured string is unambiguous regardless of module version behaviour.
        $OriginalDN = $User.DistinguishedName

        $WasProtected = $User.ProtectedFromAccidentalDeletion
        if ($WasProtected) {
            Write-Host "Unlocking object (ProtectedFromAccidentalDeletion)..." -NoNewline
            Set-ADObject -Identity $OriginalDN -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
            Write-Host " [ OK ]" -ForegroundColor Green
        }

        $UserChanges = @{
            GivenName         = $NewFirstName
            Surname           = $NewLastName
            DisplayName       = $NewDisplayName
            SamAccountName    = $NewSamAccount
            UserPrincipalName = $NewUPN
            EmailAddress      = $NewUPN
        }

        Write-Host "Updating attributes..." -NoNewline
        Set-ADUser -Identity $User @UserChanges `
                   -Replace @{ proxyAddresses = $FinalProxies.ToArray() } `
                   -ErrorAction Stop
        Write-Host " [ OK ]" -ForegroundColor Green

        # FIX: Pass DN by captured string, not the stale $User object reference.
        Write-Host "Renaming AD object (CN)..." -NoNewline
        Rename-ADObject -Identity $OriginalDN -NewName $NewDisplayName -ErrorAction Stop
        Write-Host " [ OK ]" -ForegroundColor Green

        if ($WasProtected) {
            Write-Host "Relocking object (ProtectedFromAccidentalDeletion)..." -NoNewline
            $UpdatedUser = Get-ADUser -Identity $NewSamAccount -ErrorAction Stop
            Set-ADObject -Identity $UpdatedUser.DistinguishedName `
                         -ProtectedFromAccidentalDeletion $true -ErrorAction Stop
            Write-Host " [ OK ]" -ForegroundColor Green
        }

        Write-Host "`n Rename complete." -ForegroundColor Cyan
        Write-Host " New UPN:        $NewUPN"
        Write-Host " New SAM:        $NewSamAccount"
        Write-Host " New Display:    $NewDisplayName"
    }
    Catch {
        Write-Error "Error during rename: $($_.Exception.Message)"
    }
}

# --- MAIN ---
Try {
    Invoke-ADUserRename -Identity $Identity -NewPrefix $NewPrefix -FirstName $FirstName -LastName $LastName
}
Finally {
    Stop-Transcript | Out-Null
    Write-Host "`nOpening log: $LogFile" -ForegroundColor Yellow
    Start-Process notepad.exe -ArgumentList $LogFile
}
