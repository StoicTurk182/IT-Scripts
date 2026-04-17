<#
.SYNOPSIS
    Filter Microsoft auto-generated defaults and rename policies in a baseline export folder
    produced by Export-PolicyBaseline.ps1.

.DESCRIPTION
    Two-phase workflow:

    Phase 1 (Generate): Scans an input export folder and writes a skeleton mapping file
                        (JSON) listing every CA policy and Settings Catalog profile found.
                        Known Microsoft auto-generated defaults are pre-flagged with
                        action="exclude"; everything else is pre-flagged with action="keep"
                        and newName=currentName for the operator to edit.

    Phase 2 (Apply):    Reads the edited mapping file and produces a cleaned output folder.
                        Excluded policies are dropped. Kept policies are written with their
                        new names applied to both the JSON body (displayName/name field) and
                        the filename (kebab-case slug of the new name).

    The input folder is never modified. Output is always a fresh folder.

.PARAMETER InputPath
    Folder produced by Export-PolicyBaseline.ps1. Must contain 'ConditionalAccess' and
    'SettingsCatalog' subfolders and an 'export-summary.json'.

.PARAMETER GenerateMappingFile
    Path to write the skeleton mapping JSON file. Use this on the first pass to produce a
    mapping file for editing. Mutually exclusive with -OutputPath and -MappingFile.

    By default, every 'keep' entry is pre-populated with newName = "{{TENANT}} - <currentName>"
    so the file is ready to apply with -TenantName <value> without manual editing.

.PARAMETER NoTenantPrefix
    Generate mode only. Suppress the default {{TENANT}} - prefix and produce a skeleton where
    newName equals currentName. Use when you want to hand-author renames from scratch.

.PARAMETER OutputPath
    Folder to write the cleaned export into. Created if missing. Existing content overwritten.

.PARAMETER MappingFile
    Path to the mapping file (edited from a previous -GenerateMappingFile run).

.PARAMETER TenantName
    Value substituted for the {{TENANT}} token wherever it appears in the 'newName' field
    of the mapping file. Enables one mapping file to produce differently-named output
    bundles per tenant. Optional; required only if the mapping file contains {{TENANT}}.

.PARAMETER DryRun
    Log intended actions without writing any files.

.EXAMPLE
    .\Optimize-PolicyBaseline.ps1 -InputPath C:\Lab\Export-Raw -GenerateMappingFile C:\Lab\mapping.json

    Phase 1. Produces C:\Lab\mapping.json with {{TENANT}} - <currentName> pre-filled on every
    kept entry. Microsoft auto-defaults are flagged for exclusion.

.EXAMPLE
    .\Optimize-PolicyBaseline.ps1 -InputPath C:\Lab\Export-Raw -GenerateMappingFile C:\Lab\mapping.json `
        -NoTenantPrefix

    Phase 1 without the default tenant prefix. newName = currentName on every kept entry;
    hand-author renames from scratch.

.EXAMPLE
    .\Optimize-PolicyBaseline.ps1 -InputPath C:\Lab\Export-Raw -OutputPath C:\Lab\Export-Clean `
        -MappingFile C:\Lab\mapping.json -TenantName ORION

    Phase 2 with tenant name substitution. Any {{TENANT}} token in the mapping file's
    newName fields is replaced with 'ORION'.

