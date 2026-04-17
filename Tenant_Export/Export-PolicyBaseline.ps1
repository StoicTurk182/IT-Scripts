<#
.SYNOPSIS
    Export Conditional Access policies and Intune Settings Catalog configuration profiles
    from a Microsoft 365 tenant to JSON files.

.DESCRIPTION
    Connects to Microsoft Graph and exports two object types to the specified output folder:
      - Conditional Access policies (/identity/conditionalAccess/policies, v1.0)
      - Intune Settings Catalog configuration policies (/deviceManagement/configurationPolicies, beta)

    Each policy is written as a standalone JSON file. Settings Catalog profiles include their
    nested settings and assignments via $expand. Optionally strips read-only server-assigned
    fields (id, createdDateTime, lastModifiedDateTime) for cleaner templating output.

.PARAMETER TenantId
    Source tenant ID or verified domain (e.g. contoso.onmicrosoft.com).

.PARAMETER ClientId
    App registration Application (Client) ID for app-only auth. Required unless -Interactive is used.

.PARAMETER CertificateThumbprint
    Thumbprint of a certificate in CurrentUser\My for app-only auth. Required unless -Interactive is used.

.PARAMETER Interactive
    Use interactive delegated authentication. Convenient for labbing with a global admin account.

.PARAMETER OutputPath
    Folder to write exports into. Created if missing. Existing content is overwritten.

.PARAMETER IncludeAssignments
    Include Settings Catalog assignments in the exported JSON. Default: $true.
    Assignments contain tenant-specific group IDs and are the "binding layer" the accompanying
    documentation describes.

.PARAMETER StripReadOnlyFields
    Remove server-assigned fields (id, createdDateTime, lastModifiedDateTime, modifiedDateTime,
    templateReference context) so the JSON is closer to an import-ready body. Default: $false
    for the initial inspection pass. Flip to $true once you are ready to generate template bundles.

.EXAMPLE
    .\Export-PolicyBaseline.ps1 -TenantId ajolnet.com -Interactive -OutputPath C:\Lab\Export-Raw

    Interactive export with everything preserved for first-pass inspection.

