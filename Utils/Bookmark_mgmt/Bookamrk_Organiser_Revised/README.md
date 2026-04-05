# Bookmark Management Toolkit

A set of PowerShell scripts for auditing, cleaning, and organising Edge bookmarks.

---

## What This Toolkit Does

Most people accumulate hundreds of bookmarks over years. Many are dead links, duplicates of each other, or saved Google searches that serve no purpose. This toolkit:

1. Checks every bookmark to see if it still works
2. Removes confirmed dead links, duplicates, and junk
3. Sorts everything that survives into labelled folders automatically
4. Lets you manually override any folder assignment before the sort runs

---

## Files

| File | What It Does |
|------|-------------|
| `Check-Bookmarks-Parallel.ps1` | Checks all bookmarks in parallel and produces a CSV report |
| `Organise-Bookmarks.ps1` | Cleans and sorts bookmarks into folders, optionally using the CSV |
| `Export-BookmarksToHtml.ps1` | Exports the cleaned bookmarks to an HTML file for browser import |

---

## Requirements

- **Check-Bookmarks-Parallel.ps1** requires PowerShell 7 or later
- **Organise-Bookmarks.ps1** and **Export-BookmarksToHtml.ps1** work on PowerShell 5.1 or later
- Microsoft Edge must be fully closed before running the organiser or export scripts
- Internet access for the link checker

Check your PowerShell version:

```powershell
$PSVersionTable.PSVersion
```

If the Major version is less than 7, download PowerShell 7 from:
https://github.com/PowerShell/PowerShell/releases

---

## One-Time Setup

Run this once per PowerShell session before running any of the scripts. It allows scripts to execute without being blocked by Windows:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Set a variable pointing to your script folder so you do not have to type the full path every time:

```powershell
$base = "C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\Utils\Bookmark_mgmt\Bookamrk_Organiser_Revised"
```

---

## The Full Workflow

### Step 1 — Run the Audit

This checks every bookmark and saves a report. It runs 30 checks at a time in parallel so it is fast.

```powershell
& "$base\Check-Bookmarks-Parallel.ps1"
```

This produces a CSV file on your Desktop named something like:
```
bookmark-audit-20260404-1430.csv
```

The check takes roughly 30–90 seconds for a few hundred bookmarks.

---

### Step 2 — Review the CSV in Excel

Open the CSV. Each row is one bookmark. The important columns are:

| Column | What It Means |
|--------|--------------|
| `Outcome` | Whether the link works (see table below) |
| `Status` | The HTTP status code returned |
| `Name` | The bookmark display name |
| `URL` | The full URL |
| `Note` | Why it got that outcome |
| `FolderOverride` | **You fill this in** — type a folder name to move this bookmark somewhere specific |
| `DeleteFlag` | **You fill this in** — type `Y` to force this bookmark to be deleted |

#### Outcome Values

| Outcome | Meaning | Action |
|---------|---------|--------|
| `OK` | Link works | Kept automatically |
| `AUTH` | Requires login to access (e.g. Outlook, Intune, Tailscale) | Kept automatically — these are not dead |
| `RATELIMITED` | Site blocked the check but is alive | Kept automatically |
| `TIMEOUT` | Did not respond in time — could be dead or just slow | Review manually |
| `SERVER-ERROR` | Server responded with an error | Review manually |
| `DEAD` | Link is gone | Removed automatically |
| `ERROR` | Invalid URL or connection failed completely | Removed automatically |

#### Using FolderOverride

If a bookmark has been auto-sorted into the wrong folder, type the correct folder name in the `FolderOverride` column. Use any of the folder names listed in Step 3 below, or make up your own — any name you type will become a folder.

Example: a YouTube video about Cisco switches landed in `Video and Media Production`. Type `Networking and CCNA` in its `FolderOverride` cell.

#### Using DeleteFlag

If you want a bookmark deleted even though it showed as `AUTH` or `TIMEOUT`, type `Y` in its `DeleteFlag` cell. It will be removed in Step 3.

Save the CSV when you are done reviewing.

---

### Step 3 — Run the Organiser

Set variables for your paths:

```powershell
$base   = "C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\Utils\Bookmark_mgmt\Bookamrk_Organiser_Revised"
$script = "$base\Organise-Bookmarks.ps1"
$audit  = "$base\bookmark-audit-20260404-1430.csv"  # adjust filename to match your CSV
```

**Always preview first** — this shows you what will happen without changing anything:

```powershell
& $script -AuditCsv $audit -WhatIf
```

Read through the output. When you are happy with it, close Edge completely and run for real:

```powershell
& $script -AuditCsv $audit
```

The script will print every folder it creates and how many bookmarks went into each one.

---

### Step 4 — Verify in Edge

Open Edge. Check the Favourites bar. You should see the new folders.

If something looks wrong, restore from the automatic backup (see Rollback section below) and run again.

---

### Step 5 — Sync to Your Microsoft Account

The script modifies the local bookmarks file only. If you have Edge sync enabled with a Microsoft account, do this to push the clean bookmarks to the cloud:

