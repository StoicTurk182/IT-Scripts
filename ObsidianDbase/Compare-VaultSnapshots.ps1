# Compare-VaultSnapshots.ps1
# Phase 3 - Diff the two most recent snapshots and return change objects
# Database: VaultWatch on ORIONVI\SQLEXPRESS

$SqlInstance = "ORIONVI\SQLEXPRESS"
$SqlDatabase = "VaultWatch"

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
    $RunCmd.CommandText = "SELECT TOP 2 RunID, RunTimestamp FROM SnapshotRuns ORDER BY RunID DESC;"
    $RunReader = $RunCmd.ExecuteReader()

    $Runs = [System.Collections.Generic.List[PSCustomObject]]::new()
    while ($RunReader.Read()) {
        $Runs.Add([PSCustomObject]@{
            RunID        = $RunReader["RunID"]
            RunTimestamp = $RunReader["RunTimestamp"]
        })
    }
    $RunReader.Close()

    if ($Runs.Count -lt 2) {
        Write-Host "ERROR: Not enough snapshots to compare. Run New-VaultSnapshot.ps1 at least twice." -ForegroundColor Red
        exit
    }

    $RunB = $Runs[0].RunID
    $RunA = $Runs[1].RunID

    Write-Host "Comparing RunID $RunA ($($Runs[1].RunTimestamp)) vs RunID $RunB ($($Runs[0].RunTimestamp))"

    # ============================================================================
    # DIFF QUERY
    # ============================================================================

    $DiffCmd = $Connection.CreateCommand()
    $DiffCmd.CommandText = @"
DECLARE @RunA INT = $RunA;
DECLARE @RunB INT = $RunB;

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
            ChangeType         = $DiffReader["ChangeType"]
            FileName           = $DiffReader["FileName"]
            RelativePath       = $DiffReader["RelativePath"]
            FolderName         = $DiffReader["FolderName"]
            SizeBytes_Before   = if ($DiffReader["SizeBytes_Before"]   -is [DBNull]) { $null } else { $DiffReader["SizeBytes_Before"] }
            SizeBytes_After    = if ($DiffReader["SizeBytes_After"]    -is [DBNull]) { $null } else { $DiffReader["SizeBytes_After"] }
            LineCount_Before   = if ($DiffReader["LineCount_Before"]   -is [DBNull]) { $null } else { $DiffReader["LineCount_Before"] }
            LineCount_After    = if ($DiffReader["LineCount_After"]    -is [DBNull]) { $null } else { $DiffReader["LineCount_After"] }
            ModifiedTime_Before = if ($DiffReader["ModifiedTime_Before"] -is [DBNull]) { $null } else { $DiffReader["ModifiedTime_Before"] }
            ModifiedTime_After  = if ($DiffReader["ModifiedTime_After"]  -is [DBNull]) { $null } else { $DiffReader["ModifiedTime_After"] }
        })
    }
    $DiffReader.Close()

    # ============================================================================
    # SUMMARY
    # ============================================================================

    $Added    = ($Changes | Where-Object { $_.ChangeType -eq "ADDED"    }).Count
    $Deleted  = ($Changes | Where-Object { $_.ChangeType -eq "DELETED"  }).Count
    $Modified = ($Changes | Where-Object { $_.ChangeType -eq "MODIFIED" }).Count

    Write-Host "`n--- Diff Summary ---"
    Write-Host "Added    : $Added"
    Write-Host "Deleted  : $Deleted"
    Write-Host "Modified : $Modified"
    Write-Host "Total    : $($Changes.Count)"

    if ($Changes.Count -gt 0) {
        Write-Host "`n--- Changes ---"
        $Changes | Format-Table ChangeType, FolderName, FileName, SizeBytes_Before, SizeBytes_After, LineCount_Before, LineCount_After -AutoSize
    } else {
        Write-Host "`nNo changes detected between RunID $RunA and RunID $RunB"
    }

    # Return change array for use by Export-VaultReport.ps1
    return $Changes

} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
} finally {
    if ($Connection.State -eq "Open") {
        $Connection.Close()
        Write-Host "`nConnection closed."
    }
}
