# Complete Obsidian Vault Cleanup Script (FIXED)
$vaultPath = "C:\Users\Administrator\OneDrive\Obsidian\Informal Notes"

Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   Obsidian Vault Cleanup Utility" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════`n" -ForegroundColor Cyan

Write-Host "Vault: $vaultPath`n" -ForegroundColor Gray

# ========================================
# Part 1: Find Empty Notes
# ========================================

Write-Host "[1/3] Scanning for empty notes..." -ForegroundColor Yellow

$emptyNotes = Get-ChildItem -Path $vaultPath -Filter "*.md" -Recurse | Where-Object {
    $_.Directory.Name -ne ".obsidian" -and $_.Directory.Name -ne "Templates"
} | Where-Object {
    try {
        $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
        
        if ([string]::IsNullOrWhiteSpace($content)) {
            return $true
        }
        
        $contentNoYaml = $content -replace '(?s)^---.*?---\s*', ''
        
        if ($contentNoYaml.Trim().Length -lt 30) {
            return $true
        }
        
        return $false
    } catch {
        return $false
    }
}

Write-Host "   Found: $($emptyNotes.Count) empty notes" -ForegroundColor Cyan

# ========================================
# Part 2: Find Broken Links
# ========================================

Write-Host "`n[2/3] Scanning for broken links..." -ForegroundColor Yellow

$allNotes = Get-ChildItem -Path $vaultPath -Filter "*.md" -Recurse | Where-Object {
    $_.Directory.Name -ne ".obsidian" -and $_.Directory.Name -ne "Templates"
}

$noteNames = @{}

foreach ($note in $allNotes) {
    $noteName = [System.IO.Path]::GetFileNameWithoutExtension($note.Name)
    $noteNames[$noteName] = $note.FullName
}

$brokenLinkDetails = @()
$brokenLinkFiles = @()
$totalBrokenLinks = 0

foreach ($note in $allNotes) {
    try {
        $content = Get-Content $note.FullName -Raw -ErrorAction SilentlyContinue
        
        # Skip if content is null or empty
        if ([string]::IsNullOrWhiteSpace($content)) {
            continue
        }
        
        $links = [regex]::Matches($content, '\[\[([^\]]+)\]\]')
        $brokenCount = 0
        $brokenInThisFile = @()
        
        foreach ($link in $links) {
            $linkText = $link.Groups[1].Value -replace '\|.*$', '' -replace '#.*$', ''
            $linkText = $linkText.Trim()
            
            if (-not [string]::IsNullOrWhiteSpace($linkText) -and -not $noteNames.ContainsKey($linkText)) {
                $brokenCount++
                $brokenInThisFile += $linkText
            }
        }
        
        if ($brokenCount -gt 0) {
            $brokenLinkFiles += $note.Name
            $totalBrokenLinks += $brokenCount
            $brokenLinkDetails += [PSCustomObject]@{
                File = $note.Name
                BrokenLinks = $brokenInThisFile
                Count = $brokenCount
            }
        }
    } catch {
        Write-Host "   Warning: Could not process $($note.Name)" -ForegroundColor Yellow
    }
}

Write-Host "   Found: $totalBrokenLinks broken links in $($brokenLinkFiles.Count) files" -ForegroundColor Cyan

# ========================================
# Part 3: Find Empty Folders
# ========================================

Write-Host "`n[3/3] Scanning for empty folders..." -ForegroundColor Yellow

$emptyFolders = Get-ChildItem -Path $vaultPath -Directory -Recurse | Where-Object {
    $_.Name -ne ".obsidian" -and
    $_.Name -ne "Templates" -and
    (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue).Count -eq 0
}

Write-Host "   Found: $($emptyFolders.Count) empty folders" -ForegroundColor Cyan

# ========================================
# Summary Report
# ========================================

