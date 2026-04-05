# Rename-ADUserSmart — Script Review and PowerShell Packaging Guide

Review of `Rename-ADUserSmart_v3.ps1` and a general reference for converting PowerShell scripts into reusable modules, cmdlets, and compiled executables.

---

## Script Review: Rename-ADUserSmart_v3.ps1

### Summary

The script performs a full AD identity rename: it updates `DisplayName`, `SamAccountName`, `UserPrincipalName`, `EmailAddress`, and `proxyAddresses`, preserving existing SMTP aliases and handling `ProtectedFromAccidentalDeletion` automatically. Logging is handled via `Start-Transcript`.

---

### Strengths

- Transcript logging to `$env:TEMP\ADRenameLogs\` with timestamped filenames is a sound production practice. The log opens automatically on completion.
- The `HashSet` with `OrdinalIgnoreCase` comparison for proxy address deduplication correctly prevents case-sensitive duplicate aliases.
- Forest-wide conflict check using both `SamAccountName` and `UPN` with GUID exclusion avoids false positives when checking the user against itself.
- `ProtectedFromAccidentalDeletion` is toggled off, changes are applied, then toggled back on — this is the correct sequence and avoids a common failure point.
- The `-Replace` parameter on `Set-ADUser` for `proxyAddresses` is correct; using `-Add` would only append rather than replace the full set.
- Interactive fallback for every mandatory value means the script is usable both parameterised and ad-hoc.

---

### Issues and Recommended Fixes

#### 1. SamAccountName Length Not Validated

AD enforces a 20-character maximum for `SamAccountName`. Prefixes longer than 20 characters will cause `Set-ADUser` to throw a non-obvious error.

**Current behaviour:** Runtime error from `Set-ADUser` with a cryptic LDAP message.

**Recommended fix:**

```powershell
if ($Prefix.Length -gt 20) {
    Write-Warning "SamAccountName '$Prefix' exceeds 20 characters (length: $($Prefix.Length)). AD will reject this."
    return
}
```

Add this immediately after `$NewSamAccount = $Prefix`.

Reference: [Microsoft — Active Directory naming conventions](https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/naming-conventions-for-computer-domain-site-ou)

---

#### 2. No Character Validation on Prefix

AD does not permit certain characters in `SamAccountName`: `" / \ [ ] : ; | = , + * ? < > @`. A prefix containing any of these will fail silently until `Set-ADUser` is called.

**Recommended fix:**

```powershell
if ($Prefix -match '["/\\[\]:;|=,+*?<>@]') {
    Write-Warning "Prefix '$Prefix' contains characters not permitted in SamAccountName."
    return
}
```

---

#### 3. Rename-ADObject Uses Stale Object Reference

`Rename-ADObject -Identity $User` passes the original `ADUser` object captured before `Set-ADUser` ran. The object's `DistinguishedName` is still valid at this point (the DN changes only when the CN changes, which `Rename-ADObject` performs), so this currently works. However, if `Set-ADUser` modifies the DN in a future PowerShell AD module version, this will break silently.

**Recommended fix:** Capture the DN explicitly before making changes, and pass it by string:

```powershell
$OriginalDN = $User.DistinguishedName
# ... Set-ADUser ...
Rename-ADObject -Identity $OriginalDN -NewName $NewDisplayName -ErrorAction Stop
```

---

#### 4. No Whitespace Trimming on Inputs

If a user pastes a value with a trailing space (common when copying from an email), `$Prefix` or the name fields will carry that space into AD attributes.

**Recommended fix:**

```powershell
$Prefix      = $Prefix.Trim()
$NewFirstName = $NewFirstName.Trim()
$NewLastName  = $NewLastName.Trim()
```

Apply after all inputs are collected, before the conflict check.

---

#### 5. `Get-ADUser` Filter Uses String Interpolation — Injection Risk

