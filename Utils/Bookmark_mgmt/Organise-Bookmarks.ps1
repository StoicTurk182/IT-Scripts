#Requires -Version 5.1
<#
.SYNOPSIS
    Cleans and re-organises Edge/Chrome bookmarks, optionally driven by an audit CSV.

.DESCRIPTION
    1. Creates a timestamped backup of the Bookmarks file.
    2. Flattens all bookmarks from all three roots.
    3. Removes confirmed dead links (built-in list + audit CSV outcomes + DeleteFlag).
    4. Removes saved search URLs and chrome:// internal pages.
    5. Removes duplicate URLs, keeping first occurrence.
    6. Applies folder overrides from audit CSV (FolderOverride column).
    7. Categorises remaining bookmarks into named folders by URL pattern.
    8. Writes a rebuilt clean Bookmarks JSON to disk.
    9. Exports a CSV summary report of all actions taken.

.PARAMETER BrowserPath
    Path to the Bookmarks JSON file. Defaults to Edge Default profile.

.PARAMETER AuditCsv
    Path to the CSV produced by Check-Bookmarks-Parallel.ps1.
    When supplied:
      - Bookmarks with Outcome in $RemoveOutcomes are removed automatically.
      - Bookmarks with a value in the FolderOverride column are placed in that folder.
      - Bookmarks with DeleteFlag = Y are removed regardless of outcome.

.PARAMETER RemoveOutcomes
    Audit CSV Outcome values that trigger automatic removal.
    Default: DEAD, ERROR.
    TIMEOUT, SERVER-ERROR, RATELIMITED, AUTH excluded by default.

.PARAMETER ReportPath
    Path for the CSV output report. Defaults to Desktop.

.PARAMETER WhatIf
    Preview mode. No changes written to disk.

.EXAMPLE
    # Run without audit CSV (built-in dead list only)
    .\Organise-Bookmarks.ps1

.EXAMPLE
    # Full flow: feed audit CSV in
    .\Organise-Bookmarks.ps1 -AuditCsv "$env:USERPROFILE\Desktop\bookmark-audit-20260404-1430.csv"

.EXAMPLE
    # Preview with extended removal (also remove timeouts)
    .\Organise-Bookmarks.ps1 -AuditCsv ".\audit.csv" -RemoveOutcomes DEAD,ERROR,TIMEOUT -WhatIf

.NOTES
    Author  : Andrew Jones
    Version : 2.0
    IMPORTANT: Close the browser before running.
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [string]   $BrowserPath    = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Bookmarks",
    [string]   $AuditCsv       = '',
    [string[]] $RemoveOutcomes = @('DEAD', 'ERROR'),
    [string]   $ReportPath     = "$env:USERPROFILE\Desktop\bookmark-cleanup-report.csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Null-safe defaults (guards against interactive paste without param() firing)
