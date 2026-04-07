<#
.SYNOPSIS
    IT-Scripts Toolbox Launcher Menu
.NOTES
    Author: Andrew Jones
    Usage: iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Menu.ps1")
#>
#Requires -Version 5.1

$Script:Config = @{
    RepoOwner = "StoicTurk182"
    RepoName  = "IT-Scripts"
    Branch    = "main"
}
$Script:BaseUrl = "https://raw.githubusercontent.com/$($Script:Config.RepoOwner)/$($Script:Config.RepoName)/$($Script:Config.Branch)"

$Script:MenuStructure = [ordered]@{
    "Active Directory" = @(
        @{ Name = "Copy User Groups"; Path = "ActiveDirectory/migrate_groups/migrate_user_group_memberships_param.ps1"; Description = "Copy groups from Source to Target user" }
        @{ Name = "UPN Name Change";  Path = "ActiveDirectory/Rename-UPN/UPN_NameChange.ps1";                          Description = "Change user UPN and display name" }
    )
    "Device Setup" = @(
        @{ Name = "Get Hardware Hash"; Path = "Setup/HWH/hwh.ps1"; Description = "Collect Autopilot hardware hash" }
    )
    "Utilities" = @(
        @{ Name = "Create Backup Folders"; Path = "Utils/BACKUPS/Create_Folders_v2.ps1";                              Description = "Create backup folder structure for migrations" }
        @{ Name = "Install Standard Apps"; Path = "Utils/Install-standard-apps/Install-StandardApps.ps1";             Description = "Auto-installs Winget, 7-Zip, and Notepad++" }
        @{ Name = "Set Screen Lock";       Path = "Utils/Set Screen Lock/Set-AutoLock.ps1";                           Description = "Set Windows Auto-Lock timeout for user and machine" }
        @{ Name = "Export App JSON";       Path = "Utils/Export App JSON/App Export_JSON.ps1";                        Description = "Export list of installed applications to a text file" }
        @{ Name = "Windows Mgmt";          Path = "Utils/Windows mgmt/Win11-FeatureManager.ps1";                      Description = "Manage Windows 11 features and settings" }
        @{ Name = "Set Loc";               Path = "Utils/Set Loc/Set-Region.ps1";                                     Description = "mgmt-Tools general purpose" }
        @{ Name = "Win11 App Manager"; Path = "Utils/Win11-AppManager/Win11-AppManager.ps1";                          Description = "Audit and remove built-in Windows 11 apps with duplicate detection" }
        @{ Name = "Generate WiFi QR Code"; Path = "Utils/WiFi-QR/New-WiFiQRCode.ps1";                                 Description = "Generate a static WiFi QR code PNG from SSID and password" }
    )
    "Windows Autopilot Deployment_WINhome" = @(
        @{ Name = "Create_Bypass";   Path = "Windows Autopilot Deployment_WINhome/Create_Bypass.ps1";   Description = "Create files for Windows ISO modification to prep for Home Edition" }
        @{ Name = "Install_AnyBurn"; Path = "Windows Autopilot Deployment_WINhome/Install_AnyBurn.ps1"; Description = "Install AnyBurn for ISO editing" }
    )
    "Bookmark Management" = @(
        @{ Name = "1. Audit - Check Dead Links";  Path = "Utils/Bookmark_mgmt/Check-Bookmarks-Parallel.ps1"; Description = "Parallel HTTP check of all bookmarks. Produces CSV report. Requires PS7." }
        @{ Name = "2. Organise - Clean and Sort"; Path = "Utils/Bookmark_mgmt/Organise-Bookmarks.ps1";       Description = "Remove dead links, deduplicate, sort into folders. Optionally ingests audit CSV." }
        @{ Name = "3. Export to HTML";            Path = "Utils/Bookmark_mgmt/Export-BookmarksToHtml.ps1";   Description = "Export cleaned bookmarks to Netscape HTML for browser import." }
        @{ Name = "4. Backup Bookmarks";          Path = "Utils/Bookmark_mgmt/Backup-Bookmarks.ps1";         Description = "Backup Edge bookmarks with auto-retention (keeps last 10)" }
    )
    
}


