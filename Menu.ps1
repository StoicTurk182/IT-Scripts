<#
.SYNOPSIS
    IT-Scripts Toolbox Launcher Menu
.DESCRIPTION
    Master menu script for executing IT administration scripts directly from GitHub.
.NOTES
    Author: Andrew Jones
    Usage: iex (irm "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Menu.ps1")
#>
#Requires -Version 5.1

$Script:Config = @{
    RepoOwner = "StoicTurk182"
    RepoName  = "IT-Scripts"
    Branch    = "main"
    BaseUrl   = $null
}
$Script:Config.BaseUrl = "https://raw.githubusercontent.com/$($Script:Config.RepoOwner)/$($Script:Config.RepoName)/$($Script:Config.Branch)"

$Script:MenuStructure = @{
    "Active Directory" = @(
        @{ Name = "Copy User Groups (Interactive)"; Path = "ActiveDirectory/migrate_groups/migrate_user_group_memberships_interactive.ps1"; Description = "Copy group memberships interactively" }
        @{ Name = "Copy User Groups (Parameters)"; Path = "ActiveDirectory/migrate_groups/migrate_user_group_memberships_param.ps1"; Description = "Copy group memberships with parameters" }
        @{ Name = "UPN Name Change"; Path = "ActiveDirectory/Rename-UPN/UPN_NameChange.ps1"; Description = "Change user UPN and display name" }
    )
    "Device Setup" = @(
        @{ Name = "Get Hardware Hash"; Path = "Setup/HWH/hwh.ps1"; Description = "Collect Autopilot hardware hash" }
    )
    "Utilities" = @(
        @{ Name = "Create Backup Folders"; Path = "Utils/BACKUPS/Create_Folders_v2.ps1"; Description = "Create backup folder structure for migrations" }
    )
}

function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "           IT-SCRIPTS TOOLBOX                 " -ForegroundColor White
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "  Repo: $($Script:Config.RepoOwner)/$($Script:Config.RepoName)" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-MainMenu {
    Show-Banner
    Write-Host "  SELECT A CATEGORY:" -ForegroundColor Yellow
    Write-Host ""
    $categories = @($Script:MenuStructure.Keys | Sort-Object)
    $index = 1
    foreach ($category in $categories) {
        $count = @($Script:MenuStructure[$category]).Count
        Write-Host "    [$index] $category ($count scripts)" -ForegroundColor White
        $index++
    }
    Write-Host ""
    Write-Host "    [R] Reload Menu" -ForegroundColor DarkCyan
    Write-Host "    [Q] Quit" -ForegroundColor DarkGray
    Write-Host ""
    return $categories
}

function Show-CategoryMenu {
    param ([string]$CategoryName)
    Show-Banner
    Write-Host "  CATEGORY: $CategoryName" -ForegroundColor Yellow
    Write-Host ""
    $scripts = @($Script:MenuStructure[$CategoryName])
    if ($scripts.Count -eq 0) {
        Write-Host "    No scripts in this category." -ForegroundColor DarkGray
    }
    else {
        $index = 1
        foreach ($s in $scripts) {
            Write-Host "    [$index] $($s.Name)" -ForegroundColor White
            Write-Host "        $($s.Description)" -ForegroundColor DarkGray
            $index++
        }
    }
    Write-Host ""
    Write-Host "    [B] Back" -ForegroundColor DarkCyan
    Write-Host "    [Q] Quit" -ForegroundColor DarkGray
    Write-Host ""
    return $scripts
}

function Invoke-RemoteScript {
    param ([string]$ScriptPath, [string]$ScriptName)
    $url = "$($Script:Config.BaseUrl)/$ScriptPath"
    Write-Host ""
    Write-Host "  Fetching: $ScriptName" -ForegroundColor Cyan
    Write-Host "  URL: $url" -ForegroundColor DarkGray
    try {
        $content = Invoke-RestMethod -Uri $url -ErrorAction Stop
        Write-Host ""
        Write-Host "  Executing..." -ForegroundColor Green
        Write-Host "  ==================================================" -ForegroundColor DarkGray
        Invoke-Expression $content
        Write-Host "  ==================================================" -ForegroundColor DarkGray
        Write-Host "  Complete." -ForegroundColor Green
    }
    catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "  Press any key..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Start-ToolboxMenu {
    $running = $true
    while ($running) {
        $categories = @(Show-MainMenu)
        $sel = Read-Host "  Selection"
        switch ($sel.ToUpper()) {
            "Q" {
                $running = $false
                Write-Host ""
                Write-Host "  Goodbye." -ForegroundColor Cyan
                Write-Host ""
            }
            "R" {
                try {
                    $menuUrl = "$($Script:Config.BaseUrl)/Menu.ps1"
                    Invoke-Expression (Invoke-RestMethod -Uri $menuUrl)
                    return
                }
                catch {
                    Write-Host "  Reload failed." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                }
            }
            default {
                if ($sel -match '^\d+$') {
                    $idx = [int]$sel - 1
                    if ($idx -ge 0 -and $idx -lt $categories.Count) {
                        $selectedCat = $categories[$idx]
                        $inCat = $true
                        while ($inCat) {
                            $scripts = @(Show-CategoryMenu -CategoryName $selectedCat)
                            $sSel = Read-Host "  Selection"
                            switch ($sSel.ToUpper()) {
                                "B" { $inCat = $false }
                                "Q" {
                                    $inCat = $false
                                    $running = $false
                                    Write-Host ""
                                    Write-Host "  Goodbye." -ForegroundColor Cyan
                                    Write-Host ""
                                }
                                default {
                                    if ($sSel -match '^\d+$') {
                                        $sIdx = [int]$sSel - 1
                                        if ($sIdx -ge 0 -and $sIdx -lt $scripts.Count) {
                                            Invoke-RemoteScript -ScriptPath $scripts[$sIdx].Path -ScriptName $scripts[$sIdx].Name
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
}

Start-ToolboxMenu