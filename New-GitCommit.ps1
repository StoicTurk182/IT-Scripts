#Requires -Version 5.1

<#
.SYNOPSIS
    Generates a structured conventional commit message from staged git changes.

.DESCRIPTION
    Analyses staged changes locally using git diff and git status output.
    Infers commit type (feat, fix, docs, refactor, chore) from file status codes.
    Infers scope from folder path using the IT-Scripts repository structure.
    Builds a conventional commit message, shows a preview, and prompts for
    confirmation before committing. No external API calls are made.

    Must be run from within a git repository with staged changes.

.EXAMPLE
    .\New-GitCommit.ps1
    Analyses staged changes, proposes a commit message, and prompts to confirm.

.EXAMPLE
    & "C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\New-GitCommit.ps1"
    Run from any directory using the call operator.

.NOTES
    Author:   Andrew Jones
    GitHub:   https://github.com/StoicTurk182
    Version:  1.0
    Created:  2026-04-07

    Changelog:
      1.0 — Initial release

    No external API calls. All analysis is performed locally against git output.

    Part of IT-Scripts Toolbox
    Repository: https://github.com/StoicTurk182/IT-Scripts

.LINK
    https://github.com/StoicTurk182/IT-Scripts

.LINK
    https://www.conventionalcommits.org/en/v1.0.0/
#>

[CmdletBinding()]
param()

# ============================================================================
# HELPERS
# ============================================================================

