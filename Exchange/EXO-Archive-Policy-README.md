# Exchange Online - Mailbox Archive Policy Script

Applies a retention policy with a Move-to-Archive tag to a target mailbox and kicks off the Managed Folder Assistant immediately.

Script: `Set-ArchiveRetentionPolicy.ps1`

---

## Overview

This script automates the creation and application of an Exchange Online retention policy configured to archive items older than a defined age threshold. It includes connection handling, duplicate-policy detection, archive mailbox enablement, and an immediate Managed Folder Assistant kick-start.

---

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `UserEmail` | string | Yes | — | SMTP address of the target mailbox |
| `TagName` | string | No | `Archive - 1 Year` | Name of the Retention Policy Tag to create/use |
| `PolicyName` | string | No | `Archive Policy - 1 Year` | Name of the Retention Policy to create/use |
| `AgeLimit` | int | No | `365` | Age limit in days before items are moved to archive |

---

## Script

```powershell
param (
    [Parameter(Mandatory=$true)]
    [string]$UserEmail,
    [string]$TagName = "Archive - 1 Year",
    [string]$PolicyName = "Archive Policy - 1 Year",
    [int]$AgeLimit = 365
)

# 1. Connection Logic
try {
    if (!(Get-ConnectionInformation)) {
        Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan
        Connect-ExchangeOnline -ErrorAction Stop
    }
} catch {
    Write-Error "Failed to connect to Exchange Online."
    return
}

# 2. Check for Existing Policy (Graceful Exit)
$ExistingPolicy = Get-RetentionPolicy $PolicyName -ErrorAction SilentlyContinue
if ($ExistingPolicy) {
    Write-Host "INFO: Retention Policy '$PolicyName' already exists. Exiting to prevent overwrite." -ForegroundColor Yellow
    return
}

# 3. Create Tag and Policy if not already present
try {
    # Check/Create Tag
    $ExistingTag = Get-RetentionPolicyTag $TagName -ErrorAction SilentlyContinue
    if (-not $ExistingTag) {
        New-RetentionPolicyTag -Name $TagName -Type All -AgeLimitForRetention $AgeLimit -RetentionAction MoveToArchive
        Write-Host "[+] Created Tag: $TagName" -ForegroundColor Green
    }

    # Create Policy
    New-RetentionPolicy -Name $PolicyName -RetentionPolicyTagLinks $TagName
    Write-Host "[+] Created Policy: $PolicyName" -ForegroundColor Green

    # 4. Apply to Mailbox and Kick-Start
    Enable-Mailbox -Identity $UserEmail -Archive -ErrorAction SilentlyContinue
    Set-Mailbox -Identity $UserEmail -RetentionPolicy $PolicyName -ErrorAction Stop

    # Kick-start Managed Folder Assistant
    Start-ManagedFolderAssistant -Identity $UserEmail
    Write-Host "[SUCCESS] Archive enabled and Folder Assistant kicked off for $UserEmail." -ForegroundColor Green

} catch {
    Write-Error "An unexpected error occurred: $_"
}
```

---

## Usage Examples

### Default (365-day archive)

```powershell
.\Set-ArchiveRetentionPolicy.ps1 -UserEmail "john.smith@contoso.com"
```

### Custom age limit

```powershell
.\Set-ArchiveRetentionPolicy.ps1 -UserEmail "john.smith@contoso.com" -AgeLimit 730 -TagName "Archive - 2 Years" -PolicyName "Archive Policy - 2 Years"
```

---

## Script Logic Flow

```
Start
  |
  +--> Check Exchange Online connection
  |       |
  |       +--> Not connected? --> Connect-ExchangeOnline
  |
  +--> Check if RetentionPolicy already exists
  |       |
  |       +--> EXISTS --> Write warning, exit (no overwrite)
  |
  +--> Check if RetentionPolicyTag exists
  |       |
  |       +--> NOT found --> New-RetentionPolicyTag
  |
  +--> New-RetentionPolicy (with tag link)
  |
  +--> Enable-Mailbox -Archive (silently skips if already enabled)
  |
  +--> Set-Mailbox -RetentionPolicy
  |
  +--> Start-ManagedFolderAssistant
  |
End
```

