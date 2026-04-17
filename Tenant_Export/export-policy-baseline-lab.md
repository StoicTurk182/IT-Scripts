---
title: "Export Policy Baseline Lab"
created: 2026-04-17T23:00:00
updated: 2026-04-17T23:00:00


---
# Export Policy Baseline Lab

```powershell
Primary Command: 

.\Export-PolicyBaseline.ps1 `
    -TenantId ajolnet.com `
    -Interactive `
    -OutputPath C:\Lab\Export-Template `
    -IncludeAssignments:$false `
    -StripReadOnlyFields
```

**Table of Contents**

1. [Purpose](#purpose)
2. [Scope](#scope)
3. [Prerequisites](#prerequisites)
4. [Required Graph Permissions](#required-graph-permissions)
5. [App Registration Setup (App-Only Auth)](#app-registration-setup-app-only-auth)
6. [Running the Script](#running-the-script)
	1. [Interactive Run (Simplest)](#interactive-run-simplest)
	2. [App-Only Run](#app-only-run)
7. [Parameter Reference](#parameter-reference)
8. [Output Structure](#output-structure)
9. [What to Inspect After Export](#what-to-inspect-after-export)
10. [Expected Findings](#expected-findings)
11. [Known API Behaviours](#known-api-behaviours)
12. [Troubleshooting](#troubleshooting)
13. [Next Steps After This Lab](#next-steps-after-this-lab)
14. [References](#references)


This lab validates that Conditional Access policies and Intune Settings Catalog configuration profiles can be pulled cleanly from a source Microsoft 365 tenant as JSON files suitable for templating and later cross-tenant deployment. The companion PowerShell script `Export-PolicyBaseline.ps1` performs the export. This document covers prerequisites, auth options, parameter usage, output structure, and what to look for in the exported JSON to confirm the two-layer model (portable settings body vs tenant-specific bindings) holds in practice.

## Purpose

The goal of this lab is to answer one question with evidence: when you export a CA policy or a Settings Catalog profile from your reference tenant, how much of the JSON is actually portable across tenants, and how much is tenant-specific metadata that would need handling at import time? Running this script and inspecting the output gives you that answer on your own data rather than relying on documentation claims.

## Scope

In scope:

- Conditional Access policies via `GET /identity/conditionalAccess/policies` (v1.0)
- Intune Settings Catalog configuration policies via `GET /deviceManagement/configurationPolicies` (beta) with settings and assignments expanded

Out of scope for this lab (covered by other tooling like IntuneManagement when ready to go further):

- Import into a target tenant
- Tokenisation or migration manifest generation
- Compliance policies, endpoint security, app protection, apps, filters, scope tags, Autopilot, ESP, scripts, remediations
- Entra security groups
- Drift detection

This is deliberately a read-only first-pass export. Get the data out, inspect it, decide what to do next.

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| PowerShell 5.1 or PowerShell 7 | PowerShell 7 recommended for better authentication support |
| Microsoft.Graph.Authentication module | `Install-Module Microsoft.Graph.Authentication -Scope CurrentUser` |
| Source tenant with CA policies and Settings Catalog profiles | ORION / ajolnet.com already has both |
| Account with permissions to read CA and Intune configuration | Global Administrator or Security Reader + Intune Service Administrator |
| Writable folder for output | Local path, typically under `C:\Lab\` |

Module install one-liner:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force
```

If the module is already present, confirm version:

```powershell
Get-Module Microsoft.Graph.Authentication -ListAvailable | Select-Object Version
```

## Required Graph Permissions

| Permission | Type | Purpose |
|------------|------|---------|
| `Policy.Read.All` | Application or Delegated | Read Conditional Access policies |
| `DeviceManagementConfiguration.Read.All` | Application or Delegated | Read Intune Settings Catalog profiles |

These are read-only and the minimum required. Do not grant write scopes for a read-only lab.

## App Registration Setup (App-Only Auth)

For unattended or repeat runs, an app registration with certificate authentication is cleaner than interactive auth. Skip this section if you plan to only use `-Interactive`.

1. Create the app registration:
   - Microsoft Entra admin center > Applications > App registrations > New registration
   - Name: `Lab-PolicyBaselineExport`
   - Supported account types: Accounts in this organizational directory only
   - No redirect URI required