function Write-Header { param([string]$T)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  $T" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}
function Write-Note { param([string]$T); Write-Host "  [NOTE] $T" -ForegroundColor Gray    }
function Write-Warn { param([string]$T); Write-Host "  [WARN] $T" -ForegroundColor Yellow  }
function Write-Fail { param([string]$T); Write-Host "  [FAIL] $T" -ForegroundColor Red     }
function Write-OK   { param([string]$T); Write-Host "  [OK]   $T" -ForegroundColor Green   }

# ============================================================================
# SCOPE INFERENCE — dynamic, works in any git repository
# Scope is derived from the first meaningful folder below the repo root.
# No static map required — adding new folders or using a different repo
# requires no changes to this script.
# ============================================================================

# Folders that are noise at the root level and should be skipped when
# inferring scope — the next folder down is used instead.
$ScopeSkipFolders = @('.git', 'Build', 'Release', 'dist', 'output', 'outputs', 'bin', 'obj', '.github')

# ============================================================================
# TYPE INFERENCE
# ============================================================================

function Get-CommitType {
    param (
        [string[]]$StatusCodes,   # git status --short codes e.g. 'M', 'A', 'D'
        [string[]]$Extensions     # file extensions in the staged set
    )

    # Deleted files — always chore
    if ($StatusCodes -contains 'D') { return "chore" }

    # New files — feat
    if ($StatusCodes -contains 'A' -and $StatusCodes -notcontains 'M') { return "feat" }

    # Mix of new and modified — feat
    if ($StatusCodes -contains 'A') { return "feat" }

    # Modified — infer from extension
    if ($Extensions -contains '.md' -and $Extensions.Count -eq 1) { return "docs" }
    if ($Extensions -contains '.psd1' -and $Extensions.Count -eq 1) { return "chore" }
    if ($Extensions -contains '.ps1') { return "fix" }

    return "chore"
}

function Get-CommitScope {
    param (
        [string[]]$FilePaths,
        [string]$RepoRoot
    )

    # Normalise repo root for comparison
    $repoRootNorm = $RepoRoot.Replace('\', '/').TrimEnd('/').ToLower()
    $scopes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($path in $FilePaths) {
        # git returns paths relative to repo root — normalise separators
        $parts = ($path -replace '\\\\', '/') -split '/' | Where-Object { $_ -ne '' }

        if ($parts.Count -eq 1) {
            # Root level file — use filename without extension as scope
            $scopes.Add(([System.IO.Path]::GetFileNameWithoutExtension($parts[0]))) | Out-Null
            continue
        }

        # Walk path segments from the top, skip noise folders
        # Use the first non-skipped folder as scope
        $scopeFound = $false
        foreach ($part in $parts[0..($parts.Count - 2)]) {  # exclude filename
            if ($ScopeSkipFolders -inotcontains $part) {
                $scopes.Add($part) | Out-Null
                $scopeFound = $true
                break
            }
        }

        # All folders were skip folders — fall back to filename
        if (-not $scopeFound) {
            $scopes.Add(([System.IO.Path]::GetFileNameWithoutExtension($parts[-1]))) | Out-Null
        }
    }

    if ($scopes.Count -eq 1) { return @($scopes)[0] }
    if ($scopes.Count -gt 1) { return ($scopes | Sort-Object) -join ", " }
    return ""
}

# ============================================================================
# MAIN
# ============================================================================

Write-Header "GIT COMMIT ASSISTANT"

# --- Git repo check ---
$gitCheck = git rev-parse --is-inside-work-tree 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Not inside a git repository."
    exit 1
}

$RepoRoot = git rev-parse --show-toplevel
Write-Note "Repository: $RepoRoot"

# --- Staged changes check ---
$stagedFiles = git diff --staged --name-only 2>&1
if (-not $stagedFiles) {
    Write-Fail "No staged changes. Stage files with 'git add' before running."
    Write-Note "Stage all:        git add -A"
    Write-Note "Stage one file:   git add .\path\to\file.ps1"
    exit 1
}

# --- Parse status codes ---
$statusLines = git diff --staged --name-status 2>&1
$statusCodes = @()
$filePaths   = @()
$extensions  = @()

foreach ($line in $statusLines) {
    if ($line -match '^([AMDRC])\s+(.+)$') {
        $statusCodes += $Matches[1]
        $filePaths   += $Matches[2].Trim()
        $extensions  += [System.IO.Path]::GetExtension($Matches[2].Trim()).ToLower()
    }
}

# --- Show staged files ---
Write-Host "  Staged files:" -ForegroundColor Magenta
foreach ($line in $statusLines) {
    if ($line -match '^([AMDRC])\s+(.+)$') {
        $code  = $Matches[1]
        $file  = $Matches[2].Trim()
        $color = switch ($code) {
            'A' { 'Green'  }
            'M' { 'Yellow' }
            'D' { 'Red'    }
            default { 'Gray' }
        }
        $label = switch ($code) {
            'A' { 'added   ' }
            'M' { 'modified' }
            'D' { 'deleted ' }
            default { $code }
        }
        Write-Host "    [$label]  $file" -ForegroundColor $color
    }
}
Write-Host ""

# --- Infer type and scope ---
$inferredType  = Get-CommitType  -StatusCodes $statusCodes -Extensions $extensions
$inferredScope = Get-CommitScope -FilePaths $filePaths -RepoRoot $RepoRoot

# --- Stat summary for body ---
$statLines = (git diff --staged --stat 2>&1 | Select-Object -Last 1).Trim()

# ============================================================================
# BUILD MESSAGE
# ============================================================================

Write-Host "  [COMMIT MESSAGE]" -ForegroundColor Magenta

$validTypes = @("feat", "fix", "docs", "refactor", "chore", "perf", "test")
Write-Host "  Types: $($validTypes -join ' | ')" -ForegroundColor Gray
Write-Host "  Inferred type: $inferredType" -ForegroundColor Gray
$type = (Read-Host "  Type [Enter to accept '$inferredType']").Trim().ToLower()
if ([string]::IsNullOrWhiteSpace($type)) { $type = $inferredType }
if ($type -notin $validTypes) {
    Write-Warn "'$type' is not a standard type. Proceeding anyway."
}

Write-Host ""
Write-Host "  Inferred scope: $inferredScope" -ForegroundColor Gray
$scope = (Read-Host "  Scope [Enter to accept]").Trim()
if ([string]::IsNullOrWhiteSpace($scope)) { $scope = $inferredScope }

Write-Host ""
$description = ""
while ([string]::IsNullOrWhiteSpace($description)) {
    $description = (Read-Host "  Description (imperative present tense, e.g. 'add input validation')").Trim()
}

# Build subject line
$subject = if ($scope) { "${type}(${scope}): ${description}" } else { "${type}: ${description}" }

# Build body from file list
$bodyLines = @()
foreach ($line in $statusLines) {
    if ($line -match '^([AMDRC])\s+(.+)$') {
        $label = switch ($Matches[1]) {
            'A' { 'add'    }
            'M' { 'update' }
            'D' { 'remove' }
            default { $Matches[1] }
        }
        $bodyLines += "- $label $($Matches[2].Trim())"
    }
}
$body = $bodyLines -join "`n"

# ============================================================================
# PREVIEW AND CONFIRM
# ============================================================================

Write-Host ""
Write-Host "  ----------------------------------------" -ForegroundColor Cyan
Write-Host "  $subject" -ForegroundColor White
Write-Host ""
foreach ($l in $bodyLines) { Write-Host "  $l" -ForegroundColor Gray }
Write-Host "  ----------------------------------------`n" -ForegroundColor Cyan

$action = (Read-Host "  [C]ommit  [E]dit description  [A]bort").Trim().ToUpper()

switch ($action) {
    "E" {
        $description = (Read-Host "  New description").Trim()
        $subject     = if ($scope) { "${type}(${scope}): ${description}" } else { "${type}: ${description}" }
        Write-Host "  Updated: $subject" -ForegroundColor Cyan
        $action = (Read-Host "  [C]ommit  [A]bort").Trim().ToUpper()
        if ($action -ne "C") { Write-Warn "Aborted."; exit 0 }
    }
    "A" { Write-Warn "Aborted. No changes committed."; exit 0 }
}

# ============================================================================
# COMMIT
# ============================================================================

$fullMessage = "$subject`n`n$body"
git commit -m $fullMessage

if ($LASTEXITCODE -eq 0) {
    Write-OK "Committed: $subject"
    Write-Host ""
    $push = (Read-Host "  Push to remote now? Y/N").Trim().ToUpper()
    if ($push -eq "Y") {
        git push
        if ($LASTEXITCODE -eq 0) { Write-OK "Pushed." }
        else { Write-Warn "Push failed. Run 'git push' manually." }
    }
} else {
    Write-Fail "Commit failed. Check git output above."
}
