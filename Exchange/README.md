# Enable-ArchivePolicy.ps1

Deploys an Exchange Online archive retention policy across all user mailboxes in an M365 tenant. Idempotent — safe to re-run without creating duplicates.

Script: `Enable-ArchivePolicy.ps1`

---

*Modification as of 03/03/2026 script no longer bulk applies policy make sure to run this command against the identity of the mailbox owner to to apply changes -.\Set-UserArchive.ps1 -UserEmail "john.doe@domain.com"*

> Furute modifications to policy can be done using the below method

# Updating policy 

```powershell
# Change the age from 365 to 730 days
Set-RetentionPolicyTag -Identity "Archive - 1 Year" -AgeLimitForRetention 730

# 1. Get the current tags so you don't overwrite them
$CurrentTags = (Get-RetentionPolicy "Archive Policy - 1 Year").RetentionPolicyTagLinks

# 2. Add the new tag (e.g., the built-in 'Deleted Items' tag)
$CurrentTags += "Deleted Items"

# 3. Update the policy
Set-RetentionPolicy -Identity "Archive Policy - 1 Year" -RetentionPolicyTagLinks $CurrentTags

Start-ManagedFolderAssistant -Identity "user@domain.com"
```

Scenario	Best Method	Impact
Change time from 1yr to 2yr	Set-RetentionPolicyTag	Updates everyone using that tag.

Add "Auto-Delete" to the policy	Set-RetentionPolicy	Adds a new rule to the existing policy.

Apply change immediately	Start-ManagedFolderAssistant	Forces the server to process the mailbox now.


## What It Does

1. Connects to Exchange Online
2. Creates a Retention Tag (MoveToArchive after X days) if it does not already exist
3. Creates a Retention Policy linked to that tag if it does not already exist
4. Iterates all user mailboxes and for each:
   - Enables the Online Archive if not already active
   - Assigns the retention policy
   - Triggers the Managed Folder Assistant to queue processing
5. Logs all actions to a timestamped file alongside the script

---

## Requirements

| Requirement | Detail |
|-------------|--------|
| PowerShell | 5.1 or later |
| Module | ExchangeOnlineManagement (`Install-Module ExchangeOnlineManagement`) |
| Role | Exchange Administrator or Global Administrator |
| License | Online Archive requires Exchange Online Plan 1 or higher (included in M365 Business Premium) |

---

## Usage

Default (1 year archive threshold):

```powershell
.\Enable-ArchivePolicy.ps1
```

Custom threshold:

```powershell
.\Enable-ArchivePolicy.ps1 -AgeDays 730 -TagName "Archive - 2 Years" -PolicyName "Archive Policy - 2 Years"
```

Custom log path:

```powershell
.\Enable-ArchivePolicy.ps1 -LogPath "C:\Logs\ArchiveDeploy.log"
```

WhatIf (dry run, no changes made):

```powershell
.\Enable-ArchivePolicy.ps1 -WhatIf
```

---

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| TagName | Archive - 1 Year | Name of the retention tag to create |
| PolicyName | Archive Policy - 1 Year | Name of the retention policy to create |
| AgeDays | 365 | Age threshold in days before items are moved to archive |
| LogPath | .\ArchivePolicy-YYYY-MM-DD.log | Path for the output log file |

---

## Verification

After the script completes, run this to confirm the state of all mailboxes:

```powershell
Get-Mailbox -ResultSize Unlimited | Select-Object DisplayName, ArchiveStatus, RetentionPolicy | Out-GridView
```

Check archive mailbox size for a specific user:

```powershell
Get-MailboxStatistics -Identity "user@domain.com" -Archive | Select-Object DisplayName, TotalItemSize, ItemCount
```

---

## Known Behaviours and Limitations

**Managed Folder Assistant is asynchronous**
Start-ManagedFolderAssistant queues the mailbox for processing rather than running immediately. For large mailboxes expect 12-24 hours before items visibly appear in the archive. This is a Microsoft service behaviour and cannot be changed.

**Default MRM Policy is replaced**
Assigning a custom retention policy removes the Default MRM Policy from each mailbox. Any tags in the default policy such as auto-delete rules on Deleted Items or Junk Email will no longer apply. If those behaviours are required, those tags should be added to this policy before deployment.

To check what tags the Default MRM Policy contains before replacing it:

```powershell
Get-RetentionPolicy -Identity "Default MRM Policy" | Select-Object -ExpandProperty RetentionPolicyTagLinks
```

**Archive cap on Business Premium**
M365 Business Premium (Exchange Online Plan 1) caps the archive mailbox at 50 GB. Auto-expanding archiving is not available on this license. Monitor heavy users once archiving is active:

```powershell
Get-MailboxStatistics -Identity "user@domain.com" -Archive | Select-Object TotalItemSize
```

**Folder structure is preserved**
Items moved to the archive retain their original folder path. The archive is fully browsable in Outlook and OWA.

**Personal Tags override the Default Policy Tag**
If a user has applied a Personal Tag such as Personal never move to archive to a folder, that folder will be excluded from automatic archiving regardless of the policy applied here.

---


