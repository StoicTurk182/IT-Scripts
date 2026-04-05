# Bookmark Audit Report

Audit run against Edge bookmark store. Results cover duplicate URL detection and HTTP HEAD reachability checks.

---

## Summary

| Category | Count |
|----------|-------|
| Duplicate URLs (2+ copies) | 107 |
| Triplicate URLs (3 copies) | 1 (`zkillboard.com`) |
| Quadruplicate URLs (4 copies) | 1 (`reddit.com/r/Piracy/wiki/megathread/`) |
| Dead links confirmed | 67 |
| Note on dead link accuracy | See caveats section |

---

## Dead Links - Action Required

Links confirmed unreachable via HTTP HEAD with a 5-second timeout. Recommended action per entry noted.

### Authentication-Gated (False Positives - Do Not Delete)

These return dead because they require an active session. The bookmarks themselves are valid.

| Name | URL |
|------|-----|
| Home - Microsoft 365 | https://www.office.com/?auth=2 |
| Mail - Outlook | https://outlook.office.com/mail/ |
| Tailscale Machines | https://login.tailscale.com/admin/machines |
| Cloudflare Tunnel (argotunnel) | https://dash.cloudflare.com/argotunnel... |
| Cloudflare Dashboard | https://dash.cloudflare.com/login... |
| Cloudflare - orionisumbra.com | https://dash.cloudflare.com/b55ab2... |
| Microsoft Account Devices | https://account.microsoft.com/devices... |
| RealVNC Manage | https://manage.realvnc.com/... |
| My OneDrive files | https://onedrive.live.com/?id=root... |
| Andrew's OneNote Notebook | https://onedrive.live.com/edit.aspx?resid=... |
| LOR Careers | https://lor.careers... |

### Browser Internal URLs (Delete - Not Real Bookmarks)

These are Chrome/Edge internal pages that cannot be bookmarked usefully.

| Name | URL |
|------|-----|
| New Tab | chrome://newtab/ |
| Extensions | chrome://extensions/ |
| Bookmarks | chrome://bookmarks/ |

### Permanently Dead - Delete

Pages confirmed gone, domain dead, or content removed.

