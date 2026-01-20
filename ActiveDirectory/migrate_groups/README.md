# Copy Active Directory Group Membership Between Users

## Overview

This guide provides PowerShell methods for copying group memberships from one domain user (source/template) to another (target). This is commonly used during onboarding when a new starter requires the same permissions as an existing team member.

---

## Prerequisites

- Active Directory PowerShell module (RSAT)
- Sufficient permissions to read group membership and modify group members
- Both source and target users must exist in Active Directory

### Verify AD Module Availability

```powershell
Get-Module -ListAvailable -Name ActiveDirectory
```

If not installed, enable RSAT on Windows 10/11:

```powershell
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

---

## Method 1: One-Liner (Quick Use)

For immediate use when you need to copy groups without logging or validation:

```powershell
Get-ADPrincipalGroupMembership -Identity "SourceUser" | 
    Where-Object { $_.Name -ne "Domain Users" } | 
    ForEach-Object { Add-ADGroupMember -Identity $_.Name -Members "TargetUser" }
```

Replace `SourceUser` and `TargetUser` with the appropriate sAMAccountName values.

The `Where-Object` filter excludes "Domain Users" as all domain accounts are members by default and cannot be manually added.

---

## Method 2: Basic Script with Output

Provides visual feedback of which groups are being copied:

```powershell
# Define users
$SourceUser = "j.smith"
$TargetUser = "a.newman"

# Get source user's groups (excluding Domain Users)
$Groups = Get-ADPrincipalGroupMembership -Identity $SourceUser | 
    Where-Object { $_.Name -ne "Domain Users" }

Write-Host "Copying $($Groups.Count) groups from $SourceUser to $TargetUser" -ForegroundColor Cyan

foreach ($Group in $Groups) {
    try {
        Add-ADGroupMember -Identity $Group.Name -Members $TargetUser -ErrorAction Stop
        Write-Host "  Added to: $($Group.Name)" -ForegroundColor Green
    }
    catch {
        Write-Host "  Failed: $($Group.Name) - $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host "Complete." -ForegroundColor Cyan
```

---

## Method 3: Full Script with Logging and Validation

Production-ready script with pre-flight checks, logging, and summary report:

```powershell
<#
.SYNOPSIS
    Copies Active Directory group memberships from a source user to a target user.

.DESCRIPTION
    Retrieves all group memberships from a template/source user and adds the target 
    user to those same groups. Includes validation, error handling, and logging.

.PARAMETER SourceUser
    The sAMAccountName of the user whose groups will be copied.

.PARAMETER TargetUser
    The sAMAccountName of the user who will be added to the groups.

.PARAMETER LogPath
    Optional. Path for the log file. Defaults to current directory.

.PARAMETER WhatIf
    Shows what would happen without making changes.

.EXAMPLE
    .\Copy-ADGroupMembership.ps1 -SourceUser "j.smith" -TargetUser "a.newman"

.EXAMPLE
    .\Copy-ADGroupMembership.ps1 -SourceUser "j.smith" -TargetUser "a.newman" -WhatIf
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SourceUser,

    [Parameter(Mandatory = $true)]
    [string]$TargetUser,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\ADGroupCopy_$(Get-Date -Format 'yyyyMMdd_HHmmss').log",

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

# Initialise counters
$SuccessCount = 0
$FailCount = 0
$SkipCount = 0

# Logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $LogEntry
    
    switch ($Level) {
        "INFO"    { Write-Host $Message -ForegroundColor Cyan }
        "SUCCESS" { Write-Host $Message -ForegroundColor Green }
        "WARNING" { Write-Host $Message -ForegroundColor Yellow }
        "ERROR"   { Write-Host $Message -ForegroundColor Red }
    }
}

# Validate AD module
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Log "Active Directory module not found. Install RSAT." -Level "ERROR"
    exit 1
}

Import-Module ActiveDirectory -ErrorAction Stop

# Validate source user exists
try {
    $SourceADUser = Get-ADUser -Identity $SourceUser -ErrorAction Stop
    Write-Log "Source user validated: $($SourceADUser.Name) ($SourceUser)"
}
catch {
    Write-Log "Source user '$SourceUser' not found in Active Directory." -Level "ERROR"
    exit 1
}

# Validate target user exists
try {
    $TargetADUser = Get-ADUser -Identity $TargetUser -ErrorAction Stop
    Write-Log "Target user validated: $($TargetADUser.Name) ($TargetUser)"
}
catch {
    Write-Log "Target user '$TargetUser' not found in Active Directory." -Level "ERROR"
    exit 1
}

# Get source user's group memberships
Write-Log "Retrieving group memberships for $SourceUser..."

