# New-VaultSnapshot.ps1
# Phase 2 - Collection and INSERT to VaultWatch database
# Vault: C:\Users\Administrator\OneDrive\Obsidian

$VaultRoot    = "C:\Users\Administrator\OneDrive\Obsidian"
$SqlInstance  = "ORIONVI\SQLEXPRESS"
$SqlDatabase  = "VaultWatch"

# ============================================================================
# COLLECTION
# ============================================================================

$Snapshot = [System.Collections.Generic.List[PSCustomObject]]::new()

$Files = Get-ChildItem -Path $VaultRoot -Recurse -Filter "*.md" -File

foreach ($File in $Files) {

    $RelativePath = $File.FullName.Replace($VaultRoot, "").TrimStart("\")
    $FolderName   = Split-Path $File.DirectoryName -Leaf

    $LineCount = (Get-Content -Path $File.FullName -ErrorAction SilentlyContinue).Count
    if (-not $LineCount) { $LineCount = 0 }

    $FirstLine = Get-Content -Path $File.FullName -TotalCount 1 -ErrorAction SilentlyContinue
    $HasFrontMatter = ($FirstLine -eq "---")

    $Title = $null
    if ($HasFrontMatter) {
        $FrontMatterLines = Get-Content -Path $File.FullName -TotalCount 10 -ErrorAction SilentlyContinue
        $TitleLine = $FrontMatterLines | Where-Object { $_ -match "^title:" }
        if ($TitleLine) {
            $Title = $TitleLine -replace "^title:\s*", "" -replace '"', ""
            if ($Title.Trim() -eq "") { $Title = $null }
        }
    }

    # Sanitise CreatedTime - exclude bogus 1979 dates
    $CreatedTime = $File.CreationTime
    if ($CreatedTime.Year -lt 2000) { $CreatedTime = $null }

    $Snapshot.Add([PSCustomObject]@{
        FileName       = $File.Name
        RelativePath   = $RelativePath
        FolderName     = $FolderName
        SizeBytes      = $File.Length
        LineCount      = $LineCount
        CreatedTime    = $CreatedTime
        ModifiedTime   = $File.LastWriteTime
        HasFrontMatter = $HasFrontMatter
        Title          = $Title
    })
}

# ============================================================================
# SUMMARY
# ============================================================================

$TotalFiles  = $Snapshot.Count
$TotalSizeMB = [math]::Round(($Snapshot | Measure-Object SizeBytes -Sum).Sum / 1MB, 2)

Write-Host "`nVault Root   : $VaultRoot"
Write-Host "Total Files  : $TotalFiles"
Write-Host "Total Size   : $TotalSizeMB MB"
Write-Host "With FM      : $(($Snapshot | Where-Object { $_.HasFrontMatter }).Count)"
Write-Host "Without FM   : $(($Snapshot | Where-Object { -not $_.HasFrontMatter }).Count)"
Write-Host "`nConnecting to SQL Server..."

# ============================================================================
# DATABASE INSERT
# ============================================================================

try {
    # Open connection
    $ConnectionString = "Server=$SqlInstance;Database=$SqlDatabase;Integrated Security=True;TrustServerCertificate=True;"
    $Connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
    $Connection.Open()
    Write-Host "Connected to $SqlInstance\$SqlDatabase"

    # Insert SnapshotRuns header row and capture RunID
    $RunCmd = $Connection.CreateCommand()
    $RunCmd.CommandText = @"
INSERT INTO SnapshotRuns (VaultRoot, TotalFiles, TotalSizeMB)
VALUES (@VaultRoot, @TotalFiles, @TotalSizeMB);
SELECT SCOPE_IDENTITY();
"@
    $RunCmd.Parameters.AddWithValue("@VaultRoot",    $VaultRoot)    | Out-Null
    $RunCmd.Parameters.AddWithValue("@TotalFiles",   $TotalFiles)   | Out-Null
    $RunCmd.Parameters.AddWithValue("@TotalSizeMB",  $TotalSizeMB)  | Out-Null

    $RunID = [int]$RunCmd.ExecuteScalar()
    Write-Host "SnapshotRuns row inserted - RunID: $RunID"

    # Insert FileSnapshots rows
    $Inserted = 0

    foreach ($Row in $Snapshot) {

        $FileCmd = $Connection.CreateCommand()
        $FileCmd.CommandText = @"
INSERT INTO FileSnapshots
    (RunID, FileName, RelativePath, FolderName, SizeBytes, LineCount, CreatedTime, ModifiedTime, HasFrontMatter, Title)
VALUES
    (@RunID, @FileName, @RelativePath, @FolderName, @SizeBytes, @LineCount, @CreatedTime, @ModifiedTime, @HasFrontMatter, @Title);
"@
        $FileCmd.Parameters.AddWithValue("@RunID",          $RunID)              | Out-Null
        $FileCmd.Parameters.AddWithValue("@FileName",       $Row.FileName)       | Out-Null
        $FileCmd.Parameters.AddWithValue("@RelativePath",   $Row.RelativePath)   | Out-Null
        $FileCmd.Parameters.AddWithValue("@FolderName",     $Row.FolderName)     | Out-Null
        $FileCmd.Parameters.AddWithValue("@SizeBytes",      $Row.SizeBytes)      | Out-Null
        $FileCmd.Parameters.AddWithValue("@LineCount",      $Row.LineCount)      | Out-Null
        $FileCmd.Parameters.AddWithValue("@ModifiedTime",   $Row.ModifiedTime)   | Out-Null
        $FileCmd.Parameters.AddWithValue("@HasFrontMatter", [int]$Row.HasFrontMatter) | Out-Null

        # NULL handling for nullable columns
        if ($null -eq $Row.CreatedTime) {
            $FileCmd.Parameters.AddWithValue("@CreatedTime", [DBNull]::Value) | Out-Null
        } else {
            $FileCmd.Parameters.AddWithValue("@CreatedTime", $Row.CreatedTime) | Out-Null
        }

        if ($null -eq $Row.Title) {
            $FileCmd.Parameters.AddWithValue("@Title", [DBNull]::Value) | Out-Null
        } else {
            $FileCmd.Parameters.AddWithValue("@Title", $Row.Title) | Out-Null
        }

        $FileCmd.ExecuteNonQuery() | Out-Null
        $Inserted++
    }

    Write-Host "FileSnapshots rows inserted: $Inserted"
    Write-Host "`nSnapshot complete - RunID $RunID - $Inserted files recorded`n"

} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
} finally {
    if ($Connection.State -eq "Open") {
        $Connection.Close()
        Write-Host "Connection closed."
    }
}
