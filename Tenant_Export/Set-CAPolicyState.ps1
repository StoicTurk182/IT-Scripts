<#
.SYNOPSIS
    Set the 'state' field to 'disabled' on every Conditional Access policy JSON file
    in a baseline folder.

.DESCRIPTION
    Walks the ConditionalAccess subfolder of a baseline export and rewrites the top-level
    'state' field in each JSON file to 'disabled'. Idempotent - running twice produces the
    same result.

    Does not touch Settings Catalog profiles (they have no equivalent state field).

    Use this when preparing a baseline bundle for cross-tenant import and you want CA
    policies to land inactive so you can review and enable them manually.

    Valid CA state values for reference:
      enabled                              - Policy is live and enforcing
      disabled                             - Policy is off, ignored
      enabledForReportingButNotEnforced    - Report-only, evaluates and logs but does not enforce

.PARAMETER Path
    Folder containing a ConditionalAccess subfolder with *.json files. Typically the output
    of Export-PolicyBaseline.ps1 or Optimize-PolicyBaseline.ps1.

.PARAMETER State
    Target state value. Defaults to 'disabled'. Accepts 'disabled', 'enabled', or
    'enabledForReportingButNotEnforced' for completeness.

.PARAMETER DryRun
    Log intended changes without writing any files.

.EXAMPLE
    .\Set-CAPolicyState.ps1 -Path C:\Lab\Export-Clean

    Sets every CA policy in C:\Lab\Export-Clean\ConditionalAccess to state=disabled.

.EXAMPLE
    .\Set-CAPolicyState.ps1 -Path C:\Lab\Export-Clean -State enabledForReportingButNotEnforced

    Sets every CA policy to report-only state instead.

.EXAMPLE
    .\Set-CAPolicyState.ps1 -Path C:\Lab\Export-Clean -DryRun

    Logs what would be changed without writing.

.NOTES
    Author:  Andrew Jones
    Version: 1.0
    Date:    2026-04-17
#>

#Requires -Version 5.1

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter()]
    [ValidateSet('disabled', 'enabled', 'enabledForReportingButNotEnforced')]
    [string]$State = 'disabled',

    [Parameter()]
    [switch]$DryRun
)

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "SKIP")]
        [string]$Level = "INFO"
    )
    $colors = @{
        "INFO"    = "Cyan"
        "SUCCESS" = "Green"
        "WARNING" = "Yellow"
        "ERROR"   = "Red"
        "SKIP"    = "DarkGray"
    }
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message" -ForegroundColor $colors[$Level]
}

Write-Host "`n=== Set CA Policy State ===`n" -ForegroundColor Cyan
Write-Log "Path:    $Path"
Write-Log "State:   $State"
Write-Log "Dry run: $($DryRun.IsPresent)"

# Validate input folder
$caFolder = Join-Path $Path 'ConditionalAccess'
if (-not (Test-Path $caFolder)) {
    Write-Log "ConditionalAccess folder not found under $Path" -Level ERROR
    exit 1
}

$files = Get-ChildItem -Path $caFolder -Filter *.json -File
if ($files.Count -eq 0) {
    Write-Log "No CA policy JSON files found in $caFolder" -Level WARNING
    exit 0
}

Write-Log "Found $($files.Count) CA policy files" -Level SUCCESS

$stats = @{ changed = 0; alreadyCorrect = 0; failed = 0 }

foreach ($f in $files) {
    try {
        $policy = Get-Content -Raw -Path $f.FullName | ConvertFrom-Json

        $currentState = $policy.state
        $displayName  = $policy.displayName
        if (-not $displayName) { $displayName = $f.BaseName }

        if ($currentState -eq $State) {
            Write-Log "Already '$State': $displayName" -Level SKIP
            $stats.alreadyCorrect++
            continue
        }

        if ($DryRun) {
            Write-Log "[DryRun] Would change: $displayName ($currentState -> $State)" -Level INFO
        } else {
            $policy.state = $State
            $policy | ConvertTo-Json -Depth 20 | Set-Content -Path $f.FullName -Encoding UTF8
            Write-Log "Changed: $displayName ($currentState -> $State)" -Level SUCCESS
        }
        $stats.changed++

    } catch {
        Write-Log "Failed to process $($f.Name): $_" -Level ERROR
        $stats.failed++
    }
}

Write-Host ""
Write-Host "  Changed        : $($stats.changed)" -ForegroundColor Cyan
Write-Host "  Already correct: $($stats.alreadyCorrect)" -ForegroundColor DarkGray
Write-Host "  Failed         : $($stats.failed)" -ForegroundColor $(if ($stats.failed -gt 0) { 'Red' } else { 'DarkGray' })
Write-Host ""
Write-Host "=== Done ===`n" -ForegroundColor Green
