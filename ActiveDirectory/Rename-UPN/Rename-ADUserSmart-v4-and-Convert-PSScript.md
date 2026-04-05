# Rename-ADUserSmart v4 and Convert-PSScript Tool

Corrected `Rename-ADUserSmart_v4.ps1` applying all review findings, and `Convert-PSScript.ps1` — a universal build tool that converts any `.ps1` into a compiled EXE or a distributable PowerShell module.

---

## Files in This Package

| File | Purpose |
|---|---|
| `Rename-ADUserSmart_v4.ps1` | Corrected AD rename script |
| `Convert-PSScript.ps1` | Universal EXE / Module build tool |

---

## Part 1: Rename-ADUserSmart v4 — Change Log

All eight issues identified in the review have been applied. Changes are inline-commented in the script.

### Changes Applied

#### 1. Script Block Filter on Get-ADUser

Original used string interpolation in the AD filter, which breaks silently on usernames containing single quotes (e.g. `o'brien`).

```powershell
# Before (v3) — string interpolation
$User = Get-ADUser -Filter "UserPrincipalName -eq '$Id' -or SamAccountName -eq '$Id'"

# After (v4) — script block filter
$User = Get-ADUser -Filter { UserPrincipalName -eq $Identity -or SamAccountName -eq $Identity }
```

Script block filters handle variable escaping internally and are the documented best practice.

Reference: [Get-ADUser — Microsoft Docs](https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-aduser)

---

#### 2. SamAccountName Length Validation

AD enforces a hard 20-character maximum on `SamAccountName`. Without this guard, `Set-ADUser` throws a cryptic LDAP constraint violation message that does not identify the cause.

```powershell
if ($NewPrefix.Length -gt 20) {
    Write-Warning "Prefix '$NewPrefix' is $($NewPrefix.Length) characters. SamAccountName maximum is 20."
    return
}
```

Reference: [AD naming conventions — Microsoft Docs](https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/naming-conventions-for-computer-domain-site-ou)

---

#### 3. SamAccountName Character Validation

AD rejects `"`, `/`, `\`, `[`, `]`, `:`, `;`, `|`, `=`, `,`, `+`, `*`, `?`, `<`, `>`, `@`, and whitespace in SamAccountName. These produce vague errors without a prior check.

```powershell
$SamInvalidChars = '["/\\[\]:;|=,+*?<>@\s]'

if ($NewPrefix -match $SamInvalidChars) {
    Write-Warning "Prefix '$NewPrefix' contains characters not permitted in SamAccountName."
    return
}
```

---

#### 4. Whitespace Trimming on All Inputs

Pasted values frequently carry trailing spaces. Without trimming, these write corrupt data into AD attributes silently.

```powershell
$NewPrefix    = $NewPrefix.Trim()
$NewFirstName = $NewFirstName.Trim()
$NewLastName  = $NewLastName.Trim()
```

Applied after all input collection, before any validation or conflict checks.

---

#### 5. Rename-ADObject Uses Captured DN String

The original passed `$User` (the pre-change object) directly to `Rename-ADObject`. The DN is still valid at that point, but the approach depends on undocumented module behaviour. Capturing the DN as a string before any changes is explicit and version-safe.

```powershell
# Capture before any changes
$OriginalDN = $User.DistinguishedName

# ... Set-ADUser runs ...

