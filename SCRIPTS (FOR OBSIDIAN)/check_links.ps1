# Check Broken Links in Real Documentation (Excluding Templates)
$vaultPath = "C:\Users\Administrator\OneDrive\Obsidian\Informal Notes"

Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   Real Documentation Broken Links" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════`n" -ForegroundColor Cyan

# Get all notes EXCEPT templates
$allNotes = Get-ChildItem -Path $vaultPath -Filter "*.md" -Recurse | Where-Object {
    $_.Directory.Name -ne ".obsidian" -and 
    $_.Directory.Name -ne "Templates" -and
    $_.Name -notlike "*-Template.md"
}

Write-Host "Scanning $($allNotes.Count) documentation files...`n" -ForegroundColor Gray

# Build list of all note names
$noteNames = @{}
foreach ($note in $allNotes) {
    $noteName = [System.IO.Path]::GetFileNameWithoutExtension($note.Name)
    $noteNames[$noteName] = $note.FullName
}

# Find broken links
$brokenLinkDetails = @()

foreach ($note in $allNotes) {
    try {
        $content = Get-Content $note.FullName -Raw -ErrorAction SilentlyContinue
        
        if ([string]::IsNullOrWhiteSpace($content)) {
            continue
        }
        
        $links = [regex]::Matches($content, '\[\[([^\]]+)\]\]')
        $brokenInThisFile = @()
        
        foreach ($link in $links) {
            $linkText = $link.Groups[1].Value -replace '\|.*$', '' -replace '#.*$', ''
            $linkText = $linkText.Trim()
            
            if (-not [string]::IsNullOrWhiteSpace($linkText) -and -not $noteNames.ContainsKey($linkText)) {
                $brokenInThisFile += $linkText
            }
        }
        
        if ($brokenInThisFile.Count -gt 0) {
            $brokenLinkDetails += [PSCustomObject]@{
                File = $note.Name
                FullPath = $note.FullName
                BrokenLinks = $brokenInThisFile
                Count = $brokenInThisFile.Count
            }
        }
    } catch {
        Write-Host "Warning: Could not process $($note.Name)" -ForegroundColor Yellow
    }
}

# Display results
if ($brokenLinkDetails.Count -eq 0) {
    Write-Host "✓ No broken links found in your documentation!" -ForegroundColor Green
    Write-Host "  (Templates were excluded from this scan)" -ForegroundColor Gray
} else {
    Write-Host "Found broken links in $($brokenLinkDetails.Count) files:`n" -ForegroundColor Yellow
    
    foreach ($detail in $brokenLinkDetails) {
        Write-Host "═══════════════════════════════════════" -ForegroundColor Gray
        Write-Host "📄 $($detail.File)" -ForegroundColor Cyan
        Write-Host "   Location: $($detail.FullPath)" -ForegroundColor Gray
        Write-Host "   Broken links: $($detail.Count)`n" -ForegroundColor Yellow
        
        foreach ($link in $detail.BrokenLinks) {
            Write-Host "   ✗ [[" -NoNewline -ForegroundColor Red
            Write-Host "$link" -NoNewline -ForegroundColor Yellow
            Write-Host "]]" -ForegroundColor Red
        }
        Write-Host ""
    }
    
    Write-Host "`n═══════════════════════════════════════" -ForegroundColor Gray
    Write-Host "💡 Recommendations:" -ForegroundColor Cyan
    Write-Host "   1. Create the missing notes" -ForegroundColor Gray
    Write-Host "   2. Fix the link names if misspelled" -ForegroundColor Gray
    Write-Host "   3. Remove the links if no longer needed" -ForegroundColor Gray
}

Write-Host "`n"