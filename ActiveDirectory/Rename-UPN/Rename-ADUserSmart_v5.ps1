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

    In hybrid environments, presents all available UPN suffixes from the AD forest
    so the operator can select the correct routable domain rather than inheriting
    the user's current suffix (which may be non-routable e.g. lab.local).

.PARAMETER Identity
    The SamAccountName or UserPrincipalName of the user to rename.

.PARAMETER NewPrefix
    The new username prefix (the part before the @ symbol). Maximum 20 characters.

.PARAMETER FirstName
    The new given name. If omitted, the existing value is preserved.

.PARAMETER LastName
    The new surname. If omitted, the existing value is preserved.

.EXAMPLE
    .\Rename-ADUserSmart_v5.ps1 -Identity "j.doe" -NewPrefix "john.smith" -FirstName "John" -LastName "Smith"

.EXAMPLE
    .\Rename-ADUserSmart_v5.ps1
    Runs interactively, prompting for all required values.

.NOTES
    Author:  Andrew Jones
    Version: 5.0
    Changes from v4:
      - Dynamic UPN suffix selection from Get-ADForest
      - All available suffixes presented as numbered list
      - Current suffix marked for reference
      - Operator can select by number, press Enter to keep current, or type manually
      - Sync warning domain reflects the suffix actually selected
    Changes from v3 (carried forward):
      - Get-ADUser uses script block filter to prevent injection on special characters
      - SamAccountName length validated before conflict check (AD 20-char limit)
      - SamAccountName character set validated against AD-prohibited characters
      - All user inputs trimmed of leading/trailing whitespace before use
      - OriginalDN captured before Set-ADUser; passed by string to Rename-ADObject
      - Entra Connect Sync warning added to confirmation block
      - Comment added on alias removal logic
      - Inner function param names aligned with outer script param names

.LINK
    https://github.com/StoicTurk182/IT-Scripts

.LINK
    https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adforest

.LINK
    https://learn.microsoft.com/en-us/powershell/module/activedirectory/set-aduser
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

    # Script block filter prevents unexpected behaviour if $Identity contains single quotes
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

    # FIX v5: Dynamic UPN suffix selection from AD forest.
    # In hybrid environments the user's current suffix may be non-routable (e.g. lab.local).
    # Presenting all available suffixes allows the operator to select the correct routable
    # domain for Exchange Online without having to know it in advance.
    # Get-ADForest returns the forest root domain + any additional UPN suffixes registered
    # via Active Directory Domains and Trusts.
    # Reference: https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adforest
    $CurrentSuffix = if ($User.UserPrincipalName -match "@") {
        ($User.UserPrincipalName -split "@")[1]
    } else { "" }

    Try {
        $Forest      = Get-ADForest -ErrorAction Stop
        $AllSuffixes = @($Forest.RootDomain) + @($Forest.UPNSuffixes) |
                       Where-Object { $_ } | Select-Object -Unique | Sort-Object
    }
    Catch {
        Write-Warning "Could not retrieve AD forest suffixes: $($_.Exception.Message)"
        $AllSuffixes = @($CurrentSuffix)
    }

    if ($AllSuffixes.Count -gt 1) {
        Write-Host "`nAvailable UPN suffixes:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $AllSuffixes.Count; $i++) {
            $marker = if ($AllSuffixes[$i] -ieq $CurrentSuffix) { "  <- current" } else { "" }
            Write-Host ("  [{0}] {1}{2}" -f ($i + 1), $AllSuffixes[$i], $marker)
        }
        $pick = (Read-Host "`nSelect suffix number [Enter to keep current: $CurrentSuffix]").Trim()
        $DomainSuffix = if ([string]::IsNullOrWhiteSpace($pick)) {
            $CurrentSuffix
        } elseif ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $AllSuffixes.Count) {
            $AllSuffixes[[int]$pick - 1]
        } else {
            # Allow manual entry as fallback (e.g. if suffix not yet registered in forest)
            Write-Host "  Using manually entered suffix: $pick" -ForegroundColor Gray
            $pick
        }
    } else {
        # Only one suffix available — use it without prompting
        $DomainSuffix = $CurrentSuffix
        Write-Host "Domain suffix: $DomainSuffix" -ForegroundColor Gray
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

    # Trim all inputs before use
    $NewPrefix    = $NewPrefix.Trim()
    $NewFirstName = $NewFirstName.Trim()
    $NewLastName  = $NewLastName.Trim()

    # Apply defaults for empty name fields
    $NewFirstName = if ([string]::IsNullOrWhiteSpace($NewFirstName)) { $User.GivenName  } else { $NewFirstName }
    $NewLastName  = if ([string]::IsNullOrWhiteSpace($NewLastName))  { $User.Surname    } else { $NewLastName  }

    # --- INPUT VALIDATION ---

    if ($NewPrefix -match "@") {
        Write-Warning "Invalid Input: Prefix cannot contain '@'. Enter only the part before the @ symbol."
        return
    }

    if ($NewPrefix.Length -gt 20) {
        Write-Warning "Prefix '$NewPrefix' is $($NewPrefix.Length) characters. SamAccountName maximum is 20."
        return
    }

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

    # Remove the new primary UPN from the alias set before building proxyAddresses.
    # Prevents it appearing as both SMTP: (primary) and smtp: (alias) simultaneously.
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

    # Sync warning — domain reflects the suffix actually selected by the operator
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
        # Capture DN as string before any changes — avoids stale object reference
        # on Rename-ADObject after Set-ADUser modifies the object.
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
