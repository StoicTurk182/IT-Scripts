# Export-VaultReport.ps1
# Phase 4 - Generate markdown diff report and write to Obsidian vault root
# Database: VaultWatch on ORIONVI\SQLEXPRESS

$SqlInstance = "ORIONVI\SQLEXPRESS"
$SqlDatabase = "VaultWatch"
$VaultRoot   = "C:\Users\Administrator\OneDrive\Obsidian"
$ReportDate  = Get-Date -Format "yyyy-MM-dd"
$ReportTime  = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
$OutputPath  = "$VaultRoot\VAULTWATCH-REPORT-$ReportDate.md"

try {
    # ============================================================================
    # CONNECTION
    # ============================================================================

    $ConnectionString = "Server=$SqlInstance;Database=$SqlDatabase;Integrated Security=True;TrustServerCertificate=True;"
    $Connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
    $Connection.Open()
    Write-Host "Connected to $SqlInstance\$SqlDatabase"

    # ============================================================================
    # GET TWO MOST RECENT RUN IDs
    # ============================================================================

    $RunCmd = $Connection.CreateCommand()
    $RunCmd.CommandText = "SELECT TOP 2 RunID, RunTimestamp, TotalFiles, TotalSizeMB FROM SnapshotRuns ORDER BY RunID DESC;"
    $RunReader = $RunCmd.ExecuteReader()

    $Runs = [System.Collections.Generic.List[PSCustomObject]]::new()
    while ($RunReader.Read()) {
        $Runs.Add([PSCustomObject]@{
            RunID        = $RunReader["RunID"]
            RunTimestamp = $RunReader["RunTimestamp"]
            TotalFiles   = $RunReader["TotalFiles"]
            TotalSizeMB  = $RunReader["TotalSizeMB"]
        })
    }
    $RunReader.Close()

    if ($Runs.Count -lt 2) {
        Write-Host "ERROR: Not enough snapshots to compare." -ForegroundColor Red
        exit
    }

    $RunB = $Runs[0]
    $RunA = $Runs[1]

    Write-Host "Comparing RunID $($RunA.RunID) vs RunID $($RunB.RunID)"

    # ============================================================================
    # DIFF QUERY
    # ============================================================================

    $DiffCmd = $Connection.CreateCommand()
    $DiffCmd.CommandText = @"
DECLARE @RunA INT = $($RunA.RunID);
DECLARE @RunB INT = $($RunB.RunID);

SELECT
    'MODIFIED'          AS ChangeType,
    b.FileName,
    b.RelativePath,
    b.FolderName,
    a.SizeBytes         AS SizeBytes_Before,
    b.SizeBytes         AS SizeBytes_After,
    a.LineCount         AS LineCount_Before,
    b.LineCount         AS LineCount_After,
    a.ModifiedTime      AS ModifiedTime_Before,
    b.ModifiedTime      AS ModifiedTime_After
FROM FileSnapshots a
JOIN FileSnapshots b
    ON  a.RelativePath = b.RelativePath
    AND a.RunID = @RunA
    AND b.RunID = @RunB
WHERE
    a.ModifiedTime <> b.ModifiedTime
    OR a.SizeBytes <> b.SizeBytes

UNION ALL

SELECT
    'ADDED'             AS ChangeType,
    b.FileName,
    b.RelativePath,
    b.FolderName,
    NULL                AS SizeBytes_Before,
    b.SizeBytes         AS SizeBytes_After,
    NULL                AS LineCount_Before,
    b.LineCount         AS LineCount_After,
    NULL                AS ModifiedTime_Before,
    b.ModifiedTime      AS ModifiedTime_After
FROM FileSnapshots b
WHERE b.RunID = @RunB
AND b.RelativePath NOT IN (
    SELECT RelativePath FROM FileSnapshots WHERE RunID = @RunA
)

UNION ALL

SELECT
    'DELETED'           AS ChangeType,
    a.FileName,
    a.RelativePath,
    a.FolderName,
    a.SizeBytes         AS SizeBytes_Before,
    NULL                AS SizeBytes_After,
    a.LineCount         AS LineCount_Before,
    NULL                AS LineCount_After,
    a.ModifiedTime      AS ModifiedTime_Before,
    NULL                AS ModifiedTime_After
FROM FileSnapshots a
WHERE a.RunID = @RunA
AND a.RelativePath NOT IN (
    SELECT RelativePath FROM FileSnapshots WHERE RunID = @RunB
)

ORDER BY ChangeType, RelativePath;
"@

    $DiffReader = $DiffCmd.ExecuteReader()
    $Changes = [System.Collections.Generic.List[PSCustomObject]]::new()

    while ($DiffReader.Read()) {
        $Changes.Add([PSCustomObject]@{
            ChangeType          = $DiffReader["ChangeType"]
            FileName            = $DiffReader["FileName"]
            RelativePath        = $DiffReader["RelativePath"]
            FolderName          = $DiffReader["FolderName"]
            SizeBytes_Before    = if ($DiffReader["SizeBytes_Before"]    -is [DBNull]) { $null } else { $DiffReader["SizeBytes_Before"] }
            SizeBytes_After     = if ($DiffReader["SizeBytes_After"]     -is [DBNull]) { $null } else { $DiffReader["SizeBytes_After"] }
            LineCount_Before    = if ($DiffReader["LineCount_Before"]    -is [DBNull]) { $null } else { $DiffReader["LineCount_Before"] }
            LineCount_After     = if ($DiffReader["LineCount_After"]     -is [DBNull]) { $null } else { $DiffReader["LineCount_After"] }
            ModifiedTime_Before = if ($DiffReader["ModifiedTime_Before"] -is [DBNull]) { $null } else { $DiffReader["ModifiedTime_Before"] }
            ModifiedTime_After  = if ($DiffReader["ModifiedTime_After"]  -is [DBNull]) { $null } else { $DiffReader["ModifiedTime_After"] }
        })
    }
    $DiffReader.Close()

    $Added    = ($Changes | Where-Object { $_.ChangeType -eq "ADDED"    }).Count
    $Deleted  = ($Changes | Where-Object { $_.ChangeType -eq "DELETED"  }).Count
    $Modified = ($Changes | Where-Object { $_.ChangeType -eq "MODIFIED" }).Count

    # ============================================================================
    # BUILD MARKDOWN REPORT
    # ============================================================================

    $SizeDelta = [math]::Round($RunB.TotalSizeMB - $RunA.TotalSizeMB, 2)
    $FileDelta = $RunB.TotalFiles - $RunA.TotalFiles
    $SizeDeltaStr = if ($SizeDelta -ge 0) { "+$SizeDelta MB" } else { "$SizeDelta MB" }
    $FileDeltaStr = if ($FileDelta -ge 0) { "+$FileDelta" } else { "$FileDelta" }

    $Report = [System.Text.StringBuilder]::new()

    # Front matter
    $Report.AppendLine("---") | Out-Null
    $Report.AppendLine("title: `"VaultWatch Report $ReportDate`"") | Out-Null
    $Report.AppendLine("created: $ReportTime") | Out-Null
    $Report.AppendLine("updated: $ReportTime") | Out-Null
    $Report.AppendLine("---") | Out-Null
    $Report.AppendLine("") | Out-Null

    # Title
    $Report.AppendLine("# VaultWatch Report - $ReportDate") | Out-Null
    $Report.AppendLine("") | Out-Null
    $Report.AppendLine("Automated vault diff report generated by VaultWatch. Compares the two most recent snapshots and surfaces file changes.") | Out-Null
    $Report.AppendLine("") | Out-Null

    # Snapshot summary table
    $Report.AppendLine("## Snapshot Comparison") | Out-Null
    $Report.AppendLine("") | Out-Null
    $Report.AppendLine("| | Snapshot A | Snapshot B |") | Out-Null
    $Report.AppendLine("|---|---|---|") | Out-Null
    $Report.AppendLine("| RunID | $($RunA.RunID) | $($RunB.RunID) |") | Out-Null
    $Report.AppendLine("| Timestamp | $($RunA.RunTimestamp) | $($RunB.RunTimestamp) |") | Out-Null
    $Report.AppendLine("| Total Files | $($RunA.TotalFiles) | $($RunB.TotalFiles) ($FileDeltaStr) |") | Out-Null
    $Report.AppendLine("| Total Size | $($RunA.TotalSizeMB) MB | $($RunB.TotalSizeMB) MB ($SizeDeltaStr) |") | Out-Null
    $Report.AppendLine("") | Out-Null

    # Diff summary table
    $Report.AppendLine("## Change Summary") | Out-Null
    $Report.AppendLine("") | Out-Null
    $Report.AppendLine("| Change Type | Count |") | Out-Null
    $Report.AppendLine("|---|---|") | Out-Null
    $Report.AppendLine("| Added | $Added |") | Out-Null
    $Report.AppendLine("| Deleted | $Deleted |") | Out-Null
    $Report.AppendLine("| Modified | $Modified |") | Out-Null
    $Report.AppendLine("| Total | $($Changes.Count) |") | Out-Null
    $Report.AppendLine("") | Out-Null

    if ($Changes.Count -eq 0) {
        $Report.AppendLine("No changes detected between Snapshot A and Snapshot B.") | Out-Null
        $Report.AppendLine("") | Out-Null
    }

    # Added files
    if ($Added -gt 0) {
        $Report.AppendLine("## Added Files") | Out-Null
        $Report.AppendLine("") | Out-Null
        $Report.AppendLine("| File | Folder | Size (bytes) | Lines |") | Out-Null
        $Report.AppendLine("|---|---|---|---|") | Out-Null
        foreach ($Row in ($Changes | Where-Object { $_.ChangeType -eq "ADDED" })) {
            $Report.AppendLine("| $($Row.FileName) | $($Row.FolderName) | $($Row.SizeBytes_After) | $($Row.LineCount_After) |") | Out-Null
        }
        $Report.AppendLine("") | Out-Null
    }

    # Deleted files
    if ($Deleted -gt 0) {
        $Report.AppendLine("## Deleted Files") | Out-Null
        $Report.AppendLine("") | Out-Null
        $Report.AppendLine("| File | Folder | Size (bytes) | Lines |") | Out-Null
        $Report.AppendLine("|---|---|---|---|") | Out-Null
        foreach ($Row in ($Changes | Where-Object { $_.ChangeType -eq "DELETED" })) {
            $Report.AppendLine("| $($Row.FileName) | $($Row.FolderName) | $($Row.SizeBytes_Before) | $($Row.LineCount_Before) |") | Out-Null
        }
        $Report.AppendLine("") | Out-Null
    }

    # Modified files
    if ($Modified -gt 0) {
        $Report.AppendLine("## Modified Files") | Out-Null
        $Report.AppendLine("") | Out-Null
        $Report.AppendLine("| File | Folder | Size Before | Size After | Lines Before | Lines After |") | Out-Null
        $Report.AppendLine("|---|---|---|---|---|---|") | Out-Null
        foreach ($Row in ($Changes | Where-Object { $_.ChangeType -eq "MODIFIED" })) {
            $Report.AppendLine("| $($Row.FileName) | $($Row.FolderName) | $($Row.SizeBytes_Before) | $($Row.SizeBytes_After) | $($Row.LineCount_Before) | $($Row.LineCount_After) |") | Out-Null
        }
        $Report.AppendLine("") | Out-Null
    }

    # Footer
    $Report.AppendLine("---") | Out-Null
    $Report.AppendLine("") | Out-Null
    $Report.AppendLine("Generated by VaultWatch on $ReportTime") | Out-Null

    # ============================================================================
    # WRITE REPORT
    # ============================================================================

    $Report.ToString() | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Host "Report written to: $OutputPath"

} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
} finally {
    if ($Connection.State -eq "Open") {
        $Connection.Close()
        Write-Host "Connection closed."
    }
}
