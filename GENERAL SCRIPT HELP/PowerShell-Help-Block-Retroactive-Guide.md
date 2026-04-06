# Adding Comment-Based Help to Existing PowerShell Scripts

Guide for retroactively adding standardised, expanded help blocks to scripts in the IT-Scripts toolbox. Includes a pre-populated template with known author and repository details, leaving application-specific sections to be completed per script.

Repository: https://github.com/StoicTurk182/IT-Scripts

Reference: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_comment_based_help

---

## Why Bother Retroactively

Once a script is converted to a module via `Convert-PSScript.ps1`, the help block in the source `.ps1` becomes the `Get-Help` output for that module. Without it, `Get-Help` returns empty fields. With it, every module in the toolbox becomes self-documenting — useful when handing scripts to colleagues or returning to a script months later.

Additionally, `Convert-PSScript.ps1` now detects and reuses the source help block automatically on rebuild, so the investment in writing help once carries forward to every future conversion.

---

## Placement Rule

The help block must be placed at one of two locations:

**For a script file with no top-level param block** (e.g. `clear_pre_v2.ps1`):

Place the block immediately after `#Requires` statements and before any code:

```powershell
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    ...
#>

# code starts here
```

**For a script file with a top-level param block** (e.g. `Rename-ADUserSmart_v4.ps1`):

Place the block immediately before the `param()` block:

```powershell
#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    ...
#>

[CmdletBinding()]
param (
    ...
)
```

**For a function inside a module** (e.g. inside a `.psm1`):

Place the block immediately after the opening `{` of the function:

```powershell
function Invoke-ADUserRename {
    <#
    .SYNOPSIS
        ...
    #>
    [CmdletBinding()]
    param (...)
}
```

---

## Standard Template — Pre-Populated

Copy this block into each script. Fill in the sections marked `[REQUIRED]`. Sections marked `[OPTIONAL]` can be removed if not applicable.

```powershell
<#
.SYNOPSIS
    [REQUIRED] One sentence. What does this script do.

.DESCRIPTION
    [REQUIRED] Full explanation of what the script does, what it changes,
    and any behaviour the operator needs to be aware of before running it.

    Cover:
    - What it operates on (AD, filesystem, M365, registry, etc.)
    - What it modifies or deletes
    - Any prompts or confirmations the user will see
    - Any side effects (e.g. Entra Connect Sync replication, service restarts)

.PARAMETER ParameterName
    [REQUIRED if parameters exist — repeat this block for each parameter]
    Description of what this parameter controls and what values are valid.

.EXAMPLE
    [REQUIRED] At least one example showing the most common usage.
    .\ScriptName.ps1
    Brief description of what this example does.

.EXAMPLE
    [OPTIONAL] Additional example showing a different usage pattern.
    .\ScriptName.ps1 -Parameter Value
    Brief description of what this variation does.

.INPUTS
    [OPTIONAL] None. — if the script does not accept pipeline input.
    Or describe the object type if it does accept pipeline input.

.OUTPUTS
    [OPTIONAL] None. All output is written to the console host.
    Or describe the return type if the script outputs objects.

.NOTES
    Author:   Andrew Jones
    GitHub:   https://github.com/StoicTurk182
    Version:  [REQUIRED e.g. 1.0]
    Created:  [REQUIRED e.g. 2026-04-07]
    Modified: [OPTIONAL — update on each change]

    Changelog:
      [REQUIRED] 1.0 — Initial release

    Requires: [REQUIRED if applicable — e.g. Administrator privileges, ActiveDirectory module]

    Part of IT-Scripts Toolbox
    Repository: https://github.com/StoicTurk182/IT-Scripts

.LINK
    https://github.com/StoicTurk182/IT-Scripts

.LINK
    [OPTIONAL] Microsoft Docs URL most relevant to what this script does.
#>
```

---

## Keyword Reference

| Keyword | Required | Notes |
|---|---|---|
| `.SYNOPSIS` | Yes | One line only. Shown in basic `Get-Help` output and tab completion tooltips. |
| `.DESCRIPTION` | Yes | Multiple paragraphs allowed. Shown with `Get-Help -Full` and `Get-Help -Detailed`. |
| `.PARAMETER` | If params exist | One block per parameter. Name must match the `param()` variable exactly (case-insensitive). |
| `.EXAMPLE` | Yes | At least one. Repeat the keyword for each additional example. |
| `.INPUTS` | Optional | Use `None.` if no pipeline input is accepted. |
| `.OUTPUTS` | Optional | Use `None.` if nothing is returned. |
| `.NOTES` | Yes | Free-form. Use for author, version, changelog, and requirements. |
| `.LINK` | Optional | Repeat for multiple URLs. First link appears in `Get-Help -Online`. |

---

## Per-Script Checklist

Work through each script in the repository:

```
IT-Scripts/
├── ActiveDirectory/
│   ├── Rename-UPN/
│   │   └── Rename-ADUserSmart_v4.ps1     [ ] Help block added
│   └── migrate_groups/
│       ├── migrate_user_group_memberships_interactive.ps1   [ ] Help block added
│       └── migrate_user_group_memberships_param.ps1         [ ] Help block added
├── Clear_Prefetch/
│   └── clear_pre_v2.ps1                  [x] Help block added
├── Setup/
│   └── HWH/
│       └── hwh.ps1                       [ ] Help block added
└── Utils/
    └── BACKUPS/
        └── Create_Folders_v2.ps1         [ ] Help block added
```

---

## Applied Examples for Known Scripts

### Rename-ADUserSmart_v4.ps1