1. Go to `edge://settings/profiles/sync`
2. Turn **Favourites** sync **off**
3. Close Edge
4. Run the organiser script (Step 3)
5. Open Edge — verify the folders look correct
6. Go back to `edge://settings/profiles/sync`
7. Click **Reset sync** at the bottom of the page — this clears the old cloud copy
8. Turn **Favourites** sync back **on**

Edge will now push your clean local bookmarks up to your Microsoft account. Other devices on the same account will receive the update.

---

## Folder Structure After Organising

The organiser creates these folders in your bookmark bar in this order:

| Folder | What Goes In It |
|--------|----------------|
| Microsoft 365 and Admin | Office 365, Exchange, SharePoint, admin portals |
| Intune and Endpoint Management | Intune, Autopilot, LAPS, Defender for Endpoint |
| Azure and Entra | Azure Portal, Entra ID |
| Microsoft Docs and Learn | learn.microsoft.com documentation |
| PowerShell and Scripting | PowerShell Gallery, scripting tools, Sophia Script |
| Networking and CCNA | Cisco, iPXE, subnetting guides, PXE boot resources |
| Security and Pentesting | Wireshark, Kali Linux, NetHunter |
| Homelab and Virtualisation | VMware, Docker, Cloudflare, Tailscale, NoMachine |
| EVE Online | zKillboard, DScan, Abyss Tracker, EVE tools |
| Programming and Development | Python, FutureCoders, JetBrains, GitHub repos |
| Video and Media Production | Adobe, After Effects, Premiere Pro resources |
| Gaming | Steam, Nexus Mods, FitGirl, piracy megathreads |
| Personal | Gmail, Amazon, weather, job sites |
| Tools and Utilities | Bitwarden, Rclone, Sysinternals, calculators |
| Uncategorised | Anything that did not match a rule |

Anything that lands in `Uncategorised` should be reviewed. You can add a `FolderOverride` in the CSV and re-run, or move items manually in Edge afterwards.

---

## Running Without an Audit CSV

If you just want to clean and organise without running the link checker first:

```powershell
& "$base\Organise-Bookmarks.ps1"
```

This will still remove the built-in list of confirmed dead URLs and pattern-matched junk (saved searches, chrome:// pages), deduplicate, and sort. It will not remove anything based on live HTTP checks.

---

## Removing Additional Outcome Types

By default only `DEAD` and `ERROR` outcomes are removed automatically. To also remove bookmarks that timed out:

```powershell
& $script -AuditCsv $audit -RemoveOutcomes DEAD,ERROR,TIMEOUT
```

To remove server errors as well:

```powershell
& $script -AuditCsv $audit -RemoveOutcomes DEAD,ERROR,TIMEOUT,SERVER-ERROR
```

---

## Rollback

The organiser creates a timestamped backup every time it runs before touching anything. If something goes wrong, restore it:

```powershell
# List available backups
$bookmarkDir = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
Get-ChildItem $bookmarkDir -Filter "Bookmarks.backup-*" | Sort-Object LastWriteTime -Descending

# Restore the most recent backup (close Edge first)
$latest = Get-ChildItem $bookmarkDir -Filter "Bookmarks.backup-*" |
          Sort-Object LastWriteTime -Descending |
          Select-Object -First 1

Copy-Item $latest.FullName "$bookmarkDir\Bookmarks" -Force
Write-Host "Restored from: $($latest.Name)"
```

---

## Exporting to HTML

To generate a standard browser import file from your current (already organised) bookmarks:

```powershell
& "$base\Export-BookmarksToHtml.ps1"
```

This produces an HTML file on your Desktop that can be imported into Edge, Chrome, Firefox, or any Chromium browser via their built-in import function.

To import in Edge: `Ctrl+Shift+O` > three-dot menu > Import favourites > Favourites or bookmarks HTML file.

---

## Common Problems

**Script not found**

You are not pointing at the right path. Run this to find the scripts:

```powershell
Get-ChildItem -Path $env:USERPROFILE -Recurse -Filter "Organise-Bookmarks.ps1" -ErrorAction SilentlyContinue
```

**Script will not run — execution policy error**

Run this first:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

**Bookmarks reverted after opening Edge**

Edge sync overwrote your changes. Follow Step 5 above — you need to disable sync, run the script, then reset sync before re-enabling.

**Everything landed in Uncategorised**

The URL pattern rules did not match. Open the audit CSV, fill in the `FolderOverride` column for those rows, and re-run the organiser. You can also edit the `$CategoryRules` section in the organiser script to add new patterns permanently.

**Link checker gives wrong results**

Some sites block automated checks even when they are alive. `AUTH` results are almost always alive (login-protected portals). `TIMEOUT` results are ambiguous — the site may be alive but slow. Only `DEAD` and `ERROR` are removed automatically for this reason.

---

## References

- PowerShell 7 download: https://github.com/PowerShell/PowerShell/releases
- Edge sync settings: `edge://settings/profiles/sync`
- Edge sync internals (diagnostic): `edge://sync-internals/`
- Chromium bookmark format: https://chromium.googlesource.com/chromium/src/+/refs/heads/main/components/bookmarks/browser/bookmark_codec.cc