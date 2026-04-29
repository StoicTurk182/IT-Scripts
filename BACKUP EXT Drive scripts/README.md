---
title: "Backup UserData Simple"
created: 2026-04-29T14:35:05
updated: 2026-04-29T14:35:05
---

# Backup-UserData-Simple

Single-user data preservation script for pre-reimage and pre-swap workflows. Runs from an external drive plugged into a live target machine and copies the running user's standard folders, browser profiles, OneDrive sync roots, Sage data, and Recycle Bins from every fixed drive into a labelled folder structure on the external drive. Robocopy options are tuned for NVMe-over-USB destinations.

This is the simpler counterpart to the multi-profile `Backup-UserData.ps1`. Use it for routine TransWiz-style migrations where the profile state is being handled separately and the script's job is purely to grab raw data into a predictable folder layout.

**Table of Contents**

1. [Prerequisites](#prerequisites)
2. [Usage](#usage)
3. [What Gets Captured](#what-gets-captured)
4. [What Is Not Captured](#what-is-not-captured)
5. [Output Structure](#output-structure)
6. [Robocopy Options](#robocopy-options)
7. [Behaviour Notes](#behaviour-notes)
8. [Known Limitations](#known-limitations)
9. [References](#references)

## Prerequisites

| Requirement | Reason |
|-------------|--------|
| Windows 10 or 11 with PowerShell 5.1+ | Built-in Robocopy and PowerShell |
| External drive formatted NTFS or exFAT | FAT32 fails on files larger than 4 GB and on long paths |
| Free space on destination >= source data size | No pre-flight size check is performed |
| Local Administrator (recommended) | Enables Robocopy `/B` (backup mode) for locked-file handling and reading other users' SID folders inside `$Recycle.Bin` |

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
7. Wait for completion.
8. Review `<Drive>:\<HOSTNAME>_<label>_<DDMMYYYY>\Backup_Log.txt`.

## What Gets Captured

| Subfolder | Source | Notes |
|-----------|--------|-------|
| Desktop | `%USERPROFILE%\Desktop` | |
| Documents | `%USERPROFILE%\Documents` | |
| Download | `%USERPROFILE%\Downloads` | Folder is `Download` (singular); source is `Downloads` |
| Pictures | `%USERPROFILE%\Pictures` | |
| Music | `%USERPROFILE%\Music` | |
| Browser\Edge | `%LocalAppData%\Microsoft\Edge\User Data` | Cache directories excluded |
| Browser\Chrome | `%LocalAppData%\Google\Chrome\User Data` | As above |
| Browser\Brave | `%LocalAppData%\BraveSoftware\Brave-Browser\User Data` | As above |
| Browser\Firefox | `%AppData%\Mozilla\Firefox` | As above |
| Unsynced_Onedrive\\<name\> | Each `%USERPROFILE%\OneDrive*` folder | Cloud-only placeholders skipped |
| Sage\\<location\> | `C:\ProgramData\Sage\Accounts`, `Documents\Sage`, `Public Documents\Sage` | Best-guess paths; folder only created if data found |
| RecycleBin\\<letter\> | `<DriveLetter>:\$Recycle.Bin` for each fixed drive | Destination drive itself is skipped |

## What Is Not Captured

The script is deliberately scoped. The following are out of scope and require either the multi-profile `Backup-UserData.ps1` or a profile migration tool such as TransWiz / USMT:

- Other user profiles on the machine (single-user only — script captures the user it runs as)
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
| /A-:SH | Recycle Bin | Strips System+Hidden attributes on the destination so the folder is browsable in Explorer |

## Behaviour Notes

**Pre-flight process check.** Before the folder structure is created, `Initialize-BackupFolderStructure` checks for `msedge`, `chrome`, `brave`, `opera`, `vivaldi`, `firefox`, and `OneDrive` processes. If any are running it lists them and pauses with `Read-Host`. The intent is to give the operator a hard checkpoint to close browsers and pause OneDrive sync — both common causes of `Exit=9` errors that even `/B` cannot fully resolve.

**Destination drive guard.** The Recycle Bin loop derives the destination drive letter from `$RootPath` and skips it. Without this, the script would attempt to copy the destination drive's `$Recycle.Bin` folder into itself, producing recursive nesting. The skip is logged as `[-] Skip RecycleBin-<letter>: destination drive` so it remains auditable.

**Robocopy exit codes.** Exit codes 0-7 are success states (0 = nothing to copy, 1 = files copied, 2 = extras detected, etc., bitwise combined). Exit codes 8+ indicate errors. The `Invoke-Robo` helper logs `[+] Done` for exit < 8 and `[!] Errors` for exit >= 8 with a pointer to the per-source log.

**Recycle Bin contents.** Files captured under `RecycleBin\<letter>\` are stored as Windows expects internally: `S-1-5-21-...` SID folders containing `$I<random>` (metadata) and `$R<random>` (file data) pairs. They are not directly restorable as a working Recycle Bin on the destination — a parser tool is required to map them back to original filenames.

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

## References

- Robocopy command-line reference: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy
- Robocopy exit codes: https://learn.microsoft.com/en-us/troubleshoot/windows-server/backup-and-storage/return-codes-used-robocopy-utility
- Win32_LogicalDisk DriveType values: https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-logicaldisk
- OneDrive Files On-Demand: https://support.microsoft.com/en-us/office/save-disk-space-with-onedrive-files-on-demand-for-windows-0e6860d3-d9f3-4971-b321-7092438fb38e
- Chromium User Data directory: https://chromium.googlesource.com/chromium/src/+/HEAD/docs/user_data_dir.md
- Mozilla Firefox profile contents: https://support.mozilla.org/en-US/kb/profiles-where-firefox-stores-user-data
- DPAPI overview: https://learn.microsoft.com/en-us/dotnet/standard/security/how-to-use-data-protection
- ForensiT User Profile Wizard (ProfWiz): https://www.forensit.com/user-profile-wizard.html
- ForensiT TransWiz: https://www.forensit.com/user-profile-transfer-wizard.html
- Microsoft USMT overview: https://learn.microsoft.com/en-us/windows/deployment/usmt/usmt-overview