try {
    $SourceGroups = Get-ADPrincipalGroupMembership -Identity $SourceUser -ErrorAction Stop | 
        Where-Object { $_.Name -ne "Domain Users" }
}
catch {
    Write-Log "Failed to retrieve groups: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

Write-Log "Found $($SourceGroups.Count) groups to copy (excluding Domain Users)"

# Get target user's existing memberships for comparison
$TargetExistingGroups = Get-ADPrincipalGroupMembership -Identity $TargetUser | 
    Select-Object -ExpandProperty Name

# Process each group
foreach ($Group in $SourceGroups) {
    
    # Check if target is already a member
    if ($TargetExistingGroups -contains $Group.Name) {
        Write-Log "  SKIP: $($Group.Name) - Already a member" -Level "WARNING"
        $SkipCount++
        continue
    }

    if ($WhatIf) {
        Write-Log "  WHATIF: Would add to $($Group.Name)" -Level "INFO"
        $SuccessCount++
        continue
    }

    try {
        Add-ADGroupMember -Identity $Group.Name -Members $TargetUser -ErrorAction Stop
        Write-Log "  ADDED: $($Group.Name)" -Level "SUCCESS"
        $SuccessCount++
    }
    catch {
        Write-Log "  FAILED: $($Group.Name) - $($_.Exception.Message)" -Level "ERROR"
        $FailCount++
    }
}

# Summary
Write-Log "----------------------------------------"
Write-Log "SUMMARY"
Write-Log "  Source: $SourceUser"
Write-Log "  Target: $TargetUser"
Write-Log "  Groups processed: $($SourceGroups.Count)"
Write-Log "  Successfully added: $SuccessCount" -Level "SUCCESS"
Write-Log "  Already member (skipped): $SkipCount" -Level "WARNING"
Write-Log "  Failed: $FailCount" -Level $(if ($FailCount -gt 0) { "ERROR" } else { "INFO" })
Write-Log "  Log file: $LogPath"
Write-Log "----------------------------------------"
```

### Usage Examples

```powershell
# Standard execution
.\Copy-ADGroupMembership.ps1 -SourceUser "j.smith" -TargetUser "a.newman"

# Preview mode (no changes made)
.\Copy-ADGroupMembership.ps1 -SourceUser "j.smith" -TargetUser "a.newman" -WhatIf

# Custom log location
.\Copy-ADGroupMembership.ps1 -SourceUser "j.smith" -TargetUser "a.newman" -LogPath "C:\Logs\GroupCopy.log"
```

---

## Method 4: Interactive Function

For repeated use, add this function to your PowerShell profile:

```powershell
function Copy-ADUserGroups {
    param(
        [Parameter(Mandatory = $true)]
        [string]$From,

        [Parameter(Mandatory = $true)]
        [string]$To,

        [switch]$IncludePrimaryGroup
    )

    $Groups = Get-ADPrincipalGroupMembership -Identity $From | 
        Where-Object { $_.Name -ne "Domain Users" }

    $Added = 0
    $Skipped = 0

    foreach ($Group in $Groups) {
        try {
            Add-ADGroupMember -Identity $Group.Name -Members $To -ErrorAction Stop
            Write-Host "+" $Group.Name -ForegroundColor Green
            $Added++
        }
        catch [Microsoft.ActiveDirectory.Management.ADException] {
            if ($_.Exception.Message -like "*already a member*") {
                Write-Host "=" $Group.Name "(already member)" -ForegroundColor DarkGray
                $Skipped++
            }
            else {
                Write-Host "!" $Group.Name "-" $_.Exception.Message -ForegroundColor Red
            }
        }
    }

    Write-Host "`nAdded: $Added | Skipped: $Skipped | Total: $($Groups.Count)" -ForegroundColor Cyan
}
```

Usage:

```powershell
Copy-ADUserGroups -From "j.smith" -To "a.newman"
```

---

## Verification Commands

After copying groups, verify the target user's membership:

```powershell
# List all groups for target user
Get-ADPrincipalGroupMembership -Identity "a.newman" | 
    Select-Object Name, GroupCategory, GroupScope | 
    Sort-Object Name | 
    Format-Table -AutoSize

# Compare source and target memberships
$Source = Get-ADPrincipalGroupMembership -Identity "j.smith" | Select-Object -ExpandProperty Name
$Target = Get-ADPrincipalGroupMembership -Identity "a.newman" | Select-Object -ExpandProperty Name

Compare-Object -ReferenceObject $Source -DifferenceObject $Target -IncludeEqual | 
    Sort-Object InputObject | 
    Format-Table @{L='Group';E={$_.InputObject}}, @{L='Status';E={
        switch ($_.SideIndicator) {
            '==' { 'Both' }
            '<=' { 'Source Only' }
            '=>' { 'Target Only' }
        }
    }}
```

---

## Common Errors and Resolutions

| Error | Cause | Resolution |
|-------|-------|------------|
| Cannot find an object with identity | User sAMAccountName incorrect | Verify username with `Get-ADUser -Filter "Name -like '*smith*'"` |
| Insufficient access rights | Lacking permissions to modify group | Run as account with group management rights or request delegation |
| The specified account name is already a member | Target already in group | Safe to ignore; script Method 3 handles this automatically |
| The server is unwilling to process the request | Attempting to add to Domain Users or protected group | These groups cannot be manually modified |

---

## Security Considerations

- Review groups before copying; source user may have elevated access not appropriate for the target
- Consider using `-WhatIf` first to preview changes
- Log all changes for audit purposes
- Some organisations require approval workflows before granting group access

### Audit Existing Groups First

```powershell
# Display source user's groups with descriptions for review
Get-ADPrincipalGroupMembership -Identity "j.smith" | 
    Get-ADGroup -Properties Description | 
    Select-Object Name, Description, GroupCategory | 
    Sort-Object Name | 
    Format-Table -AutoSize -Wrap
```

---

## Cmdlet Reference

| Cmdlet | Purpose |
|--------|---------|
| `Get-ADPrincipalGroupMembership` | Returns all groups a user is a member of |
| `Add-ADGroupMember` | Adds members to an AD group |
| `Get-ADUser` | Retrieves user object from AD |
| `Get-ADGroup` | Retrieves group object and properties |

---

## Sources

- Microsoft Learn: Get-ADPrincipalGroupMembership - https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adprincipalgroupmembership
- Microsoft Learn: Add-ADGroupMember - https://learn.microsoft.com/en-us/powershell/module/activedirectory/add-adgroupmember
- Microsoft Learn: Get-ADUser - https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-aduser
- Microsoft Learn: Active Directory Module for Windows PowerShell - https://learn.microsoft.com/en-us/powershell/module/activedirectory

---

*Document Version: 1.0*
*Last Updated: January 2025*
