# Bug Fix: Get-DomainHealth.ps1 - Invalid Filename from URL Input

## Problem

When a full URL is passed as the domain target (e.g. `http://www.toast-group.com`), the script constructs an output filename that includes the raw URL string. Windows rejects this because `:` and `\` are illegal in file and directory names.

**Error output:**

```
Out-File: C:\...\IT-Scripts\NS Lookup Auto\Get-DomainHealth.ps1:712:15
Line |
 712 |      $report | Out-File -FilePath $filePath -Encoding UTF8
     |                ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | The filename, directory name, or volume label syntax is incorrect. :
     | '...\DomainHealth_http:\www-toast-group-com\_20260311_084551.md'
```

**Root cause:**

The filename was being generated from the raw input domain string, which still contained the `http://` protocol prefix. When dots were replaced with hyphens, the slashes and colon from the protocol remained, producing a path fragment like `http:\www-toast-group-com\` that Windows interprets as a drive-relative path with subdirectories.

Windows invalid filename characters: `\ / : * ? " < > |`

## Fix

Locate the section of `Get-DomainHealth.ps1` where `$filePath` is constructed (near or before line 712) and add a sanitization step to strip the protocol prefix and replace any remaining illegal characters before building the filename.

### Before (example pattern causing the bug)

```powershell
$safeDomain = $domain -replace '\.', '-'
$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$filePath   = Join-Path $OutputPath "DomainHealth_${safeDomain}_${timestamp}.md"
```

### After (fixed)

```powershell
# Strip protocol prefix (http:// or https://) before sanitizing
$safeDomain = $domain -replace '^https?://', ''

# Replace all Windows-illegal filename characters with underscores
$safeDomain = $safeDomain -replace '[\\/:*?"<>|]', '_'

# Replace dots with hyphens for readability (optional but consistent)
$safeDomain = $safeDomain -replace '\.', '-'

# Remove any trailing separator characters left behind
$safeDomain = $safeDomain.Trim('_-')

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$filePath  = Join-Path $OutputPath "DomainHealth_${safeDomain}_${timestamp}.md"
```

### Result

| Input | Old filename fragment | New filename fragment |
|---|---|---|
| `http://www.toast-group.com` | `DomainHealth_http:\www-toast-group-com\_...` | `DomainHealth_www-toast-group-com_...` |
| `https://toast-group.com` | `DomainHealth_https:\toast-group-com\_...` | `DomainHealth_toast-group-com_...` |
| `toast-group.com` | `DomainHealth_toast-group-com_...` (worked) | `DomainHealth_toast-group-com_...` |

The fix is backward-compatible — bare domain inputs without a protocol (e.g. `toast-group.com`) pass through the `-replace '^https?://', ''` step unchanged and produce the same output as before.

## Why the Script Still Reported SUCCESS

The `[SUCCESS]` log line appeared because the `Out-File` error was non-terminating. PowerShell continued execution after the failed write and the logging function evaluated `$?` or similar as true from a prior successful operation. The file was not actually written.

To catch this and surface a real failure, wrap the `Out-File` call:

```powershell
try {
    $report | Out-File -FilePath $filePath -Encoding UTF8 -ErrorAction Stop
    Write-Log "Report exported: $filePath" -Level SUCCESS
} catch {
    Write-Log "Failed to export report: $_" -Level ERROR
}
```

## Full Context: Line 712 Area

Typical pattern for the affected block after both fixes applied:

```powershell
# --- Sanitize domain for use in filename ---
$safeDomain = $Domain -replace '^https?://', ''
$safeDomain = $safeDomain -replace '[\\/:*?"<>|]', '_'
$safeDomain = $safeDomain -replace '\.', '-'
$safeDomain = $safeDomain.Trim('_-')

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$fileName  = "DomainHealth_${safeDomain}_${timestamp}.md"
$filePath  = Join-Path $OutputPath $fileName

try {
    $report | Out-File -FilePath $filePath -Encoding UTF8 -ErrorAction Stop
    Write-Log "Report exported: $filePath" -Level SUCCESS
} catch {
    Write-Log "Failed to export report: $($_.Exception.Message)" -Level ERROR
}
```

## References

- Microsoft Docs - Naming Files, Paths, and Namespaces: https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file
- PowerShell `Out-File`: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/out-file
- PowerShell `-replace` operator (regex): https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_comparison_operators
