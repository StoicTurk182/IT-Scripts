param (
    [string]$BookmarkPath = '',
    [string]$BackupRoot   = ''
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# INTERACTIVE MODE - works via iex (irm ...) and direct run
# ============================================================================

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Bookmark Backup" -ForegroundColor Cyan
Write-Host "================================================`n" -ForegroundColor Cyan

if (-not $BookmarkPath) {
    $def = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Bookmarks"
    Write-Host "[1/2] Bookmark file to back up"
    Write-Host "      Default: $def"
    $i = (Read-Host "      Press Enter for default or paste path").Trim()
    $BookmarkPath = if ($i) { $i } else { $def }
}

if (-not $BackupRoot) {
    $def = "$env:USERPROFILE\OneDrive\DEV_OPS\IT-Scripts\Utils\Bookmark_mgmt\Backups"
    Write-Host "`n[2/2] Backup destination folder"
    Write-Host "      Default: $def"
    $i = (Read-Host "      Press Enter for default or paste path").Trim()
    $BackupRoot = if ($i) { $i } else { $def }
}

Write-Host ""

# ============================================================================
# BACKUP
# ============================================================================

if (-not (Test-Path $BookmarkPath)) {
    Write-Error "Source not found: $BookmarkPath"
    exit 1
}

if (-not (Test-Path $BackupRoot)) {
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    Write-Host "Created backup folder: $BackupRoot"
}

$timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupFile = Join-Path $BackupRoot "Bookmarks.backup-$timestamp"

Copy-Item -Path $BookmarkPath -Destination $backupFile -Force
Write-Host "Backup saved : $backupFile" -ForegroundColor Green

# ============================================================================
# RETENTION - keep last 10 backups, delete older ones
# ============================================================================

$allBackups = Get-ChildItem -Path $BackupRoot -Filter "Bookmarks.backup-*" |
              Sort-Object LastWriteTime -Descending

$retainCount = 10
if ($allBackups.Count -gt $retainCount) {
    $toDelete = $allBackups | Select-Object -Skip $retainCount
    foreach ($file in $toDelete) {
        Remove-Item $file.FullName -Force
        Write-Host "Pruned old backup : $($file.Name)" -ForegroundColor DarkGray
    }
}

Write-Host "`nBackup folder contains $([Math]::Min($allBackups.Count, $retainCount)) backup(s)."

# ============================================================================
# LIST CURRENT BACKUPS
# ============================================================================

Write-Host "`nCurrent backups (newest first):" -ForegroundColor Cyan
Get-ChildItem -Path $BackupRoot -Filter "Bookmarks.backup-*" |
    Sort-Object LastWriteTime -Descending |
    Select-Object Name, @{N='Size KB';E={[math]::Round($_.Length/1KB,1)}}, LastWriteTime |
    Format-Table -AutoSize

Write-Host "Done.`n"
