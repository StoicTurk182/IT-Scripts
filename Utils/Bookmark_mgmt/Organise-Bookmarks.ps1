param (
    [string]   $BrowserPath    = '',
    [string]   $AuditCsv       = '',
    [string[]] $RemoveOutcomes = @(),
    [string]   $ReportPath     = '',
    [switch]   $WhatIf
)

Set-StrictMode -Version Latest
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
Write-Host "  Bookmark Organiser v2.1" -ForegroundColor Cyan
Write-Host "================================================`n" -ForegroundColor Cyan

if (-not $BrowserPath) {
    Write-Host "[1/4] Select Edge profile to organise"
    $BrowserPath = Get-EdgeBookmarkPath
    if (-not $BrowserPath) { Write-Error "No bookmark file selected."; exit 1 }
}

if (-not $AuditCsv) {
    Write-Host "`n[2/4] Audit CSV from Check-Bookmarks-Parallel"
    Write-Host "      Leave blank to run without audit data"
    $i = (Read-Host "      CSV path (or Enter to skip)").Trim()
    $AuditCsv = $i
}

if (-not $WhatIf) {
    Write-Host "`n[3/4] Preview mode - no changes will be written"
    $i = (Read-Host "      Preview only? (Y/N, default N)").Trim()
    if ($i -match '^(Y|yes)$') { $WhatIf = $true }
}

if (-not $RemoveOutcomes -or $RemoveOutcomes.Count -eq 0) {
    Write-Host "`n[4/4] Outcomes to auto-remove from audit CSV"
    Write-Host "      Options : DEAD, ERROR, TIMEOUT, SERVER-ERROR, RATELIMITED, AUTH"
    Write-Host "      Note    : Duplicates are always removed automatically regardless of this setting"
    Write-Host "      Default : DEAD,ERROR"
    $i = (Read-Host "      Press Enter for default or type comma-separated list").Trim()
    $RemoveOutcomes = if ($i) { $i -split ',' | ForEach-Object { $_.Trim() } } else { @('DEAD','ERROR') }
}

if (-not $ReportPath) { $ReportPath = "$([Environment]::GetFolderPath('Desktop'))\bookmark-cleanup-report.csv" }

Write-Host ""

# ============================================================================
# CONFIGURATION - Confirmed Dead URLs
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
# CONFIGURATION - Pattern removal
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
# CONFIGURATION - Category Rules
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
# LOAD AUDIT CSV
# ============================================================================

$script:AuditOutcomes  = @{}
$script:FolderOverride = @{}
$script:ManualDeletes  = @{}

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
    Write-Warning "AuditCsv not found: $AuditCsv - continuing without audit data."
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
            $out.Add([PSCustomObject]@{ Name=[string]$item.name; URL=[string]$item.url; DateAdded=[string]$item.date_added; FolderPath=$FolderPath })
        }
        elseif ($item.type -eq 'folder') {
            $sub = if ($FolderPath) { "$FolderPath > $($item.name)" } else { $item.name }
            foreach ($s in (Get-AllBookmarksFlat -Node $item -FolderPath $sub)) { $out.Add($s) }
        }
    }
    return $out
}

function Get-BookmarkCategory {
    param ([string]$Name, [string]$Url)
    if ($script:FolderOverride.ContainsKey($Url)) { return $script:FolderOverride[$Url] }
    foreach ($folder in $CategoryRules.Keys) {
        foreach ($pattern in $CategoryRules[$folder]) { if ($Url -match $pattern) { return $folder } }
    }
    if ($Url -match 'youtube\.com|youtu\.be|m\.youtube\.com') {
        $n = $Name.ToLower()
        if ($n -match 'cisco|network|vlan|pxe|routing|switching|ccna|comptia|subnet|tftp|ipxe')             { return 'Networking and CCNA' }
        if ($n -match 'powershell|intune|azure|defender|active directory|autopilot|m365|office 365|entra')   { return 'Microsoft 365 and Admin' }
        if ($n -match 'kali|wireshark|nmap|hack|pentest|security|malware|inject')                            { return 'Security and Pentesting' }
        if ($n -match 'python|docker|programming|linux|bash|code|script|devop')                              { return 'Programming and Development' }
        if ($n -match 'hyper-v|vmware|virtualiz|wsl|esxi|proxmox|parsec')                                   { return 'Homelab and Virtualisation' }
        if ($n -match 'after effects|premiere|photoshop|adobe|particle|motion|animation|trapcode|mogrt|obs') { return 'Video and Media Production' }
        if ($n -match '\beve\b|zkill|abyss|fleet|pvp|pve|eve online')                                       { return 'EVE Online' }
        if ($n -match 'battletech|aliens.*descent|gaming|fps')                                               { return 'Gaming' }
        return 'Video and Media Production'
    }
    if ($Url -match 'github\.com') {
        $n = $Name.ToLower()
        if ($n -match '\beve\b|zkill|fleet|dscan')                  { return 'EVE Online' }
        if ($n -match 'battletech|game')                            { return 'Gaming' }
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
        children=($Children); date_added=$now; date_modified=$now
        guid=[guid]::NewGuid().ToString(); id=New-NodeId; name=$FolderName; type='folder'
    }
}

