# Update author in all Obsidian templates
# Location: C:\Scripts\Update-TemplateAuthor.ps1

$templatesPath = "C:\Users\Administrator\OneDrive\Obsidian\Informal Notes\Templates"
$newAuthor = "Andrew J Jones"  # Change this to update author name

Write-Host "Updating templates in: $templatesPath" -ForegroundColor Cyan
Write-Host "New author: $newAuthor`n" -ForegroundColor Green

Get-ChildItem -Path $templatesPath -Filter "*.md" | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    
    # Replace any existing author line
    if ($content -match 'author: .*') {
        $newContent = $content -replace 'author: .*', "author: $newAuthor"
        Set-Content -Path $_.FullName -Value $newContent -NoNewline
        Write-Host "✓ Updated: $($_.Name)" -ForegroundColor Green
    } else {
        Write-Host "⚠ No author field found in: $($_.Name)" -ForegroundColor Yellow
    }
}

Write-Host "`n✓ All templates updated!" -ForegroundColor Cyan