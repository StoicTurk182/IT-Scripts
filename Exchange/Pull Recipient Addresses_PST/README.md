---
title: "Get-SentRecipients - PST Recipient Harvester"
created: 2026-06-11T11:30:00
updated: 2026-06-11T11:30:00
---
# Get-SentRecipients - PST Recipient Harvester

Extracts every unique recipient SMTP address from one or more PST files exported from Microsoft Purview eDiscovery, producing a flat address list with per-address send counts.

**Table of Contents**

1. [Purpose](#purpose)
2. [Requirements](#requirements)
3. [Workflow](#workflow)
4. [Usage](#usage)
5. [Parameters](#parameters)
6. [Output](#output)
7. [Notes](#notes)
8. [References](#references)


## Purpose

Reads To/Cc/Bcc from each message in a PST, resolves Exchange (EX) addresses to SMTP, de-duplicates, and writes a flat `addresses.txt` plus an `addresses.csv` (display name, address, count). Built for the case where the source mail lives in a large in-place archive that is impractical to harvest via local Outlook COM directly - the data is pulled out via a Purview eDiscovery export first, then parsed offline by this script.


## Requirements

- Classic (Win32) Outlook installed with a working profile.
- Run non-elevated, in the same user context as the Outlook profile. Outlook COM does not bind cleanly from an elevated session against a normal-user profile.
- PowerShell 5.1 or later.


## Workflow

1. In Microsoft Purview eDiscovery, create a search scoped to the target mailbox with the query `from:<user@domain>`. This returns all sent mail across the primary mailbox and the in-place archive.
2. Export the search results as PST (deduplicated). Large exports are split into multiple PST files.
3. Point this script at the exported PST file or the export folder. Because the export is already filtered to sent mail, the script scans all folders by default.


## Usage

Single PST:

```powershell
.\Get-SentRecipients.ps1 -PstPath "C:\Exports\andrew.pst"
```

Folder of split PSTs (processed in one pass and aggregated):

```powershell
.\Get-SentRecipients.ps1 -PstPath "C:\Exports\PurviewExport"
```

To recipients only, excluding Cc and Bcc:

```powershell
.\Get-SentRecipients.ps1 -PstPath "C:\Exports\andrew.pst" -ToRecipientsOnly
```

Full-mailbox export (no from: filter) restricted to the Sent Items folder:

```powershell
.\Get-SentRecipients.ps1 -PstPath "C:\Exports\full.pst" -SentItemsOnly
```


## Parameters

| Parameter | Required | Default | Purpose |
|-----------|----------|---------|---------|
| `-PstPath` | Yes | - | Path to a `.pst` file, or a folder of PSTs (searched recursively) |
| `-OutputDir` | No | Desktop | Where `addresses.txt` and `addresses.csv` are written |
| `-SentItemsOnly` | No | Off | Restrict to a folder named "Sent Items"; for unfiltered full-mailbox exports |
| `-ToRecipientsOnly` | No | Off | Capture only To recipients, excluding Cc and Bcc |


## Output

| File | Contents |
|------|----------|
| `addresses.txt` | One SMTP address per line, sorted, de-duplicated |
| `addresses.csv` | `DisplayName`, `SmtpAddress`, `Count` (number of messages sent to that address) |

A run summary prints to the console: PSTs processed, messages scanned, and unique address count.


## Notes

- Address resolution from a cloud-exported PST is usually cleaner than from a live mailbox; recipients tend to carry the SMTP address directly or via the `PR_SMTP` MAPI property, so the EX-to-SMTP fallback fires less often.
- Any unresolved entries will be the few items that exported as bare EX / X500 with no SMTP property. This is expected, not a script fault.
- If `Messages scanned` is 0 on a full-mailbox export, omit `-SentItemsOnly` so all folders are scanned, or confirm the PST contains mail items.
- The script attaches each PST to the Outlook profile, harvests, then detaches it. If a detach fails, a warning names the PST so it can be removed manually in Outlook.


## References

- Microsoft Learn - Export search results in eDiscovery: https://learn.microsoft.com/en-us/purview/edisc-search-export
- Microsoft Learn - MS-OXPROPS PidTagSmtpAddress (0x39FE): https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-oxprops/
- Microsoft Learn - Outlook Recipient object (COM): https://learn.microsoft.com/en-us/office/vba/api/outlook.recipient
- Microsoft Learn - NameSpace.AddStore / RemoveStore methods: https://learn.microsoft.com/en-us/office/vba/api/outlook.namespace.addstore
