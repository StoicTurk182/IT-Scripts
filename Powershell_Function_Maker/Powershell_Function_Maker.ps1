# ============================================================================
# New-QuickFunction.ps1
# Generate reusable quick-access functions (SSH, path, app, or command) and
# register them in the PowerShell profile. Inserts functions idempotently via
# named markers, logs every change, and supports removal and listing.
#
# Types:
#   SSH     - ssh user@host -p port
#   Path    - Set-Location -LiteralPath '<path>'
#   App     - Start-Process -FilePath '<target>' [-ArgumentList '<args>']
#   Command - a verbatim command line
#
# Examples:
#   .\New-QuickFunction.ps1
#   .\New-QuickFunction.ps1 -Type SSH -Name Connect-DebianVPS -Target debian@100.75.228.108 -Port 22023 -Alias vps
#   .\New-QuickFunction.ps1 -Type Path -Name lab -Target 'C:\Users\Administrator\Andrew J IT Labs'
#   .\New-QuickFunction.ps1 -Type App  -Name vault -Target 'C:\Users\Administrator\OneDrive\Obsidian'
#   .\New-QuickFunction.ps1 -Remove -Name vault
#   .\New-QuickFunction.ps1 -List
#
# Author : Andrew Jones
# Version: 1.1
# Date   : 2026-06-25
# ============================================================================

[CmdletBinding()]
param (
    [ValidateSet('SSH','Path','App','Command')]
    [string]$Type,
    [string]$Name,
    [string]$Target,
    [int]$Port = 22,
    [string]$Arguments,
    [string]$Alias,
    [switch]$Remove,
    [switch]$List,
    [string]$LogPath = (Join-Path $HOME 'PowerShell-QuickFunctions.csv')
)

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet('INFO','SUCCESS','WARNING','ERROR')]
        [string]$Level = 'INFO'
    )
    $colors = @{ INFO = 'Cyan'; SUCCESS = 'Green'; WARNING = 'Yellow'; ERROR = 'Red' }
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message" -ForegroundColor $colors[$Level]
}

function Test-FunctionName {
    param([string]$Value)
    # Letters, numbers, hyphen, underscore; must start with a letter.
    return $Value -match '^[A-Za-z][A-Za-z0-9_-]*$'
}