.EXAMPLE
    .\Optimize-PolicyBaseline.ps1 -InputPath C:\Lab\Export-Raw -OutputPath C:\Lab\Export-Clean `
        -MappingFile C:\Lab\mapping.json -TenantName Blenheim -DryRun

    Phase 2 dry-run against a different tenant. Same mapping file, different output.

.NOTES
    Author:  Andrew Jones
    Version: 1.0
    Date:    2026-04-17

    The Microsoft auto-default detection list is maintained inline in the script.
    Update $Script:MicrosoftDefaults if new auto-generated defaults appear in future
    Intune releases.
#>

#Requires -Version 5.1

[CmdletBinding(DefaultParameterSetName='Apply')]
param (
    [Parameter(Mandatory)]
    [string]$InputPath,

    [Parameter(Mandatory, ParameterSetName='Generate')]
    [string]$GenerateMappingFile,

    [Parameter(ParameterSetName='Generate')]
    [switch]$NoTenantPrefix,

    [Parameter(Mandatory, ParameterSetName='Apply')]
    [string]$OutputPath,

    [Parameter(Mandatory, ParameterSetName='Apply')]
    [string]$MappingFile,

    [Parameter(ParameterSetName='Apply')]
    [string]$TenantName,

    [Parameter(ParameterSetName='Apply')]
    [switch]$DryRun
)

# ============================================================================
# CONFIG
# ============================================================================

# Known Microsoft auto-generated policy names. Exact match, case-insensitive.
# These are created automatically by Intune when certain features are enabled
# and should not be included in a portable baseline bundle - every tenant gets
# its own on feature enablement.
$Script:MicrosoftDefaults = @{
    'Default EDR policy for all devices' = 'Auto-created when MDE integration is enabled'
    'Default_Policy'                      = 'Auto-created Endpoint Security default'
    'Firewall Windows default policy'     = 'Auto-created when Defender Firewall baseline is enabled'
    'NGP Windows default policy'          = 'Auto-created Next Generation Protection (Defender AV) default'
}

# ============================================================================
# FUNCTIONS
# ============================================================================

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

function ConvertTo-SafeFileName {
    param ([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return "unnamed-$(New-Guid)" }
    $clean = $Name -replace '[\\/:*?"<>|]', '-'
    $clean = $clean -replace '\s+', '-'
    $clean = $clean -replace '-+', '-'
    $clean = $clean.Trim('-').ToLowerInvariant()
    if ($clean.Length -gt 120) { $clean = $clean.Substring(0, 120).TrimEnd('-') }
    return $clean
}

function Test-IsMicrosoftDefault {
    param ([string]$PolicyName)
    return $Script:MicrosoftDefaults.ContainsKey($PolicyName)
}

function Get-MicrosoftDefaultReason {
    param ([string]$PolicyName)
    return $Script:MicrosoftDefaults[$PolicyName]
}

function Resolve-Tokens {
    <#
        Substitutes known tokens in a string. Currently supports {{TENANT}}.
        Returns the string unchanged if no tokens are present or $TenantName is empty.
    #>
    param (
        [string]$Value,
        [string]$TenantName
    )
    if ([string]::IsNullOrEmpty($Value)) { return $Value }
    if ($TenantName) {
        $Value = $Value -replace '\{\{TENANT\}\}', $TenantName
    }
    return $Value
}

function Test-HasUnresolvedTokens {
    <#
        Returns $true if the string still contains {{...}} tokens after resolution.
    #>
    param ([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return $false }
    return $Value -match '\{\{[^}]+\}\}'
}

function Read-PolicyFiles {
    <#
        Reads every *.json file in the given folder and returns an array of
        @{ file; currentName; policy } objects. $NameProperty is the JSON property
        to read as the display name ('displayName' for CA, 'name' for Settings Catalog).
    #>
    param (
        [string]$FolderPath,
        [string]$NameProperty
    )
    $result = @()
    if (-not (Test-Path $FolderPath)) { return $result }

    $files = Get-ChildItem -Path $FolderPath -Filter *.json -File
    foreach ($f in $files) {
        try {
            $policy = Get-Content -Raw -Path $f.FullName | ConvertFrom-Json
            $currentName = $policy.$NameProperty
            if (-not $currentName) { $currentName = $f.BaseName }
            $result += [pscustomobject]@{
                file        = $f.FullName
                currentName = $currentName
                policy      = $policy
            }
        } catch {
            Write-Log "Failed to parse $($f.FullName): $_" -Level WARNING
        }
    }
    return $result
}

function New-MappingEntry {
    param (
        [string]$CurrentName,
        [bool]$IsDefault,
        [bool]$PrefixWithTenantToken = $true
    )
    if ($IsDefault) {
        return [ordered]@{
            currentName = $CurrentName
            newName     = ''
            action      = 'exclude'
            reason      = Get-MicrosoftDefaultReason -PolicyName $CurrentName
        }
    } else {
        $newName = if ($PrefixWithTenantToken) {
            "{{TENANT}} - $CurrentName"
        } else {
            $CurrentName
        }
        return [ordered]@{
            currentName = $CurrentName
            newName     = $newName
            action      = 'keep'
        }
    }
}

function Invoke-GenerateMapping {
    param (
        [string]$InputPath,
        [string]$OutputFile,
        [bool]$PrefixWithTenantToken = $true
    )

    Write-Log "Generate mode"
    Write-Log "Input path:   $InputPath"
    Write-Log "Mapping file: $OutputFile"
    if ($PrefixWithTenantToken) {
        Write-Log "Prefix style: {{TENANT}} - <currentName>"
    } else {
        Write-Log "Prefix style: newName = currentName (no prefix)"
    }

    $caFolder = Join-Path $InputPath 'ConditionalAccess'
    $scFolder = Join-Path $InputPath 'SettingsCatalog'

    $caPolicies = Read-PolicyFiles -FolderPath $caFolder -NameProperty 'displayName'
    $scPolicies = Read-PolicyFiles -FolderPath $scFolder -NameProperty 'name'

    Write-Log "Found $($caPolicies.Count) CA policies" -Level SUCCESS
    Write-Log "Found $($scPolicies.Count) Settings Catalog profiles" -Level SUCCESS

    $mapping = [ordered]@{
        description        = 'Policy baseline cleanup mapping. Edit newName to rename, set action to exclude to drop.'
        generated          = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        sourceInputPath    = $InputPath
        conditionalAccess  = @()
        settingsCatalog    = @()
    }

    foreach ($p in $caPolicies) {
        $isDef = Test-IsMicrosoftDefault -PolicyName $p.currentName
        $mapping.conditionalAccess += New-MappingEntry -CurrentName $p.currentName -IsDefault $isDef -PrefixWithTenantToken $PrefixWithTenantToken
    }

    foreach ($p in $scPolicies) {
        $isDef = Test-IsMicrosoftDefault -PolicyName $p.currentName
        $entry = New-MappingEntry -CurrentName $p.currentName -IsDefault $isDef -PrefixWithTenantToken $PrefixWithTenantToken
        $mapping.settingsCatalog += $entry
        if ($isDef) {
            Write-Log "Flagged for exclusion: $($p.currentName) - $($entry.reason)" -Level WARNING
        }
    }

    # Write mapping file
    $parentDir = Split-Path -Path $OutputFile -Parent
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    $json = $mapping | ConvertTo-Json -Depth 10
    Set-Content -Path $OutputFile -Value $json -Encoding UTF8
    Write-Log "Mapping file written: $OutputFile" -Level SUCCESS

    # Summary
    $caKeep    = ($mapping.conditionalAccess  | Where-Object { $_.action -eq 'keep' }).Count
    $caExclude = ($mapping.conditionalAccess  | Where-Object { $_.action -eq 'exclude' }).Count
    $scKeep    = ($mapping.settingsCatalog    | Where-Object { $_.action -eq 'keep' }).Count
    $scExclude = ($mapping.settingsCatalog    | Where-Object { $_.action -eq 'exclude' }).Count

    Write-Host ""
    Write-Host "  Conditional Access : keep=$caKeep exclude=$caExclude" -ForegroundColor Cyan
    Write-Host "  Settings Catalog   : keep=$scKeep exclude=$scExclude" -ForegroundColor Cyan
    Write-Host ""
    if ($PrefixWithTenantToken) {
        Write-Host "Mapping file is ready to apply as-is. Every kept policy has newName = '{{TENANT}} - <currentName>'." -ForegroundColor Yellow
        Write-Host "Next step:" -ForegroundColor Yellow
        Write-Host "  - Optionally edit $OutputFile to customise newName values or flip more policies to 'exclude'" -ForegroundColor Yellow
        Write-Host "  - Run apply mode: -MappingFile $OutputFile -OutputPath <folder> -TenantName <value> -DryRun" -ForegroundColor Yellow
    } else {
        Write-Host "Mapping file written without tenant prefix. Every kept policy has newName = currentName." -ForegroundColor Yellow
        Write-Host "Next step: edit $OutputFile to set renames, then run apply mode" -ForegroundColor Yellow
    }
    Write-Host ""
}

function Invoke-ApplyMapping {
    param (
        [string]$InputPath,
        [string]$OutputPath,
        [string]$MappingFile,
        [string]$TenantName,
        [switch]$DryRun
    )

    Write-Log "Apply mode"
    Write-Log "Input path:   $InputPath"
    Write-Log "Output path:  $OutputPath"
    Write-Log "Mapping file: $MappingFile"
    if ($TenantName) {
        Write-Log "Tenant name:  $TenantName (substituted for {{TENANT}} tokens)"
    } else {
        Write-Log "Tenant name:  (not supplied)"
    }
    Write-Log "Dry run:      $($DryRun.IsPresent)"

    if (-not (Test-Path $MappingFile)) {
        Write-Log "Mapping file not found: $MappingFile" -Level ERROR
        exit 1
    }

    $mapping = Get-Content -Raw -Path $MappingFile | ConvertFrom-Json

    # Pre-flight: detect {{TENANT}} tokens and enforce -TenantName presence
    $allNewNames = @()
    $allNewNames += $mapping.conditionalAccess | ForEach-Object { $_.newName }
    $allNewNames += $mapping.settingsCatalog   | ForEach-Object { $_.newName }
    $tokenedNames = $allNewNames | Where-Object { $_ -match '\{\{TENANT\}\}' }
    if ($tokenedNames.Count -gt 0 -and -not $TenantName) {
        Write-Log "Mapping file contains {{TENANT}} tokens in $($tokenedNames.Count) entries but -TenantName was not supplied" -Level ERROR
        Write-Log "Re-run with -TenantName <value> to resolve them" -Level ERROR
        exit 1
    }
    if ($TenantName -and $tokenedNames.Count -eq 0) {
        Write-Log "-TenantName supplied but no {{TENANT}} tokens found in mapping - value will have no effect" -Level WARNING
    }

    $caFolder   = Join-Path $InputPath  'ConditionalAccess'
    $scFolder   = Join-Path $InputPath  'SettingsCatalog'
    $caOut      = Join-Path $OutputPath 'ConditionalAccess'
    $scOut      = Join-Path $OutputPath 'SettingsCatalog'

    if (-not $DryRun) {
        foreach ($p in @($OutputPath, $caOut, $scOut)) {
            if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
        }
    }

    $caPolicies = Read-PolicyFiles -FolderPath $caFolder -NameProperty 'displayName'
    $scPolicies = Read-PolicyFiles -FolderPath $scFolder -NameProperty 'name'

    # Build lookup: currentName -> mapping entry
    $caMap = @{}
    foreach ($m in $mapping.conditionalAccess) { $caMap[$m.currentName] = $m }
    $scMap = @{}
    foreach ($m in $mapping.settingsCatalog)   { $scMap[$m.currentName] = $m }

    # Track collisions
    $caOutputNames = New-Object System.Collections.Generic.HashSet[string]
    $scOutputNames = New-Object System.Collections.Generic.HashSet[string]

    $stats = @{ caKept=0; caExcluded=0; caMissing=0; scKept=0; scExcluded=0; scMissing=0 }

    # --- Conditional Access ---
    foreach ($p in $caPolicies) {
        $entry = $caMap[$p.currentName]
        if (-not $entry) {
            Write-Log "CA policy not in mapping (skipping): $($p.currentName)" -Level WARNING
            $stats.caMissing++
            continue
        }

        if ($entry.action -eq 'exclude') {
            $reason = if ($entry.reason) { " ($($entry.reason))" } else { '' }
            Write-Log "Excluded CA: $($p.currentName)$reason" -Level SKIP
            $stats.caExcluded++
            continue
        }

        $newName = if ([string]::IsNullOrWhiteSpace($entry.newName)) { $p.currentName } else { $entry.newName }
        $newName = Resolve-Tokens -Value $newName -TenantName $TenantName

        if (Test-HasUnresolvedTokens -Value $newName) {
            Write-Log "CA policy '$($p.currentName)' has unresolved tokens in newName: '$newName' - aborting" -Level ERROR
            exit 1
        }

        # Collision check
        if ($caOutputNames.Contains($newName)) {
            Write-Log "CA name collision on output: '$newName' - aborting" -Level ERROR
            exit 1
        }
        [void]$caOutputNames.Add($newName)

        # Rename inside JSON
        $p.policy.displayName = $newName

        $safeName = ConvertTo-SafeFileName -Name $newName
        $outFile  = Join-Path $caOut "$safeName.json"

        if ($DryRun) {
            Write-Log "[DryRun] Would write CA: $newName -> $outFile" -Level INFO
        } else {
            $p.policy | ConvertTo-Json -Depth 20 | Set-Content -Path $outFile -Encoding UTF8
            $msg = if ($p.currentName -ne $newName) { "$($p.currentName) -> $newName" } else { $newName }
            Write-Log "Kept CA: $msg" -Level SUCCESS
        }
        $stats.caKept++
    }

    # --- Settings Catalog ---
    foreach ($p in $scPolicies) {
        $entry = $scMap[$p.currentName]
        if (-not $entry) {
            Write-Log "Settings Catalog policy not in mapping (skipping): $($p.currentName)" -Level WARNING
            $stats.scMissing++
            continue
        }

        if ($entry.action -eq 'exclude') {
            $reason = if ($entry.reason) { " ($($entry.reason))" } else { '' }
            Write-Log "Excluded SC: $($p.currentName)$reason" -Level SKIP
            $stats.scExcluded++
            continue
        }

        $newName = if ([string]::IsNullOrWhiteSpace($entry.newName)) { $p.currentName } else { $entry.newName }
        $newName = Resolve-Tokens -Value $newName -TenantName $TenantName

        if (Test-HasUnresolvedTokens -Value $newName) {
            Write-Log "Settings Catalog policy '$($p.currentName)' has unresolved tokens in newName: '$newName' - aborting" -Level ERROR
            exit 1
        }

        # Collision check
        if ($scOutputNames.Contains($newName)) {
            Write-Log "Settings Catalog name collision on output: '$newName' - aborting" -Level ERROR
            exit 1
        }
        [void]$scOutputNames.Add($newName)

        # Rename inside JSON (Settings Catalog uses 'name')
        $p.policy.name = $newName

        $safeName = ConvertTo-SafeFileName -Name $newName
        $outFile  = Join-Path $scOut "$safeName.json"

        if ($DryRun) {
            Write-Log "[DryRun] Would write SC: $newName -> $outFile" -Level INFO
        } else {
            $p.policy | ConvertTo-Json -Depth 20 | Set-Content -Path $outFile -Encoding UTF8
            $msg = if ($p.currentName -ne $newName) { "$($p.currentName) -> $newName" } else { $newName }
            Write-Log "Kept SC: $msg" -Level SUCCESS
        }
        $stats.scKept++
    }

    # --- Summary ---
    if (-not $DryRun) {
        $summary = [ordered]@{
            optimizedAt            = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            sourceInputPath        = $InputPath
            mappingFile            = $MappingFile
            tenantName             = $TenantName
            conditionalAccessKept  = $stats.caKept
            settingsCatalogKept    = $stats.scKept
            conditionalAccessExcluded = $stats.caExcluded
            settingsCatalogExcluded   = $stats.scExcluded
        }
        $summaryPath = Join-Path $OutputPath 'optimize-summary.json'
        $summary | ConvertTo-Json -Depth 10 | Set-Content -Path $summaryPath -Encoding UTF8
        Write-Log "Wrote summary to $summaryPath" -Level SUCCESS
    }

    Write-Host ""
    Write-Host "  Conditional Access : kept=$($stats.caKept) excluded=$($stats.caExcluded) missing=$($stats.caMissing)" -ForegroundColor Cyan
    Write-Host "  Settings Catalog   : kept=$($stats.scKept) excluded=$($stats.scExcluded) missing=$($stats.scMissing)" -ForegroundColor Cyan
    Write-Host ""
}

# ============================================================================
# MAIN
# ============================================================================

Write-Host "`n=== Policy Baseline Optimize ===`n" -ForegroundColor Cyan

if (-not (Test-Path $InputPath)) {
    Write-Log "Input path not found: $InputPath" -Level ERROR
    exit 1
}

switch ($PSCmdlet.ParameterSetName) {
    'Generate' {
        Invoke-GenerateMapping -InputPath $InputPath -OutputFile $GenerateMappingFile `
            -PrefixWithTenantToken (-not $NoTenantPrefix.IsPresent)
    }
    'Apply' {
        Invoke-ApplyMapping -InputPath $InputPath -OutputPath $OutputPath `
            -MappingFile $MappingFile -TenantName $TenantName -DryRun:$DryRun
    }
}

Write-Host "=== Done ===`n" -ForegroundColor Green