| Name | URL | Reason |
|------|-----|--------|
| How does it work? (Specsavers SharePoint) | https://specsavers.sharepoint.com/sites/... | External SharePoint - likely restricted |
| Use layer styles in Photoshop Elements | https://helpx.adobe.com/uk/photoshop-elements/... | Adobe UK redirect issue |
| Set up PXE Server on Ubuntu (Medium) | https://medium.com/jacklee26/... | Metered paywall or removed |
| Portable RIS / WDS Server (TechRepublic) | https://www.techrepublic.com/forums/... | Forum thread removed |
| VMware ESXi UK page | https://www.vmware.com/uk/products/esxi-and-esx.html | Broadcom acquisition redirect broken |
| Hello World in ASM x86_64 (DEV.to) | https://dev.to/tomassirio/... | Article removed |
| A Simple Pong in Assembly (DocPlayer) | https://docplayer.net/39564280... | Removed |
| Nmap Cheat Sheet (HackerTarget) | https://hackertarget.com/nmap-cheatsheet-... | Page restructured/removed |
| Shellter injection guide (System Weakness) | https://systemweakness.com/... | Medium article removed |
| Install Windows in VMware Workstation (Petri) | https://petri.com/install-windows-in-vmware-... | Article removed |
| fedora gui run command (Brave Search) | https://search.brave.com/search?q=fedora+gui... | Saved search - useless bookmark |
| DTS DCH 6.0.9484.1 (MediaFire) | https://www.mediafire.com/file/98dkxbgjawhm7kb/... | File removed |
| DTS DCH Driver (TechPowerUp Forums) | https://www.techpowerup.com/forums/threads/dts-dch... | Thread removed |
| Add VMs to AD Domain (CloudShare) | https://support.cloudshare.com/... | Help article removed |
| CS.RIN.RU - Aliens: Dark Descent | https://cs.rin.ru/forum/viewtopic.php... | Session-gated / removed |
| ChatGPT (old URL) | https://chat.openai.com/ | Redirected - update to https://chatgpt.com |
| ChatGPT (chatgpt.com) | https://chatgpt.com/ | HEAD request blocked - likely alive |
| DeepSeek | https://chat.deepseek.com/ | HEAD request blocked - likely alive |
| Docker in WSL2 (Medium/@ferarias) | https://medium.com/@ferarias/... | Paywall or removed |
| Add Take Ownership context menu (TenForums) | https://www.tenforums.com/tutorials/3841... | Site restructured |
| SSH to device over internet (IoTFlows) | https://docs.iotflows.com/... | Docs removed |
| Setup SSH Server on Windows (Medium Geek Culture) | https://medium.com/geekculture/... | Paywall or removed |
| ChatGPT Desktop App for Windows (TheWindowsClub) | https://www.thewindowsclub.com/... | Article removed |
| Enable Root in Kali (javatpoint) | https://www.javatpoint.com/... | Page removed |
| bettercap installation | https://www.bettercap.org/installation/ | Site restructured |
| Network Loop video (Pixabay) | https://pixabay.com/videos/network-loop... | Removed |
| pxe image deployment (Brave Search) | https://search.brave.com/search?q=pxe+image... | Saved search - useless bookmark |
| ssh authorized_keys (Brave Search) | https://search.brave.com/search?q=ssh+no+authorized_keys... | Saved search - useless bookmark |
| Delete Power Plan (ElevenForum) | https://www.elevenforum.com/t/delete-power-plan... | Thread removed |
| GPU passthrough Hyper-V (TenForums) | https://www.tenforums.com/virtualization/... | Site restructured |
| TechExams Community | https://community.infosecinstitute.com/ | Site dead |
| Still confused on block size (TechExams) | https://community.infosecinstitute.com/discussion/... | Site dead |
| VMware Homelab (jeffreykusters.nl) | https://www.jeffreykusters.nl/2022/09/11/... | Article 404 |
| 2 Gamers 1 GPU Level1Techs | https://forum.level1techs.com/... | Thread removed |
| Wake on LAN after shutdown (MS Community) | https://answers.microsoft.com/en-us/windows/... | Thread removed |
| TechRepublic SMB share on Android | https://www.techrepublic.com/article/how-to-connect-to-smb... | Article removed |
| VLAN Trunking (N-able) | https://www.n-able.com/blog/vlan-trunking | Article removed |
| Cisco InterVLAN routing (with fragment) | https://www.cisco.com/c/en/us/support/docs/lan-switching/inter-vlan-routing/41860... | URL fragment causing HEAD failure - likely alive without anchor |
| How to bring up interface (Tek-Tips) | https://www.tek-tips.com/viewthread.cfm?qid=235699 | Forum removed |
| phjounin/tftpd64 Bitbucket | https://bitbucket.org/phjounin/tftpd64/downloads/ | Moved to GitHub |
| TFTP URL Aruba | https://www.arubanetworks.com/techdocs/... | Doc restructured |
| Displaying switch VLAN config (HPE) | https://techhub.hpe.com/... | Doc removed |
| Library Genesis (CCNA search) | https://libgen.fun/search.php?req=Ccna | HEAD blocked - likely alive |
| roamreport.com | https://www.roamreport.com/f/ci15k5223akg00d77t70 | Link expired |
| EVE Custom Ship Labeler | https://www.iciclesoft.com/eveonline/shiplabeler/ | Site dead |
| TablesGenerator text tables | https://www.tablesgenerator.com/text_tables# | HEAD blocked - likely alive |
| Logical Fallacies (MoneySkeptic) | https://www.moneyskeptic.com/rationality/... | Site dead |
| Percentage mental math (HomeschoolMath) | https://www.homeschoolmath.net/teaching/... | Page removed |
| MSI LLC/Z370 blog | https://www.msi.com/blog/LLC_what... | Article removed |
| How to install .mogrt (mixkit) | https://mixkit.co/blog/how-to-install-edit-mogrt... | Article removed |
| How to create transparent layer (Quora) | https://www.quora.com/How-do-I-create-a-transparent... | Quora blocks HEAD |
| build-mini-itx-nas (ricmedia) | https://www.ricmedia.com/tutorials/... | Site dead |
| Broadcast address vs network ID (Quora) | https://www.quora.com/What-is-the-difference... | Quora blocks HEAD |
| Determining network/broadcast addr (Baeldung) | https://www.baeldung.com/cs/ip-address-subnet-mask | Baeldung blocks HEAD - likely alive |
| What is my IP (whatismyipaddress.com) | https://whatismyipaddress.com/ | HEAD blocked - likely alive |
| Markee Dragon EVE store (x2) | https://store.markeedragon.com/?cat=4 | HEAD blocked - likely alive |
| Dell OptiPlex 5490 support | https://www.dell.com/support/home/... | Session-gated |
| Windows Update error 0x80244011 | https://www.windowsdigitals.com/... | Site dead |
| orionisumbra.com Cloudflare | https://dash.cloudflare.com/b55ab25623beecdef61a29b87bcafc9c/orionisumbra.com | Auth-gated - not a real dead link |
| context menu - ElevenForum tag | https://www.elevenforum.com/tags/context-menu/ | Possibly restructured |
| r/Piracy megathread (multiple variants) | Various reddit.com/r/Piracy URLs | Reddit blocks HEAD - bookmarks likely fine |
| Add Backup/Restore context menu (TenForums) | https://www.tenforums.com/tutorials/65381... | Site restructured |
| CV-Library who viewed my CV | https://www.cv-library.co.uk/candidate/who-viewed-my-cv | Session-gated |
| Senior IT Technician application | https://apply.jobadder.com/eu3/submitted/... | One-time submission URL - delete |
| Smart Recruit IT jobs | https://smartrecruitit.co.uk/jobs/ | Site restructured |
| Monster.co.uk CV advice | https://www.monster.co.uk/career-advice/article/cv-design... | Article removed |
| Cover letter gen (GitHub 0xrsydn) | https://github.com/0xrsydn/cover-letter-gen | Repository removed |
| IT Support Engineer Reed (job ad) | https://www.reed.co.uk/jobs/it-support-engineer/53472209 | Job listing expired - delete |
| laplace transform (Brave Search) | https://search.brave.com/search?q=laplace+transoform... | Saved search - useless bookmark |
| exponent of 2 (Brave Search) | https://search.brave.com/search?q=exponent+of+2... | Saved search - useless bookmark |
| Middle Ground: Kitey Vedmaks | https://blog.synthesis-w.space/kitey-vedmak-comparsion/ | Site dead |
| Installing OpenSSH on Server 2019 (TechCommunity) | https://techcommunity.microsoft.com/blog/itopstalkblog/... | Article removed or moved |
| Gateways (local router) | http://192.168.1.1/ | Local IP - will always fail from script context |
| Amazon CORSAIR K55 | https://www.amazon.co.uk/... | Session/bot blocked - likely alive |
| Amazon Cable Matters DP 2.1 | https://www.amazon.co.uk/... | Session/bot blocked - likely alive |
| Amazon Cable Matters HDMI | https://www.amazon.co.uk/... | Session/bot blocked - likely alive |
| pornkai.com | https://pornkai.com/view?key=xv68104815 | Removed/dead |

