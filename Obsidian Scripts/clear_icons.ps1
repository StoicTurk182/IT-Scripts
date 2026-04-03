# LIVE - Actually modifies files
$vaultPath = "C:\Users\Administrator\OneDrive\Obsidian\Informal Notes"
$icons = @('■', '▶', '◆', '▸')

Write-Host "⚠️  LIVE MODE - Files will be modified!" -ForegroundColor Red
Write-Host "Vault: $vaultPath`n" -ForegroundColor Cyan

$totalFiles = 0
$filesModified = 0

Get-ChildItem -Path $vaultPath -Filter "*.md" -Recurse | ForEach-Object {
    $file = $_
    $content = Get-Content $file.FullName -Raw
    $modified = $false
    
    $newContent = ($content -split "`r?`n") | ForEach-Object {
        $line = $_
        
        if ($line -match '^\s*#+\s+') {
            $originalLine = $line
            
            foreach ($icon in $icons) {
                $line = $line -replace [regex]::Escape($icon), ''
            }
            
            $line = $line -replace '\s+', ' '
            $line = $line.TrimEnd()
            
            if ($line -ne $originalLine) {
                $modified = $true
                Write-Host "  $($file.Name): '$originalLine' → '$line'" -ForegroundColor Yellow
            }
        }
        
        $line
    }
    
    if ($modified) {
        $newContent -join "`r`n" | Set-Content $file.FullName -NoNewline
        Write-Host "✓ Updated: $($file.Name)" -ForegroundColor Green
        $filesModified++
    }
    
    $totalFiles++
}

Write-Host "`n--- Complete ---" -ForegroundColor Cyan
Write-Host "Files scanned: $totalFiles"
Write-Host "Files modified: $filesModified" -ForegroundColor Green