.EXAMPLE
    .\Export-PolicyBaseline.ps1 -TenantId ajolnet.com -Interactive `
        -OutputPath C:\Lab\Export-Clean -StripReadOnlyFields

    Interactive export with read-only fields stripped.

.EXAMPLE
    .\Export-PolicyBaseline.ps1 -TenantId source.onmicrosoft.com `
        -ClientId abcd1234-... -CertificateThumbprint 1A2B3C... `
        -OutputPath C:\Lab\Export-AppOnly

    Unattended app-only export.

.NOTES
    Author:  Andrew Jones
    Version: 1.0
    Date:    2026-04-17

    Required Microsoft Graph permissions (app or delegated):
      Policy.Read.All
      DeviceManagementConfiguration.Read.All

    Module requirement:
      Microsoft.Graph.Authentication

    Install with:
      Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
#>

#Requires -Version 5.1
#Requires -Modules Microsoft.Graph.Authentication

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter()]
    [string]$ClientId,

    [Parameter()]
    [string]$CertificateThumbprint,

    [Parameter()]
    [switch]$Interactive,

    [Parameter(Mandatory)]
    [string]$OutputPath,

    [Parameter()]
    [bool]$IncludeAssignments = $true,

    [Parameter()]
    [switch]$StripReadOnlyFields
)

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
    $colors = @{
        "INFO"    = "Cyan"
        "SUCCESS" = "Green"
        "WARNING" = "Yellow"
        "ERROR"   = "Red"
    }
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message" -ForegroundColor $colors[$Level]
}

function Invoke-GraphGetAll {
    <#
        Handles Microsoft Graph paging. Returns an array of items aggregated across
        all pages using @odata.nextLink.
    #>
    param ([string]$Uri)
    $results = New-Object System.Collections.ArrayList
    $next = $Uri
    while ($next) {
        try {
            $response = Invoke-MgGraphRequest -Method GET -Uri $next -ErrorAction Stop
        } catch {
            Write-Log "Graph GET failed for $next : $_" -Level ERROR
            throw
        }
        if ($response.value) {
            foreach ($item in $response.value) { [void]$results.Add($item) }
        }
        $next = $response.'@odata.nextLink'
    }
    return ,$results.ToArray()
}

function ConvertTo-SafeFileName {
    <#
        Produces a filesystem-safe kebab-case name from an arbitrary display name.
    #>
    param ([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return "unnamed-$(New-Guid)" }
    $clean = $Name -replace '[\\/:*?"<>|]', '-'
    $clean = $clean -replace '\s+', '-'
    $clean = $clean -replace '-+', '-'
    $clean = $clean.Trim('-').ToLowerInvariant()
    if ($clean.Length -gt 120) { $clean = $clean.Substring(0, 120).TrimEnd('-') }
    return $clean
}

function Remove-ReadOnlyFields {
    <#
        Recursively walks a hashtable (as returned by Invoke-MgGraphRequest) and removes
        fields that are server-assigned or tenant-specific metadata. Leaves the settings
        body intact.
    #>
    param ($Object)

    $stripKeys = @(
        'id',
        'createdDateTime',
        'modifiedDateTime',
        'lastModifiedDateTime',
        '@odata.context',
        '@odata.count',
        '@odata.nextLink'
    )

    function Walk ($o) {
        if ($null -eq $o) { return }
        if ($o -is [System.Collections.IDictionary]) {
            foreach ($key in @($o.Keys)) {
                if ($stripKeys -contains $key) {
                    $o.Remove($key)
                } else {
                    Walk $o[$key]
                }
            }
            return
        }
        if ($o -is [System.Collections.IList]) {
            foreach ($item in $o) { Walk $item }
            return
        }
    }

    Walk $Object
    return $Object
}

function Save-PolicyJson {
    <#
        Saves a policy object to a JSON file with the specified display name as the filename stem.
    #>
    param (
        $Policy,
        [string]$FolderPath,
        [string]$DisplayName
    )
    $safeName = ConvertTo-SafeFileName -Name $DisplayName
    $filePath = Join-Path $FolderPath "$safeName.json"
    $json = $Policy | ConvertTo-Json -Depth 20
    Set-Content -Path $filePath -Value $json -Encoding UTF8
    return $filePath
}

# ============================================================================
# MAIN
# ============================================================================

Write-Host "`n=== Policy Baseline Export ===`n" -ForegroundColor Cyan
Write-Log "Tenant:             $TenantId"
Write-Log "Output path:        $OutputPath"
Write-Log "Include assignments: $IncludeAssignments"
Write-Log "Strip read-only:    $($StripReadOnlyFields.IsPresent)"

# Prepare output folders
$caFolder = Join-Path $OutputPath 'ConditionalAccess'
$scFolder = Join-Path $OutputPath 'SettingsCatalog'

foreach ($p in @($OutputPath, $caFolder, $scFolder)) {
    if (-not (Test-Path $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
}

# -----------------------------------------------------------------------------
# Connect to Graph
# -----------------------------------------------------------------------------
Write-Log "Connecting to Microsoft Graph"
try {
    if ($Interactive) {
        Connect-MgGraph -TenantId $TenantId `
            -Scopes "Policy.Read.All", "DeviceManagementConfiguration.Read.All" `
            -NoWelcome -ErrorAction Stop
    } else {
        if (-not $ClientId -or -not $CertificateThumbprint) {
            throw "Provide -ClientId and -CertificateThumbprint, or use -Interactive."
        }
        Connect-MgGraph -TenantId $TenantId -ClientId $ClientId `
            -CertificateThumbprint $CertificateThumbprint -NoWelcome -ErrorAction Stop
    }
    $ctx = Get-MgContext
    Write-Log "Connected as $($ctx.Account) to tenant $($ctx.TenantId)" -Level SUCCESS
} catch {
    Write-Log "Connection failed: $_" -Level ERROR
    exit 1
}