Write-Host "`n═══════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   Cleanup Summary" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════`n" -ForegroundColor Cyan

Write-Host "📋 Empty Notes: $($emptyNotes.Count)" -ForegroundColor Yellow
if ($emptyNotes.Count -gt 0) {
    foreach ($note in $emptyNotes | Select-Object -First 5) {
        Write-Host "   - $($note.Name)" -ForegroundColor Gray
    }
    if ($emptyNotes.Count -gt 5) {
        Write-Host "   ... and $($emptyNotes.Count - 5) more" -ForegroundColor Gray
    }
}

Write-Host "`n🔗 Broken Links: $totalBrokenLinks in $($brokenLinkFiles.Count) files" -ForegroundColor Yellow
if ($brokenLinkDetails.Count -gt 0) {
    foreach ($detail in $brokenLinkDetails | Select-Object -First 3) {
        Write-Host "`n   📄 $($detail.File) ($($detail.Count) broken links):" -ForegroundColor Cyan
        foreach ($link in $detail.BrokenLinks | Select-Object -First 5) {
            Write-Host "      ✗ [[" -NoNewline -ForegroundColor Red
            Write-Host "$link" -NoNewline -ForegroundColor Yellow
            Write-Host "]]" -ForegroundColor Red
        }
        if ($detail.BrokenLinks.Count -gt 5) {
            Write-Host "      ... and $($detail.BrokenLinks.Count - 5) more" -ForegroundColor Gray
        }
    }
    if ($brokenLinkDetails.Count -gt 3) {
        Write-Host "`n   ... and $($brokenLinkDetails.Count - 3) more files" -ForegroundColor Gray
    }
}

Write-Host "`n📁 Empty Folders: $($emptyFolders.Count)" -ForegroundColor Yellow
if ($emptyFolders.Count -gt 0) {
    foreach ($folder in $emptyFolders | Select-Object -First 5) {
        $relativePath = $folder.FullName.Replace($vaultPath, "").TrimStart('\')
        Write-Host "   - $relativePath" -ForegroundColor Gray
    }
    if ($emptyFolders.Count -gt 5) {
        Write-Host "   ... and $($emptyFolders.Count - 5) more" -ForegroundColor Gray
    }
}

# ========================================
# Cleanup Options
# ========================================

Write-Host "`n═══════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   Cleanup Actions" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════`n" -ForegroundColor Cyan

if ($emptyNotes.Count -gt 0) {
    Write-Host "Delete empty notes? (Y/N): " -NoNewline -ForegroundColor Yellow
    $deleteNotes = Read-Host
    
    if ($deleteNotes -eq 'Y' -or $deleteNotes -eq 'y') {
        foreach ($note in $emptyNotes) {
            Remove-Item $note.FullName -Force
            Write-Host "   ✓ Deleted: $($note.Name)" -ForegroundColor Green
        }
        Write-Host "`n✓ Deleted $($emptyNotes.Count) empty notes" -ForegroundColor Cyan
    }
}

if ($emptyFolders.Count -gt 0) {
    Write-Host "`nDelete empty folders? (Y/N): " -NoNewline -ForegroundColor Yellow
    $deleteFolders = Read-Host
    
    if ($deleteFolders -eq 'Y' -or $deleteFolders -eq 'y') {
        # Sort by depth (deepest first) to avoid errors
        $sortedFolders = $emptyFolders | Sort-Object { $_.FullName.Split('\').Count } -Descending
        foreach ($folder in $sortedFolders) {
            try {
                Remove-Item $folder.FullName -Force -Recurse -ErrorAction Stop
                Write-Host "   ✓ Deleted: $($folder.Name)" -ForegroundColor Green
            } catch {
                Write-Host "   ✗ Could not delete: $($folder.Name)" -ForegroundColor Red
            }
        }
        Write-Host "`n✓ Deleted $($emptyFolders.Count) empty folders" -ForegroundColor Cyan
    }
}

if ($brokenLinkDetails.Count -gt 0) {
    Write-Host "`n💡 Tip: Review broken links manually in Obsidian" -ForegroundColor Cyan
    Write-Host "   Some broken links may be intentional placeholders in templates" -ForegroundColor Gray
}

Write-Host "`n✓ Cleanup complete!`n" -ForegroundColor Cyan