2. Grant API permissions:
   - API permissions > Add a permission > Microsoft Graph > Application permissions
   - Select `Policy.Read.All` and `DeviceManagementConfiguration.Read.All`
   - Grant admin consent for the directory

3. Upload the certificate:
   - Generate a self-signed cert in the user store:
     ```powershell
     $cert = New-SelfSignedCertificate `
         -Subject "CN=Lab-PolicyBaselineExport" `
         -CertStoreLocation "Cert:\CurrentUser\My" `
         -KeyExportPolicy Exportable `
         -KeySpec Signature `
         -KeyLength 2048 `
         -KeyAlgorithm RSA `
         -HashAlgorithm SHA256 `
         -NotAfter (Get-Date).AddYears(2)
     Export-Certificate -Cert $cert -FilePath "$env:USERPROFILE\Desktop\Lab-PolicyBaselineExport.cer" | Out-Null
     $cert.Thumbprint
     ```
   - In the app registration: Certificates & secrets > Certificates > Upload certificate > select the `.cer`

4. Record:
   - Application (client) ID (from the Overview blade)
   - Directory (tenant) ID
   - Certificate thumbprint (from step 3)

## Running the Script

### Interactive Run (Simplest)

First run, while confirming the script does what you expect. Uses delegated auth as the signed-in user:

```powershell
.\Export-PolicyBaseline.ps1 `
    -TenantId ajolnet.com `
    -Interactive `
    -OutputPath C:\Lab\Export-Raw
```

A browser window prompts for credentials. Results land in `C:\Lab\Export-Raw`.

Once comfortable, re-run with read-only fields stripped for a cleaner template-shaped output:

```powershell
.\Export-PolicyBaseline.ps1 `
    -TenantId ajolnet.com `
    -Interactive `
    -OutputPath C:\Lab\Export-Stripped `
    -StripReadOnlyFields
```

### App-Only Run

For unattended or scheduled use with the app registration from the previous section:

```powershell
.\Export-PolicyBaseline.ps1 `
    -TenantId ajolnet.com `
    -ClientId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' `
    -CertificateThumbprint '1A2B3C4D5E6F7890ABCDEF1234567890ABCDEF12' `
    -OutputPath C:\Lab\Export-AppOnly `
    -StripReadOnlyFields
```

## Parameter Reference

| Parameter | Type | Required | Default | Purpose |
|-----------|------|----------|---------|---------|
| `TenantId` | string | Yes | - | Source tenant ID or verified domain |
| `ClientId` | string | No | - | App registration client ID (required for app-only) |
| `CertificateThumbprint` | string | No | - | Certificate in `CurrentUser\My` (required for app-only) |
| `Interactive` | switch | No | off | Use delegated auth in a browser prompt |
| `OutputPath` | string | Yes | - | Folder to write exports into |
| `IncludeAssignments` | bool | No | `$true` | Include Settings Catalog assignments in JSON |
| `StripReadOnlyFields` | switch | No | off | Remove `id`, `createdDateTime`, `modifiedDateTime`, `lastModifiedDateTime` |

## Output Structure

```
<OutputPath>/
├── export-summary.json
├── ConditionalAccess/
│   ├── ca001-require-mfa-for-admins.json
│   ├── ca002-block-legacy-auth.json
│   └── ...
└── SettingsCatalog/
    ├── win-orion-sc-d-bitlocker.json
    ├── win-orion-sc-d-defender.json
    └── ...
