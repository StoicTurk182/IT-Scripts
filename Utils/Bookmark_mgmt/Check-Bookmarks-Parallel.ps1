param (
    [string]$BookmarkPath  = '',
    [int]   $ThrottleLimit = 0,
    [int]   $TimeoutSec    = 0,
    [string]$ReportPath    = ''
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "`nThis script requires PowerShell 7 or later." -ForegroundColor Red
    Write-Host "Your version: $($PSVersionTable.PSVersion)"
    Write-Host "Download PS7: https://github.com/PowerShell/PowerShell/releases`n"
    exit 1
}

# ============================================================================
# EDGE PROFILE DISCOVERY
# ============================================================================

function Get-EdgeBookmarkPath {
    $userDataRoot = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    if (-not (Test-Path $userDataRoot)) { Write-Warning "Edge User Data not found: $userDataRoot"; return $null }

    $profiles = Get-ChildItem $userDataRoot -Directory |
        Where-Object { Test-Path "$($_.FullName)\Bookmarks" } |
        ForEach-Object {
            $displayName = $_.Name
            $prefFile    = "$($_.FullName)\Preferences"
            if (Test-Path $prefFile) {
                try { $n = (Get-Content $prefFile -Raw | ConvertFrom-Json).profile.name; if ($n) { $displayName = $n } } catch {}
            }
            [PSCustomObject]@{ Index=0; FolderName=$_.Name; DisplayName=$displayName; FullPath="$($_.FullName)\Bookmarks" }
        } | Sort-Object FolderName

    if (-not $profiles -or $profiles.Count -eq 0) { Write-Warning "No Edge profiles with bookmarks found."; return $null }

    $i = 1; foreach ($p in $profiles) { $p.Index = $i++ }

    if ($profiles.Count -eq 1) {
        Write-Host "Profile : $($profiles[0].DisplayName) ($($profiles[0].FolderName))"
        return $profiles[0].FullPath
    }

    Write-Host "Edge profiles found:"
    foreach ($p in $profiles) { Write-Host ("  [{0}] {1,-30} {2}" -f $p.Index, $p.DisplayName, $p.FolderName) }
    Write-Host "  [C] Custom path`n"

    do {
        $sel = (Read-Host "  Select profile number (or C for custom)").Trim()
        if ($sel -match '^[Cc]$') {
            $custom = (Read-Host "  Paste full Bookmarks path").Trim()
            if (Test-Path $custom) { return $custom }
            Write-Warning "Path not found: $custom"; return $null
        }
        $match = $profiles | Where-Object { $_.Index -eq [int]$sel }
    } until ($match)

    Write-Host "  Selected: $($match.DisplayName) ($($match.FolderName))`n"
    return $match.FullPath
}

# ============================================================================
# INTERACTIVE MODE
# ============================================================================

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Bookmark Audit - Parallel Link Checker v1.1" -ForegroundColor Cyan
Write-Host "================================================`n" -ForegroundColor Cyan

if (-not $BookmarkPath) {
    Write-Host "[1/3] Select Edge profile to audit"
    $BookmarkPath = Get-EdgeBookmarkPath
    if (-not $BookmarkPath) { Write-Error "No bookmark file selected."; exit 1 }
}

if ($ThrottleLimit -lt 1) {
    Write-Host "`n[2/3] Concurrent requests (throttle limit)"
    Write-Host "      Default: 30  |  Recommended range: 10-50"
    $i = (Read-Host "      Press Enter for default or type a number").Trim()
    $ThrottleLimit = if ($i -match '^\d+$') { [int]$i } else { 30 }
}

if ($TimeoutSec -lt 1) {
    Write-Host "`n[3/3] Timeout per request in seconds"
    Write-Host "      Default: 8"
    $i = (Read-Host "      Press Enter for default or type a number").Trim()
    $TimeoutSec = if ($i -match '^\d+$') { [int]$i } else { 8 }
}

if (-not $ReportPath) {
    $def = "$env:USERPROFILE\Desktop\bookmark-audit-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
    Write-Host "`nReport output path"
    Write-Host "  Default : $def"
    Write-Host "  Running as : $env:USERNAME"
    $i = (Read-Host "  Press Enter for default or paste a different path").Trim()
    $ReportPath = if ($i) { $i } else { $def }
}


Write-Host ""

# ============================================================================
# LOAD AND FLATTEN BOOKMARKS
# ============================================================================

if (-not (Test-Path $BookmarkPath)) { Write-Error "Bookmarks file not found: $BookmarkPath"; exit 1 }

$bookmarks = Get-Content $BookmarkPath -Raw | ConvertFrom-Json

function Get-AllBookmarks {
    param ($Node)
    if (-not $Node.PSObject.Properties['children'] -or -not $Node.children) { return }
    foreach ($item in $Node.children) {
        if ($item.type -eq 'url') { [PSCustomObject]@{ Name = [string]$item.name; URL = [string]$item.url } }
        if ($item.type -eq 'folder') { Get-AllBookmarks -Node $item }
    }
}

$allBookmarks  = @()
$allBookmarks += Get-AllBookmarks -Node $bookmarks.roots.bookmark_bar
$allBookmarks += Get-AllBookmarks -Node $bookmarks.roots.other
$allBookmarks += Get-AllBookmarks -Node $bookmarks.roots.synced

