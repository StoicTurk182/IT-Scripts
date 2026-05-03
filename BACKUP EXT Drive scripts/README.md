---
title: "Backup UserData Simple"
created: 2026-04-29T14:35:05
updated: 2026-05-03T09:06:18
---

# Backup-UserData-Simple

Single-user data preservation script for pre-reimage and pre-swap workflows. Runs from an external drive plugged into a live target machine and copies a target user's standard folders, browser profiles, OneDrive sync roots, Sage data, and Recycle Bins from every fixed drive into a labelled folder structure on the external drive. Robocopy options are tuned for NVMe-over-USB destinations.

This is the simpler counterpart to the multi-profile `Backup-UserData.ps1`. Use it for routine TransWiz-style migrations where the profile state is being handled separately and the script's job is purely to grab raw data into a predictable folder layout.

**Table of Contents**

1. [Prerequisites](#prerequisites)
2. [Usage](#usage)
3. [What Gets Captured](#what-gets-captured)
4. [What Is Not Captured](#what-is-not-captured)
5. [Output Structure](#output-structure)
6. [Robocopy Options](#robocopy-options)
7. [Behaviour Notes](#behaviour-notes)
8. [Target Profile Resolution](#target-profile-resolution)
	1. [The Problem](#the-problem)
	2. [Why It Happens](#why-it-happens)
	3. [How Resolution Works](#how-resolution-works)
	4. [Behaviour by Scenario](#behaviour-by-scenario)
	5. [Operator Workflow](#operator-workflow)
	6. [Audit Trail](#audit-trail)
9. [Known Limitations](#known-limitations)
10. [Change Log](#change-log)
11. [References](#references)

## Prerequisites

| Requirement | Reason |
|-------------|--------|
| Windows 10 or 11 with PowerShell 5.1+ | Built-in Robocopy and PowerShell |
| External drive formatted NTFS or exFAT | FAT32 fails on files larger than 4 GB and on long paths |
| Free space on destination >= source data size | No pre-flight size check is performed |
| Local Administrator (recommended) | Enables Robocopy `/B` (backup mode) for locked-file handling, reading other users' SID folders inside `$Recycle.Bin`, and reading another user's profile when running elevated from a different account |

Admin is not strictly required. The script runs as the current user. Without admin, `/B` silently no-ops and locked browser databases (`History`, `Login Data`) may copy partially or not at all.

## Usage

1. Plug the external NVMe drive into the live target machine.
2. Open PowerShell. Run as Administrator if available.
3. Execute:

```powershell
.\Backup-UserData-Simple.ps1
```

4. Enter the destination drive letter when prompted (e.g. `W`).
5. Enter a backup label (e.g. `old_PC`, `pre_reimage`, `migration`).
6. If running browsers or OneDrive are detected the script lists them and pauses. Close them, pause OneDrive sync, then press ENTER.
7. The script displays profile detection results. If running-as and interactive console users differ, choose the correct target profile when prompted (see [Target Profile Resolution](#target-profile-resolution)).
8. Wait for completion.
9. Review `<Drive>:\<HOSTNAME>_<label>_<DDMMYYYY>\Backup_Log.txt`.

## What Gets Captured

| Subfolder | Source | Notes |
|-----------|--------|-------|
| Desktop | `<TargetHome>\Desktop` | |
| Documents | `<TargetHome>\Documents` | |
| Download | `<TargetHome>\Downloads` | Folder is `Download` (singular); source is `Downloads` |
| Pictures | `<TargetHome>\Pictures` | |
| Music | `<TargetHome>\Music` | |
| Browser\Edge | `<TargetHome>\AppData\Local\Microsoft\Edge\User Data` | Cache directories excluded |
| Browser\Chrome | `<TargetHome>\AppData\Local\Google\Chrome\User Data` | As above |
| Browser\Brave | `<TargetHome>\AppData\Local\BraveSoftware\Brave-Browser\User Data` | As above |
| Browser\Firefox | `<TargetHome>\AppData\Roaming\Mozilla\Firefox` | As above |
| Unsynced_Onedrive\\<name\> | Each `<TargetHome>\OneDrive*` folder | Cloud-only placeholders skipped |
| Sage\\<location\> | `C:\ProgramData\Sage\Accounts`, `Documents\Sage`, `Public Documents\Sage` | Best-guess paths; folder only created if data found |
| RecycleBin\\<letter\> | `<DriveLetter>:\$Recycle.Bin` for each fixed drive | Destination drive itself is skipped |

`<TargetHome>` is the resolved profile path (e.g. `C:\Users\Andrew`). See [Target Profile Resolution](#target-profile-resolution) for how this is determined.

## What Is Not Captured

The script is deliberately scoped. The following are out of scope and require either the multi-profile `Backup-UserData.ps1` or a profile migration tool such as TransWiz / USMT:

- Other user profiles on the machine (single-user only — script captures one resolved target user)
- AppData beyond browser User Data folders. No Outlook PSTs/OSTs, no signatures, no templates, no VS Code settings, no app-specific config
- Profile-root dotfolders such as `.ssh`, `.aws`, `.azure`, `.docker`, `.gitconfig`
- DPAPI master keys (no offline browser-password decryption capability)
- Registry hives (NTUSER.DAT)
- Anything stored outside the user profile or its OneDrive folders
- Anything on non-fixed drives (USB sticks, network shares)
- Installed application binaries

## Output Structure

```
<Drive>:\<HOSTNAME>_<label>_<DDMMYYYY>\
  Backup_Log.txt
  Desktop\
  Documents\
  Download\
  Pictures\
  Music\
  Browser\
    Edge\
    Chrome\
    Brave\
    Firefox\
  Unsynced_Onedrive\
    OneDrive\
    OneDrive - Tenant Name\
  Sage\                      (only if Sage data found)
  RecycleBin\
    C\
    D\
    ...
```

Each subfolder has a matching `.log` file alongside it (e.g. `Browser\Edge.log`, `RecycleBin\C.log`) containing detailed Robocopy output. The combined `Backup_Log.txt` at the run root is the high-level summary written by the script's `Write-Log` helper.

## Robocopy Options

Common options applied by the `Invoke-Robo` helper:

| Flag | Purpose |
|------|---------|
| /E | Copy subfolders including empty |
| /COPY:DAT | Data, Attributes, Timestamps (ACLs deliberately not copied) |
| /DCOPY:T | Copy directory timestamps |
| /J | Unbuffered I/O — faster for large files on NVMe destinations |
| /MT:32 | 32 concurrent threads |
| /R:2 | Retry failed files twice |
| /W:5 | Wait 5 seconds between retries |
| /XJ | Skip junction points to avoid reparse loops |
| /NP | No per-file progress (cleaner logs) |
| /NDL | No directory listing (cleaner logs) |
| /LOG: | Per-source log file |

Source-specific extras:

| Flag | Used For | Purpose |
|------|----------|---------|
| /B | Browser, Recycle Bin | Backup mode — uses `SeBackupPrivilege` to read locked files. Silently no-ops without admin |
| /XD | Browser | Excludes cache directories: `Cache`, `GPUCache`, `Crashpad`, `ShaderCache`, `GrShaderCache` |
| /XA:O | OneDrive | Excludes files with the Offline attribute set (cloud-only placeholders). Without this, Robocopy would either fail or trigger downloads |
| /A-:SH | Recycle Bin | Strips System+Hidden attributes from copied files. Note this only acts on files; directories are handled post-copy by `Clear-HiddenSystemAttrs` |

## Behaviour Notes

**Pre-flight process check.** Before the folder structure is created, `Initialize-BackupFolderStructure` checks for `msedge`, `chrome`, `brave`, `opera`, `vivaldi`, `firefox`, and `OneDrive` processes. If any are running it lists them and pauses with `Read-Host`. The intent is to give the operator a hard checkpoint to close browsers and pause OneDrive sync — both common causes of `Exit=9` errors that even `/B` cannot fully resolve.

**Destination drive guard.** The Recycle Bin loop derives the destination drive letter from `$RootPath` and skips it. Without this, the script would attempt to copy the destination drive's `$Recycle.Bin` folder into itself, producing recursive nesting. The skip is logged as `[-] Skip RecycleBin-<letter>: destination drive` so it remains auditable.

**Robocopy exit codes.** Exit codes 0-7 are success states (0 = nothing to copy, 1 = files copied, 2 = extras detected, etc., bitwise combined). Exit codes 8+ indicate errors. The `Invoke-Robo` helper logs `[+] Done` for exit < 8 and `[!] Errors` for exit >= 8 with a pointer to the per-source log.

**Recycle Bin contents and visibility.** Files captured under `RecycleBin\<letter>\` are stored as Windows expects internally: `S-1-5-21-...` SID folders containing `$I<random>` (metadata) and `$R<random>` (file data) pairs. They are not directly restorable as a working Recycle Bin on the destination — a parser tool is required to map them back to original filenames. The `Clear-HiddenSystemAttrs` helper runs after each Recycle Bin copy to strip Hidden+System attributes from the destination directory tree, so the contents are visible in Explorer without needing to enable "Show hidden files".

## Target Profile Resolution

The `Resolve-TargetProfile` function determines which user profile is backed up. It exists to prevent silently backing up the wrong user when the script is launched from an elevated session under a different account.

### The Problem

If the script is launched by elevating to a different account (e.g. running as a local Administrator from a session signed in as a standard user), `$env:USERNAME` and `$env:USERPROFILE` resolve to the elevated account, not the user whose data needs preserving. Without explicit handling, the script silently backs up the wrong profile — typically capturing an empty or near-empty Administrator profile while ignoring the actual user data.

This is the most likely cause of "missing data" complaints after a reimage and is hard to diagnose after the fact: the script reports success, the destination has the expected folder structure, the logs look clean, but the contents are wrong.

### Why It Happens

When a process is elevated via UAC, Windows starts a new process with the elevated account's security token. Process-scoped APIs reflect the new identity:

| API | Returns |
|-----|---------|
| `$env:USERNAME` | The elevated account |
| `$env:USERPROFILE` | The elevated account's profile path |
| `[Security.Principal.WindowsIdentity]::GetCurrent().Name` | The elevated account |
| `whoami` | The elevated account |

The "interactive console user" (the person actually signed into the desktop session) is a separate concept exposed through different APIs. The relevant one for this script is `Win32_ComputerSystem.UserName`, which returns the active console user in `DOMAIN\user` format and survives elevation because it queries the desktop session rather than the running process token.

### How Resolution Works

The `Resolve-TargetProfile` function performs three steps:

1. Records the running-as user (`$env:USERNAME`).
2. Queries `Win32_ComputerSystem.UserName` for the interactive console user, taking the part after the backslash.
3. Compares the two values:
	- If they match, or no interactive user is detectable, defaults silently to the running-as user.
	- If they differ, presents the operator with a three-option prompt.

The selected username is validated against `C:\Users\<name>\` and the actual on-disk casing is captured. The result is written to two script-scope variables:

| Variable | Contents |
|----------|----------|
| `$Script:TargetUser` | Username matching the on-disk profile folder (e.g. `Andrew`) |
| `$Script:TargetHome` | Full path to the profile root (e.g. `C:\Users\Andrew`) |

`Copy-UserData` reads from these variables instead of `$env:USERPROFILE` / `$env:USERNAME`.

### Behaviour by Scenario

| Scenario | Running-as | Interactive | Behaviour |
|----------|-----------|-------------|-----------|
| Standard run, not elevated | User | User | Silent default to User |
| Elevated within same user session | User | User | Silent default to User |
| Elevated from different account (the bug case) | Admin | User | Prompt, operator picks |
| Run from console-less context (RDP only, scheduled task) | Whatever | (none) | Silent default to running-as |
| User logged off, technician resolving via slaved disk | Tech | (none or Tech) | Falls through to option 3 if a different profile is needed |

### Operator Workflow

In the no-mismatch case the operator sees an informational block but no extra prompt:

```
Profile detection:
  Running as          : Andrew
  Interactive console : Andrew
  Selected            : Andrew
```

In the mismatch case the operator must choose:

```
Profile detection:
  Running as          : Administrator
  Interactive console : Andrew

MISMATCH: script was elevated from a different account.
Backing up the wrong profile is the most likely cause of missing data after a reimage.

Choose target profile to back up:
  [1] Andrew  (interactive console user - usually correct)
  [2] Administrator  (elevated / running-as user)
  [3] Specify a different username

Choice [1/2/3]:
```

Option 3 lists every profile folder under `C:\Users\` that contains an `NTUSER.DAT` (the marker for a real Windows profile). This filters out junk folders like the `%USERNAME%` ghost folder created by misexpanded variables in older scripts, and any other non-profile directories that happen to live under `C:\Users\`.

The recommended workflow for MSP / migration use is:

1. Elevate the PowerShell session (right-click > Run as administrator). Provides the rights needed to read other users' profiles and Recycle Bin SID folders.
2. Run the script. The mismatch prompt appears.
3. Select option 1 (the interactive console user). The script reads with admin rights but writes the correct user's data into the backup folder.

### Audit Trail

Three log lines are written to `Backup_Log.txt` for every run, regardless of whether a mismatch was detected:

```
Target profile resolved: Andrew
Profile path: C:\Users\Andrew
Running-as user was: Administrator (interactive: Andrew)
```

The third line records both the running-as account and the interactive account, so it remains possible to determine after the fact whether elevation was involved and whether the operator chose the same profile that detection would have defaulted to.

## Known Limitations

| Limitation | Workaround |
|------------|------------|
| Recycle Bin contents not directly restorable | Use a `$I`/`$R` parser to recover filenames if needed |
| OneDrive cloud-only files not captured | Pin them locally with "Always keep on this device" before running, or rely on cloud sync to a new device |
| Browser passwords are DPAPI-encrypted | Will not decrypt offline without the user's `AppData\Roaming\Microsoft\Protect` master keys (deliberately not captured here). Account-sync on the new device is the reliable path |
| Single user only | For multi-profile capture, use the full `Backup-UserData.ps1` |
| No file count or hash verification | Robocopy exit codes are the only integrity signal |
| Sage paths are best-guess defaults | Sage 50, Sage 200, Sage Payroll, and customised installs may store data elsewhere. Verify against the target install and add to `$SageSources` |
| Browser App-Bound Encryption (Chrome 127+, Edge equivalent) | Newer Chromium versions add a service-bound encryption layer on top of DPAPI for cookies and (Chrome 132+) passwords. Even with DPAPI keys, decryption requires the original Windows user context. Limits offline-decryption usefulness on modern installs |

## Change Log

**2026-05-03**

- Added `Resolve-TargetProfile` function. Detects elevation mismatch and prompts the operator to pick the correct target profile. Replaces direct use of `$env:USERPROFILE` / `$env:USERNAME` in `Copy-UserData` with `$Script:TargetHome` / `$Script:TargetUser`. See [Target Profile Resolution](#target-profile-resolution).
- Added `Clear-HiddenSystemAttrs` helper. Strips Hidden and System attributes from Recycle Bin destination directories post-copy so the contents are browsable in Explorer (Robocopy `/A-:SH` only acts on files, not directories).

**2026-04-29**

- Initial documented version. Captures Desktop, Documents, Downloads, Pictures, Music, browser User Data folders (Edge / Chrome / Brave / Firefox), OneDrive sync roots (excluding cloud-only placeholders), Sage data from common locations, and Recycle Bins from all fixed drives.
- NVMe-tuned Robocopy options (`/MT:32 /J`).
- Pre-flight process check for browsers and OneDrive with operator pause.
- Destination drive guard for the Recycle Bin loop.

## References

- Robocopy command-line reference: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy
- Robocopy exit codes: https://learn.microsoft.com/en-us/troubleshoot/windows-server/backup-and-storage/return-codes-used-robocopy-utility
- Win32_LogicalDisk DriveType values: https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-logicaldisk
- Win32_ComputerSystem class (`UserName` property): https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-computersystem
- About environment variables in PowerShell: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_environment_variables
- User Account Control overview: https://learn.microsoft.com/en-us/windows/security/application-security/application-control/user-account-control/how-it-works
- WindowsIdentity.GetCurrent method: https://learn.microsoft.com/en-us/dotnet/api/system.security.principal.windowsidentity.getcurrent
- OneDrive Files On-Demand: https://support.microsoft.com/en-us/office/save-disk-space-with-onedrive-files-on-demand-for-windows-0e6860d3-d9f3-4971-b321-7092438fb38e
- Chromium User Data directory: https://chromium.googlesource.com/chromium/src/+/HEAD/docs/user_data_dir.md
- Mozilla Firefox profile contents: https://support.mozilla.org/en-US/kb/profiles-where-firefox-stores-user-data
- DPAPI overview: https://learn.microsoft.com/en-us/dotnet/standard/security/how-to-use-data-protection
- ForensiT User Profile Wizard (ProfWiz): https://www.forensit.com/user-profile-wizard.html
- ForensiT TransWiz: https://www.forensit.com/user-profile-transfer-wizard.html
- Microsoft USMT overview: https://learn.microsoft.com/en-us/windows/deployment/usmt/usmt-overview