# ============================================================================
# MAIN
# ============================================================================

Write-Host "=== Bookmark Cleanup and Organiser v2.1 ===" -ForegroundColor Cyan
Write-Host "Target : $BrowserPath"
if ($AuditCsv) { Write-Host "Audit  : $AuditCsv" }
if ($WhatIf)   { Write-Host "[WHATIF MODE - no changes written]" -ForegroundColor Yellow }
Write-Host ""

if (-not (Test-Path $BrowserPath)) { Write-Error "Bookmarks file not found: $BrowserPath"; exit 1 }

$timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = "$BrowserPath.backup-$timestamp"
if (-not $WhatIf) {
    Copy-Item $BrowserPath $backupPath -Force
    Write-Host "Backup : $backupPath" -ForegroundColor Green
}

$data = Get-Content $BrowserPath -Raw | ConvertFrom-Json
$all  = [System.Collections.Generic.List[PSObject]]::new()
foreach ($bm in (Get-AllBookmarksFlat -Node $data.roots.bookmark_bar -FolderPath 'Bookmark Bar'))   { $all.Add($bm) }
foreach ($bm in (Get-AllBookmarksFlat -Node $data.roots.other        -FolderPath 'Other Bookmarks')) { $all.Add($bm) }
foreach ($bm in (Get-AllBookmarksFlat -Node $data.roots.synced       -FolderPath 'Synced'))          { $all.Add($bm) }

$originalCount = $all.Count
Write-Host "Extracted : $originalCount bookmarks`n"

$removedDead = [System.Collections.Generic.List[PSObject]]::new()
$step1       = [System.Collections.Generic.List[PSObject]]::new()
foreach ($bm in $all) {
    if ($ConfirmedDeadUrls.Contains($bm.URL) -or
        ($script:AuditOutcomes.ContainsKey($bm.URL) -and $script:AuditOutcomes[$bm.URL] -in $RemoveOutcomes) -or
        $script:ManualDeletes.ContainsKey($bm.URL)) { $removedDead.Add($bm) } else { $step1.Add($bm) }
}

$removedJunk = [System.Collections.Generic.List[PSObject]]::new()
$step2       = [System.Collections.Generic.List[PSObject]]::new()
foreach ($bm in $step1) {
    $junk = $false
    foreach ($p in $RemoveIfUrlMatchesPattern) { if ($bm.URL -match $p) { $junk = $true; break } }
    if ($junk) { $removedJunk.Add($bm) } else { $step2.Add($bm) }
}

$seen         = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$removedDupes = [System.Collections.Generic.List[PSObject]]::new()
$unique       = [System.Collections.Generic.List[PSObject]]::new()
foreach ($bm in $step2) { if ($seen.Add($bm.URL)) { $unique.Add($bm) } else { $removedDupes.Add($bm) } }

Write-Host "Removed - dead / audit / manual : $($removedDead.Count)"
Write-Host "Removed - junk/search URLs      : $($removedJunk.Count)"
Write-Host "Removed - duplicates            : $($removedDupes.Count)"
Write-Host "Remaining for organisation      : $($unique.Count)`n"

$categorised = [ordered]@{}
foreach ($bm in $unique) {
    $cat = Get-BookmarkCategory -Name $bm.Name -Url $bm.URL
    if (-not $categorised.Contains($cat)) { $categorised[$cat] = [System.Collections.Generic.List[PSObject]]::new() }
    $categorised[$cat].Add($bm)
}