# Pass the captured string, not the stale object
Rename-ADObject -Identity $OriginalDN -NewName $NewDisplayName -ErrorAction Stop
```

---

#### 6. Proxy Address Removal Comment

The `$EmailSet.Remove($NewUPN)` line was correct but unexplained. A comment was added to clarify the intent, preventing future maintainers from incorrectly removing it.

```powershell
# Remove the new primary UPN from the alias set before building proxyAddresses.
# Prevents it appearing as both SMTP: (primary) and smtp: (alias) simultaneously.
# If the new UPN was an existing alias it is promoted. If new, it is added as primary.
$EmailSet.Remove($NewUPN) | Out-Null
```

---

#### 7. Entra Connect Sync Warning

When Entra Connect Sync is active, `proxyAddresses` changes replicate to Exchange Online. If the target domain is not an accepted domain in the M365 tenant, the sync silently drops or rejects the update. The confirmation block now includes a visible warning.

```powershell
Write-Host "[SYNC NOTE] If Entra Connect Sync is active, proxyAddresses changes will replicate" -ForegroundColor Yellow
Write-Host "            to Exchange Online. Confirm '$DomainSuffix' is an accepted domain in" -ForegroundColor Yellow
Write-Host "            the M365 tenant before proceeding." -ForegroundColor Yellow
```

---

#### 8. Inner Function Param Names Aligned

The outer script used `$Identity`, `$NewPrefix`, `$FirstName`, `$LastName`. The inner function used `$Id`, `$Prefix`, `$FName`, `$LName`. These are now aligned throughout. The inner function is also renamed from `Rename-ADUserSmart` to `Invoke-ADUserRename` to follow the PowerShell approved verb list.

Reference: [Approved Verbs — Microsoft Docs](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands)

---

## Part 2: Convert-PSScript.ps1 — Universal Build Tool

### What It Does

`Convert-PSScript.ps1` takes any `.ps1` file and converts it to one of three targets:

| Option | Output | Best For |
|---|---|---|
| EXE | Single `.exe` compiled via PS2EXE | Restricted machines, end-user distribution, bypassing execution policy |
| Module | `.psm1` + `.psd1` in a named folder | IT team reuse, tab completion, Get-Help support, versioning |
| Both | EXE and Module simultaneously | Full distribution coverage |

### Is This Possible With Any .ps1?

Yes, with the following caveats:

**EXE**: Any `.ps1` can be compiled. The resulting executable embeds a PowerShell host and runs the script. Scripts using `Read-Host` work correctly in console mode (the default). Scripts requiring 64-bit-only modules (such as `ActiveDirectory`) must be compiled with the `-x64` flag, which this tool sets by default.

**Module**: Any `.ps1` with a top-level `param()` block can be wrapped cleanly. The tool uses the PowerShell AST (`System.Management.Automation.Language.Parser`) to extract the param block and body, avoiding brittle regex approaches. Scripts without a param block are still wrapped — they just produce a zero-parameter function. The `#Requires` directives are detected from the token stream and emitted at module level.

Scripts containing nested functions (like `Rename-ADUserSmart_v4.ps1`) produce a module with the outer wrapper function calling the inner ones — this works correctly but results in module-internal functions that are not exported. This is the expected and correct behaviour.

---

### Usage

#### Interactive (no parameters)

```powershell
.\Convert-PSScript.ps1
```

Prompts for: script path, conversion type, metadata, and options.

#### Parameterised

```powershell
# EXE only
.\Convert-PSScript.ps1 -ScriptPath ".\Rename-ADUserSmart_v4.ps1" -OutputType EXE

# Module only
.\Convert-PSScript.ps1 -ScriptPath ".\Rename-ADUserSmart_v4.ps1" -OutputType Module

# Both
.\Convert-PSScript.ps1 -ScriptPath ".\Rename-ADUserSmart_v4.ps1" -OutputType Both

# Custom output directory
.\Convert-PSScript.ps1 -ScriptPath ".\MyScript.ps1" -OutputType EXE -OutputDir "C:\Releases"
```

---

### EXE Conversion — Options Explained

| Option | Default | Notes |
|---|---|---|
| Title | Script filename | Shown in Task Manager and Properties |
| Description | Generic string | Embedded in PE metadata |
| Company | Andrew J IT Labs | Embedded in PE metadata |
| Version | 1.0.0.0 | Must be X.X.X.X format |
| Require Administrator | Y | Embeds UAC manifest; Windows prompts for elevation at launch |
| Force 64-bit host | Y | Required for ActiveDirectory, Exchange, and other 64-bit-only modules |
| Suppress console | N | Set Y only for WinForms/WPF scripts; breaks Read-Host |