# -----------------------------------------------------------------------------
# 1. Export Conditional Access policies
# -----------------------------------------------------------------------------
Write-Log "Retrieving Conditional Access policies"
try {
    $caPolicies = Invoke-GraphGetAll -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies"
    Write-Log "Found $($caPolicies.Count) CA policies" -Level SUCCESS
} catch {
    Write-Log "Failed to retrieve CA policies: $_" -Level ERROR
    $caPolicies = @()
}

$caExported = @()
foreach ($policy in $caPolicies) {
    $displayName = $policy.displayName
    if (-not $displayName) { $displayName = "unnamed-ca-$($policy.id)" }

    if ($StripReadOnlyFields) {
        $policy = Remove-ReadOnlyFields -Object $policy
    }

    try {
        $filePath = Save-PolicyJson -Policy $policy -FolderPath $caFolder -DisplayName $displayName
        Write-Log "Exported CA: $displayName" -Level SUCCESS
        $caExported += @{ displayName = $displayName; file = (Split-Path $filePath -Leaf) }
    } catch {
        Write-Log "Failed to export CA policy '$displayName': $_" -Level ERROR
    }
}

# -----------------------------------------------------------------------------
# 2. Export Intune Settings Catalog configuration profiles
# -----------------------------------------------------------------------------
Write-Log "Retrieving Intune Settings Catalog profiles"
try {
    $expand = 'settings'
    if ($IncludeAssignments) { $expand += ',assignments' }
    $uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$expand=$expand"
    $scPolicies = Invoke-GraphGetAll -Uri $uri
    Write-Log "Found $($scPolicies.Count) Settings Catalog profiles" -Level SUCCESS
} catch {
    Write-Log "Failed to retrieve Settings Catalog profiles: $_" -Level ERROR
    $scPolicies = @()
}

$scExported = @()
foreach ($profile in $scPolicies) {
    # Settings Catalog uses 'name' not 'displayName'
    $displayName = $profile.name
    if (-not $displayName) { $displayName = "unnamed-sc-$($profile.id)" }

    if ($StripReadOnlyFields) {
        $profile = Remove-ReadOnlyFields -Object $profile
    }

    try {
        $filePath = Save-PolicyJson -Policy $profile -FolderPath $scFolder -DisplayName $displayName
        Write-Log "Exported SC: $displayName" -Level SUCCESS
        $scExported += @{ name = $displayName; file = (Split-Path $filePath -Leaf) }
    } catch {
        Write-Log "Failed to export Settings Catalog profile '$displayName': $_" -Level ERROR
    }
}

# -----------------------------------------------------------------------------
# 3. Write export summary
# -----------------------------------------------------------------------------
$summary = [ordered]@{
    exportedAt             = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    sourceTenantId         = $ctx.TenantId
    sourceAccount          = $ctx.Account
    scriptVersion          = "1.0"
    stripReadOnlyFields    = $StripReadOnlyFields.IsPresent
    includeAssignments     = $IncludeAssignments
    conditionalAccessCount = $caExported.Count
    settingsCatalogCount   = $scExported.Count
    conditionalAccess      = $caExported
    settingsCatalog        = $scExported
}
$summaryPath = Join-Path $OutputPath 'export-summary.json'
$summary | ConvertTo-Json -Depth 10 | Set-Content -Path $summaryPath -Encoding UTF8
Write-Log "Wrote summary to $summaryPath" -Level SUCCESS

# -----------------------------------------------------------------------------
# Disconnect
# -----------------------------------------------------------------------------
try { Disconnect-MgGraph | Out-Null } catch { }

Write-Host "`n=== Export Complete ===" -ForegroundColor Green
Write-Host "  Conditional Access : $($caExported.Count) policies"
Write-Host "  Settings Catalog   : $($scExported.Count) profiles"
Write-Host "  Output folder      : $OutputPath"
Write-Host ""
