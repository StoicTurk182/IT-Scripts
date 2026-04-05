#Requires -Version 7.0
<#
.SYNOPSIS
    Audits Edge bookmarks for duplicates and dead links using parallel HTTP checks.

.DESCRIPTION
    1. Loads and flattens all bookmarks from all three roots.
    2. Reports duplicate URLs.
    3. Checks all URLs in parallel using ForEach-Object -Parallel.
    4. Outputs results to console and exports a CSV report.

.PARAMETER BookmarkPath
    Path to the Bookmarks file. Defaults to Edge Default profile.

.PARAMETER ThrottleLimit
    Maximum number of concurrent HTTP requests. Default: 30.
    Lower this on slow connections or if sites start rate-limiting.

.PARAMETER TimeoutSec
    Per-request timeout in seconds. Default: 8.

.PARAMETER ReportPath
    Path for the CSV output report. Defaults to Desktop.

.EXAMPLE
    .\Check-Bookmarks-Parallel.ps1

.EXAMPLE
    .\Check-Bookmarks-Parallel.ps1 -ThrottleLimit 15 -TimeoutSec 10

.NOTES
    Author  : Andrew Jones
    Version : 1.0
    Requires: PowerShell 7.0+ (ForEach-Object -Parallel)
    Check PS version: $PSVersionTable.PSVersion
#>

[CmdletBinding()]
param (
    [string]$BookmarkPath  = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Bookmarks",
    [int]   $ThrottleLimit = 30,
    [int]   $TimeoutSec    = 8,
    [string]$ReportPath    = "$env:USERPROFILE\Desktop\bookmark-audit-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
)

$ErrorActionPreference = 'Stop'