Write-Host "Total bookmarks : $($allBookmarks.Count)"
Write-Host "Throttle limit  : $ThrottleLimit concurrent requests"
Write-Host "Timeout         : $TimeoutSec seconds per request`n"

# ============================================================================
# DUPLICATE CHECK
# ============================================================================

$duplicates = $allBookmarks | Group-Object -Property URL | Where-Object { $_.Count -gt 1 }
if ($duplicates) {
    Write-Host "Duplicates found: $($duplicates.Count) URLs" -ForegroundColor Yellow
    $duplicates | Select-Object Count, Name | Sort-Object Count -Descending | Format-Table -AutoSize
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
    $status     = $null
    $outcome    = $null
    $note       = $null
    $handler    = $null
    $client     = $null

    try {
        $handler = [System.Net.Http.HttpClientHandler]::new()
        $handler.AllowAutoRedirect        = $true
        $handler.MaxAutomaticRedirections = 5
        $handler.ServerCertificateCustomValidationCallback =
            [System.Net.Http.HttpClientHandler]::DangerousAcceptAnyServerCertificateValidator

        $client         = [System.Net.Http.HttpClient]::new($handler)
        $client.Timeout = [System.TimeSpan]::FromSeconds($timeoutSec)
        $client.DefaultRequestHeaders.UserAgent.ParseAdd(
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0 Safari/537.36'
        )

        $request  = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Head, [System.Uri]$bm.URL)
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $status   = [int]$response.StatusCode

        if     ($status -in 200..299)            { $outcome = 'OK';           $note = "HTTP $status" }
        elseif ($status -in 301,302,303,307,308) { $outcome = 'OK';           $note = "HTTP $status (redirect)" }
        elseif ($status -in 401,403,407)         { $outcome = 'AUTH';         $note = "HTTP $status (auth-gated, likely alive)" }
        elseif ($status -eq 405)                 { $outcome = 'OK';           $note = "HTTP 405 (HEAD not allowed, site alive)" }
        elseif ($status -eq 429)                 { $outcome = 'RATELIMITED';  $note = "HTTP 429 (rate limited, likely alive)" }
        elseif ($status -ge 500)                 { $outcome = 'SERVER-ERROR'; $note = "HTTP $status (server error)" }
        else                                     { $outcome = 'DEAD';         $note = "HTTP $status" }
    }
    catch [System.UriFormatException]                    { $outcome = 'ERROR';   $note = "Invalid URL format" }
    catch [System.Threading.Tasks.TaskCanceledException] { $outcome = 'TIMEOUT'; $note = "Timed out after ${timeoutSec}s" }
    catch [System.Net.Http.HttpRequestException]         { $outcome = 'DEAD';    $note = $_.Exception.Message -replace '\r?\n',' ' }
    catch                                                { $outcome = 'ERROR';   $note = $_.Exception.Message -replace '\r?\n',' ' }
    finally {
        if ($client)  { $client.Dispose() }
        if ($handler) { $handler.Dispose() }
    }

    [PSCustomObject]@{
        Outcome        = $outcome
        Status         = $status
        Name           = $bm.Name
        URL            = $bm.URL
        Note           = $note
        FolderOverride = ''
        DeleteFlag     = ''
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
Write-Host ("OK            : {0}"                -f $ok.Count)          -ForegroundColor Green
Write-Host ("Auth-gated    : {0} (likely alive)" -f $auth.Count)        -ForegroundColor DarkYellow
Write-Host ("Rate limited  : {0} (likely alive)" -f $rateLimited.Count) -ForegroundColor DarkYellow
Write-Host ("Timed out     : {0}"                -f $timeouts.Count)    -ForegroundColor Yellow
Write-Host ("Server errors : {0}"                -f $serverErr.Count)   -ForegroundColor Yellow
Write-Host ("Dead          : {0}"                -f $dead.Count)        -ForegroundColor Red
Write-Host ("Errors        : {0}"                -f $errors.Count)      -ForegroundColor Red

if ($dead.Count -gt 0) {
    Write-Host "`n--- Confirmed Dead ---" -ForegroundColor Red
    $dead | Select-Object Name, URL, Note | Format-Table -AutoSize -Wrap
}
if ($timeouts.Count -gt 0) {
    Write-Host "`n--- Timed Out ---" -ForegroundColor Yellow
    $timeouts | Select-Object Name, URL | Format-Table -AutoSize -Wrap
}
if ($auth.Count -gt 0) {
    Write-Host "`n--- Auth-Gated (likely alive) ---" -ForegroundColor DarkYellow
    $auth | Select-Object Name, URL, Note | Format-Table -AutoSize -Wrap
}

$results | Sort-Object Outcome, Name | Export-Csv -Path $ReportPath -NoTypeInformation
Write-Host "`nReport saved : $ReportPath" -ForegroundColor Green
Write-Host "Open in Excel, fill FolderOverride / DeleteFlag columns, then run Organise-Bookmarks.ps1 with -AuditCsv.`n"

Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Total checked : $($allBookmarks.Count)"
Write-Host "OK            : $($ok.Count)"
Write-Host "Auth-gated    : $($auth.Count)"
Write-Host "Rate limited  : $($rateLimited.Count)"
Write-Host "Timed out     : $($timeouts.Count)"
Write-Host "Server errors : $($serverErr.Count)"
Write-Host "Dead          : $($dead.Count)"
Write-Host "Errors        : $($errors.Count)"
Write-Host ""