```powershell
<#
.SYNOPSIS
    Renames an AD user, updates UPN and primary SMTP, and preserves existing aliases.

.DESCRIPTION
    Performs a full identity rename on an Active Directory user object.

    Updates the following attributes in a single Set-ADUser call:
    DisplayName, SamAccountName, UserPrincipalName, EmailAddress, proxyAddresses.

    Existing SMTP proxy addresses are preserved as secondary aliases.
    The new UPN is promoted to primary SMTP (SMTP:) automatically.
    ProtectedFromAccidentalDeletion is toggled off, changes applied, then restored.

    All changes are logged to $env:TEMP\ADRenameLogs\ via Start-Transcript.
    The log file opens automatically on completion.

    If Entra Connect Sync is active, proxyAddresses changes will replicate to
    Exchange Online. Confirm the target domain is an accepted domain in the M365
    tenant before proceeding.

.PARAMETER Identity
    The SamAccountName or UserPrincipalName of the user to rename.
    If omitted, the script prompts interactively.

.PARAMETER NewPrefix
    The new username prefix — the portion before the @ symbol.
    Maximum 20 characters. Cannot contain: " / \ [ ] : ; | = , + * ? < > @ or spaces.
    If omitted, the script prompts interactively.

.PARAMETER FirstName
    The new given name. If omitted or left blank at the prompt, the existing value is preserved.

.PARAMETER LastName
    The new surname. If omitted or left blank at the prompt, the existing value is preserved.

.EXAMPLE
    .\Rename-ADUserSmart_v4.ps1 -Identity "j.doe" -NewPrefix "john.smith" -FirstName "John" -LastName "Smith"
    Fully parameterised rename. No interactive prompts.

.EXAMPLE
    .\Rename-ADUserSmart_v4.ps1
    Runs interactively. Prompts for username, new prefix, first name, and last name.

.EXAMPLE
    .\Rename-ADUserSmart_v4.ps1 -Identity "j.doe" -NewPrefix "john.smith"
    Renames username and UPN only. First and last name are preserved from current values.

.INPUTS
    None. Does not accept pipeline input.

.OUTPUTS
    None. Results are written to the console and logged to $env:TEMP\ADRenameLogs\.

.NOTES
    Author:   Andrew Jones
    GitHub:   https://github.com/StoicTurk182
    Version:  4.0
    Created:  2026-04-06

    Changelog:
      4.0 — Script block filter on Get-ADUser, SamAccountName length and character
            validation, whitespace trimming, OriginalDN captured before changes,
            Entra Connect Sync warning, param name alignment
      3.0 — Initial toolbox version

    Requires: ActiveDirectory module, AD delegation rights for the target OU.

    Part of IT-Scripts Toolbox
    Repository: https://github.com/StoicTurk182/IT-Scripts

.LINK
    https://github.com/StoicTurk182/IT-Scripts

.LINK
    https://learn.microsoft.com/en-us/powershell/module/activedirectory/set-aduser

.LINK
    https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/naming-conventions-for-computer-domain-site-ou
#>
```

---

### hwh.ps1 (Hardware Hash / Autopilot)

```powershell
<#
.SYNOPSIS
    [REQUIRED — describe what hwh.ps1 does specifically]

.DESCRIPTION
    [REQUIRED]

.EXAMPLE
    .\hwh.ps1
    [REQUIRED — describe the expected output or behaviour]

.INPUTS
    None.

.OUTPUTS
    [REQUIRED — e.g. CSV file at C:\hwh\ containing the Autopilot hardware hash]

.NOTES
    Author:   Andrew Jones
    GitHub:   https://github.com/StoicTurk182
    Version:  [REQUIRED]
    Created:  [REQUIRED]

    Changelog:
      [REQUIRED] 1.0 — Initial release

    Requires: Administrator privileges. Run on the target device to be enrolled.

    Part of IT-Scripts Toolbox
    Repository: https://github.com/StoicTurk182/IT-Scripts

.LINK
    https://github.com/StoicTurk182/IT-Scripts

.LINK
    https://learn.microsoft.com/en-us/autopilot/add-devices
#>
```

---

## Verifying Help After Adding the Block

After adding the block, test before converting to a module:

```powershell
# Test the script-level help directly
Get-Help ".\ScriptName.ps1" -Full

# Check synopsis appears
Get-Help ".\ScriptName.ps1"

# Check examples
Get-Help ".\ScriptName.ps1" -Examples
```

If `Get-Help` returns nothing, the most common causes are:

| Cause | Fix |
|---|---|
| Help block is not in a valid position | Move block to immediately before `param()` or after `#Requires` |
| `<#` and `#>` are not on their own lines | Each delimiter must be on its own line |
| A `#Requires` or other statement appears between the block and `param()` | Move `#Requires` to above the help block |
| The block is inside a function but not at the top | Move block to first line after `{` |

---

## Rebuilding Modules After Adding Help

Once the help block is in the source `.ps1`, rebuild the module:

```powershell
# Remove existing module
Remove-Module ModuleName -Force -ErrorAction SilentlyContinue
Remove-Item "$env:USERPROFILE\Documents\PowerShell\Modules\ModuleName" -Recurse -Force

# Rebuild
& "C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\Convert-PSScript.ps1"

# Verify help is populated
Import-Module ModuleName
Get-Help FunctionName -Full
```

`Convert-PSScript.ps1` will detect the help block automatically and reuse it in the generated `.psm1`. No manual editing of the module file is needed.

---

## References

- about_Comment_Based_Help: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_comment_based_help
- Get-Help: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/get-help
- Approved PowerShell Verbs: https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands
- about_Requires: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_requires