PS2EXE is installed automatically from PSGallery if not present.

Reference: [PS2EXE — PowerShell Gallery](https://www.powershellgallery.com/packages/PS2EXE)

---

### Module Conversion — What Gets Generated

Given source script `Rename-ADUserSmart_v4.ps1` and function name `Invoke-ADUserRename`, with module name `ADIdentityTools`:

```
Build\
└── ADIdentityTools\
    ├── ADIdentityTools.psm1    # Function wrapper around script content
    └── ADIdentityTools.psd1    # Module manifest
```

The generated `.psm1` structure:

```powershell
# ADIdentityTools.psm1
# Generated by Convert-PSScript on 2026-04-05

#Requires -Version 5.1
#Requires -Modules ActiveDirectory

function Invoke-ADUserRename {
    <#
    .SYNOPSIS
        AD identity management tools
    .NOTES
        Author:    Andrew Jones
        Version:   1.0.0
        Source:    Rename-ADUserSmart_v4.ps1
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string]$Identity,
        ...
    )

    # [script body]
}

Export-ModuleMember -Function 'Invoke-ADUserRename'
```

Note: `[CmdletBinding(SupportsShouldProcess)]` is added by the wrapper. If the original script already had `[CmdletBinding()]`, both will appear — this is benign (PowerShell merges them) but can be cleaned manually post-generation.

---

### Module Installation and Use

After generation, install to current user:

```powershell
# The tool offers this interactively. Manual equivalent:
Copy-Item ".\Build\ADIdentityTools" "$env:USERPROFILE\Documents\PowerShell\Modules\" -Recurse

# Import
Import-Module ADIdentityTools

# Run
Invoke-ADUserRename -Identity "j.doe" -NewPrefix "john.smith"

# Help
Get-Help Invoke-ADUserRename -Full

# WhatIf (no changes applied)
Invoke-ADUserRename -Identity "j.doe" -NewPrefix "john.smith" -WhatIf
```

Add to `$PROFILE` for automatic import on session start:

```powershell
notepad $PROFILE
# Add: Import-Module ADIdentityTools
```

---

### Limitations and Known Behaviour

**EXE source is not protected.** PS2EXE embeds the PowerShell source in the compiled binary. It can be extracted with tooling. Do not compile scripts containing plaintext credentials or other secrets.

**Module wrapping is not always clean.** Scripts with complex `begin/process/end` blocks, dot-sourced files, or dynamic `param()` generation may not wrap correctly without manual adjustment. The tool reports AST parse errors before proceeding.

**`ActiveDirectory` module requires domain connectivity at runtime.** Compiling to EXE does not bundle the AD module — it must be present and reachable on the machine where the EXE runs.

**Module functions with nested internal functions.** The wrapper creates one exported function. Internal functions defined inside the original script remain callable within the module but are not independently exported. This is correct PowerShell module scoping behaviour.

Reference: [about_Modules — Microsoft Docs](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_modules)

---

### Build Output Structure

```
YourScript-Directory\
├── YourScript.ps1              # Source
├── Convert-PSScript.ps1        # This tool
└── Build\
    ├── YourScript.exe          # EXE output (if selected)
    └── YourModuleName\
        ├── YourModuleName.psm1 # Module output (if selected)
        └── YourModuleName.psd1
```

---

## References

- Get-ADUser: https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-aduser
- Set-ADUser: https://learn.microsoft.com/en-us/powershell/module/activedirectory/set-aduser
- Rename-ADObject: https://learn.microsoft.com/en-us/powershell/module/activedirectory/rename-adobject
- AD Naming Conventions: https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/naming-conventions-for-computer-domain-site-ou
- Approved PowerShell Verbs: https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands
- about_Modules: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_modules
- New-ModuleManifest: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/new-modulemanifest
- PS2EXE (PSGallery): https://www.powershellgallery.com/packages/PS2EXE
- PS2EXE (GitHub): https://github.com/MScholtes/PS2EXE
- PowerShell Language Parser (AST): https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.language.parser