```

Filenames are derived from the policy's `displayName` (CA) or `name` (Settings Catalog), sanitised to kebab-case with filesystem-unsafe characters replaced.

The `export-summary.json` records the run metadata:

```json
{
  "exportedAt": "2026-04-17T22:30:00Z",
  "sourceTenantId": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  "sourceAccount": "admin@ajolnet.com",
  "scriptVersion": "1.0",
  "stripReadOnlyFields": true,
  "includeAssignments": true,
  "conditionalAccessCount": 6,
  "settingsCatalogCount": 12,
  "conditionalAccess": [
    { "displayName": "CA001: Require MFA for admins", "file": "ca001-require-mfa-for-admins.json" }
  ],
  "settingsCatalog": [
    { "name": "Win - ORION - SC - D - BitLocker", "file": "win-orion-sc-d-bitlocker.json" }
  ]
}
```

## What to Inspect After Export

After the first run, open each category and check specific fields to confirm the two-layer model:

**Conditional Access (e.g. `ca001-require-mfa-for-admins.json`):**

| Section | What to Look For |
|---------|------------------|
| `displayName`, `state`, `conditions.clientAppTypes`, `grantControls.builtInControls` | Plain strings and enum values, no GUIDs. Fully portable. |
| `conditions.users.includeRoles` | GUIDs here are built-in Entra role template IDs and are **identical** in every tenant. Confirm by googling one (e.g. `62e90394-69f5-4237-9190-012177145e10` should resolve to Global Administrator). |
| `conditions.users.excludeGroups` | GUIDs here are per-tenant group object IDs. These are the tenant-specific bindings that would need resolution on import. |
| `conditions.users.excludeUsers` | Per-tenant user object IDs, typically break-glass accounts. |
| `conditions.applications.includeApplications` | Strings like `"All"` or `"Office365"` are portable. GUIDs matching first-party Microsoft app IDs (e.g. Exchange `00000002-0000-0ff1-ce00-000000000000`) are also identical across tenants. Custom enterprise app GUIDs would be per-tenant. |
| `id`, `createdDateTime`, `modifiedDateTime` | Only present if not using `-StripReadOnlyFields`. Server-assigned, cannot be transplanted. |

**Settings Catalog (e.g. `win-orion-sc-d-bitlocker.json`):**

| Section | What to Look For |
|---------|------------------|
| `name`, `description`, `platforms`, `technologies` | Plain strings and enum values. Fully portable. |
| `settings[]` | Each setting has a `settingInstance.settingDefinitionId` (a CSP-style identifier like `device_vendor_msft_bitlocker_...`) that is **identical** in every tenant. This is the core of the policy's portability. |
| `settings[].settingInstance.choiceSettingValue.value` | Values like `device_vendor_msft_bitlocker_<setting>_true`. Portable strings, not GUIDs. |
| `assignments[]` | Contains `target.groupId` — these are per-tenant group IDs, the bindings layer. |
| `roleScopeTagIds` | Per-tenant scope tag IDs. For a fresh tenant with no custom scope tags, this is typically `["0"]` (the default). |
| `id`, `createdDateTime`, `lastModifiedDateTime` | Stripped if `-StripReadOnlyFields` used. |

Open two or three files in a text editor and walk through them field by field. This is where the abstract "two-layer model" becomes concrete.

## Expected Findings

If the reference tenant (ORION / ajolnet.com) is configured as documented — CA001–CA004 policies, Win - INF - SC - D - ... Settings Catalog baseline — the export should produce:

- A handful of CA policy JSON files (one per active policy including report-only)
- A dozen or more Settings Catalog profile JSON files depending on baseline scope
- CA policies with `includeRoles` populated with well-known role template IDs; `excludeGroups` or `excludeUsers` pointing at the break-glass exclusion group and accounts
- Settings Catalog profiles with fully enumerated `settings[]` arrays and nested `settingInstance` structures
- A clean `export-summary.json` summarising the run

What confirms the lab's success:

- Every CA policy's `displayName` is present in the output
- Every CA policy's GUID-heavy fields (`includeRoles`, `includeGroups`, `excludeGroups`, `excludeUsers`) are clearly tenant-agnostic (role template IDs) or clearly tenant-specific (groups, users) — no mysterious GUIDs
- Every Settings Catalog profile's `settings[]` is present and contains `settingInstance` children with CSP-backed `settingDefinitionId` values
- The JSON is valid and round-trips through `ConvertFrom-Json | ConvertTo-Json` without loss

## Known API Behaviours

- **Settings Catalog requires the beta endpoint** for full `$expand=settings,assignments` support at the time of writing. The v1.0 endpoint exists but does not return the nested settings tree in the same shape.
- **CA policies on v1.0 are stable**. The beta endpoint exposes some preview fields (for example, newer risk detection signals) that do not round-trip cleanly; use v1.0 for templating.
- **Graph paging**. Both endpoints can return `@odata.nextLink`. The script handles this. Very large tenants (hundreds of profiles) will take longer.
- **ReadWrite vs Read scopes**. Delegated `-Interactive` auth will prompt for consent on first use if the required scopes are not already granted on the Microsoft Graph PowerShell enterprise app or your user.
- **Intune licensing gates**. A tenant without Intune licensing will return zero Settings Catalog profiles. The script logs `Found 0 Settings Catalog profiles` and continues. This is expected, not an error.

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| `Connect-MgGraph : AADSTS65001: The user or administrator has not consented to use the application` | First-time use of Microsoft Graph PowerShell enterprise app in this tenant | Complete the consent prompt as a Global Administrator, or pre-consent the scopes in the Entra admin center |
| `Connect-MgGraph : AADSTS700016: Application with identifier ... was not found` | Wrong `ClientId` or app not created in the specified tenant | Confirm the app registration exists and the client ID matches |
| `Insufficient privileges to complete the operation` on GET | Missing `Policy.Read.All` or `DeviceManagementConfiguration.Read.All` consent | Grant admin consent in the app registration's API permissions blade |
| Zero CA policies returned | Tenant has no CA policies (fresh tenant) or Security Defaults is enabled instead of CA | Expected in a fresh tenant; CA requires Entra ID P1 or M365 Business Premium |
| Zero Settings Catalog profiles returned | No Intune licensing or no Settings Catalog profiles created yet | Confirm Intune is licensed and at least one profile exists in the portal |
| `The certificate was not found in the certificate store` | Cert thumbprint wrong or cert not in `CurrentUser\My` | Verify with `Get-ChildItem Cert:\CurrentUser\My \| Where-Object Thumbprint -eq '<thumb>'` |
| JSON files contain `@odata.type` and `@odata.context` entries | Expected behaviour; Graph emits type hints | Harmless; they round-trip through POST on import |
| Policy export filename collides with another | Two policies with near-identical `displayName` collapsing to the same kebab-case slug | Rename one of the source policies to something more distinct and re-export |

## Next Steps After This Lab

Once the export behaves as expected and the JSON shape is understood:

1. **Version the output in Git.** Commit the `Export-Stripped` folder as `baseline-v1.0` and tag it. This is your first template bundle.
2. **Review each file for tenant-specific bindings.** Build a short list of every place where a group GUID, user UPN, or filter GUID appears. This is the input for the next lab (token substitution and import).
3. **Establish naming conventions** for groups, filters, and scope tags in the reference tenant if not already done. Every name that must resolve across tenants must be identical across tenants.
4. **Decide on import tooling.** For production MSP use, adopt IntuneManagement (or Microsoft365DSC). For learning and full control, extend this script with an import side and a migration manifest. Both paths have been explored in companion docs.
5. **Re-export periodically.** Treat the reference tenant's baseline as living; re-export on a cadence (monthly or on-change) and commit version bumps.

## References

- Microsoft Graph - conditionalAccessPolicy resource type: https://learn.microsoft.com/en-us/graph/api/resources/conditionalaccesspolicy
- Microsoft Graph - List conditional access policies: https://learn.microsoft.com/en-us/graph/api/conditionalaccessroot-list-policies
- Microsoft Graph - deviceManagementConfigurationPolicy resource type: https://learn.microsoft.com/en-us/graph/api/resources/intune-shared-devicemanagementconfigurationpolicy
- Microsoft Graph - List configurationPolicies: https://learn.microsoft.com/en-us/graph/api/intune-shared-devicemanagementconfigurationpolicy-list
- Microsoft Graph PowerShell SDK - Connect-MgGraph: https://learn.microsoft.com/en-us/powershell/microsoftgraph/authentication-commands
- Microsoft Graph PowerShell SDK - Invoke-MgGraphRequest: https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.authentication/invoke-mggraphrequest
- Microsoft Graph - Paging: https://learn.microsoft.com/en-us/graph/paging
- Entra - Create a self-signed certificate for app-only authentication: https://learn.microsoft.com/en-us/graph/powershell/app-only
