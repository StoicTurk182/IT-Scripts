---
title: "VaultWatch - Obsidian Vault Monitoring System"
created: 2026-04-14T00:00:00
updated: 2026-04-14T00:00:00
---

# VaultWatch - Obsidian Vault Monitoring System

Reference documentation for the VaultWatch project. Covers architecture, database schema, script reference, daily workflow, maintenance procedures, and known limitations. Built on PowerShell, SQL Server Express 2022, Python 3.14, and Flask with Chart.js.

**Table of Contents**

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [File and Folder Structure](#file-and-folder-structure)
4. [Database Reference](#database-reference)
   1. [SnapshotRuns Table](#snapshotruns-table)
   2. [FileSnapshots Table](#filesnapshots-table)
5. [Script Reference](#script-reference)
   1. [New-VaultSnapshot.ps1](#new-vaultsnapshotps1)
   2. [Compare-VaultSnapshots.ps1](#compare-vaultsnapshotsps1)
   3. [Export-VaultReport.ps1](#export-vaultreportps1)
   4. [app.py](#apppy)
6. [Daily Workflow](#daily-workflow)
7. [Dashboard Reference](#dashboard-reference)
8. [Known Limitations](#known-limitations)
9. [Maintenance Procedures](#maintenance-procedures)
   1. [Taking a Manual Snapshot](#taking-a-manual-snapshot)
   2. [Generating a Report](#generating-a-report)
   3. [Starting the Dashboard](#starting-the-dashboard)
   4. [Purging Old Snapshots](#purging-old-snapshots)
   5. [Backing Up the Database](#backing-up-the-database)
   6. [Verifying Database Health](#verifying-database-health)
   7. [Checking SQL Server Service Status](#checking-sql-server-service-status)
   8. [Restarting the SQL Server Service](#restarting-the-sql-server-service)
10. [Troubleshooting](#troubleshooting)
11. [Future Development - Phase 6](#future-development---phase-6)
12. [References](#references)

---

## Project Overview

VaultWatch is a local vault monitoring system for Obsidian. It takes point-in-time snapshots of all markdown files in the vault, stores the metadata in a SQL Server Express database, and provides two output mechanisms:

- A markdown diff report written directly to the vault root, readable in Obsidian
- A Flask web dashboard with Chart.js visualisations showing vault growth, folder distribution, largest files, and recent changes

The system was built as a practical learning project covering PowerShell loops and arrays, SQL Server schema design, T-SQL queries including JOINs and UNION ALL, Python Flask routing, and JavaScript Chart.js integration.

**Scope:** Markdown files only (`.md`). Attachments, images, PDFs, and other file types are excluded by design. The vault size metric therefore reflects markdown content only, not total vault storage consumption.

---

## Architecture

```
Obsidian Vault (C:\Users\Administrator\OneDrive\Obsidian)
        |
        | Get-ChildItem recursive, *.md filter
        v
New-VaultSnapshot.ps1
  - Loops all .md files
  - Extracts metadata and front matter fields
  - Inserts to SQL Server via System.Data.SqlClient
        |
        v
SQL Server Express 2022 (ORIONVI\SQLEXPRESS)
  Database: VaultWatch
  Tables: SnapshotRuns, FileSnapshots
        |
        |--- Compare-VaultSnapshots.ps1
        |       T-SQL diff (JOIN + UNION ALL)
        |       Returns change object array
        |
        |--- Export-VaultReport.ps1
        |       Calls diff logic
        |       Writes markdown report to vault root
        |
        |--- app.py (Flask)
                Four API endpoints serving JSON
                index.html renders Chart.js dashboard
                Accessible at http://127.0.0.1:5000
```

---

## File and Folder Structure

```
C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\ObsidianDbase\
├── New-VaultSnapshot.ps1
├── Compare-VaultSnapshots.ps1
├── Export-VaultReport.ps1
├── vault_snapshot_test.csv
└── dashboard\
    ├── app.py
    └── templates\
        └── index.html

C:\Users\Administrator\OneDrive\Obsidian\
└── VAULTWATCH-REPORT-YYYY-MM-DD.md
```

---

## Database Reference

**Instance:** `ORIONVI\SQLEXPRESS`
**Database:** `VaultWatch`
**Authentication:** Windows Authentication
**Connection String:** `Server=ORIONVI\SQLEXPRESS;Database=VaultWatch;Integrated Security=True;TrustServerCertificate=True;`

### SnapshotRuns Table

One row per execution of `New-VaultSnapshot.ps1`. Acts as the header record for each snapshot batch.

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| RunID | INT IDENTITY | No | Primary key, auto-increment |
| RunTimestamp | DATETIME2 | No | Date and time the snapshot was taken. Defaults to GETDATE(). |
| VaultRoot | NVARCHAR(500) | No | Full path to the vault root scanned |
| TotalFiles | INT | No | Total .md files found in that run |
| TotalSizeMB | DECIMAL(10,2) | No | Sum of all .md file sizes in MB |
| Notes | NVARCHAR(500) | Yes | Optional free-text note. Not currently populated by scripts. |

### FileSnapshots Table

One row per file per snapshot run. Foreign key to SnapshotRuns on RunID.

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| SnapshotID | INT IDENTITY | No | Primary key, auto-increment |
| RunID | INT | No | Foreign key to SnapshotRuns.RunID |
| FileName | NVARCHAR(500) | No | Filename including extension |
| RelativePath | NVARCHAR(500) | No | Path relative to vault root. Used as the stable identifier for diff comparisons. |
| FolderName | NVARCHAR(100) | No | Immediate parent folder name |
| SizeBytes | INT | No | File size in bytes |
| LineCount | INT | No | Total line count of the file |
| CreatedTime | DATETIME2 | Yes | File creation timestamp. Nullable because OneDrive and Git sync can corrupt this value. Files with a CreatedTime before year 2000 are stored as NULL. |
| ModifiedTime | DATETIME2 | No | Last modified timestamp. Primary diff signal. |
| HasFrontMatter | BIT | No | 1 if the file opens with ---, 0 otherwise |
| Title | NVARCHAR(200) | Yes | Title extracted from front matter. Nullable for files without front matter or with a blank title field. |

**Diff logic relies on:** `RelativePath` as the stable file identifier, `ModifiedTime` and `SizeBytes` as change signals. `CreatedTime` is stored for completeness but excluded from diff logic due to OneDrive sync timestamp unreliability.

---

## Script Reference

### New-VaultSnapshot.ps1

**Purpose:** Scans the vault and inserts a full snapshot into the database.

**Path:** `C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\ObsidianDbase\New-VaultSnapshot.ps1`

**Run:**
```powershell
& "C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\ObsidianDbase\New-VaultSnapshot.ps1"
```

**What it does:**
- Runs `Get-ChildItem` recursively on the vault root with `-Filter "*.md"`
- Loops through every file and builds a `PSCustomObject` with metadata
- Peeks at the first 10 lines of each file to extract the front matter title
- Sanitises `CreatedTime` — any timestamp before year 2000 is stored as NULL
- Inserts a `SnapshotRuns` header row and captures the returned `RunID`
- Inserts one `FileSnapshots` row per file using parameterised INSERT statements
- Closes the connection in a `finally` block

**Expected output:**
```
Vault Root   : C:\Users\Administrator\OneDrive\Obsidian
Total Files  : 541
Total Size   : 8.79 MB
With FM      : 527
Without FM   : 14
Connecting to SQL Server...
Connected to ORIONVI\SQLEXPRESS\VaultWatch
SnapshotRuns row inserted - RunID: N
FileSnapshots rows inserted: 541
Snapshot complete - RunID N - 541 files recorded
Connection closed.
```

---

### Compare-VaultSnapshots.ps1

**Purpose:** Diffs the two most recent snapshots and returns a change object array.

**Path:** `C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\ObsidianDbase\Compare-VaultSnapshots.ps1`

**Run:**
```powershell
& "C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\ObsidianDbase\Compare-VaultSnapshots.ps1"
```

**What it does:**
- Queries the two most recent RunIDs from `SnapshotRuns` automatically
- Runs a three-part UNION ALL T-SQL query:
  - MODIFIED: files present in both runs where `ModifiedTime` or `SizeBytes` differs
  - ADDED: files in RunB not present in RunA by `RelativePath`
  - DELETED: files in RunA not present in RunB by `RelativePath`
- Prints a summary to console
- Returns the change array for use by `Export-VaultReport.ps1`

Zero results is correct behaviour when no vault changes occurred between the two snapshots.

---

### Export-VaultReport.ps1

**Purpose:** Generates a markdown diff report and writes it to the vault root.

**Path:** `C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\ObsidianDbase\Export-VaultReport.ps1`

**Run:**
```powershell
& "C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\ObsidianDbase\Export-VaultReport.ps1"
```

**What it does:**
- Connects to the database and runs the same diff logic as `Compare-VaultSnapshots.ps1`
- Builds a markdown document using `System.Text.StringBuilder`
- Writes front matter matching the Obsidian vault standard (title, created, updated)
- Produces a snapshot comparison table, change summary table, and per-change-type detail tables
- Outputs to `C:\Users\Administrator\OneDrive\Obsidian\VAULTWATCH-REPORT-YYYY-MM-DD.md`

The output file appears in Obsidian immediately and is readable as a standard note. If a report for today already exists it is overwritten with the latest diff data.

---

### app.py

**Purpose:** Flask web application serving the VaultWatch dashboard.

**Path:** `C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\ObsidianDbase\dashboard\app.py`

**Run:**
```powershell
cd "C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\ObsidianDbase\dashboard"
python app.py
```

**Access:** `http://127.0.0.1:5000`

**Stop:** `Ctrl+C` in the terminal running `python app.py`

**API Endpoints:**

| Endpoint | Returns |
|----------|---------|
| `/` | Rendered dashboard HTML |
| `/api/vault-size-over-time` | All snapshot runs with timestamp, file count, and size |
| `/api/files-per-folder` | Top 15 folders by file count from latest snapshot |
| `/api/largest-files` | Top 10 largest files from latest snapshot |
| `/api/recent-changes` | Diff between two most recent snapshots |

---

## Daily Workflow

The recommended workflow for keeping VaultWatch current is two commands run in sequence.

**Step 1 - Take a snapshot:**
```powershell
& "C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\ObsidianDbase\New-VaultSnapshot.ps1"
```

**Step 2 - Generate the report:**
```powershell
& "C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\ObsidianDbase\Export-VaultReport.ps1"
```

The report appears in the vault root as `VAULTWATCH-REPORT-YYYY-MM-DD.md` and is immediately readable in Obsidian.

**Optional - View the dashboard:**
```powershell
cd "C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\ObsidianDbase\dashboard"
python app.py
```

Then open `http://127.0.0.1:5000` in a browser.

**Recommended snapshot frequency:** Once per active work session on the vault. More frequent snapshots produce more granular diff history and make the time-series charts more meaningful over weeks and months.

---

## Dashboard Reference

The dashboard at `http://127.0.0.1:5000` provides the following panels.

**Stat Cards (top row)**

| Card | Source | Notes |
|------|--------|-------|
| Total Files | SnapshotRuns.TotalFiles latest run | .md files only |
| Vault Size | SnapshotRuns.TotalSizeMB latest run | .md files only, not total vault storage |
| Latest Run | SnapshotRuns.RunID latest | Auto-increments each snapshot |
| Recent Changes | Count of diff rows between last two runs | 0 is correct when no changes occurred |

**Charts**

| Chart | Type | Data |
|-------|------|------|
| File Count Over Time | Line | All snapshot runs ordered by RunID |
| Vault Size Over Time | Line | All snapshot runs ordered by RunID |
| Files per Folder | Horizontal bar | Top 15 folders, latest snapshot |
| Largest Files | Horizontal bar | Top 10 by SizeBytes, latest snapshot |

**Tables**

| Table | Data |
|-------|------|
| Recent Changes | ADDED, DELETED, MODIFIED files between last two snapshots |
| Largest Files Detail | Full detail rows for top 10 largest files |

**Note on Vault Size metric:** The size figure reflects the sum of all `.md` file sizes only. It does not include attachments, images, PDFs, or other non-markdown content. The metric is consistent across all snapshots making it valid for trend comparison even though it does not represent total vault storage.

---

## Known Limitations

**Vault size is markdown only.** Total vault storage including attachments is not measured. This is by design — tracking only `.md` files keeps the diff signal clean and avoids noise from binary file changes.

**CreatedTime is unreliable.** OneDrive sync and Git operations can corrupt filesystem creation timestamps, producing dates in 1979 or other anomalous values. VaultWatch stores NULL for any `CreatedTime` before year 2000. `ModifiedTime` is the reliable change signal and is used for all diff logic.

**Renamed files appear as DELETED plus ADDED.** The diff logic uses `RelativePath` as the stable identifier. A file that is moved or renamed will appear as a deletion of the old path and an addition of the new path. There is no rename detection in the current implementation.

**OneDrive sync buffering.** OneDrive may buffer file write timestamps briefly before flushing to the filesystem. If a snapshot is taken immediately after editing a file, the `ModifiedTime` on disk may not yet reflect the change. Waiting 60 seconds after editing before snapshotting avoids this.

**Single vault support.** The diff logic does not filter by vault root. If the vault root path changes between runs the diff will report all files as deleted and re-added.

**No scheduled execution.** Snapshots are taken manually. Windows Task Scheduler can automate `New-VaultSnapshot.ps1` on a schedule if required.

**SQL Server Express 10GB limit.** At approximately 9MB of markdown per snapshot, this limit would not be reached for many years of daily snapshots.

---

## Maintenance Procedures

### Taking a Manual Snapshot

```powershell
& "C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\ObsidianDbase\New-VaultSnapshot.ps1"
```

Confirm the output shows the expected file count and a new RunID one higher than the previous run.

---

### Generating a Report

```powershell
& "C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\ObsidianDbase\Export-VaultReport.ps1"
```

The report file `VAULTWATCH-REPORT-YYYY-MM-DD.md` will appear in the vault root. If a report for today already exists it will be overwritten.

---

### Starting the Dashboard

```powershell
cd "C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\ObsidianDbase\dashboard"
python app.py
```

Open `http://127.0.0.1:5000` in a browser. Stop with `Ctrl+C`.

---

### Purging Old Snapshots

At 541 files per run, 365 daily snapshots produces approximately 197,000 rows. If purging is required, delete by RunID range:

```sql
-- Preview rows to be deleted
SELECT COUNT(*) FROM FileSnapshots WHERE RunID <= 10;

-- Delete FileSnapshots first (foreign key constraint)
DELETE FROM FileSnapshots WHERE RunID <= 10;

-- Then delete the run headers
DELETE FROM SnapshotRuns WHERE RunID <= 10;
```

Always delete `FileSnapshots` before `SnapshotRuns` due to the foreign key constraint on `RunID`.

---

### Backing Up the Database

From SSMS:

```sql
BACKUP DATABASE VaultWatch
TO DISK = 'C:\Backups\VaultWatch.bak'
WITH FORMAT, COMPRESSION, STATS = 10;
```

From PowerShell (requires SqlServer module):

```powershell
$Date       = Get-Date -Format "yyyyMMdd"
$BackupPath = "C:\Backups\VaultWatch_$Date.bak"

Invoke-Sqlcmd -ServerInstance "ORIONVI\SQLEXPRESS" -Query @"
BACKUP DATABASE VaultWatch
TO DISK = '$BackupPath'
WITH FORMAT, COMPRESSION, STATS = 10;
"@

Write-Host "Backup written to: $BackupPath"
```

Install the module if needed: `Install-Module SqlServer -Scope CurrentUser`

---

### Verifying Database Health

Run in SSMS against VaultWatch:

```sql
SELECT
    r.RunID,
    r.RunTimestamp,
    r.TotalFiles,
    r.TotalSizeMB,
    COUNT(f.SnapshotID) AS ActualFileRows
FROM SnapshotRuns r
LEFT JOIN FileSnapshots f ON r.RunID = f.RunID
GROUP BY r.RunID, r.RunTimestamp, r.TotalFiles, r.TotalSizeMB
ORDER BY r.RunID DESC;
```

`TotalFiles` should match `ActualFileRows` for every run. A mismatch indicates a partial insert.

---

### Checking SQL Server Service Status

```powershell
Get-Service -Name "MSSQL`$SQLEXPRESS" | Select-Object DisplayName, Status
```

---

### Restarting the SQL Server Service

```powershell
Restart-Service -Name "MSSQL`$SQLEXPRESS" -Force
```

Run as Administrator.

---

## Troubleshooting

**Snapshot script cannot connect to SQL Server**

Check the service is running:
```powershell
Get-Service -Name "MSSQL`$SQLEXPRESS"
```
If stopped:
```powershell
Start-Service -Name "MSSQL`$SQLEXPRESS"
```

**Dashboard shows no data or errors in browser console**

Confirm Flask is running and listening on port 5000. Check the terminal running `python app.py` for Python tracebacks. Most common cause is the SQL Server service not running.

**Zero changes on every diff**

Expected behaviour when no vault activity occurred between snapshots. If changes were made but are not detected, OneDrive sync buffering may be holding the `ModifiedTime` update. Wait 60 seconds after editing and re-snapshot.

**Renamed or moved files showing as DELETED and ADDED**

Correct behaviour. The diff uses `RelativePath` as the file identifier. A rename or move changes the path and appears as a deletion of the old entry and addition of the new one.

**Report file not appearing in Obsidian**

Check `Export-VaultReport.ps1` completed without errors. Confirm the output path exists on disk. OneDrive sync may delay the file appearing on other devices.

**1979 dates in CreatedTime**

Expected. These are OneDrive or Git sync artifacts. VaultWatch stores NULL for these values. They do not affect diff logic or reporting.

---

## Future Development - Phase 6

The following enhancements are candidates for future development:

- Scheduled snapshots via Windows Task Scheduler running `New-VaultSnapshot.ps1` on a daily or per-session basis
- Rename detection by correlating `CreatedTime` and `SizeBytes` between runs to identify likely renames rather than treating them as delete and add pairs
- Folder growth tracking by storing per-folder file counts and sizes in a summary table per run
- Dashboard date range filtering to scope time-series charts to a specific period
- Tailscale access to make the Flask dashboard accessible from other devices on the mesh
- Total vault size metric by running a secondary scan including all file types
- Hugo integration to publish the VaultWatch report directly as a Hugo blog post

---

## References

- Microsoft Docs - SQL Server Express: https://learn.microsoft.com/en-us/sql/sql-server/editions-and-components-of-sql-server-2022
- Microsoft Docs - System.Data.SqlClient: https://learn.microsoft.com/en-us/dotnet/api/system.data.sqlclient
- Microsoft Docs - T-SQL UNION ALL: https://learn.microsoft.com/en-us/sql/t-sql/language-elements/set-operators-union-transact-sql
- Flask Documentation: https://flask.palletsprojects.com/en/3.1.x/
- Chart.js Documentation: https://www.chartjs.org/docs/latest/
- pyodbc Documentation: https://github.com/mkleehammer/pyodbc/wiki
- Microsoft ODBC Driver for SQL Server: https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server