# Guard against null params when sourced interactively rather than run as a .ps1 file
if (-not $BookmarkPath)                          { $BookmarkPath  = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Bookmarks" }
if (-not $ThrottleLimit -or $ThrottleLimit -lt 1){ $ThrottleLimit = 30 }
if (-not $TimeoutSec    -or $TimeoutSec    -lt 1){ $TimeoutSec    = 8  }
if (-not $ReportPath)                            { $ReportPath    = "$env:USERPROFILE\Desktop\bookmark-audit-$(Get-Date -Format 'yyyyMMdd-HHmm').csv" }

# ============================================================================
# LOAD AND FLATTEN BOOKMARKS
# ============================================================================

if (-not (Test-Path $BookmarkPath)) {
    Write-Error "Bookmarks file not found: $BookmarkPath"
    exit 1
}

$bookmarks = Get-Content $BookmarkPath -Raw | ConvertFrom-Json

function Get-AllBookmarks {
    param ($Node)
    if (-not $Node.PSObject.Properties['children'] -or -not $Node.children) { return }
    foreach ($item in $Node.children) {
        if ($item.type -eq 'url') {
            [PSCustomObject]@{ Name = [string]$item.name; URL = [string]$item.url }
        }
        if ($item.type -eq 'folder') {
            Get-AllBookmarks -Node $item
        }
    }
}

$allBookmarks  = @()
$allBookmarks += Get-AllBookmarks -Node $bookmarks.roots.bookmark_bar
$allBookmarks += Get-AllBookmarks -Node $bookmarks.roots.other
$allBookmarks += Get-AllBookmarks -Node $bookmarks.roots.synced

Write-Host "`n=== Bookmark Audit ===" -ForegroundColor Cyan
Write-Host "Total bookmarks : $($allBookmarks.Count)"
Write-Host "Throttle limit  : $ThrottleLimit concurrent requests"
Write-Host "Timeout         : $TimeoutSec seconds per request`n"

# ============================================================================
# DUPLICATE CHECK
# ============================================================================

$duplicates = $allBookmarks | Group-Object -Property URL | Where-Object { $_.Count -gt 1 }

if ($duplicates) {
    Write-Host "Duplicates found: $($duplicates.Count) URLs" -ForegroundColor Yellow
    $duplicates |
        Select-Object Count, Name |
        Sort-Object Count -Descending |
        Format-Table -AutoSize
} else {
    Write-Host "No duplicates found." -ForegroundColor Green
}

# ============================================================================
# PARALLEL DEAD LINK CHECK
# ============================================================================

Write-Host "Checking $($allBookmarks.Count) URLs in parallel (throttle: $ThrottleLimit)..." -ForegroundColor Cyan

$results = $allBookmarks | ForEach-Object -Parallel {
    $bm         = $_
    $timeoutSec = $using:TimeoutSec

    $status  = $null
    $outcome = $null
    $note    = $null

    $handler = $null
    $client  = $null

    try {
        $handler = [System.Net.Http.HttpClientHandler]::new()
        $handler.AllowAutoRedirect    = $true
        $handler.MaxAutomaticRedirections = 5
        # Accept any certificate (equivalent to -SkipCertificateCheck, avoids SSL dead-link false positives)
        $handler.ServerCertificateCustomValidationCallback =
            [System.Net.Http.HttpClientHandler]::DangerousAcceptAnyServerCertificateValidator

        $client          = [System.Net.Http.HttpClient]::new($handler)
        $client.Timeout  = [System.TimeSpan]::FromSeconds($timeoutSec)
        $client.DefaultRequestHeaders.UserAgent.ParseAdd(
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0 Safari/537.36'
        )

        $request  = [System.Net.Http.HttpRequestMessage]::new(
            [System.Net.Http.HttpMethod]::Head,
            [System.Uri]$bm.URL
        )
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $status   = [int]$response.StatusCode

        if ($status -in 200..299) {
            $outcome = 'OK'
            $note    = "HTTP $status"
        } elseif ($status -in 301, 302, 303, 307, 308) {
            $outcome = 'OK'
            $note    = "HTTP $status (redirect)"
        } elseif ($status -in 401, 403, 407) {
            $outcome = 'AUTH'
            $note    = "HTTP $status (auth-gated, likely alive)"
        } elseif ($status -eq 405) {
            # HEAD not allowed - site is alive, just rejects HEAD
            $outcome = 'OK'
            $note    = "HTTP 405 (HEAD not allowed, site alive)"
        } elseif ($status -eq 429) {
            $outcome = 'RATELIMITED'
            $note    = "HTTP 429 (rate limited, likely alive)"
        } elseif ($status -ge 500) {
            $outcome = 'SERVER-ERROR'
            $note    = "HTTP $status (server error)"
        } else {
            $outcome = 'DEAD'
            $note    = "HTTP $status"
        }
    }
    catch [System.UriFormatException] {
        $outcome = 'ERROR'
        $note    = "Invalid URL format"
    }
    catch [System.Threading.Tasks.TaskCanceledException] {
        $outcome = 'TIMEOUT'
        $note    = "Timed out after ${timeoutSec}s"
    }
    catch [System.Net.Http.HttpRequestException] {
        $outcome = 'DEAD'
        $note    = $_.Exception.Message -replace '\r?\n', ' '
    }
    catch {
        $outcome = 'ERROR'
        $note    = $_.Exception.Message -replace '\r?\n', ' '
    }
    finally {
        if ($client)  { $client.Dispose() }
        if ($handler) { $handler.Dispose() }
    }

    [PSCustomObject]@{
        Outcome = $outcome
        Status  = $status
        Name    = $bm.Name
        URL     = $bm.URL
        Note    = $note
    }

} -ThrottleLimit $ThrottleLimit

# ============================================================================
# OUTPUT RESULTS
# ============================================================================

$ok          = $results | Where-Object Outcome -eq 'OK'
$auth        = $results | Where-Object Outcome -eq 'AUTH'
$rateLimited = $results | Where-Object Outcome -eq 'RATELIMITED'
$timeouts    = $results | Where-Object Outcome -eq 'TIMEOUT'
$serverErr   = $results | Where-Object Outcome -eq 'SERVER-ERROR'
$dead        = $results | Where-Object Outcome -eq 'DEAD'
$errors      = $results | Where-Object Outcome -eq 'ERROR'

Write-Host "`n=== Results ===" -ForegroundColor Cyan
Write-Host ("OK            : {0}" -f $ok.Count)          -ForegroundColor Green
Write-Host ("Auth-gated    : {0} (likely alive)" -f $auth.Count)  -ForegroundColor DarkYellow
Write-Host ("Rate limited  : {0} (likely alive)" -f $rateLimited.Count) -ForegroundColor DarkYellow
Write-Host ("Timed out     : {0}" -f $timeouts.Count)    -ForegroundColor Yellow
Write-Host ("Server errors : {0}" -f $serverErr.Count)   -ForegroundColor Yellow
Write-Host ("DEAD          : {0}" -f $dead.Count)        -ForegroundColor Red
Write-Host ("Errors        : {0}" -f $errors.Count)      -ForegroundColor Red

if ($dead.Count -gt 0) {
    Write-Host "`n--- Confirmed Dead ---" -ForegroundColor Red
    $dead | Select-Object Name, URL, Note | Format-Table -AutoSize -Wrap
}

if ($timeouts.Count -gt 0) {
    Write-Host "`n--- Timed Out (investigate manually) ---" -ForegroundColor Yellow
    $timeouts | Select-Object Name, URL | Format-Table -AutoSize -Wrap
}

if ($auth.Count -gt 0) {
    Write-Host "`n--- Auth-Gated (portal/session URLs) ---" -ForegroundColor DarkYellow
    $auth | Select-Object Name, URL, Note | Format-Table -AutoSize -Wrap
}

# ============================================================================
# CSV REPORT
# ============================================================================

$results |
    Sort-Object Outcome, Name |
    Export-Csv -Path $ReportPath -NoTypeInformation

Write-Host "`nReport saved to: $ReportPath" -ForegroundColor Green

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Total checked : $($allBookmarks.Count)"
Write-Host "OK            : $($ok.Count)"
Write-Host "Auth-gated    : $($auth.Count)"
Write-Host "Rate limited  : $($rateLimited.Count)"
Write-Host "Timed out     : $($timeouts.Count)"
Write-Host "Server errors : $($serverErr.Count)"
Write-Host "Dead          : $($dead.Count)"
Write-Host "Errors        : $($errors.Count)"
Write-Host ""
