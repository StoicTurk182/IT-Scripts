# Rename-FoldersToTitleCase

Recursively renames all folders under a root directory to Title Case, handling both plain and hyphenated folder names. Safe for use on Git repositories when followed by a commit.

Script location (IT-Scripts repo): `Utils/FolderTools/Rename-FoldersToTitleCase.ps1`

## Quick Reference

```powershell
# Preview only - no changes made
.\Rename-FoldersToTitleCase.ps1 -RootPath "C:\IT-Scripts" -WhatIf

# Apply renames to all subfolders
.\Rename-FoldersToTitleCase.ps1 -RootPath "C:\IT-Scripts"

# Apply renames including the root folder itself
.\Rename-FoldersToTitleCase.ps1 -RootPath "C:\IT-Scripts" -IncludeRoot
```

## Why This Script Exists

Windows NTFS is case-insensitive, meaning it treats `rename-upn`, `Rename-UPN`, and `RENAME-UPN` as the same folder. A simple `Rename-Item` call with only a case change will fail or silently do nothing because the OS considers the source and destination identical.

This script handles that by routing every rename through a temporary name, forcing Windows to treat it as a genuine rename operation.

Additionally, because renaming a parent folder while iterating its children produces broken paths, the script processes directories deepest-first (sorted by path length, descending) before working back up the tree.

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-RootPath` | String | Yes | - | Root directory to start from |
| `-IncludeRoot` | Switch | No | False | Also rename the root folder itself |
| `-WhatIf` | Switch | No | False | Preview mode, no disk changes |

## Capitalisation Logic

Each folder name is processed word by word. Words are defined as sequences of letters (`[A-Za-z]+`). Hyphens and spaces are treated as word boundaries and are preserved in the output.

| Input | Output |
|-------|--------|
| `rename-upn` | `Rename-Upn` |
| `active directory` | `Active Directory` |
| `BACKUP-tools` | `Backup-Tools` |
| `hwh` | `Hwh` |
| `NetworkTools` | `Networktools` |
| `My Folder` | `My Folder` (skipped, already correct) |

Note: All-caps abbreviations (e.g. `UPN`, `HWH`) will be lowercased to `Upn`, `Hwh`. If you need to preserve specific casing conventions, rename those folders manually afterwards. The script will skip any folder whose name already matches the Title Case output exactly (case-sensitive comparison).

## Detailed Usage

### Step 1: Preview First

Always run with `-WhatIf` before applying. This shows every planned rename without touching the filesystem:

```powershell
.\Rename-FoldersToTitleCase.ps1 -RootPath "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts" -WhatIf
```

Output format:
```
[10:42:01] [WARNING] PREVIEW  rename-upn  ->  Rename-Upn
[10:42:01] [INFO]             C:\IT-Scripts\ActiveDirectory\rename-upn
[10:42:01] [SKIP]    Already correct: C:\IT-Scripts\ActiveDirectory\Migrate-Groups
```

### Step 2: Apply

Once the preview looks correct, run without `-WhatIf`:

```powershell
.\Rename-FoldersToTitleCase.ps1 -RootPath "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts"
```

### Step 3: Commit to Git (if applicable)

Windows renames are not automatically staged by Git. After the script completes, stage and commit manually:

```powershell
cd "C:\Users\Administrator\Andrew J IT Labs\IT-Scripts"
git add -A
git status
git commit -m "Chore: Rename folders to Title Case"
git push
```

Verify the renames are staged correctly with `git status` before committing. Git on Windows may require `core.ignorecase = false` in `.git/config` to detect case-only renames:

```powershell
git config core.ignorecase false
```

## Run from IT-Scripts Menu

To run directly from GitHub without downloading:

```powershell
iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Utils/FolderTools/Rename-FoldersToTitleCase.ps1")
```

Note: When run this way, the `-RootPath` prompt will appear interactively. Enter the full path when prompted. `-WhatIf` cannot be passed as a switch in this execution mode; download the script locally first if preview mode is needed.

## Adding to IT-Scripts Menu

```powershell
"Utilities" = @(
    # existing entries...
    @{ Name = "Rename Folders to Title Case"; Path = "Utils/FolderTools/Rename-FoldersToTitleCase.ps1"; Description = "Recursively rename folders to Title Case" }
)
```

## Edge Cases

### Folders with numbers or symbols

Numbers and non-letter characters (digits, underscores, dots) are not touched by the regex and pass through unchanged.

| Input | Output |
|-------|--------|
| `2024-reports` | `2024-Reports` |
| `v1.2_backup` | `V1.2_Backup` |
| `_internal` | `_Internal` |

### Nested folders

Subfolders are processed before their parents. Example:

```
IT-Scripts/
  active directory/          <- renamed second
    rename-upn/              <- renamed first
```

This ordering prevents a situation where renaming `active directory` to `Active Directory` would leave the script holding a stale path to `rename-upn`.

### Read-only or locked folders

If a folder is open in Explorer or locked by another process, `Rename-Item` will throw an access error. The script catches this, logs it as `[ERROR]`, and continues with remaining folders. Re-run after closing any open file handles.

### Git repository sensitivity

Git tracks file and folder names. If `core.ignorecase = true` (the Windows Git default), case-only renames may not be detected. Set `core.ignorecase = false` before committing renames:

```powershell
git config core.ignorecase false
git add -A
git status
```

Source: [Git documentation - core.ignoreCase](https://git-scm.com/docs/git-config#Documentation/git-config.txt-coreignoreCase)

## Troubleshooting

### Rename did nothing / folder name unchanged

The most likely cause is that `core.ignorecase` is `true` and Git is not detecting the case change. Set it to `false` and re-stage:

```powershell
git config core.ignorecase false
git add -A
git status
```

### Access denied error

The folder is in use. Close Explorer windows browsing inside the path, then re-run.

### Path not found mid-run

A parent folder was renamed before its children were processed. This should not occur because the script sorts deepest-first, but can happen if the folder tree was modified externally during the run. Re-run the script; already-correct folders will be skipped.

### Git shows renames as delete + add rather than rename

This is expected behaviour when `core.ignorecase = true` was set during the rename. The content is the same; only the presentation in `git log` differs. It does not affect functionality.

## References

- Rename-Item (PowerShell): https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/rename-item
- Get-ChildItem (PowerShell): https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-childitem
- Regex.Replace (.NET): https://learn.microsoft.com/en-us/dotnet/api/system.text.regularexpressions.regex.replace
- Git core.ignoreCase: https://git-scm.com/docs/git-config#Documentation/git-config.txt-coreignoreCase
- NTFS case sensitivity: https://learn.microsoft.com/en-us/windows/wsl/case-sensitivity