The filter `"UserPrincipalName -eq '$Id'"` is safe in a controlled tool but will behave unexpectedly if `$Id` contains single quotes (e.g., an apostrophe in a username, rare but valid in some environments).

**Recommended fix for lookup:**

```powershell
$User = Get-ADUser -Filter { UserPrincipalName -eq $Id -or SamAccountName -eq $Id } `
                   -Properties ...
```

Script block filters handle variable escaping automatically and are the documented best practice.

Reference: [Get-ADUser — Microsoft Docs](https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-aduser)

---

#### 6. Alias Removal Logic Has a Gap

```powershell
$EmailSet.Remove($NewUPN) | Out-Null
```

This removes the new primary SMTP from the alias set before promoting it, which is correct. However, if the user's current primary SMTP matches the new UPN exactly (i.e., no change), the existing `SMTP:` entry is removed from `proxyAddresses` and re-added as the new primary — which is correct behaviour but worth noting in a comment for maintainability.

---

#### 7. No Exchange / M365 Sync Warning

When `proxyAddresses` is modified directly in on-premises AD and Entra Connect Sync is running, the change will sync to Exchange Online. If the new primary SMTP address does not match an accepted domain in M365, the sync will fail or the address change will be silently dropped.

This is an operational note, not a code defect. A warning message before the confirmation prompt would prevent surprises:

```powershell
Write-Host "[NOTE] If Entra Connect Sync is active, proxyAddresses changes will replicate to M365." -ForegroundColor Yellow
Write-Host "       Ensure '$NewUPN' is an accepted domain in the target tenant before proceeding." -ForegroundColor Yellow
```

---

#### 8. Minor: Inner Function Parameters Shadow Outer Parameters

The outer script parameters are `$Identity`, `$NewPrefix`, `$FirstName`, `$LastName`. The inner function uses `$Id`, `$Prefix`, `$FName`, `$LName`. This works correctly but makes the script harder to read. In a module refactor (see below), the function signature should align with the outer param names.

---

### Corrected Snippet — Input Validation Block

Insert after all inputs are collected, before the conflict check:

```powershell
# Trim whitespace
$Prefix       = $Prefix.Trim()
$NewFirstName = $NewFirstName.Trim()
$NewLastName  = $NewLastName.Trim()

# SamAccountName length check
if ($Prefix.Length -gt 20) {
    Write-Warning "Prefix '$Prefix' is $($Prefix.Length) characters. Maximum is 20."
    return
}

# SamAccountName character check
if ($Prefix -match '["/\\[\]:;|=,+*?<>@]') {
    Write-Warning "Prefix '$Prefix' contains characters not permitted in SamAccountName."
    return
}
```

---

## Packaging PowerShell Scripts: Cmdlets, Modules, and Executables

This section covers the three main distribution patterns for PowerShell tooling, using `Rename-ADUserSmart` as the reference example throughout.

---

## Pattern 1: Converting to a Module Cmdlet (.psm1)

A PowerShell module wraps one or more functions and exposes them as commands importable with `Import-Module`. This is the standard pattern for reusable IT tooling.

### When to Use

- You want the function available in any PowerShell session without opening a specific file.
- You want to version-control and distribute a collection of related tools.
- You want tab completion and `Get-Help` support.

### Module Directory Structure

```
Modules/
└── ADIdentityTools/
    ├── ADIdentityTools.psd1      # Module manifest
    ├── ADIdentityTools.psm1      # Module script (functions)
    └── en-US/
        └── ADIdentityTools.dll-Help.xml  # Optional: external help
```

### Step 1: Create the Module Folder

```powershell
$ModulePath = "$env:USERPROFILE\Documents\PowerShell\Modules\ADIdentityTools"
New-Item -Path $ModulePath -ItemType Directory -Force
```

PowerShell automatically searches `$env:PSModulePath` for modules. The `Documents\PowerShell\Modules` path is included by default for the current user.

Verify:

```powershell
$env:PSModulePath -split ';'
```

Reference: [about_Modules — Microsoft Docs](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_modules)

---

### Step 2: Create the Module Script (.psm1)

The `.psm1` file contains your functions. For `Rename-ADUserSmart`, the conversion looks like this:

```powershell
# ADIdentityTools.psm1

