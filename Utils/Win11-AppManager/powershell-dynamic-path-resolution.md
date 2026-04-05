# PowerShell - Dynamic Path Resolution

Guide covering the correct method for resolving user-specific paths in PowerShell scripts that need to run portably across different machines, user accounts, and OneDrive-redirected environments.

---

## The Problem

Scripts that hardcode `$env:USERPROFILE\Desktop` as an output path will fail silently or with an error on machines where:

- The Desktop has been redirected to OneDrive (e.g. `C:\Users\andy\OneDrive - Andrew J IT Labs\Desktop`)
- The user profile is on a non-standard drive or path
- The script is running under a different user context than expected (e.g. running as Administrator while the working user is `andy`)
- The machine is in a roaming profile or VDI environment

### Example of the Failure

On a machine with OneDrive folder redirection enabled:

```
$env:USERPROFILE\Desktop = C:\Users\andy\Desktop   <-- does not exist
Actual Desktop            = C:\Users\andy\OneDrive - Andrew J IT Labs\Desktop
```

Any `Add-Content`, `Export-Csv`, or `Set-Content` call targeting `$env:USERPROFILE\Desktop` will throw a path not found error or write to a location the user cannot see.

This was discovered when `Win11-AppManager.ps1` failed to create its log file on a machine where the Desktop was OneDrive-redirected.

---

## The Fix

Use the Windows Shell API via `[Environment]::GetFolderPath()` instead of constructing paths manually from environment variables.

### Replace This

```powershell
$path = "$env:USERPROFILE\Desktop\output.csv"
```

### With This

```powershell
$path = "$([Environment]::GetFolderPath('Desktop'))\output.csv"
```

`[Environment]::GetFolderPath()` calls the Windows Shell directly and returns the actual resolved path for that folder, regardless of redirection, OneDrive sync state, or profile configuration.

---

## Common Folder References

| Folder | Unreliable Method | Correct Method |
|--------|------------------|----------------|
| Desktop | `$env:USERPROFILE\Desktop` | `[Environment]::GetFolderPath('Desktop')` |
| Documents | `$env:USERPROFILE\Documents` | `[Environment]::GetFolderPath('MyDocuments')` |
| Downloads | `$env:USERPROFILE\Downloads` | No Shell API equivalent — use `(New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path` |
| AppData Roaming | `$env:APPDATA` | `[Environment]::GetFolderPath('ApplicationData')` |
| AppData Local | `$env:LOCALAPPDATA` | `[Environment]::GetFolderPath('LocalApplicationData')` |
| Startup | Manual path | `[Environment]::GetFolderPath('Startup')` |
| Programs | Manual path | `[Environment]::GetFolderPath('Programs')` |
| System | `$env:SystemRoot\System32` | `[Environment]::GetFolderPath('System')` |

Full list of valid `SpecialFolder` enum values:

```powershell
[System.Environment+SpecialFolder] | Get-Member -Static -MemberType Property | Select-Object -ExpandProperty Name
```

---

## Bulk Patching Existing Scripts

To find all scripts in a repository that use the unreliable pattern:

```powershell
Get-ChildItem -Path ".\Utils" -Filter "*.ps1" -Recurse |
    Select-String -Pattern 'USERPROFILE\\Desktop'
```

To patch all instances in one pass:

```powershell
$files = Get-ChildItem -Path ".\Utils" -Filter "*.ps1" -Recurse |
    Select-String -Pattern 'USERPROFILE\\Desktop' |
    Select-Object -ExpandProperty Path -Unique

foreach ($file in $files) {
    $content = Get-Content $file -Raw
    $updated = $content -replace '\$env:USERPROFILE\\Desktop', '$([Environment]::GetFolderPath(''Desktop''))'
    Set-Content $file -Value $updated -Encoding UTF8
    Write-Host "Patched: $file"
}
```

Verify nothing remains:

```powershell
Get-ChildItem -Path ".\Utils" -Filter "*.ps1" -Recurse |
    Select-String -Pattern 'USERPROFILE\\Desktop'
```

No output means all instances have been patched.

---

## Scripts Updated

The following scripts in the IT-Scripts repository were patched during this session:

| Script | Line | Change |
|--------|------|--------|
| `Utils\Bookmark_mgmt\Check-Bookmarks-Parallel.ps1` | 92 | Desktop path for audit CSV output |
| `Utils\Bookmark_mgmt\Export-BookmarksToHtml.ps1` | 69 | Desktop path for HTML export output |
| `Utils\Bookmark_mgmt\Organise-Bookmarks.ps1` | 94 | Desktop path for cleanup report CSV |
| `Utils\TDR\Get-GPUTDRStatus.ps1` | 252 | Desktop path for TDR report CSV |
| `Utils\Win11-AppManager\Win11-AppManager.ps1` | 44 | Desktop path for app audit CSV and log |

Additionally, `Backup-Bookmarks.ps1` had a hardcoded OneDrive path for the backup destination:

```powershell
# Before
$def = "$env:USERPROFILE\OneDrive\DEV_OPS\IT-Scripts\Utils\Bookmark_mgmt\Backups"

# After
$def = "$([Environment]::GetFolderPath('MyDocuments'))\BookmarkBackups"
```

---

## Additional Guard - Output Folder Creation

When writing output files, always ensure the destination folder exists before attempting to write. This prevents silent failures when the resolved path points to a folder that has not yet been created or synced:

```powershell
$outputDir = Split-Path $ReportPath
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
```

This was added to `Win11-AppManager.ps1` before the log file initialisation block to prevent `Add-Content` from failing on first run.

---

## Why Not Just Use $env:USERPROFILE?

`$env:USERPROFILE` is reliable for the base profile path but the folder structure beneath it is not guaranteed. Windows allows individual known folders (Desktop, Documents, Downloads, Pictures etc.) to be redirected independently via:

- Group Policy folder redirection
- OneDrive Known Folder Move (KFM)
- Manual shell folder registration via registry

When any of these redirections are active, the physical path differs from the assumed path. The Shell API accounts for all of these redirections automatically because it reads from the same registry keys that Windows itself uses to resolve the paths.

---

## Checking the Actual Resolved Path on Any Machine

```powershell
# Print all common resolved paths
$folders = @('Desktop','MyDocuments','ApplicationData','LocalApplicationData','Startup','System')
foreach ($folder in $folders) {
    try {
        $path = [Environment]::GetFolderPath($folder)
        Write-Host ("{0,-25} : {1}" -f $folder, $path)
    } catch {
        Write-Host ("{0,-25} : ERROR - {1}" -f $folder, $_.Exception.Message) -ForegroundColor Red
    }
}
```

Run this on any machine to immediately see where each known folder actually resolves to.

---

## References

- .NET Environment.GetFolderPath: https://learn.microsoft.com/en-us/dotnet/api/system.environment.getfolderpath
- .NET SpecialFolder Enum: https://learn.microsoft.com/en-us/dotnet/api/system.environment.specialfolder
- OneDrive Known Folder Move: https://learn.microsoft.com/en-us/sharepoint/redirect-known-folders
- Windows Shell Known Folders: https://learn.microsoft.com/en-us/windows/win32/shell/known-folders