if (-not $BrowserPath)  { $BrowserPath  = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Bookmarks" }
if (-not $RemoveOutcomes -or $RemoveOutcomes.Count -eq 0) { $RemoveOutcomes = @('DEAD','ERROR') }
if (-not $ReportPath)   { $ReportPath   = "$env:USERPROFILE\Desktop\bookmark-cleanup-report.csv" }

# ============================================================================
# CONFIGURATION - Confirmed Dead URLs (exact match, always removed)
# ============================================================================

$ConfirmedDeadUrls = [System.Collections.Generic.HashSet[string]]@(
    'https://helpx.adobe.com/uk/photoshop-elements/using/layer-styles.html'
    'https://www.techrepublic.com/forums/discussions/portable-ris-wds-server/'
    'https://www.vmware.com/uk/products/esxi-and-esx.html'
    'https://dev.to/tomassirio/hello-world-in-asm-x8664-jg7'
    'https://docplayer.net/39564280-A-simple-pong-in-assembly-language.html'
    'https://hackertarget.com/nmap-cheatsheet-a-quick-reference-guide/'
    'https://systemweakness.com/how-to-inject-malicious-code-inside-exe-files-using-shellter-7e871b60b339'
    'https://petri.com/install-windows-in-vmware-workstation-pro/'
    'https://www.mediafire.com/file/98dkxbgjawhm7kb/DTS_DCH_6.0.9484.1.7z/file#'
    'https://www.techpowerup.com/forums/threads/dts-dch-driver-for-realtek-dts-x.279972/'
    'https://support.cloudshare.com/hc/en-us/articles/200700935-Add-Virtual-Machines-to-an-Active-Directory-Domain-'
    'https://community.infosecinstitute.com/'
    'https://community.infosecinstitute.com/discussion/72044/still-confused-on-how-to-get-block-size'
    'https://blog.synthesis-w.space/kitey-vedmak-comparsion/'
    'https://techcommunity.microsoft.com/blog/itopstalkblog/installing-and-configuring-openssh-on-windows-server-2019/309540'
    'https://docs.iotflows.com/device-management-and-secure-remote-access/ssh-to-your-device-over-the-internet'
    'https://medium.com/geekculture/setup-ssh-server-on-windows-10-11-34c7f096eaff'
    'https://medium.com/@ferarias/docker-in-windows-11-using-wsl2-8e30faddc32c'
    'https://www.thewindowsclub.com/chatgpt-desktop-app-for-windows'
    'https://www.javatpoint.com/enable-root-user-in-kali-linux'
    'https://www.bettercap.org/installation/'
    'https://pixabay.com/videos/network-loop-energy-technology-12716/'
    'https://www.moneyskeptic.com/rationality/logical-fallacies-cheat-sheet'
    'https://www.homeschoolmath.net/teaching/percent/percent_of_number_mental_math.php'
    'https://www.msi.com/blog/LLC_what_is_it_and_why_are_MSI_Z370_motherboards_the_best_choice_for_overclocking'
    'https://mixkit.co/blog/how-to-install-edit-mogrt-file-adobe-premiere-pro/'
    'https://www.ricmedia.com/tutorials/build-mini-itx-nas-raid-server-enterprise-sas-hard-drives'
    'https://www.windowsdigitals.com/0x80244011-windows-update-error-code/'
    'https://smarthomepursuits.com/how-to-create-a-powershell-menu-gui/'
    'https://www.roamreport.com/f/ci15k5223akg00d77t70'
    'https://www.iciclesoft.com/eveonline/shiplabeler/'
    'https://www.tenforums.com/tutorials/3841-add-take-ownership-context-menu-windows-10-a.html'
    'https://www.tenforums.com/tutorials/65381-add-windows-backup-restore-context-menu-windows-10-a.html'
    'https://www.tenforums.com/virtualization/195745-tutorial-passing-through-gpu-hyper-v-guest-vm.html'
    'https://www.elevenforum.com/t/delete-power-plan-in-windows-11.6907/#Two'
    'https://www.elevenforum.com/tags/context-menu/'
    'https://forum.level1techs.com/t/2-gamers-1-gpu-with-hyper-v-gpu-p-gpu-partitioning-finally-made-possible-with-hyperv/172234'
    'https://www.n-able.com/blog/vlan-trunking'
    'https://bitbucket.org/phjounin/tftpd64/downloads/'
    'https://www.arubanetworks.com/techdocs/AOS-CX/10.07/HTML/5200-7849/Content/Chp_Cfg_FW_mgt/FW_mgt_cmds/tft-url.htm'
    'https://techhub.hpe.com/eginfolib/networking/docs/switches/RA/15-18/5998-8155_ra-2620_atmg/content/ch01s04.html'
    'https://www.tek-tips.com/viewthread.cfm?qid=235699'
    'https://medium.com/jacklee26/set-up-pxe-server-on-ubuntu20-04-and-window-10-e69733c1de87'
    'https://premierebro.com/premiere-in-post/dansky-the-secret-to-easy-particle-effects-in-premiere-pro'
    'https://www.quora.com/How-do-I-create-a-transparent-layer-in-After-Effects'
    'https://www.indeed.com/career-advice/career-development/how-to-extract-substring-in-excel'
    'https://www.sljfaq.org/cgi/e2k.cgi'
    'https://ukreloaded.com/beware-psyops-extinction-rebellion-psychological-warfare-against-the-people/'
    'https://www.jeffreykusters.nl/2022/09/11/how-to-build-a-vmware-homelab-step-by-step-tutorial-series-1-introduction-2/'
    'https://apply.jobadder.com/eu3/submitted/1712/558486/or7mrgibbyretegg44sphpyej4'
    'https://www.monster.co.uk/career-advice/article/cv-design-and-formatting'
    'https://github.com/0xrsydn/cover-letter-gen'
    'https://weather.com/storms/hurricane/video/hilarys-outer-bands-flooding-california-desert-town'
    'https://pornkai.com/view?key=xv68104815'
    'https://chat.openai.com/'
    'http://192.168.1.1/'
)

# ============================================================================
# CONFIGURATION - Pattern-based removal (regex on URL)
# ============================================================================

$RemoveIfUrlMatchesPattern = @(
    'search\.brave\.com/search\?'
    '^https?://www\.google\.com/search\?'
    '^chrome://'
    '^about:'
    'reed\.co\.uk/jobs/it-support-engineer/53472209'
    'cv-library\.co\.uk/candidate/who-viewed-my-cv'
    'smartrecruitit\.co\.uk/jobs/'
    'weather\.com/en-GB/weather/hourbyhour'
    'google\.com/search\?q=le%20mans'
    'google\.com/search\?q=megabits'
    'google\.com/search\?q=cisco.*switch.*enable.*http'
)

# ============================================================================
# CONFIGURATION - Category Rules (ordered, first match wins)
# ============================================================================

$CategoryRules = [ordered]@{

    'Intune and Endpoint Management' = @(
        'intune\.microsoft\.com'
        '/endpoint/'
        'microsoft\.com.*(autopilot|laps|defender.*endpoint|win32.*app|compliance.*policy)'
    )
    'Microsoft 365 and Admin' = @(
        'admin\.microsoft\.com'
        'office\.com'
        'outlook\.office'
        'exchange.*admin'
        'microsoft365'
        'copilot\.microsoft'
        'portal\.office'
        'microsoft\.com.*(exchange|sharepoint|teams)'
    )
    'Azure and Entra' = @(
        'entra\.microsoft\.com'
        'portal\.azure\.com'
        'azure\.microsoft\.com'
        'learn\.microsoft\.com.*(azure|entra)'
    )
    'EVE Online' = @(
        'zkillboard\.com'
        'adam4eve\.eu'
        'evemetro\.com'
        'dscan\.info'
        'abysstracker\.com'
        'bravecollective\.com'
        'fuzzwork\.co\.uk'
        'localthreat\.xyz'
        'eveworkbench\.com'
        'eve-scout'
        'dotlan.*eve|evemaps'
        'electusmatari\.com'
        'devfleet/awesome-eve'
        'pochven'
        'eveonline\.com'
        'EveOPlus|erythana.*EveSquadron'
    )
    'Networking and CCNA' = @(
        'cisco\.com'
        'ipxe\.org'
        'rmprepusb\.com'
        'ventoy\.net'
        'manski\.net.*pxe'
        'networkworld\.com'
        'homenethowto\.com'
        'grandmetric\.com'
        'patchbox\.com'
        'stationx\.net'
        'etherboot\.org'
        'fs\.com.*layer'
        'softwaretestinghelp\.com.*(subnet|router|switch)'
        'psychz\.net.*subnet'
        'ionos.*broadcast'
        'baeldung\.com/cs/ip-address'
        'deltaconfig\.com'
    )
    'Security and Pentesting' = @(
        'wireshark\.org'
        'hackertarget\.com'
        'kali\.org'
        'nethunter'
        'ntcore\.com'
        'top-password\.com'
        'Hax4us/Nethunter'
        'aioont/kex'
    )
    'Homelab and Virtualisation' = @(
        'vmware\.com'
        'hub\.docker\.com'
        'docker\.com'
        'getlabsdone\.com'
        'nomachine\.com'
        'realvnc\.com'
        'tailscale\.com'
        'login\.tailscale'
        'cloudflare\.com'
        'dash\.cloudflare'
        'parsecgaming\.com|ParsecGaming'
        'aaalgo/hyperv2hosts'
    )
    'Programming and Development' = @(
        'freecodecamp\.org'
        'futurecoder\.io'
        'w3schools\.com/python'
        'pyinstaller'
        'jetbrains\.com'
        'blackbox.*ai|chat\.blackbox'
        'tobiohlala/Asciify'
        'console\.cloud\.google\.com'
    )
    'PowerShell and Scripting' = @(
        'learn\.microsoft\.com.*powershell'
        'powershellgallery\.com'
        'psgallery'
        'farag2/Sophia'
        'scripting.*blog'
        'pdq\.com'
        'steviecoaster/PSSysadminToolkit'
        'zerotomastery\.io/cheatsheets/vba'
    )
    'Microsoft Docs and Learn' = @(
        'learn\.microsoft\.com'
        'docs\.microsoft\.com'
    )
    'Video and Media Production' = @(
        'adobe\.com'
        'helpx\.adobe'
        'matesfx\.com'
    )
    'Gaming' = @(
        'nexusmods\.com'
        'steamcommunity\.com'
        'fitgirl-repacks'
        'skidrowcodex'
        'allpcworld\.com'
        'filecr\.com'
        'piratedgames'
        'cs\.rin\.ru'
        'gofile\.io'
        'byxatab\.com'
        'reddit\.com/r/[Pp]iracy'
        'github\.com/Igglybuff/awesome-piracy'
        'riverstore/piratedgames'
        'mad2342/CameraUnchained'
        'BattletechModders'
    )
    'Personal' = @(
        'mail\.google\.com'
        'gmail\.com'
        'weather\.com'
        'google\.com/maps'
        'apply4u\.co\.uk'
        'reed\.co\.uk'
        'cv-library\.co\.uk'
        'vodafone\.co\.uk'
        'amazon\.co\.uk'
        'monster\.co\.uk'
        'doogal\.co\.uk'
        'markeedragon\.com'
    )
    'Tools and Utilities' = @(
        'bitwarden\.com'
        'rclone\.org'
        'sysinternals'
        'winutil'
        'ScoopInstaller'
        'pdq\.com'
        'AnalogJ/hatchet'
        'WaqasZafar9/VPN'
        'runasdate'
        'bbc\.co\.uk.*bitesize'
        'mathsisfun\.com'
        'physics\.info'
        'britannica\.com'
        'libretexts\.org'
        'tablesgenerator'
    )
}

# ============================================================================
# LOAD AUDIT CSV (if supplied)
# Script-scope so Get-BookmarkCategory can reach them without passing parameters
# ============================================================================

$script:AuditOutcomes  = @{}   # URL -> Outcome string
$script:FolderOverride = @{}   # URL -> folder name string (from FolderOverride column)
$script:ManualDeletes  = @{}   # URL -> $true (from DeleteFlag column)

if ($AuditCsv -and (Test-Path $AuditCsv)) {
    $auditRows = Import-Csv $AuditCsv
    foreach ($row in $auditRows) {
        if (-not $row.URL) { continue }
        $url = $row.URL.Trim()

        if ($row.Outcome) { $script:AuditOutcomes[$url] = $row.Outcome.Trim() }

        if ($row.PSObject.Properties['FolderOverride'] -and $row.FolderOverride.Trim()) {
            $script:FolderOverride[$url] = $row.FolderOverride.Trim()
        }
        if ($row.PSObject.Properties['DeleteFlag'] -and $row.DeleteFlag -match '^(Y|yes|1|true|delete)$') {
            $script:ManualDeletes[$url] = $true
        }
    }

    Write-Host "Audit CSV loaded  : $($auditRows.Count) entries"
    Write-Host "  Remove outcomes : $($RemoveOutcomes -join ', ')"
    Write-Host "  Matching dead   : $(($auditRows | Where-Object { $_.Outcome -in $RemoveOutcomes }).Count)"
    Write-Host "  Folder overrides: $($script:FolderOverride.Count)"
    Write-Host "  Manual deletes  : $($script:ManualDeletes.Count)`n"
} elseif ($AuditCsv) {
    Write-Warning "AuditCsv not found at: $AuditCsv - continuing without audit data."
}

# ============================================================================
# HELPERS
# ============================================================================

$Script:IdCounter = 500

function New-NodeId { return ([string]($Script:IdCounter++)) }

function Get-WinFileTime {
    $epoch = [datetime]'1601-01-01'
    return [string][math]::Round(([datetime]::UtcNow - $epoch).TotalSeconds * 1000000)
}

function Get-AllBookmarksFlat {
    param ($Node, [string]$FolderPath = '')
    $out = [System.Collections.Generic.List[PSObject]]::new()
    if (-not $Node.PSObject.Properties['children'] -or -not $Node.children) { return $out }
    foreach ($item in $Node.children) {
        if ($item.type -eq 'url') {
            $out.Add([PSCustomObject]@{
                Name       = [string]$item.name
                URL        = [string]$item.url
                DateAdded  = [string]$item.date_added
                FolderPath = $FolderPath
            })
        }
        elseif ($item.type -eq 'folder') {
            $sub     = if ($FolderPath) { "$FolderPath > $($item.name)" } else { $item.name }
            $subList = Get-AllBookmarksFlat -Node $item -FolderPath $sub
            foreach ($s in $subList) { $out.Add($s) }
        }
    }
    return $out
}

function Get-BookmarkCategory {
    param ([string]$Name, [string]$Url)

    # Priority 1: FolderOverride column from audit CSV
    if ($script:FolderOverride.ContainsKey($Url)) {
        return $script:FolderOverride[$Url]
    }

    # Priority 2: Ordered category rules against URL
    foreach ($folder in $CategoryRules.Keys) {
        foreach ($pattern in $CategoryRules[$folder]) {
            if ($Url -match $pattern) { return $folder }
        }
    }

    # Priority 3: YouTube - classify by bookmark name keywords
    if ($Url -match 'youtube\.com|youtu\.be|m\.youtube\.com') {
        $n = $Name.ToLower()
        if ($n -match 'cisco|network|vlan|pxe|routing|switching|ccna|comptia|subnet|tftp|ipxe')            { return 'Networking and CCNA' }
        if ($n -match 'powershell|intune|azure|defender|active directory|autopilot|m365|office 365|entra')  { return 'Microsoft 365 and Admin' }
        if ($n -match 'kali|wireshark|nmap|hack|pentest|security|malware|inject')                           { return 'Security and Pentesting' }
        if ($n -match 'python|docker|programming|linux|bash|code|script|devop')                             { return 'Programming and Development' }
        if ($n -match 'hyper-v|vmware|virtualiz|wsl|esxi|proxmox|parsec')                                  { return 'Homelab and Virtualisation' }
        if ($n -match 'after effects|premiere|photoshop|adobe|particle|motion|animation|trapcode|mogrt|obs') { return 'Video and Media Production' }
        if ($n -match '\beve\b|zkill|abyss|fleet|pvp|pve|eve online')                                      { return 'EVE Online' }
        if ($n -match 'battletech|aliens.*descent|gaming|fps')                                              { return 'Gaming' }
        return 'Video and Media Production'
    }

    # Priority 4: GitHub fallback by name
    if ($Url -match 'github\.com') {
        $n = $Name.ToLower()
        if ($n -match '\beve\b|zkill|fleet|dscan')         { return 'EVE Online' }
        if ($n -match 'battletech|game')                   { return 'Gaming' }
        if ($n -match 'powershell|ps1|script|sophia|intune|win32') { return 'PowerShell and Scripting' }
        return 'Programming and Development'
    }

    return 'Uncategorised'
}

function New-UrlNode {
    param ([PSCustomObject]$Bookmark)
    return [PSCustomObject]@{
        date_added = if ($Bookmark.DateAdded) { $Bookmark.DateAdded } else { Get-WinFileTime }
        guid       = [guid]::NewGuid().ToString()
        id         = New-NodeId
        name       = $Bookmark.Name
        type       = 'url'
        url        = $Bookmark.URL
    }
}

function New-FolderNode {
    param ([string]$FolderName, [array]$Children)
    $now = Get-WinFileTime
    return [PSCustomObject]@{
        children      = $Children
        date_added    = $now
        date_modified = $now
        guid          = [guid]::NewGuid().ToString()
        id            = New-NodeId
        name          = $FolderName
        type          = 'folder'
    }
}

# ============================================================================
# MAIN
# ============================================================================

Write-Host "`n=== Bookmark Cleanup and Organiser v2.0 ===" -ForegroundColor Cyan
Write-Host "Target : $BrowserPath"
if ($AuditCsv) { Write-Host "Audit  : $AuditCsv" }
if ($WhatIfPreference) { Write-Host "[WHATIF MODE - no changes written]`n" -ForegroundColor Yellow }

if (-not (Test-Path $BrowserPath)) { Write-Error "Bookmarks file not found: $BrowserPath"; exit 1 }

# Backup
$timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = "$BrowserPath.backup-$timestamp"
if (-not $WhatIfPreference) {
    Copy-Item $BrowserPath $backupPath -Force
    Write-Host "Backup : $backupPath`n" -ForegroundColor Green
}

# Load and flatten
$data = Get-Content $BrowserPath -Raw | ConvertFrom-Json
$all  = [System.Collections.Generic.List[PSObject]]::new()
foreach ($bm in (Get-AllBookmarksFlat -Node $data.roots.bookmark_bar -FolderPath 'Bookmark Bar'))   { $all.Add($bm) }
foreach ($bm in (Get-AllBookmarksFlat -Node $data.roots.other        -FolderPath 'Other Bookmarks')) { $all.Add($bm) }
foreach ($bm in (Get-AllBookmarksFlat -Node $data.roots.synced       -FolderPath 'Synced'))          { $all.Add($bm) }

$originalCount = $all.Count
Write-Host "Extracted : $originalCount bookmarks`n"

# --- Step 1: Remove dead URLs (built-in + audit outcomes + manual delete flag) ---
$removedDead = [System.Collections.Generic.List[PSObject]]::new()
$step1       = [System.Collections.Generic.List[PSObject]]::new()
foreach ($bm in $all) {
    $isBuiltIn     = $ConfirmedDeadUrls.Contains($bm.URL)
    $isAuditDead   = $script:AuditOutcomes.ContainsKey($bm.URL) -and ($script:AuditOutcomes[$bm.URL] -in $RemoveOutcomes)
    $isManual      = $script:ManualDeletes.ContainsKey($bm.URL)
    if ($isBuiltIn -or $isAuditDead -or $isManual) { $removedDead.Add($bm) }
    else { $step1.Add($bm) }
}

# --- Step 2: Remove pattern-matched junk ---
$removedJunk = [System.Collections.Generic.List[PSObject]]::new()
$step2       = [System.Collections.Generic.List[PSObject]]::new()
foreach ($bm in $step1) {
    $junk = $false
    foreach ($p in $RemoveIfUrlMatchesPattern) { if ($bm.URL -match $p) { $junk = $true; break } }
    if ($junk) { $removedJunk.Add($bm) } else { $step2.Add($bm) }
}

# --- Step 3: Deduplicate ---
$seen         = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$removedDupes = [System.Collections.Generic.List[PSObject]]::new()
$unique       = [System.Collections.Generic.List[PSObject]]::new()
foreach ($bm in $step2) {
    if ($seen.Add($bm.URL)) { $unique.Add($bm) } else { $removedDupes.Add($bm) }
}

Write-Host "Removed - dead / audit / manual : $($removedDead.Count)"
Write-Host "Removed - junk/search URLs      : $($removedJunk.Count)"
Write-Host "Removed - duplicates            : $($removedDupes.Count)"
Write-Host "Remaining for organisation      : $($unique.Count)`n"

# --- Step 4: Categorise ---
$categorised = [ordered]@{}
foreach ($bm in $unique) {
    $cat = Get-BookmarkCategory -Name $bm.Name -Url $bm.URL
    if (-not $categorised.Contains($cat)) {
        $categorised[$cat] = [System.Collections.Generic.List[PSObject]]::new()
    }
    $categorised[$cat].Add($bm)
}

Write-Host "Category breakdown:"
foreach ($cat in $categorised.Keys) {
    $hasOverrides = @($categorised[$cat] | Where-Object { $script:FolderOverride.ContainsKey($_.URL) }).Count
    $tag = if ($hasOverrides -gt 0) { "  [$hasOverrides override(s) from audit CSV]" } else { '' }
    Write-Host ("  {0,-44} {1}{2}" -f $cat, $categorised[$cat].Count, $tag)
}
Write-Host ""

# --- Step 5: Build new folder structure ---
$folderOrder = @(
    'Microsoft 365 and Admin'
    'Intune and Endpoint Management'
    'Azure and Entra'
    'Microsoft Docs and Learn'
    'PowerShell and Scripting'
    'Networking and CCNA'
    'Security and Pentesting'
    'Homelab and Virtualisation'
    'EVE Online'
    'Programming and Development'
    'Video and Media Production'
    'Gaming'
    'Personal'
    'Tools and Utilities'
    'Uncategorised'
)
foreach ($cat in $categorised.Keys) { if ($cat -notin $folderOrder) { $folderOrder += $cat } }

$newBarChildren = [System.Collections.Generic.List[PSObject]]::new()
foreach ($folderName in $folderOrder) {
    if (-not $categorised.Contains($folderName)) { continue }
    $nodes      = @($categorised[$folderName] | ForEach-Object { New-UrlNode -Bookmark $_ })
    $folderNode = New-FolderNode -FolderName $folderName -Children $nodes
    $newBarChildren.Add($folderNode)
    Write-Host "  Built: $folderName ($($nodes.Count))"
}

$data.roots.bookmark_bar.children = @($newBarChildren)
$data.roots.other.children        = @()
$data.roots.synced.children       = @()

# --- Step 6: Write ---
if (-not $WhatIfPreference) {
    [System.IO.File]::WriteAllText($BrowserPath, ($data | ConvertTo-Json -Depth 50), [System.Text.Encoding]::UTF8)
    Write-Host "`nBookmarks file written." -ForegroundColor Green
} else {
    Write-Host "`n[WhatIf] No changes written." -ForegroundColor Yellow
}

# --- Step 7: CSV Report ---
$report = [System.Collections.Generic.List[PSObject]]::new()
foreach ($bm in $removedDead) {
    $reason = if     ($script:ManualDeletes.ContainsKey($bm.URL))  { 'Manual delete flag' }
              elseif ($ConfirmedDeadUrls.Contains($bm.URL))        { 'Built-in dead list' }
              elseif ($script:AuditOutcomes.ContainsKey($bm.URL))  { "Audit: $($script:AuditOutcomes[$bm.URL])" }
              else   { 'Unknown' }
    $report.Add([PSCustomObject]@{ Action='Removed-Dead'; Reason=$reason;         Name=$bm.Name; URL=$bm.URL; NewFolder='';  OriginalFolder=$bm.FolderPath })
}
foreach ($bm in $removedJunk)  { $report.Add([PSCustomObject]@{ Action='Removed-Junk'; Reason='Pattern match'; Name=$bm.Name; URL=$bm.URL; NewFolder=''; OriginalFolder=$bm.FolderPath }) }
foreach ($bm in $removedDupes) { $report.Add([PSCustomObject]@{ Action='Removed-Dupe'; Reason='Duplicate URL'; Name=$bm.Name; URL=$bm.URL; NewFolder=''; OriginalFolder=$bm.FolderPath }) }
foreach ($cat in $categorised.Keys) {
    foreach ($bm in $categorised[$cat]) {
        $overrideUsed = $script:FolderOverride.ContainsKey($bm.URL)
        $report.Add([PSCustomObject]@{
            Action         = 'Kept'
            Reason         = if ($overrideUsed) { 'Audit CSV folder override' } else { 'Auto-categorised' }
            Name           = $bm.Name
            URL            = $bm.URL
            NewFolder      = $cat
            OriginalFolder = $bm.FolderPath
        })
    }
}

if (-not $WhatIfPreference) {
    $report | Export-Csv $ReportPath -NoTypeInformation
    Write-Host "Report  : $ReportPath"
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Original   : $originalCount"
Write-Host "Dead/manual: $($removedDead.Count)"
Write-Host "Junk       : $($removedJunk.Count)"
Write-Host "Duplicates : $($removedDupes.Count)"
Write-Host "Final      : $($unique.Count)"
Write-Host "Overrides  : $($script:FolderOverride.Count) folder overrides applied"
Write-Host "Backup     : $backupPath`n"