#Requires -Modules ActiveDirectory

function Invoke-ADUserRename {
    <#
    .SYNOPSIS
        Renames an AD user, updates UPN/mail, and demotes old primary SMTP to alias.
    
    .DESCRIPTION
        Performs a full identity rename on an Active Directory user object:
        DisplayName, SamAccountName, UserPrincipalName, EmailAddress, and proxyAddresses.
        Preserves existing SMTP aliases. Handles ProtectedFromAccidentalDeletion automatically.
        Logs all actions to a transcript in $env:TEMP\ADRenameLogs\.
    
    .PARAMETER Identity
        The SamAccountName or UPN of the user to rename.
    
    .PARAMETER NewPrefix
        The new username prefix (before the @ sign). Maximum 20 characters.
    
    .PARAMETER FirstName
        The new given name. If omitted, the existing value is preserved.
    
    .PARAMETER LastName
        The new surname. If omitted, the existing value is preserved.
    
    .EXAMPLE
        Invoke-ADUserRename -Identity "j.doe" -NewPrefix "john.smith" -FirstName "John" -LastName "Smith"
    
    .EXAMPLE
        Invoke-ADUserRename
        Runs interactively, prompting for all values.
    
    .NOTES
        Author: Andrew Jones
        Version: 1.0
        Requires: ActiveDirectory module, appropriate AD delegation rights.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory=$false)]
        [string]$Identity,

        [Parameter(Mandatory=$false)]
        [ValidateLength(1, 20)]
        [string]$NewPrefix,

        [Parameter(Mandatory=$false)]
        [string]$FirstName,

        [Parameter(Mandatory=$false)]
        [string]$LastName
    )

    # Setup logging
    $LogDir  = "$env:TEMP\ADRenameLogs"
    if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $LogFile = "$LogDir\Log_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"
    Start-Transcript -Path $LogFile -Append | Out-Null

    try {
        # [Script body goes here — identical to original function content]
    }
    finally {
        Stop-Transcript | Out-Null
        Start-Process notepad.exe -ArgumentList $LogFile
    }
}

# Export only the public function
Export-ModuleMember -Function Invoke-ADUserRename
```

Key differences from the original script:

| Original | Module Version | Reason |
|---|---|---|
| Function named `Rename-ADUserSmart` | Renamed to `Invoke-ADUserRename` | Follows PowerShell approved verb list |
| `[CmdletBinding()]` | `[CmdletBinding(SupportsShouldProcess)]` | Adds `-WhatIf` and `-Confirm` support |
| `[string]$NewPrefix` | `[ValidateLength(1, 20)]` on `$NewPrefix` | Enforces AD 20-char limit declaratively |
| No `Export-ModuleMember` | `Export-ModuleMember -Function Invoke-ADUserRename` | Controls what is publicly accessible |

Approved PowerShell verbs reference: [Approved Verbs — Microsoft Docs](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands)

---

### Step 3: Create the Module Manifest (.psd1)

The manifest declares metadata and dependencies. Generate it with:

```powershell
New-ModuleManifest `
    -Path "$ModulePath\ADIdentityTools.psd1" `
    -ModuleVersion "1.0.0" `
    -Author "Andrew Jones" `
    -Description "Active Directory identity management tools" `
    -RootModule "ADIdentityTools.psm1" `
    -RequiredModules @("ActiveDirectory") `
    -FunctionsToExport @("Invoke-ADUserRename") `
    -PowerShellVersion "5.1"
```

Reference: [New-ModuleManifest — Microsoft Docs](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/new-modulemanifest)

---

### Step 4: Import and Use

```powershell
# Import once per session (or add to $PROFILE)
Import-Module ADIdentityTools