Write-Host "Category breakdown:"
foreach ($cat in $categorised.Keys) {
    $ov = @($categorised[$cat] | Where-Object { $script:FolderOverride.ContainsKey($_.URL) }).Count
    Write-Host ("  {0,-44} {1}{2}" -f $cat, $categorised[$cat].Count, $(if ($ov -gt 0) { "  [$ov override(s)]" } else { '' }))
}
Write-Host ""

$folderOrder = @(
    'Microsoft 365 and Admin'; 'Intune and Endpoint Management'; 'Azure and Entra'
    'Microsoft Docs and Learn'; 'PowerShell and Scripting'; 'Networking and CCNA'
    'Security and Pentesting'; 'Homelab and Virtualisation'; 'EVE Online'
    'Programming and Development'; 'Video and Media Production'; 'Gaming'
    'Personal'; 'Tools and Utilities'; 'Uncategorised'
)
foreach ($cat in $categorised.Keys) { if ($cat -notin $folderOrder) { $folderOrder += $cat } }

$newBarChildren = [System.Collections.Generic.List[PSObject]]::new()
foreach ($folderName in $folderOrder) {
    if (-not $categorised.Contains($folderName)) { continue }
    $nodes = @($categorised[$folderName] | ForEach-Object { New-UrlNode -Bookmark $_ })
    $newBarChildren.Add((New-FolderNode -FolderName $folderName -Children $nodes))
    Write-Host "  Built: $folderName ($($nodes.Count))"
}

$data.roots.bookmark_bar.children = @($newBarChildren)
$data.roots.other.children        = @()
$data.roots.synced.children       = @()

if (-not $WhatIf) {
    [System.IO.File]::WriteAllText($BrowserPath, ($data | ConvertTo-Json -Depth 50), [System.Text.Encoding]::UTF8)
    Write-Host "`nBookmarks file written." -ForegroundColor Green
} else {
    Write-Host "`n[WhatIf] No changes written." -ForegroundColor Yellow
}

$report = [System.Collections.Generic.List[PSObject]]::new()
foreach ($bm in $removedDead) {
    $reason = if ($script:ManualDeletes.ContainsKey($bm.URL)) { 'Manual delete flag' }
              elseif ($ConfirmedDeadUrls.Contains($bm.URL))   { 'Built-in dead list' }
              elseif ($script:AuditOutcomes.ContainsKey($bm.URL)) { "Audit: $($script:AuditOutcomes[$bm.URL])" }
              else { 'Unknown' }
    $report.Add([PSCustomObject]@{ Action='Removed-Dead'; Reason=$reason; Name=$bm.Name; URL=$bm.URL; NewFolder=''; OriginalFolder=$bm.FolderPath })
}
foreach ($bm in $removedJunk)  { $report.Add([PSCustomObject]@{ Action='Removed-Junk'; Reason='Pattern match'; Name=$bm.Name; URL=$bm.URL; NewFolder=''; OriginalFolder=$bm.FolderPath }) }
foreach ($bm in $removedDupes) { $report.Add([PSCustomObject]@{ Action='Removed-Dupe'; Reason='Duplicate URL'; Name=$bm.Name; URL=$bm.URL; NewFolder=''; OriginalFolder=$bm.FolderPath }) }
foreach ($cat in $categorised.Keys) {
    foreach ($bm in $categorised[$cat]) {
        $report.Add([PSCustomObject]@{
            Action='Kept'; Reason=if ($script:FolderOverride.ContainsKey($bm.URL)) { 'Audit CSV folder override' } else { 'Auto-categorised' }
            Name=$bm.Name; URL=$bm.URL; NewFolder=$cat; OriginalFolder=$bm.FolderPath
        })
    }
}

if (-not $WhatIf) {
    $report | Export-Csv $ReportPath -NoTypeInformation
    Write-Host "Report  : $ReportPath"
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Original   : $originalCount"
Write-Host "Dead/manual: $($removedDead.Count)"
Write-Host "Junk       : $($removedJunk.Count)"
Write-Host "Duplicates : $($removedDupes.Count)"
Write-Host "Final      : $($unique.Count)"
Write-Host "Overrides  : $($script:FolderOverride.Count) applied"
if (-not $WhatIf) { Write-Host "Backup     : $backupPath" }
Write-Host ""

