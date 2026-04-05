param (
    [string]$BookmarkPath = '',
    [string]$BackupRoot   = ''
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# EDGE PROFILE DISCOVERY
# ============================================================================

function Get-EdgeBookmarkPath {
    $userDataRoot = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    if (-not (Test-Path $userDataRoot)) { Write-Warning "Edge User Data not found: $userDataRoot"; return $null }

    $profiles = Get-ChildItem $userDataRoot -Directory |
        Where-Object { Test-Path "$($_.FullName)\Bookmarks" } |
        ForEach-Object {
            $displayName = $_.Name
            $prefFile    = "$($_.FullName)\Preferences"
            if (Test-Path $prefFile) {
                try { $n = (Get-Content $prefFile -Raw | ConvertFrom-Json).profile.name; if ($n) { $displayName = $n } } catch {}
            }
            [PSCustomObject]@{ Index=0; FolderName=$_.Name; DisplayName=$displayName; FullPath="$($_.FullName)\Bookmarks" }
        } | Sort-Object FolderName

    if (-not $profiles -or $profiles.Count -eq 0) { Write-Warning "No Edge profiles with bookmarks found."; return $null }

    $i = 1; foreach ($p in $profiles) { $p.Index = $i++ }

    if ($profiles.Count -eq 1) {
        Write-Host "Profile : $($profiles[0].DisplayName) ($($profiles[0].FolderName))"
        return $profiles[0].FullPath
    }

    Write-Host "Edge profiles found:"
    foreach ($p in $profiles) { Write-Host ("  [{0}] {1,-30} {2}" -f $p.Index, $p.DisplayName, $p.FolderName) }
    Write-Host "  [C] Custom path`n"

    do {
        $sel = (Read-Host "  Select profile number (or C for custom)").Trim()
        if ($sel -match '^[Cc]$') {
            $custom = (Read-Host "  Paste full Bookmarks path").Trim()
            if (Test-Path $custom) { return $custom }
            Write-Warning "Path not found: $custom"; return $null
        }
        $match = $profiles | Where-Object { $_.Index -eq [int]$sel }
    } until ($match)

    Write-Host "  Selected: $($match.DisplayName) ($($match.FolderName))`n"
    return $match.FullPath
}

# ============================================================================
# INTERACTIVE MODE
# ============================================================================

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Bookmark Backup" -ForegroundColor Cyan
Write-Host "================================================`n" -ForegroundColor Cyan

if (-not $BookmarkPath) {
    Write-Host "[1/2] Select Edge profile to back up"
    $BookmarkPath = Get-EdgeBookmarkPath
    if (-not $BookmarkPath) { Write-Error "No bookmark file selected."; exit 1 }
}

if (-not $BackupRoot) {
    $def = "$env:USERPROFILE\OneDrive\DEV_OPS\IT-Scripts\Utils\Bookmark_mgmt\Backups"
    Write-Host "[2/2] Backup destination folder"
    Write-Host "      Default: $def"
    $i = (Read-Host "      Press Enter for default or paste path").Trim()
    $BackupRoot = if ($i) { $i } else { $def }
}

Write-Host ""

# ============================================================================
# BACKUP
# ============================================================================

if (-not (Test-Path $BookmarkPath)) { Write-Error "Source not found: $BookmarkPath"; exit 1 }

if (-not (Test-Path $BackupRoot)) {
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    Write-Host "Created backup folder: $BackupRoot"
}

$timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupFile = Join-Path $BackupRoot "Bookmarks.backup-$timestamp"

Copy-Item -Path $BookmarkPath -Destination $backupFile -Force
Write-Host "Backup saved : $backupFile" -ForegroundColor Green

# Retention - keep last 10
$allBackups = Get-ChildItem -Path $BackupRoot -Filter "Bookmarks.backup-*" | Sort-Object LastWriteTime -Descending
if ($allBackups.Count -gt 10) {
    foreach ($file in ($allBackups | Select-Object -Skip 10)) {
        Remove-Item $file.FullName -Force
        Write-Host "Pruned : $($file.Name)" -ForegroundColor DarkGray
    }
}

Write-Host "`nCurrent backups (newest first):" -ForegroundColor Cyan
Get-ChildItem -Path $BackupRoot -Filter "Bookmarks.backup-*" |
    Sort-Object LastWriteTime -Descending |
    Select-Object Name, @{N='Size KB';E={[math]::Round($_.Length/1KB,1)}}, LastWriteTime |
    Format-Table -AutoSize

Write-Host "Done.`n"