# Run the cmdlet
Invoke-ADUserRename -Identity "j.doe" -NewPrefix "john.smith" -FirstName "John" -LastName "Smith"

# WhatIf support (no changes applied)
Invoke-ADUserRename -Identity "j.doe" -NewPrefix "john.smith" -WhatIf

# Full help
Get-Help Invoke-ADUserRename -Full
```

### Auto-Import via $PROFILE

```powershell
notepad $PROFILE
```

Add:

```powershell
Import-Module ADIdentityTools
```

---

### Distributing the Module

Copy the module folder to the same path on any machine where it is needed:

```powershell
Copy-Item "C:\Users\Andrew\Documents\PowerShell\Modules\ADIdentityTools" `
          "\\TargetPC\C$\Users\Administrator\Documents\PowerShell\Modules\" -Recurse
```

Or install system-wide (all users, requires admin):

```powershell
Copy-Item ".\ADIdentityTools" "C:\Program Files\PowerShell\Modules\" -Recurse
```

---

## Pattern 2: Creating a Self-Contained .exe

Compiling a PowerShell script to an executable is useful when:

- The target machine restricts PowerShell execution policy.
- You need a double-click launcher with no console setup.
- You want to distribute to non-technical staff or deploy via Intune/SCCM.

The standard tool for this is **PS2EXE**, a community module that wraps the script in a compiled C# stub.