---

## Differences: Previous vs Revised Script

| Aspect | Previous Version | Revised Version |
|--------|-----------------|-----------------|
| Connection check | Manual / assumed connected | Uses `Get-ConnectionInformation` to detect and auto-connect |
| Duplicate policy handling | Would attempt to re-create, risk of error | Graceful exit with `SilentlyContinue` + `return` |
| Tag existence check | Not present — always attempted creation | Checks with `Get-RetentionPolicyTag` before creating |
| Error handling | Basic or absent | Wrapped in `try/catch` with descriptive `Write-Error` |
| Archive enablement | Not included | `Enable-Mailbox -Archive` with `SilentlyContinue` (non-fatal if already enabled) |
| MFA / Session handling | Session-dependent, brittle | Handled through EXOv2 module connection detection |
| Kick-start | Not included | `Start-ManagedFolderAssistant` fires immediately after policy assignment |
| Parameterisation | Likely hardcoded values | Fully parameterised with sane defaults |
| Idempotency | Not idempotent | Safe to run multiple times — exits cleanly if policy exists |

---

## Applying Policy and Tags Across All Mailboxes

The policy and tag created by the script are tenant-wide objects — once created, they can be assigned to any mailbox. The sections below cover bulk application via both the GUI and Exchange Online PowerShell.

### Method 1: Exchange Admin Centre (GUI)

> Applies to: Microsoft 365 Exchange Admin Centre at https://admin.exchange.microsoft.com

#### Apply to a Single Mailbox (GUI)

1. Navigate to **Recipients > Mailboxes**
2. Select the target mailbox
3. Click **Mailbox** tab in the detail pane
4. Under **Retention policy**, click **Edit** or select from the dropdown
5. Select `Archive Policy - 1 Year` (or your custom policy name)
6. Click **Save**

#### Apply to All Mailboxes (GUI — Bulk Select)

> Note: The EAC bulk selection is limited and does not support applying retention policies to all mailboxes simultaneously via GUI. For true bulk application, use PowerShell. The GUI is suitable for individual or small-scale assignment only.

---

### Method 2: Exchange Online PowerShell (Bulk Application)

#### Prerequisites

```powershell
# Install module if not present
Install-Module ExchangeOnlineManagement -Scope CurrentUser

# Connect
Connect-ExchangeOnline
```

#### Apply to All Mailboxes

```powershell
$PolicyName = "Archive Policy - 1 Year"

Get-Mailbox -ResultSize Unlimited | ForEach-Object {
    Set-Mailbox -Identity $_.Identity -RetentionPolicy $PolicyName
    Write-Host "[+] Applied policy to: $($_.PrimarySmtpAddress)" -ForegroundColor Green
}
```

#### Apply and Enable Archive for All Mailboxes

If archive mailboxes are not yet enabled on all accounts:

```powershell
$PolicyName = "Archive Policy - 1 Year"

Get-Mailbox -ResultSize Unlimited | ForEach-Object {
    Enable-Mailbox -Identity $_.Identity -Archive -ErrorAction SilentlyContinue
    Set-Mailbox -Identity $_.Identity -RetentionPolicy $PolicyName
    Start-ManagedFolderAssistant -Identity $_.Identity
    Write-Host "[+] Processed: $($_.PrimarySmtpAddress)" -ForegroundColor Green
}
```

#### Apply to a Specific Group or Filter

Filter by department, OU, or licence:

```powershell
# Example: Apply only to user mailboxes (exclude shared/room)
$PolicyName = "Archive Policy - 1 Year"

Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox | ForEach-Object {
    Set-Mailbox -Identity $_.Identity -RetentionPolicy $PolicyName
    Write-Host "[+] $($_.PrimarySmtpAddress)" -ForegroundColor Green
}
```