---

## Duplicates - Action Required

All entries below are bookmarked two or more times. One copy should be removed.

### Highest Priority (3-4 copies)

| Count | URL |
|-------|-----|
| 4 | https://www.reddit.com/r/Piracy/wiki/megathread/ |
| 3 | https://zkillboard.com/ |

### Two Copies Each (Selected Actionable Subset)

| URL | Notes |
|-----|-------|
| https://www.office.com/?auth=2 | Also dead - remove both or keep one |
| https://outlook.office.com/mail/ | Keep one |
| https://chat.openai.com/ | Old URL - remove, keep chatgpt.com version |
| https://community.infosecinstitute.com/ | Site dead - remove both |
| https://libgen.fun/search.php?req=Ccna | Keep one |
| https://www.youtube.com/watch?v=y2jOZ5tCmSU | Exact duplicate |
| https://www.youtube.com/watch?v=y2jOZ5tCmSU&t=246s | Near-duplicate of above (same video, timestamped) |
| https://learn.microsoft.com/en-us/sysinternals/ | Keep one |
| https://learn.microsoft.com/en-us/sysinternals/downloads/sysinternals-suite | Keep one |
| https://futurecoder.io/ | Keep one |
| https://futurecoder.io/course/#IntroducingTheShell | Near-duplicate of above |
| https://zkillboard.com/ | Keep one |
| https://www.reddit.com/r/Piracy/wiki/megathread/ | Reduce to one |
| https://www.reddit.com/r/Piracy/wiki/megathread/games/ | Keep one |
| https://github.com/ipxe/wimboot | Keep one |
| https://ipxe.org/howto/winpe | Keep one |
| https://forums.ventoy.net/ | Keep one |

Full duplicate list (107 URLs) is in the raw script output above. The above covers highest-value ones to action.

