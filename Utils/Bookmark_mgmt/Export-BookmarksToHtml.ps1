param (
    [string]$BookmarkPath = '',
    [string]$OutputPath   = ''
)

$ErrorActionPreference = 'Stop'

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
Write-Host "  Bookmark HTML Export" -ForegroundColor Cyan
Write-Host "================================================`n" -ForegroundColor Cyan

if (-not $BookmarkPath) {
    Write-Host "[1/2] Select Edge profile to export"
    $BookmarkPath = Get-EdgeBookmarkPath
    if (-not $BookmarkPath) { Write-Error "No bookmark file selected."; exit 1 }
}

if (-not $OutputPath) {
    $def = "$([Environment]::GetFolderPath('Desktop'))\bookmarks-export-$(Get-Date -Format 'yyyyMMdd-HHmm').html"
    Write-Host "`n[2/2] HTML output path"
    Write-Host "  Default    : $def"
    Write-Host "  Running as : $env:USERNAME"
    $i = (Read-Host "  Press Enter for default or paste a different path").Trim()
    $OutputPath = if ($i) { $i } else { $def }
}

Write-Host ""

# ============================================================================
# LOAD BOOKMARKS
# ============================================================================

if (-not (Test-Path $BookmarkPath)) { Write-Error "Bookmarks file not found: $BookmarkPath"; exit 1 }

$data = Get-Content $BookmarkPath -Raw | ConvertFrom-Json

# ============================================================================
# RECURSIVE HTML BUILDER
# ============================================================================

Add-Type -AssemblyName System.Web

function ConvertTo-BookmarkHtml {
    param ($Node, [int]$Depth = 0)

    $indent = '    ' * $Depth
    $sb     = [System.Text.StringBuilder]::new()

    if (-not $Node.PSObject.Properties['children'] -or -not $Node.children) { return '' }

    foreach ($item in $Node.children) {
        if ($item.type -eq 'url') {
            $name      = [System.Web.HttpUtility]::HtmlEncode([string]$item.name)
            $url       = [System.Web.HttpUtility]::HtmlAttributeEncode([string]$item.url)
            $dateAdded = 0
            if ($item.date_added) {
                try {
                    $epoch     = [datetime]'1601-01-01'
                    $dt        = $epoch.AddTicks([long]$item.date_added * 10)
                    $dateAdded = [int64]($dt - [datetime]'1970-01-01').TotalSeconds
                } catch {}
            }
            [void]$sb.AppendLine("$indent<DT><A HREF=`"$url`" ADD_DATE=`"$dateAdded`">$name</A>")
        }
        elseif ($item.type -eq 'folder') {
            $folderName = [System.Web.HttpUtility]::HtmlEncode([string]$item.name)
            [void]$sb.AppendLine("$indent<DT><H3>$folderName</H3>")
            [void]$sb.AppendLine("$indent<DL><p>")
            [void]$sb.Append((ConvertTo-BookmarkHtml -Node $item -Depth ($Depth + 1)))
            [void]$sb.AppendLine("$indent</DL><p>")
        }
    }
    return $sb.ToString()
}

# ============================================================================
# BUILD HTML
# ============================================================================

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('<!DOCTYPE NETSCAPE-Bookmark-file-1>')
[void]$sb.AppendLine('<!-- This is an automatically generated file. DO NOT EDIT! -->')
[void]$sb.AppendLine('<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">')
[void]$sb.AppendLine('<TITLE>Bookmarks</TITLE>')
[void]$sb.AppendLine('<H1>Bookmarks</H1>')
[void]$sb.AppendLine('<DL><p>')

[void]$sb.AppendLine('    <DT><H3 PERSONAL_TOOLBAR_FOLDER="true">Bookmarks bar</H3>')
[void]$sb.AppendLine('    <DL><p>')
[void]$sb.Append((ConvertTo-BookmarkHtml -Node $data.roots.bookmark_bar -Depth 2))
[void]$sb.AppendLine('    </DL><p>')

if ($data.roots.other.children -and $data.roots.other.children.Count -gt 0) {
    [void]$sb.AppendLine('    <DT><H3>Other Bookmarks</H3>')
    [void]$sb.AppendLine('    <DL><p>')
    [void]$sb.Append((ConvertTo-BookmarkHtml -Node $data.roots.other -Depth 2))
    [void]$sb.AppendLine('    </DL><p>')
}

[void]$sb.AppendLine('</DL><p>')

# ============================================================================
# WRITE OUTPUT
# ============================================================================

[System.IO.File]::WriteAllText($OutputPath, $sb.ToString(), [System.Text.Encoding]::UTF8)

$lineCount     = ($sb.ToString() -split "`n").Count
$bookmarkCount = ([regex]::Matches($sb.ToString(), '<DT><A ')).Count

Write-Host "Export complete" -ForegroundColor Green
Write-Host "Output     : $OutputPath"
Write-Host "Bookmarks  : $bookmarkCount"
Write-Host "Lines      : $lineCount"

Write-Host "`nImport into Firefox:" -ForegroundColor Cyan
Write-Host "  Bookmarks menu > Manage Bookmarks (Ctrl+Shift+O)"
Write-Host "  Import and Backup > Import Bookmarks from HTML"
Write-Host "  Select: $OutputPath"

Write-Host "`nImport into Edge:" -ForegroundColor Cyan
Write-Host "  Settings > Favourites > three-dot menu > Import favourites"
Write-Host "  Favourites or bookmarks HTML file"
Write-Host "  Select: $OutputPath"

Write-Host "`nImport into Chrome:" -ForegroundColor Cyan
Write-Host "  chrome://bookmarks > three-dot menu > Import bookmarks"
Write-Host "  Select: $OutputPath"
Write-Host ""