function ConvertTo-SingleQuoted {
    # Wraps a string in single quotes, escaping any embedded single quotes.
    param([string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

function Edit-ProfileBlock {
    # Inserts, updates, or removes a named marker block in the profile.
    # Pass $BlockLines to create/update; omit it to remove. Returns the action taken.
    param (
        [string]$Path,
        [string]$Name,
        [string[]]$BlockLines
    )
    $start = "# region QuickFunction: $Name (auto-generated)"
    $end   = "# endregion QuickFunction: $Name"

    $existing = @(Get-Content -Path $Path -ErrorAction SilentlyContinue)

    $si = -1; $ei = -1
    for ($i = 0; $i -lt $existing.Count; $i++) {
        if ($existing[$i] -eq $start) { $si = $i }
        elseif ($existing[$i] -eq $end -and $si -ge 0) { $ei = $i; break }
    }
    $found = ($si -ge 0 -and $ei -ge $si)

    if ($BlockLines) {
        $full = @($start) + $BlockLines + @($end)
        if ($found) {
            $before = @(); $after = @()
            if ($si -gt 0) { $before = $existing[0..($si - 1)] }
            if ($ei -lt ($existing.Count - 1)) { $after = $existing[($ei + 1)..($existing.Count - 1)] }
            $new = @($before) + $full + @($after)
            $action = 'Updated'
        }
        else {
            $new = @($existing)
            if ($new.Count -gt 0 -and $new[-1] -ne '') { $new += '' }
            $new += $full
            $action = 'Created'
        }
        Set-Content -Path $Path -Value $new -Encoding UTF8
        return $action
    }
    else {
        if (-not $found) { return 'NotFound' }
        $before = @(); $after = @()
        if ($si -gt 0) { $before = $existing[0..($si - 1)] }
        if ($ei -lt ($existing.Count - 1)) { $after = $existing[($ei + 1)..($existing.Count - 1)] }
        $new = @($before) + @($after)
        Set-Content -Path $Path -Value $new -Encoding UTF8
        return 'Removed'
    }
}

function Write-LogEntry {
    param (
        [hashtable]$Fields,
        [string]$Path
    )
    try {
        [pscustomobject]$Fields | Export-Csv -Path $Path -NoTypeInformation -Append -ErrorAction Stop
    } catch {
        Write-Log "Could not write to log '$Path': $($_.Exception.Message)" 'WARNING'
    }
}

# ============================================================================
# MAIN
# ============================================================================

# --- List mode ---
if ($List) {
    if (Test-Path $LogPath) {
        Import-Csv -Path $LogPath | Format-Table -AutoSize
    } else {
        Write-Log "No log found at $LogPath" 'WARNING'
    }
    return
}

# --- Resolve profile (needed for create and remove) ---
$profilePath = $PROFILE
$profileDir  = Split-Path $profilePath -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    Write-Log "Created profile directory: $profileDir" 'INFO'
}
if (-not (Test-Path $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
    Write-Log "Created profile: $profilePath" 'INFO'
}

# --- Remove mode ---
if ($Remove) {
    if (-not $Name) { $Name = Read-Host 'Function name to remove' }
    if (-not (Test-FunctionName $Name)) {
        Write-Log "Invalid function name '$Name'." 'ERROR'; return
    }
    $action = Edit-ProfileBlock -Path $profilePath -Name $Name
    if ($action -eq 'NotFound') {
        Write-Log "No managed block named '$Name' found in the profile." 'WARNING'; return
    }
    Write-Log "Removed function '$Name' from the profile." 'SUCCESS'
    Write-LogEntry -Path $LogPath -Fields @{
        Timestamp = (Get-Date -Format 'o'); FunctionName = $Name; Type = ''
        Body = ''; Alias = ''; Action = 'Removed'
        Edition = $PSVersionTable.PSEdition; ProfilePath = $profilePath
    }
    Write-Host "`nReload your profile to apply:" -ForegroundColor Yellow
    Write-Host "    . `$PROFILE`n" -ForegroundColor Yellow
    return
}

# --- Create mode ---
Write-Host "`n=== New Quick-Access Function ===`n" -ForegroundColor Cyan

# Type
if (-not $Type) {
    Write-Host 'Select function type:'
    Write-Host '  1) SSH connection'
    Write-Host '  2) Path (jump to a directory)'
    Write-Host '  3) Application / file / folder / URL'
    Write-Host '  4) Raw command'
    switch (Read-Host 'Choice [1-4]') {
        '1' { $Type = 'SSH' }
        '2' { $Type = 'Path' }
        '3' { $Type = 'App' }
        '4' { $Type = 'Command' }
        default { Write-Log 'Invalid choice. Aborting.' 'ERROR'; return }
    }
}

# Name
if (-not $Name) { $Name = Read-Host 'Function name (e.g. Connect-DebianVPS, lab, vault)' }
if (-not (Test-FunctionName $Name)) {
    Write-Log "Invalid function name '$Name'. Use letters, numbers, hyphen or underscore; must start with a letter." 'ERROR'
    return
}

# Type-specific body
$body = ''
switch ($Type) {

    'SSH' {
        if (-not $Target) { $Target = Read-Host 'SSH target (user@host, e.g. debian@100.75.228.108)' }
        if ([string]::IsNullOrWhiteSpace($Target)) { Write-Log 'No target provided. Aborting.' 'ERROR'; return }
        if (-not $PSBoundParameters.ContainsKey('Port')) {
            $portInput = Read-Host "SSH port (press Enter for $Port)"
            if (-not [string]::IsNullOrWhiteSpace($portInput)) {
                $parsed = 0
                if ([int]::TryParse($portInput, [ref]$parsed)) { $Port = $parsed }
                else { Write-Log "Invalid port '$portInput'. Aborting." 'ERROR'; return }
            }
        }
        $body = "ssh $Target -p $Port"
    }

    'Path' {
        if (-not $Target) { $Target = Read-Host 'Directory path' }
        if ([string]::IsNullOrWhiteSpace($Target)) { Write-Log 'No path provided. Aborting.' 'ERROR'; return }
        if (-not (Test-Path -LiteralPath $Target)) {
            Write-Log "Path does not currently exist: $Target (function will still be created)." 'WARNING'
        }
        $body = "Set-Location -LiteralPath $(ConvertTo-SingleQuoted $Target)"
    }

    'App' {
        if (-not $Target) { $Target = Read-Host 'Application, file, folder, or URL' }
        if ([string]::IsNullOrWhiteSpace($Target)) { Write-Log 'No target provided. Aborting.' 'ERROR'; return }
        if (-not $PSBoundParameters.ContainsKey('Arguments') -and [string]::IsNullOrWhiteSpace($Arguments)) {
            $Arguments = Read-Host 'Arguments (press Enter to skip)'
        }
        if ([string]::IsNullOrWhiteSpace($Arguments)) {
            $body = "Start-Process -FilePath $(ConvertTo-SingleQuoted $Target)"
        } else {
            $body = "Start-Process -FilePath $(ConvertTo-SingleQuoted $Target) -ArgumentList $(ConvertTo-SingleQuoted $Arguments)"
        }
    }

    'Command' {
        if (-not $Target) { $Target = Read-Host 'Command line to run' }
        if ([string]::IsNullOrWhiteSpace($Target)) { Write-Log 'No command provided. Aborting.' 'ERROR'; return }
        $body = $Target
    }
}

# Alias
if (-not $PSBoundParameters.ContainsKey('Alias') -and [string]::IsNullOrWhiteSpace($Alias)) {
    $Alias = Read-Host 'Optional alias (press Enter to skip)'
}

# Assemble managed block (alias lives inside the block so removal cleans it up too)
$blockLines = New-Object System.Collections.Generic.List[string]
$blockLines.Add("function $Name { $body }")
if (-not [string]::IsNullOrWhiteSpace($Alias)) {
    $blockLines.Add("Set-Alias -Name $Alias -Value $Name")
}

$action = Edit-ProfileBlock -Path $profilePath -Name $Name -BlockLines $blockLines.ToArray()

# Log (alias display computed first to avoid inline expressions in the hashtable)
$aliasDisplay = ''
if (-not [string]::IsNullOrWhiteSpace($Alias)) { $aliasDisplay = $Alias }

Write-LogEntry -Path $LogPath -Fields @{
    Timestamp    = (Get-Date -Format 'o')
    FunctionName = $Name
    Type         = $Type
    Body         = $body
    Alias        = $aliasDisplay
    Action       = $action
    Edition      = $PSVersionTable.PSEdition
    ProfilePath  = $profilePath
}

# Summary
Write-Log "$action [$Type] function '$Name'" 'SUCCESS'
Write-Log "  $body" 'INFO'
if ($aliasDisplay) { Write-Log "  alias: $aliasDisplay" 'INFO' }
Write-Log "Profile : $profilePath" 'INFO'
Write-Log "Log     : $LogPath" 'INFO'

Write-Host "`nReload your profile to use it now:" -ForegroundColor Yellow
Write-Host "    . `$PROFILE`n" -ForegroundColor Yellow