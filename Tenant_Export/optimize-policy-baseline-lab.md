---
title: "Optimize Policy Baseline Lab"
created: 2026-04-17T23:30:00
updated: 2026-04-17T23:55:00


---
# Optimize Policy Baseline Lab

**Table of Contents**

1. [Purpose](#purpose)
2. [Two-Phase Workflow](#two-phase-workflow)
3. [Phase 1: Generate the Mapping File](#phase-1-generate-the-mapping-file)
4. [Phase 2: Edit the Mapping File](#phase-2-edit-the-mapping-file)
	1. [Mapping File Structure](#mapping-file-structure)
	2. [Naming Convention to Apply](#naming-convention-to-apply)
	3. [Tenant Name Substitution via {{TENANT}} Token](#tenant-name-substitution-via-tenant-token)
	4. [Worked ORION Example](#worked-orion-example)
5. [Phase 3: Apply the Mapping](#phase-3-apply-the-mapping)
6. [Output Structure](#output-structure)
7. [Microsoft Auto-Generated Defaults (Hardcoded Exclusions)](#microsoft-auto-generated-defaults-hardcoded-exclusions)
8. [Parameter Reference](#parameter-reference)
9. [Safety Rails](#safety-rails)
10. [Troubleshooting](#troubleshooting)
11. [Next Steps](#next-steps)
12. [References](#references)


`Optimize-PolicyBaseline.ps1` is the second stage of the baseline-authoring pipeline. It takes the raw folder produced by `Export-PolicyBaseline.ps1`, drops Microsoft auto-generated default policies, applies operator-defined renames to align policies with a consistent naming convention, and writes a cleaned output folder. The input folder is never modified — the output is always a fresh folder, making the operation fully reversible and safe to iterate.

## Purpose

The export script produces a faithful snapshot of whatever is in the source tenant, including policies that were never intended to be part of a shareable baseline (Microsoft auto-generated defaults, experimental lab profiles, legacy items with inconsistent naming). This script cleans that up through an explicit, reviewable mapping file rather than hidden logic, so every exclusion and every rename is documented and version-controllable.

The two-phase design is deliberate: you never rename anything without reviewing the list first.

## Two-Phase Workflow

```
Phase 1: Generate              Phase 2: Apply
---------------                --------------
Raw export                     Edited mapping file
     |                                |
     v                                v
Optimize-PolicyBaseline         Optimize-PolicyBaseline
  -GenerateMappingFile            -MappingFile
     |                                |
     v                                v
mapping.json  (edit this)       Clean export folder
```

Phase 1 is a scan-only operation. It reads the input folder and writes a skeleton mapping JSON with every policy listed, Microsoft defaults pre-flagged for exclusion, everything else pre-flagged to keep with `newName = currentName`. You then edit the file to set your naming convention and exclude any additional policies.

Phase 2 reads the edited mapping and produces the cleaned output folder.

## Phase 1: Generate the Mapping File

```powershell
.\Optimize-PolicyBaseline.ps1 `
    -InputPath C:\Lab\Export-Raw `
    -GenerateMappingFile C:\Lab\mapping.json
```

Console output for the ORION tenant will look like:

```
=== Policy Baseline Optimize ===

[22:45:01] [INFO] Generate mode
[22:45:01] [INFO] Input path:   C:\Lab\Export-Raw
[22:45:01] [INFO] Mapping file: C:\Lab\mapping.json
[22:45:01] [SUCCESS] Found 4 CA policies
[22:45:01] [SUCCESS] Found 15 Settings Catalog profiles
[22:45:01] [WARNING] Flagged for exclusion: Default EDR policy for all devices - Auto-created when MDE integration is enabled
[22:45:01] [WARNING] Flagged for exclusion: Default_Policy - Auto-created Endpoint Security default
[22:45:01] [WARNING] Flagged for exclusion: Firewall Windows default policy - Auto-created when Defender Firewall baseline is enabled
[22:45:01] [WARNING] Flagged for exclusion: NGP Windows default policy - Auto-created Next Generation Protection (Defender AV) default
[22:45:01] [SUCCESS] Mapping file written: C:\Lab\mapping.json

  Conditional Access : keep=4 exclude=0
  Settings Catalog   : keep=11 exclude=4
```

Four Microsoft auto-defaults flagged. Eleven Settings Catalog profiles and four CA policies remain for review.

## Phase 2: Edit the Mapping File

Open `C:\Lab\mapping.json` in your editor.

### Mapping File Structure

```json
{
  "description": "Policy baseline cleanup mapping. Edit newName to rename, set action to exclude to drop.",
  "generated": "2026-04-17T22:45:00Z",
  "sourceInputPath": "C:\\Lab\\Export-Raw",
  "conditionalAccess": [
    {
      "currentName": "CA001 - Require MFA for All Users",
      "newName": "CA001 - Require MFA for All Users",
      "action": "keep"
    }
  ],
  "settingsCatalog": [
    {
      "currentName": "Default EDR policy for all devices",
      "newName": "",
      "action": "exclude",
      "reason": "Auto-created when MDE integration is enabled"
    },
    {
      "currentName": "BitLocker - Enable Encryption",
      "newName": "BitLocker - Enable Encryption",
      "action": "keep"
    }
  ]
}
```

Two fields drive behaviour per entry:

| Field | Values | Effect |
|-------|--------|--------|
| `action` | `keep` | Policy is included in the output |
| `action` | `exclude` | Policy is dropped; written nowhere |
| `newName` | string identical to `currentName` | Policy is kept unchanged |
| `newName` | different non-empty string | Policy is renamed (JSON `displayName` / `name` is updated and filename regenerated) |
| `newName` | empty string | Treated as "keep unchanged" (falls back to `currentName`) |

Fields you do not need to touch: `currentName` (used as the lookup key), `reason` (free-text annotation).

### Naming Convention to Apply

Adapted from OpenIntuneBaseline and the earlier generic-naming doc, the recommended convention for Settings Catalog profiles is:

```
<PLATFORM> - <BASELINE> - <TYPE> - <AUDIENCE> - <AREA>
```

| Element | ORION Values |
|---------|--------------|
| PLATFORM | `Win`, `Mac`, `iOS`, `AndroidWP` |
| BASELINE | `ORION` |
| TYPE | `SC` (Settings Catalog), `ES` (Endpoint Security) |
| AUDIENCE | `D` (device), `U` (user) |
| AREA | Short functional label |

CA policies already follow a clean convention (`CA001 - ...`, `CA002 - ...`) and do not need renaming unless you want to align with an even more formal scheme.

### Tenant Name Substitution via {{TENANT}} Token

The `newName` field supports a single token: `{{TENANT}}`. At apply time, pass `-TenantName <value>` and every occurrence of `{{TENANT}}` in `newName` is replaced with that value. This lets one mapping file produce tenant-specific output bundles from a single template.

Example mapping entry:

```json
{
  "currentName": "BitLocker - Enable Encryption",
  "newName": "{{TENANT}} - BitLocker",
  "action": "keep"
}
```

Applied with `-TenantName ORION`:

```
{{TENANT}} - BitLocker   ->   ORION - BitLocker
```

Applied with `-TenantName Blenheim`:

```
{{TENANT}} - BitLocker   ->   Blenheim - BitLocker
```

Pre-flight enforcement:

| Condition | Behaviour |
|-----------|-----------|
| Mapping contains `{{TENANT}}` and `-TenantName` supplied | Substitution happens, rename proceeds |
| Mapping contains `{{TENANT}}` and `-TenantName` not supplied | Script aborts with error before writing anything |
| Mapping contains no `{{TENANT}}` and `-TenantName` supplied | Warning logged; substitution is a no-op |
| Mapping contains no `{{TENANT}}` and `-TenantName` not supplied | Proceeds normally |

The token regex is `\{\{TENANT\}\}` — exact case, exactly two braces either side. If you want other tokens (e.g. `{{REGION}}`, `{{CLIENT_CODE}}`) they are easy to add in `Resolve-Tokens`, but only `{{TENANT}}` is supported today.

### Worked ORION Example

Here's a suggested mapping that uses `{{TENANT}}` so the same file works against ORION today and any client tenant tomorrow. Paste the `newName` values in place of the equivalent entries in the generated file:

```json
{
  "conditionalAccess": [
    { "currentName": "CA001 - Require MFA for All Users",   "newName": "CA001 - Require MFA for All Users",   "action": "keep" },
    { "currentName": "CA002 - Require MFA for Admins",      "newName": "CA002 - Require MFA for Admins",      "action": "keep" },
    { "currentName": "CA003 - Block Legacy Authentication", "newName": "CA003 - Block Legacy Authentication", "action": "keep" },
    { "currentName": "CA004 - Block Non UK/EU Sign-Ins",    "newName": "CA004 - Block Non UK EU Sign-Ins",    "action": "keep" }
  ],
  "settingsCatalog": [
    { "currentName": "Allow Edge Sign-in",                  "newName": "{{TENANT}} - Edge SignIn",              "action": "keep" },
    { "currentName": "BitLocker - Enable Encryption",       "newName": "{{TENANT}} - BitLocker",                "action": "keep" },
    { "currentName": "Browser Sign-in",                     "newName": "{{TENANT}} - Browser SignIn",           "action": "keep" },
    { "currentName": "CFG-Security-LocalAdmin-Orion",       "newName": "{{TENANT}} - LocalAdmin",               "action": "keep" },
    { "currentName": "Config - Block USB Storage",          "newName": "{{TENANT}} - USB Storage Block",        "action": "keep" },
    { "currentName": "Default EDR policy for all devices",  "newName": "",                                       "action": "exclude", "reason": "Auto-created when MDE integration is enabled" },
    { "currentName": "Default_Policy",                      "newName": "",                                       "action": "exclude", "reason": "Auto-created Endpoint Security default" },
    { "currentName": "Email Security",                      "newName": "{{TENANT}} - Email Security",           "action": "keep" },
    { "currentName": "Enable Automatic Updates",            "newName": "{{TENANT}} - Windows Update",           "action": "keep" },
    { "currentName": "Firewall Windows default policy",     "newName": "",                                       "action": "exclude", "reason": "Auto-created when Defender Firewall baseline is enabled" },
    { "currentName": "Lab Config INTUNE",                   "newName": "",                                       "action": "exclude", "reason": "Experimental lab debris" },
    { "currentName": "LAPS-AzureAD",                        "newName": "{{TENANT}} - LAPS",                     "action": "keep" },
    { "currentName": "NGP Windows default policy",          "newName": "",                                       "action": "exclude", "reason": "Auto-created Next Generation Protection default" },
    { "currentName": "OneDrive Enterprise",                 "newName": "{{TENANT}} - OneDrive",                 "action": "keep" },
    { "currentName": "Windows Cloud Backup Restore",        "newName": "{{TENANT}} - Windows Backup",           "action": "keep" }
  ]
}
```

This pattern uses "tenant name / policy name" as you described — simple, scannable in the Intune portal, fully tenant-neutral in the mapping file.

Applied with `-TenantName ORION` produces 4 CA + 10 Settings Catalog policies with names like `ORION - BitLocker`, `ORION - LAPS`, etc. Applied with `-TenantName Blenheim` produces `Blenheim - BitLocker`, `Blenheim - LAPS`, etc. — same mapping file, different bundle.

Note the minor CA004 change: the forward slash in `UK/EU` is a filesystem-unsafe character. Either rename to `UK EU` (shown above) or to something like `non-EEA`. Leaving the slash in place works at the Graph layer but produces an awkward kebab-case slug on disk.

## Phase 3: Apply the Mapping

Dry run first to see what will happen without writing anything:

```powershell
.\Optimize-PolicyBaseline.ps1 `
    -InputPath C:\Lab\Export-Template `
    -OutputPath C:\Lab\Export-Clean `
    -MappingFile C:\Lab\mapping.json `
    -TenantName ORION `
    -DryRun
```

If the plan looks right, re-run without `-DryRun`:

```powershell
.\Optimize-PolicyBaseline.ps1 `
    -InputPath C:\Lab\Export-Template `
    -OutputPath C:\Lab\Export-Clean `
    -MappingFile C:\Lab\mapping.json `
    -TenantName ORION
```

To produce a different client's bundle from the same mapping, change only the `-TenantName` and `-OutputPath`:

```powershell
.\Optimize-PolicyBaseline.ps1 `
    -InputPath C:\Lab\Export-Template `
    -OutputPath C:\Lab\Export-Clean-Blenheim `
    -MappingFile C:\Lab\mapping.json `
    -TenantName Blenheim
```

Console output (ORION example):

```
=== Policy Baseline Optimize ===

[22:50:01] [INFO] Apply mode
[22:50:01] [INFO] Input path:   C:\Lab\Export-Template
[22:50:01] [INFO] Output path:  C:\Lab\Export-Clean
[22:50:01] [INFO] Mapping file: C:\Lab\mapping.json
[22:50:01] [INFO] Tenant name:  ORION (substituted for {{TENANT}} tokens)
[22:50:01] [INFO] Dry run:      False
[22:50:01] [SUCCESS] Kept CA: CA001 - Require MFA for All Users
[22:50:01] [SUCCESS] Kept CA: CA002 - Require MFA for Admins
[22:50:01] [SUCCESS] Kept CA: CA003 - Block Legacy Authentication
[22:50:01] [SUCCESS] Kept CA: CA004 - Block Non UK/EU Sign-Ins -> CA004 - Block Non UK EU Sign-Ins
[22:50:01] [SUCCESS] Kept SC: Allow Edge Sign-in -> ORION - Edge SignIn
[22:50:01] [SUCCESS] Kept SC: BitLocker - Enable Encryption -> ORION - BitLocker
[22:50:01] [SKIP]    Excluded SC: Default EDR policy for all devices (Auto-created when MDE integration is enabled)
... etc.
[22:50:01] [SUCCESS] Wrote summary to C:\Lab\Export-Clean\optimize-summary.json

  Conditional Access : kept=4 excluded=0 missing=0
  Settings Catalog   : kept=10 excluded=5 missing=0
```

## Output Structure

```
C:\Lab\Export-Clean\
├── optimize-summary.json
├── ConditionalAccess\
│   ├── ca001-require-mfa-for-all-users.json
│   ├── ca002-require-mfa-for-admins.json
│   ├── ca003-block-legacy-authentication.json
│   └── ca004-block-non-uk-eu-sign-ins.json
└── SettingsCatalog\
    ├── orion-bitlocker.json
    ├── orion-browser-signin.json
    ├── orion-edge-signin.json
    ├── orion-email-security.json
    ├── orion-laps.json
    ├── orion-localadmin.json
    ├── orion-onedrive.json
    ├── orion-usb-storage-block.json
    ├── orion-windows-backup.json
    └── orion-windows-update.json
```

Both the filename (kebab-case slug derived from the resolved `newName`) and the policy's in-file name (`displayName` for CA, `name` for Settings Catalog) are rewritten to match the new convention. Everything else in the JSON is untouched. The `optimize-summary.json` records the `tenantName` used so the bundle carries its provenance.

## Microsoft Auto-Generated Defaults (Hardcoded Exclusions)

These are detected by exact name match and pre-flagged for exclusion in the generated mapping file:

| Policy Name | Why It's Excluded |
|-------------|-------------------|
| `Default EDR policy for all devices` | Auto-created when MDE integration is enabled |
| `Default_Policy` | Auto-created Endpoint Security default |
| `Firewall Windows default policy` | Auto-created when Defender Firewall baseline is enabled |
| `NGP Windows default policy` | Auto-created Next Generation Protection (Defender AV) default |

The operator can override any of these by editing the mapping file and changing the action back to `keep` — the script does not enforce the exclusion at apply time, it only pre-populates the mapping. If Microsoft adds new auto-generated defaults in future Intune releases, update the `$Script:MicrosoftDefaults` hashtable at the top of the script.

## Parameter Reference

| Parameter | Mode | Required | Purpose |
|-----------|------|----------|---------|
| `InputPath` | Both | Yes | Folder produced by `Export-PolicyBaseline.ps1` |
| `GenerateMappingFile` | Generate | Yes | Path to write the skeleton mapping JSON |
| `OutputPath` | Apply | Yes | Folder to write the cleaned export into |
| `MappingFile` | Apply | Yes | Path to the edited mapping JSON |
| `TenantName` | Apply | Conditional | Value substituted for `{{TENANT}}` tokens. Required if the mapping file contains the token |
| `DryRun` | Apply | No | Log intended actions without writing files |

Parameter sets are mutually exclusive. Use `-GenerateMappingFile` or use `-OutputPath` + `-MappingFile` (+ optional `-TenantName` and `-DryRun`), not both.

## Safety Rails

- **Input is read-only.** The script never modifies `InputPath`. Worst case, you get a wrong output folder and delete it.
- **Collision detection.** If two mapping entries resolve to the same new name, the script aborts before writing anything. This catches accidental duplicate renames.
- **Missing entries.** If a policy exists in the input folder but not in the mapping, the script logs a `missing` warning and skips that policy. It never silently drops or silently retains unknown policies.
- **Dry-run.** `-DryRun` in apply mode logs every intended write without touching disk. Use it as a diff preview.
- **JSON round-trip fidelity.** The script uses `ConvertTo-Json -Depth 20`. Policies with nesting deeper than 20 levels will have content truncated — rare but possible for complex Settings Catalog configurations with nested groupSetting collections. Re-run the export with `-StripReadOnlyFields` if this happens; the stripped variant is shallower.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Input path not found` | Wrong `-InputPath` | Confirm the folder exists and contains `ConditionalAccess` and `SettingsCatalog` subfolders |
| `Mapping file not found` | Wrong `-MappingFile` | Regenerate with `-GenerateMappingFile` |
| `Mapping file contains {{TENANT}} tokens ... but -TenantName was not supplied` | Token in mapping but no value passed | Re-run with `-TenantName <value>` |
| `has unresolved tokens in newName` | Unknown token pattern (e.g. `{{REGION}}`) that the script doesn't support | Remove the token or extend `Resolve-Tokens` to handle it |
| `-TenantName supplied but no {{TENANT}} tokens found` (warning) | Passed `-TenantName` against a mapping with no tokens | Harmless; the argument is ignored |
| `CA name collision on output` or `Settings Catalog name collision on output` | Two mapping entries resolve to the same `newName` after token substitution | Edit the mapping file to give them distinct names, re-run |
| Warnings about policies "not in mapping" | Input folder contains JSON files the mapping does not cover (e.g. the input was re-exported and has new policies) | Regenerate the mapping, merge your edits manually, re-run |
| Settings Catalog file has `name` field but script reports it can't find `currentName` | JSON malformed (corrupted during manual edit) | Re-export to get a clean source |
| Filenames look odd (have trailing hyphens, unexpected truncation) | Display name contains characters that stripped down to an empty slug or ran over the 120-char limit | Shorten the `newName`, re-run |

## Next Steps

With a clean, consistently named export in `Export-Clean`:

1. **Commit it to Git.** Tag the commit `baseline-v1.0`. This is the first version of your ORION baseline template bundle.
2. **Version the mapping file alongside it.** The mapping file is the record of how you got from raw to clean — keep it next to the bundle in Git.
3. **Diff against the raw export periodically.** Re-running the export against ORION monthly, then re-running optimize with the same mapping file, tells you two things: what changed in the reference tenant (should be intentional), and whether any new Microsoft defaults have appeared (mapping file may need extending).
4. **Decide on the import side.** Options covered in prior docs:
   - Tokenise the clean export and write an import script with a resolver (full control, more code)
   - Feed the clean export folder to IntuneManagement's import flow (fastest to production)
   - Translate the clean export into Microsoft365DSC configurations (strongest drift model)

The clean baseline folder is the artefact that feeds whichever path you pick.

## References

- Microsoft Graph - conditionalAccessPolicy displayName: https://learn.microsoft.com/en-us/graph/api/resources/conditionalaccesspolicy
- Microsoft Graph - deviceManagementConfigurationPolicy name: https://learn.microsoft.com/en-us/graph/api/resources/intune-shared-devicemanagementconfigurationpolicy
- Microsoft Intune - Endpoint security policies (including auto-created defaults): https://learn.microsoft.com/en-us/mem/intune/protect/endpoint-security-policy
- Microsoft Intune - Defender for Endpoint integration: https://learn.microsoft.com/en-us/mem/intune/protect/advanced-threat-protection-configure
- OpenIntuneBaseline naming convention (reference): https://github.com/SkipToTheEndpoint/OpenIntuneBaseline