Reference: [PS2EXE — PowerShell Gallery](https://www.powershellgallery.com/packages/PS2EXE)

### Important Limitation

PS2EXE does not obfuscate or protect the script. The source PowerShell is embedded in the executable and can be extracted. Do not use this for scripts containing credentials or sensitive logic.

---

### Step 1: Install PS2EXE

```powershell
Install-Module -Name PS2EXE -Scope CurrentUser -Force
```

Verify:

```powershell
Get-Module -ListAvailable PS2EXE
```

---

### Step 2: Compile the Script

Basic compilation:

```powershell
Invoke-PS2EXE `
    -InputFile ".\Rename-ADUserSmart_v3.ps1" `
    -OutputFile ".\Rename-ADUserSmart.exe"
```

With metadata and console configuration:

```powershell
Invoke-PS2EXE `
    -InputFile  ".\Rename-ADUserSmart_v3.ps1" `
    -OutputFile ".\Rename-ADUserSmart.exe" `
    -Title      "AD User Rename Tool" `
    -Description "Renames AD user identity and updates SMTP aliases" `
    -Company    "Andrew J IT Labs" `
    -Version    "3.0.0.0" `
    -NoConsole:$false  # Keep console window (required for interactive Read-Host)
```

For scripts using `Read-Host` (like `Rename-ADUserSmart`), `-NoConsole` must remain `$false`. Setting it to `$true` creates a Windows-style application that cannot display terminal prompts.

---

### Step 3: Require Administrator at Launch

Add a manifest to the exe so Windows prompts for elevation automatically:

```powershell
Invoke-PS2EXE `
    -InputFile  ".\Rename-ADUserSmart_v3.ps1" `
    -OutputFile ".\Rename-ADUserSmart.exe" `
    -RequireAdmin
```

This embeds a UAC manifest requesting `requireAdministrator` execution level.

Reference: [Invoke-PS2EXE parameters — GitHub](https://github.com/MScholtes/PS2EXE)

---

### Step 4: Target Architecture

If the script uses `ActiveDirectory` module or other 64-bit only modules:

```powershell
Invoke-PS2EXE `
    -InputFile  ".\Rename-ADUserSmart_v3.ps1" `
    -OutputFile ".\Rename-ADUserSmart.exe" `
    -x64
```

The `-x64` flag ensures the exe launches a 64-bit PowerShell host. The AD module is not available in 32-bit PowerShell on most systems.

---

### Comparison: Module vs EXE

| Factor | Module (.psm1) | Executable (.exe) |
|---|---|---|
| Requires PowerShell | Yes | No (host is embedded) |
| Execution policy | Inherits session policy | Bypassed by compiled stub |
| Tab completion | Full | None |
| Get-Help support | Full | None |
| Source visible | Yes (.psm1 is plain text) | Extractable but not obvious |
| AD module dependency | Explicit via manifest | Must be present on machine |
| Distribution method | Copy folder or PSGallery | Copy single file |
| Interactive prompts | Yes | Yes (console mode) |
| Best suited for | IT team internal use | End-user or policy-restricted deployment |

---

## Pattern 3: Deploying via Intune as a Win32 App

For managed device deployment, the `.exe` (or the `.ps1` directly) can be wrapped and deployed via Microsoft Intune Win32 app packaging.

### Overview

1. Package the `.exe` or `.ps1` into a `.intunewin` file using the Win32 Content Prep Tool.
2. Upload to Intune and configure install command, detection rule, and assignment.

### Step 1: Download Win32 Content Prep Tool

```
https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool
```

### Step 2: Create the Package

```powershell
.\IntuneWinAppUtil.exe `
    -c "C:\Source\ADRenameTools" `
    -s "Rename-ADUserSmart.exe" `
    -o "C:\Output"
```

This creates `Rename-ADUserSmart.intunewin` in `C:\Output`.

### Step 3: Configure in Intune

| Field | Value |
|---|---|
| Install command | `Rename-ADUserSmart.exe` |
| Uninstall command | `cmd /c echo uninstall` (or a dedicated uninstall script) |
| Install behaviour | User or System depending on AD permissions |
| Detection rule | File exists: `C:\Program Files\ADRenameTools\Rename-ADUserSmart.exe` |

Reference: [Win32 app management — Microsoft Docs](https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management)

---

## Putting It Together: Recommended Structure for This Tool

```
ADIdentityTools/
├── ADIdentityTools.psd1                    # Module manifest
├── ADIdentityTools.psm1                    # Module (Invoke-ADUserRename)
├── Scripts/
│   └── Rename-ADUserSmart_v3.ps1           # Standalone script (original)
├── Build/
│   └── Build-Exe.ps1                       # PS2EXE build script
└── Release/
    └── Rename-ADUserSmart.exe              # Compiled output
```

Build script (`Build/Build-Exe.ps1`):

```powershell
#Requires -Modules PS2EXE

$Root    = Split-Path $PSScriptRoot -Parent
$Source  = "$Root\Scripts\Rename-ADUserSmart_v3.ps1"
$Output  = "$Root\Release\Rename-ADUserSmart.exe"

Invoke-PS2EXE `
    -InputFile    $Source `
    -OutputFile   $Output `
    -Title        "AD User Rename Tool" `
    -Description  "Renames AD user identity and updates SMTP aliases" `
    -Company      "Andrew J IT Labs" `
    -Version      "3.0.0.0" `
    -RequireAdmin `
    -x64

Write-Host "Built: $Output" -ForegroundColor Green
```

Run the build:

```powershell
& ".\Build\Build-Exe.ps1"
```

---

## References

- Get-ADUser: https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-aduser
- Set-ADUser: https://learn.microsoft.com/en-us/powershell/module/activedirectory/set-aduser
- Rename-ADObject: https://learn.microsoft.com/en-us/powershell/module/activedirectory/rename-adobject
- about_Modules: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_modules
- New-ModuleManifest: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/new-modulemanifest
- Approved PowerShell Verbs: https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands
- PS2EXE (PowerShell Gallery): https://www.powershellgallery.com/packages/PS2EXE
- PS2EXE (GitHub): https://github.com/MScholtes/PS2EXE
- AD Naming Conventions: https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/naming-conventions-for-computer-domain-site-ou
- Win32 App Management (Intune): https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management
- Win32 Content Prep Tool: https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool
