#Requires -Version 5.1
<#
.SYNOPSIS
    Extracts every unique recipient SMTP address from one or more PST files
    exported from Microsoft Purview eDiscovery, producing a flat address list.

.DESCRIPTION
    Built for the Purview workflow where a search is scoped to from:<user>,
    so every exported item is mail the user sent. Reads To/Cc/Bcc from each
    message, resolves Exchange (EX) addresses to SMTP, de-duplicates, and
    writes addresses.txt (one per line) plus addresses.csv (name, address,
    count).

    Accepts a single .pst file OR a folder of split PSTs - Purview commonly
    splits large exports into multiple PST files.

    The live-mailbox path from earlier versions has been removed. Because the
    Purview query already restricts results to sent mail, the default scans
    every folder in the PST. Use -SentItemsOnly only if you exported a full
    mailbox without a from: filter and want to restrict to the Sent Items
    folder.

.PARAMETER PstPath
    Path to a .pst file, OR a folder containing one or more .pst files
    (searched recursively).

.PARAMETER OutputDir
    Where to write addresses.txt and addresses.csv. Defaults to Desktop.

.PARAMETER SentItemsOnly
    Restrict harvesting to a folder named "Sent Items". Off by default;
    only needed for an unfiltered full-mailbox export.

.PARAMETER ToRecipientsOnly
    Capture only To recipients, excluding Cc and Bcc. Off by default
    (captures To, Cc, and Bcc).

.EXAMPLE
    .\Get-SentRecipients.ps1 -PstPath "C:\Exports\andrew.pst"

.EXAMPLE
    .\Get-SentRecipients.ps1 -PstPath "C:\Exports\PurviewExport"
    Processes every .pst found under the export folder.

.EXAMPLE
    .\Get-SentRecipients.ps1 -PstPath "C:\Exports\andrew.pst" -ToRecipientsOnly

.NOTES
    Author: Andrew Jones
    Version: 3.0
    Date: 2026-06-11
    Run non-elevated, in the same user context as the Outlook profile.
    Requires classic (Win32) Outlook installed with a working profile.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PstPath,

    [string]$OutputDir = "$env:USERPROFILE\Desktop",

    [switch]$SentItemsOnly,

    [switch]$ToRecipientsOnly
)

# PR_SMTP_ADDRESS (ASCII). 0x39FE = identifier, 001E = PT_STRING8.
$PR_SMTP = "http://schemas.microsoft.com/mapi/proptag/0x39FE001E"
$olMail  = 43          # OlObjectClass.olMail
$olTo    = 1           # OlMailRecipientType.olTo

$collected    = @{}    # key = lowercased SMTP -> record
$scannedItems = 0

function Get-Smtp($entry, $fallback) {
    try {
        if ($entry -and $entry.Type -eq "EX") {
            $u = $entry.GetExchangeUser()
            if ($u -and $u.PrimarySmtpAddress) { return $u.PrimarySmtpAddress }
            try { return $entry.PropertyAccessor.GetProperty($PR_SMTP) } catch { return $fallback }
        }
        return $fallback
    } catch { return $fallback }
}

function Add-Addr($name, $smtp) {
    if ([string]::IsNullOrWhiteSpace($smtp) -or $smtp -notmatch '@') { return }
    $key = $smtp.ToLower().Trim()
    if ($collected.ContainsKey($key)) {
        $collected[$key].Count++
    } else {
        $collected[$key] = [pscustomobject]@{
            DisplayName = $name
            SmtpAddress = $smtp.Trim()
            Count       = 1
        }
    }
}

function Walk($folder, [bool]$sentOnly, [bool]$toOnly) {
    # With a from:<user> Purview export, every item is already sent mail, so
    # harvest from all folders. -SentItemsOnly narrows to the Sent Items folder
    # for the unfiltered full-mailbox case.
    $harvest = (-not $sentOnly) -or ($folder.Name -ieq "Sent Items")
    if ($harvest) {
        $items = $folder.Items
        for ($i = 1; $i -le $items.Count; $i++) {
            try { $it = $items.Item($i) } catch { continue }
            if ($it.Class -ne $olMail) { continue }
            $script:scannedItems++
            try {
                foreach ($r in $it.Recipients) {
                    if ($toOnly -and $r.Type -ne $olTo) { continue }
                    Add-Addr $r.Name (Get-Smtp $r.AddressEntry $r.Address)
                }
            } catch {}
        }
    }
    foreach ($sub in $folder.Folders) { Walk $sub $sentOnly $toOnly }
}

# --- Resolve PST list (single file or folder of split PSTs) ---
if (-not (Test-Path $PstPath)) { throw "Path not found: $PstPath" }

if ((Get-Item $PstPath).PSIsContainer) {
    $pstFiles = Get-ChildItem -Path $PstPath -Filter *.pst -File -Recurse |
                Select-Object -ExpandProperty FullName
    if (-not $pstFiles) { throw "No .pst files found under: $PstPath" }
} else {
    $pstFiles = @($PstPath)
}

# --- Connect to Outlook ---
$outlook = New-Object -ComObject Outlook.Application
$ns      = $outlook.GetNamespace("MAPI")

$sentOnly = [bool]$SentItemsOnly
$toOnly   = [bool]$ToRecipientsOnly

# --- Harvest each PST ---
foreach ($pst in $pstFiles) {
    Write-Host ("Processing: {0}" -f $pst) -ForegroundColor Cyan
    $root = $null
    try {
        $ns.AddStore($pst)
        $store = $ns.Stores | Where-Object { $_.FilePath -ieq $pst } | Select-Object -First 1
        if (-not $store) { Write-Warning "Could not locate attached PST: $pst"; continue }
        $root = $store.GetRootFolder()
        Walk $root $sentOnly $toOnly
    }
    catch {
        Write-Warning ("Failed on {0}: {1}" -f $pst, $_.Exception.Message)
    }
    finally {
        if ($root) {
            try { $ns.RemoveStore($root) }
            catch { Write-Warning "Detach the PST manually in Outlook: $pst" }
        }
    }
}

# --- Output ---
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
$txt = Join-Path $OutputDir "addresses.txt"
$csv = Join-Path $OutputDir "addresses.csv"

$sorted = $collected.Values | Sort-Object SmtpAddress
$sorted | Select-Object -ExpandProperty SmtpAddress | Set-Content -Path $txt -Encoding UTF8
$sorted | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host ("PSTs processed   : {0}" -f $pstFiles.Count) -ForegroundColor Cyan
Write-Host ("Messages scanned : {0}" -f $scannedItems)   -ForegroundColor Cyan
Write-Host ("Unique addresses : {0}" -f $sorted.Count)   -ForegroundColor Green
Write-Host ("Text list        : {0}" -f $txt)
Write-Host ("CSV list         : {0}" -f $csv)
if ($scannedItems -eq 0) {
    Write-Warning "No messages scanned. For a full-mailbox export omit -SentItemsOnly so all folders are scanned, or confirm the PST contains mail items."
}