function Show-Banner {
    Clear-Host
    Write-Host "`n  ============================================" -ForegroundColor Cyan
    Write-Host "           IT-SCRIPTS TOOLBOX                 " -ForegroundColor White
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "  Repo: $($Script:Config.RepoOwner)/$($Script:Config.RepoName)`n" -ForegroundColor DarkGray
}

function Show-MainMenu {
    Show-Banner
    Write-Host "  SELECT A CATEGORY:`n" -ForegroundColor Yellow
    $i = 1
    foreach ($cat in $Script:MenuStructure.Keys) {
        Write-Host "    [$i] $cat ($($Script:MenuStructure[$cat].Count) scripts)" -ForegroundColor White
        $i++
    }
    Write-Host "`n    [R] Reload Menu" -ForegroundColor DarkCyan
    Write-Host "    [Q] Quit`n" -ForegroundColor DarkGray
}

function Show-CategoryMenu {
    param ([string]$CategoryName)
    Show-Banner
    Write-Host "  CATEGORY: $CategoryName`n" -ForegroundColor Yellow
    $scripts = $Script:MenuStructure[$CategoryName]
    $i = 1
    foreach ($s in $scripts) {
        Write-Host "    [$i] $($s.Name)" -ForegroundColor White
        Write-Host "        $($s.Description)" -ForegroundColor DarkGray
        $i++
    }
    Write-Host "`n    [B] Back" -ForegroundColor DarkCyan
    Write-Host "    [Q] Quit`n" -ForegroundColor DarkGray
}

function Invoke-RemoteScript {
    param ([string]$ScriptPath, [string]$ScriptName)
    $url = "$($Script:BaseUrl)/$ScriptPath"
    Write-Host "`n  Fetching: $ScriptName" -ForegroundColor Cyan
    Write-Host "  URL: $url" -ForegroundColor DarkGray
    try {
        $content = Invoke-RestMethod -Uri $url -ErrorAction Stop
        Write-Host "`n  Executing..." -ForegroundColor Green
        Write-Host "  ==================================================" -ForegroundColor DarkGray
        Invoke-Expression $content
        Write-Host "  ==================================================" -ForegroundColor DarkGray
        Write-Host "  Complete.`n" -ForegroundColor Green
    }
    catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host "  Press any key..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Main loop
$running = $true
$categoryNames = @($Script:MenuStructure.Keys)

while ($running) {
    Show-MainMenu
    $sel = Read-Host "  Selection"
    
    switch ($sel.ToUpper()) {
        "Q" { $running = $false; Write-Host "`n  Goodbye.`n" -ForegroundColor Cyan }
        "R" {
            try {
                Invoke-Expression (Invoke-RestMethod -Uri "$Script:BaseUrl/Menu.ps1")
                return
            } catch { Write-Host "  Reload failed." -ForegroundColor Red; Start-Sleep 2 }
        }
        default {
            if ($sel -match '^\d+$') {
                $catIdx = [int]$sel - 1
                if ($catIdx -ge 0 -and $catIdx -lt $categoryNames.Count) {
                    $currentCat = $categoryNames[$catIdx]
                    $inCat = $true
                    
                    while ($inCat) {
                        Show-CategoryMenu -CategoryName $currentCat
                        $sSel = Read-Host "  Selection"
                        
                        switch ($sSel.ToUpper()) {
                            "B" { $inCat = $false }
                            "Q" { $inCat = $false; $running = $false; Write-Host "`n  Goodbye.`n" -ForegroundColor Cyan }
                            default {
                                if ($sSel -match '^\d+$') {
                                    $scriptIdx = [int]$sSel - 1
                                    $scriptList = $Script:MenuStructure[$currentCat]
                                    if ($scriptIdx -ge 0 -and $scriptIdx -lt $scriptList.Count) {
                                        $selectedScript = $scriptList[$scriptIdx]
                                        Invoke-RemoteScript -ScriptPath $selectedScript.Path -ScriptName $selectedScript.Name
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}