#### Kick-Start Managed Folder Assistant for All Mailboxes

The Managed Folder Assistant runs on Microsoft's schedule (typically every 7 days). To process immediately after bulk assignment:

```powershell
Get-Mailbox -ResultSize Unlimited | ForEach-Object {
    Start-ManagedFolderAssistant -Identity $_.Identity
}
```

> Note: `Start-ManagedFolderAssistant` queues processing — it does not guarantee immediate completion. Large mailboxes may take hours to process. Source: [Microsoft Learn - Start-ManagedFolderAssistant](https://learn.microsoft.com/en-us/powershell/module/exchange/start-managedfolderassistant)

#### Verify Policy Assignment

```powershell
Get-Mailbox -ResultSize Unlimited | Select-Object DisplayName, PrimarySmtpAddress, RetentionPolicy | Format-Table -AutoSize
```

Export to CSV:

```powershell
Get-Mailbox -ResultSize Unlimited |
    Select-Object DisplayName, PrimarySmtpAddress, RetentionPolicy |
    Export-Csv -Path "C:\Temp\RetentionPolicyAudit.csv" -NoTypeInformation
```

---

## Behaviour Notes

### `-ErrorAction SilentlyContinue` on `Enable-Mailbox`

`Enable-Mailbox -Archive` throws a non-terminating error if the archive is already enabled. Using `SilentlyContinue` prevents the script from failing on already-provisioned mailboxes. This is intentional and safe — the subsequent `Set-Mailbox` still runs and applies the policy.

### Managed Folder Assistant Timing

Items are not moved to archive the moment the policy is applied. The Managed Folder Assistant must process the mailbox first. `Start-ManagedFolderAssistant` queues this immediately, but processing time depends on mailbox size and service load. Users may not see items move for several hours.

### Policy Idempotency

The script exits early if the policy name already exists. If you need to modify an existing policy (e.g., change the age limit), use:

```powershell
Set-RetentionPolicyTag -Identity "Archive - 1 Year" -AgeLimitForRetention 730
```

This modifies the tag in-place. Mailboxes with the policy already assigned will pick up the change on their next Managed Folder Assistant cycle.

---

## Required Permissions

| Role | Required For |
|------|-------------|
| Exchange Administrator | Creating policies, tags, assigning to mailboxes |
| Global Administrator | Can perform all of the above |
| Recipient Management | Applying policies to mailboxes (not creating them) |

---

## Troubleshooting

### Policy already exists but should be overwritten

The script exits to prevent unintended changes. To force re-creation:

```powershell
Remove-RetentionPolicy -Identity "Archive Policy - 1 Year" -Confirm:$false
Remove-RetentionPolicyTag -Identity "Archive - 1 Year" -Confirm:$false
```

Then re-run the script.

### Archive not appearing in Outlook

1. Verify archive is enabled: `Get-Mailbox -Identity user@domain.com | Select-Object ArchiveStatus`
2. Kick-start the assistant: `Start-ManagedFolderAssistant -Identity user@domain.com`
3. Allow up to 24 hours for Outlook to reflect the archive folder

### Items not moving after policy applied

- Confirm the tag type is `All` (applies to all folders)
- Confirm `RetentionAction` is `MoveToArchive`
- Verify the archive mailbox is enabled and not over quota
- Check the Managed Folder Assistant has run: `Get-MailboxFolderStatistics -Identity user@domain.com -FolderScope Archive`

---

## References

- [New-RetentionPolicyTag - Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/exchange/new-retentionpolicytag)
- [New-RetentionPolicy - Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/exchange/new-retentionpolicy)
- [Set-Mailbox - Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/exchange/set-mailbox)
- [Enable-Mailbox - Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/exchange/enable-mailbox)
- [Start-ManagedFolderAssistant - Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/exchange/start-managedfolderassistant)
- [Get-ConnectionInformation - Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/exchange/get-connectioninformation)
- [Retention policies and retention labels - Microsoft Learn](https://learn.microsoft.com/en-us/microsoft-365/compliance/retention)