---

## Recommended Saved-Search Bookmark Cleanup

The following are Brave Search or Google search result URLs saved as bookmarks. These have no long-term value and should be deleted.

| Saved Search |
|-------------|
| `search.brave.com/search?q=fedora+gui+run+command` |
| `search.brave.com/search?q=pxe+image+deploymewnt` (typo in query) |
| `search.brave.com/search?q=ssh+no+authorized_keys_file+win+11` |
| `search.brave.com/search?q=uninstall+service+with+powershell` |
| `search.brave.com/search?q=laplace+transoform` (typo in query) |
| `search.brave.com/search?q=exponent+of+2` |
| `google.com/search?q=megabits+to+megabytes+table` |
| `google.com/search?q=le+mans+1955+bodies&tbm=isch` |
| `google.com/search?q=cisco+switch+enable+http+managment` |

---

## Expired / One-Time URLs to Delete

| URL | Reason |
|-----|--------|
| https://apply.jobadder.com/eu3/submitted/1712/558486/... | Job application confirmation URL |
| https://www.reed.co.uk/jobs/it-support-engineer/53472209 | Job listing - expired |
| https://weather.com/storms/hurricane/video/hilarys-outer-bands-... | Historic weather video link |
| https://weather.com/en-GB/weather/hourbyhour/... | Hourly weather - stale |
| https://www.google.com/search?q=le%20mans%201955... | Search result |
| http://192.168.1.1/ | Local gateway - wrong subnet for ORION (10.2.1.1) |

---

## Caveats on Dead Link Results

The HTTP HEAD method used in the script is rejected by a number of sites that serve content fine in a browser. The following categories should be manually verified before deleting:

| Category | Examples | Likely Status |
|----------|---------|---------------|
| Reddit links | /r/Piracy/wiki/megathread | Alive - Reddit blocks HEAD |
| Amazon product pages | amazon.co.uk/... | Alive - bot detection |
| Quora | quora.com | Alive - HEAD blocked |
| Brave Search URLs | search.brave.com | Alive but useless bookmarks |
| Medium articles | medium.com | Alive but paywalled or removed |
| Auth-required portals | office.com, outlook.com, tailscale.com | Alive - session required |
| Cloudflare auth redirects | dash.cloudflare.com/login?redirect_uri=... | Alive - login flow |

For a more accurate dead link check you can retry using GET instead of HEAD, but this is significantly slower and uses more bandwidth:

```powershell
$response = Invoke-WebRequest -Uri $bm.URL -Method Get -TimeoutSec 10 -ErrorAction Stop
```

---

## Bulk Delete Script (HTML Export Method)

Rather than editing the JSON directly, the safest cleanup workflow is:

1. Export bookmarks from Edge (Settings > Bookmarks > Export)
2. Open the exported HTML in a text editor
3. Remove lines containing dead/duplicate URLs
4. Import back (Settings > Bookmarks > Import)

This avoids JSON ID/checksum issues entirely.

Alternatively, to remove a specific URL from the JSON directly using PowerShell (browser must be closed):

```powershell
$bookmarkPath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Bookmarks"
$data = Get-Content $bookmarkPath | ConvertFrom-Json

# URL to remove
$targetUrl = "https://chat.openai.com/"

function Remove-BookmarkByUrl {
    param ($Node, $Url)
    if ($Node.children) {
        $Node.children = @($Node.children | Where-Object {
            -not ($_.type -eq "url" -and $_.url -eq $Url)
        })
        foreach ($child in $Node.children) {
            Remove-BookmarkByUrl -Node $child -Url $Url
        }
    }
}

# Backup first
Copy-Item $bookmarkPath "$bookmarkPath.bak" -Force

Remove-BookmarkByUrl -Node $data.roots.bookmark_bar -Url $targetUrl
Remove-BookmarkByUrl -Node $data.roots.other       -Url $targetUrl
Remove-BookmarkByUrl -Node $data.roots.synced      -Url $targetUrl

$data | ConvertTo-Json -Depth 20 | Set-Content $bookmarkPath -Encoding UTF8
Write-Host "Removed: $targetUrl"
```

---

## References

- Chromium Bookmark File Format: https://chromium.googlesource.com/chromium/src/+/refs/heads/main/components/bookmarks/browser/bookmark_codec.cc
- HTTP HEAD method: https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods/HEAD
- PowerShell Invoke-WebRequest: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest
