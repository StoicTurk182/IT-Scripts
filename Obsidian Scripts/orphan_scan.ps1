# Just scan, don't delete anything
$vaultPath = "C:\Users\Administrator\OneDrive\Obsidian\Informal Notes"

# Count empty notes
$empty = Get-ChildItem -Path $vaultPath -Filter "*.md" -Recurse | Where-Object {
    $c = Get-Content $_.FullName -Raw
    [string]::IsNullOrWhiteSpace($c) -or ($c -replace '(?s)^---.*?---\s*', '').Trim().Length -lt 30
}

Write-Host "Empty notes: $($empty.Count)"
$empty | Select-Object Name, Directory, Length | Format-Table