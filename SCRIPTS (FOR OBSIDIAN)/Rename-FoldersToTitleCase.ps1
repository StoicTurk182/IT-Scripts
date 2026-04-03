<#
.SYNOPSIS
    Recursively renames all folders under a root path to Title Case.

.DESCRIPTION
    Traverses all subdirectories under a given root path and renames each folder
    so that every word (split on spaces and hyphens) is capitalised. Processing
    is performed deepest-first to avoid broken paths mid-rename.

    Supports a -WhatIf preview mode that shows all planned renames without
    making any changes to disk.

.PARAMETER RootPath
    The root directory to start from. All child folders (recursive) plus the
    root folder itself are evaluated.

.PARAMETER IncludeRoot
    If specified, the root folder itself is also renamed. Defaults to false.

.PARAMETER WhatIf
    Preview mode. Lists all planned renames without making any changes.

.EXAMPLE
    .\Rename-FoldersToTitleCase.ps1 -RootPath "C:\IT-Scripts" -WhatIf
    Previews all renames without making changes.

.EXAMPLE
    .\Rename-FoldersToTitleCase.ps1 -RootPath "C:\IT-Scripts"
    Renames all child folders to Title Case.

.EXAMPLE
    .\Rename-FoldersToTitleCase.ps1 -RootPath "C:\IT-Scripts" -IncludeRoot
    Renames all child folders AND the root folder itself.

.NOTES
    Author: Andrew Jones
    Version: 1.1
    Requires: PowerShell 5.1+, Write access to target path
    Git note: If renaming folders tracked by Git, run `git add -A` and
    commit after this script completes to reflect renames in your repository.
#>

#Requires -Version 5.1

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$RootPath,

    [Parameter()]
    [switch]$IncludeRoot,

    [Parameter()]
    [switch]$WhatIf
)

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "SKIP")]
        [string]$Level = "INFO"
    )
    $colours = @{
        "INFO"    = "Cyan"
        "SUCCESS" = "Green"
        "WARNING" = "Yellow"
        "ERROR"   = "Red"
        "SKIP"    = "DarkGray"
    }
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message" -ForegroundColor $colours[$Level]
}

function ConvertTo-TitleCase {
    param ([string]$Name)

    # Return the full folder name in uppercase
    return $Name.ToUpper()
}

function Rename-FoldersRecursive {
    param (
        [string]$Path,
        [bool]$Preview
    )

    # Get all subdirectories deepest-first to avoid broken paths during rename
    $allFolders = Get-ChildItem -LiteralPath $Path -Directory -Recurse |
        Sort-Object { $_.FullName.Length } -Descending

    $renamedCount = 0
    $skippedCount = 0
    $errorCount   = 0

    foreach ($folder in $allFolders) {
        $original  = $folder.Name
        $titleCase = ConvertTo-TitleCase -Name $original

        if ($original -ceq $titleCase) {
            Write-Log "Already correct: $($folder.FullName)" -Level SKIP
            $skippedCount++
            continue
        }

        $newPath = Join-Path $folder.Parent.FullName $titleCase

        if ($Preview) {
            Write-Log "PREVIEW  $original  ->  $titleCase" -Level WARNING
            Write-Log "         $($folder.FullName)" -Level INFO
            $renamedCount++
            continue
        }

        try {
            # Windows NTFS is case-insensitive; rename via temp name to force case change
            $tempName = $original + "_TMPRENAME_" + [System.Guid]::NewGuid().ToString("N").Substring(0, 6)
            $tempPath = Join-Path $folder.Parent.FullName $tempName

            Rename-Item -LiteralPath $folder.FullName -NewName $tempName -ErrorAction Stop
            Rename-Item -LiteralPath $tempPath         -NewName $titleCase  -ErrorAction Stop

            Write-Log "Renamed: $original  ->  $titleCase" -Level SUCCESS
            $renamedCount++
        }
        catch {
            Write-Log "FAILED to rename '$original': $_" -Level ERROR
            $errorCount++
        }
    }

    return @{
        Renamed  = $renamedCount
        Skipped  = $skippedCount
        Errors   = $errorCount
    }
}

# ============================================================================
# MAIN
# ============================================================================

Write-Host "`n=== Folder Title Case Renamer ===`n" -ForegroundColor Cyan

# Validate root path
if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
    Write-Log "Root path not found: $RootPath" -Level ERROR
    exit 1
}

$resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path
Write-Log "Root path : $resolvedRoot" -Level INFO
Write-Log "Mode      : $(if ($WhatIf) { 'PREVIEW (no changes will be made)' } else { 'LIVE' })" -Level INFO
Write-Log "Scope     : $(if ($IncludeRoot) { 'All subfolders + root folder' } else { 'All subfolders only' })" -Level INFO
Write-Host ""

# Process subdirectories
$result = Rename-FoldersRecursive -Path $resolvedRoot -Preview $WhatIf.IsPresent

# Optionally rename the root folder itself
if ($IncludeRoot) {
    $rootFolder   = Get-Item -LiteralPath $resolvedRoot
    $originalRoot = $rootFolder.Name
    $titleRoot    = ConvertTo-TitleCase -Name $originalRoot

    if ($originalRoot -ceq $titleRoot) {
        Write-Log "Root already correct: $originalRoot" -Level SKIP
        $result.Skipped++
    }
    elseif ($WhatIf) {
        Write-Log "PREVIEW (root)  $originalRoot  ->  $titleRoot" -Level WARNING
        $result.Renamed++
    }
    else {
        try {
            $parentPath = $rootFolder.Parent.FullName
            $tempName   = $originalRoot + "_TMPRENAME_" + [System.Guid]::NewGuid().ToString("N").Substring(0, 6)
            $tempPath   = Join-Path $parentPath $tempName

            Rename-Item -LiteralPath $resolvedRoot -NewName $tempName  -ErrorAction Stop
            Rename-Item -LiteralPath $tempPath     -NewName $titleRoot -ErrorAction Stop

            Write-Log "Renamed root: $originalRoot  ->  $titleRoot" -Level SUCCESS
            $result.Renamed++
        }
        catch {
            Write-Log "FAILED to rename root '$originalRoot': $_" -Level ERROR
            $result.Errors++
        }
    }
}

# Summary
Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "$(if ($WhatIf) { 'Would rename' } else { 'Renamed' }) : $($result.Renamed)" -ForegroundColor Green
Write-Host "Skipped (already correct) : $($result.Skipped)" -ForegroundColor DarkGray
Write-Host "Errors                    : $($result.Errors)"  -ForegroundColor $(if ($result.Errors -gt 0) { 'Red' } else { 'DarkGray' })

if ($WhatIf) {
    Write-Host "`nNo changes were made. Remove -WhatIf to apply." -ForegroundColor Yellow
}
elseif ($result.Renamed -gt 0) {
    Write-Host "`nIf this folder is a Git repository, run:" -ForegroundColor Cyan
    Write-Host "  git add -A" -ForegroundColor White
    Write-Host "  git commit -m `"Chore: Rename folders to Title Case`"" -ForegroundColor White
    Write-Host "  git push" -ForegroundColor White
}

Write-Host ""