---
title: "Policy Baseline Pipeline README"
created: 2026-04-17T22:30:00
updated: 2026-04-17T22:30:00


---
# Policy Baseline Pipeline

**Table of Contents**

1. [Scripts](#scripts)
2. [Pipeline Flow](#pipeline-flow)
3. [Quick Start](#quick-start)
4. [Per-Script Reference](#per-script-reference)
5. [Common Variations](#common-variations)
6. [File Layout](#file-layout)
7. [References](#references)


Three-stage pipeline to pull Conditional Access policies and Intune Settings Catalog profiles from a reference tenant, sanitise them into a tenant-neutral baseline bundle, and set CA policies to a known state before deployment. All three scripts are idempotent, log per-policy, and support `-DryRun` where destructive.

## Scripts

| Script | Stage | Input | Output |
|--------|-------|-------|--------|
| `Export-PolicyBaseline.ps1` | Extract | Live Microsoft Graph (source tenant) | Raw JSON folder |
| `Optimize-PolicyBaseline.ps1` | Transform | Raw JSON folder + mapping file | Clean JSON folder (renamed, filtered, tenant-stamped) |
| `Set-CAPolicyState.ps1` | Finalise | Clean JSON folder | Same folder with CA `state` rewritten |

## Pipeline Flow

```
Source tenant (Graph)
        |
        v
  Export-PolicyBaseline.ps1
        |
        v
  C:\Lab\Export-Template\         <- raw, tenant-specific
        |
        v
  Optimize-PolicyBaseline.ps1  (phase 1: generate mapping)
        |
        v
  C:\Lab\mapping.json             <- review, optional edits
        |
        v
  Optimize-PolicyBaseline.ps1  (phase 2: apply mapping)
        |
        v
  C:\Lab\Export-Clean\            <- clean, renamed, tenant-stamped
        |
        v
  Set-CAPolicyState.ps1
        |
        v
  C:\Lab\Export-Clean\            <- CA policies set to disabled
        |
        v
  Git commit: baseline-v1.0
```

## Quick Start

End-to-end run against your reference tenant (ORION / ajolnet.com), producing a deployable bundle stamped for the `AJolnet` tenant with all CA policies disabled. One time setup:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force
mkdir C:\Lab
cd C:\Lab
# drop the three .ps1 files into C:\Lab
```

Run:

```powershell
# 1. Extract from reference tenant
.\Export-PolicyBaseline.ps1 `
    -TenantId ajolnet.com `
    -Interactive `
    -OutputPath C:\Lab\Export-Template `
    -IncludeAssignments:$false `
    -StripReadOnlyFields

# 2a. Generate mapping file (auto-prefixes with {{TENANT}})
.\Optimize-PolicyBaseline.ps1 `
    -InputPath C:\Lab\Export-Template `
    -GenerateMappingFile C:\Lab\mapping.json

# 2b. (Optional) Edit C:\Lab\mapping.json - rename entries, exclude noise
#     Validate after editing:
Get-Content C:\Lab\mapping.json -Raw | ConvertFrom-Json | Out-Null; if ($?) { "JSON valid" }

# 2c. Apply mapping with tenant name substitution
.\Optimize-PolicyBaseline.ps1 `
    -InputPath C:\Lab\Export-Template `
    -OutputPath C:\Lab\Export-Clean `
    -MappingFile C:\Lab\mapping.json `
    -TenantName AJolnet `
    -DryRun

# 2d. If dry-run looks right, apply for real
.\Optimize-PolicyBaseline.ps1 `
    -InputPath C:\Lab\Export-Template `
    -OutputPath C:\Lab\Export-Clean `
    -MappingFile C:\Lab\mapping.json `
    -TenantName AJolnet

# 3. Set CA policies to disabled for safe import
.\Set-CAPolicyState.ps1 -Path C:\Lab\Export-Clean
```

`C:\Lab\Export-Clean` is the deployable baseline bundle. Commit to Git and tag `baseline-v1.0`.

## Per-Script Reference

### Export-PolicyBaseline.ps1

| Parameter | Required | Default | Purpose |
|-----------|----------|---------|---------|
| `TenantId` | Yes | - | Source tenant ID or verified domain |
| `Interactive` | No | off | Delegated auth via browser prompt |
| `ClientId` | No (app-only) | - | App registration client ID |
| `CertificateThumbprint` | No (app-only) | - | Cert in `CurrentUser\My` |
| `OutputPath` | Yes | - | Folder to write exports into |
| `IncludeAssignments` | No | `$true` | Include Settings Catalog `assignments[]` in JSON |
| `StripReadOnlyFields` | No | off | Remove `id`, timestamps, OData metadata |

For template bundles destined for cross-tenant import, run with `-IncludeAssignments:$false -StripReadOnlyFields`. For audit snapshots or drift detection, run with defaults.

### Optimize-PolicyBaseline.ps1

Two parameter sets, mutually exclusive.

**Generate mode:**

| Parameter | Required | Purpose |
|-----------|----------|---------|
| `InputPath` | Yes | Folder produced by Export-PolicyBaseline.ps1 |
| `GenerateMappingFile` | Yes | Path to write skeleton mapping JSON |
| `NoTenantPrefix` | No | Skip the default `{{TENANT}} -` prefix on `newName` |

**Apply mode:**

| Parameter | Required | Purpose |
|-----------|----------|---------|
| `InputPath` | Yes | Folder produced by Export-PolicyBaseline.ps1 |
| `OutputPath` | Yes | Folder to write cleaned bundle into |
| `MappingFile` | Yes | Edited mapping JSON from generate mode |
| `TenantName` | Conditional | Value substituted for `{{TENANT}}` in `newName` |
| `DryRun` | No | Log intended actions without writing |

Input folder is never modified. Script aborts on name collision or unresolved token before writing anything. Microsoft auto-generated defaults are pre-flagged for exclusion.

### Set-CAPolicyState.ps1

| Parameter | Required | Default | Purpose |
|-----------|----------|---------|---------|
| `Path` | Yes | - | Folder containing a `ConditionalAccess` subfolder |
| `State` | No | `disabled` | Target state: `disabled`, `enabled`, `enabledForReportingButNotEnforced` |
| `DryRun` | No | off | Log intended changes without writing |

Does not touch Settings Catalog profiles. Idempotent.

## Common Variations

**Produce a bundle for a different tenant from the same mapping:**

```powershell
.\Optimize-PolicyBaseline.ps1 `
    -InputPath C:\Lab\Export-Template `
    -OutputPath C:\Lab\Export-Clean-Blenheim `
    -MappingFile C:\Lab\mapping.json `
    -TenantName Blenheim
```

Only `-OutputPath` and `-TenantName` change.

**Flip a clean bundle to report-only instead of disabled:**

```powershell
.\Set-CAPolicyState.ps1 -Path C:\Lab\Export-Clean -State enabledForReportingButNotEnforced
```

**Flip to live after review:**

```powershell
.\Set-CAPolicyState.ps1 -Path C:\Lab\Export-Clean -State enabled
```

**Regenerate mapping (overwrites existing mapping file):**

```powershell
Copy-Item C:\Lab\mapping.json C:\Lab\mapping.backup.json
.\Optimize-PolicyBaseline.ps1 -InputPath C:\Lab\Export-Template -GenerateMappingFile C:\Lab\mapping.json
```

**Validate mapping JSON after manual edits:**

```powershell
Get-Content C:\Lab\mapping.json -Raw | ConvertFrom-Json | Out-Null; if ($?) { "JSON valid" } else { "JSON broken" }
```

## File Layout

Recommended layout for a Git-tracked baseline repository:

```
IT-Baselines/
├── scripts/
│   ├── Export-PolicyBaseline.ps1
│   ├── Optimize-PolicyBaseline.ps1
│   └── Set-CAPolicyState.ps1
├── docs/
│   ├── export-policy-baseline-lab.md
│   ├── optimize-policy-baseline-lab.md
│   └── policy-baseline-pipeline-readme.md
├── baselines/
│   └── v1.0/
│       ├── mapping.json
│       ├── Export-Template/          <- raw, git-ignored or kept for reference
│       └── Export-Clean/              <- deployable artefact
│           ├── optimize-summary.json
│           ├── ConditionalAccess/
│           └── SettingsCatalog/
└── README.md
```

`mapping.json` lives with the baseline version; it is the record of how raw was cleaned.

## References

- Export script documentation: `export-policy-baseline-lab.md`
- Optimize script documentation: `optimize-policy-baseline-lab.md`
- Microsoft Graph Conditional Access API: https://learn.microsoft.com/en-us/graph/api/resources/conditionalaccesspolicy
- Microsoft Graph Settings Catalog API: https://learn.microsoft.com/en-us/graph/api/resources/intune-shared-devicemanagementconfigurationpolicy
- Microsoft Graph PowerShell SDK: https://learn.microsoft.com/en-us/powershell/microsoftgraph
