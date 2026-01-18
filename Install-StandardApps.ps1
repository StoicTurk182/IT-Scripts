<#
.SYNOPSIS
    Installs standard software using Winget.
.DESCRIPTION
    1. Checks for Winget.
    2. Installs Winget automatically if missing.
    3. Installs/Upgrades 7-Zip and Notepad++.
#>

$AppsToInstall = @(
    "7zip.7zip",
    "Notepad++.Notepad++"
)

function Write-Log {
    param ([string]$Message, [string]$Color="White")
    $TimeStamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$TimeStamp] $Message" -ForegroundColor $Color
}

function Install-WingetProvider {
    Write-Log "Winget not found. Attempting to install..." -Color Yellow
    try {
        # 1. Get the URL for the latest Winget release from GitHub API
        $LatestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $Asset = $LatestRelease.assets | Where-Object { $_.name -like "*.msixbundle" } | Select-Object -First 1
        
        if (-not $Asset) { throw "Could not find Winget download URL." }

        # 2. Download to Temp
        $DownloadPath = "$env:TEMP\winget.msixbundle"
        Write-Log "Downloading Winget ($($Asset.size / 1MB | Math::Round(2)) MB)..." -Color Cyan
        Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $DownloadPath -UseBasicParsing

        # 3. Install
        Write-Log "Installing Winget..." -Color Cyan
        Add-AppxPackage -Path $DownloadPath -ErrorAction Stop
        
        Write-Log "Winget installed successfully!" -Color Green
        return $true
    }
    catch {
        Write-Log "Failed to install Winget automatically." -Color Red
        Write-Log "Error: $($_.Exception.Message)" -Color Red
        return $false
    }
}

Clear-Host
Write-Log "--- Starting Standard Software Install ---" -Color Cyan

# --- STEP 1: CHECK & INSTALL WINGET ---
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    $Result = Install-WingetProvider
    if (-not $Result) {
        Write-Log "ABORTING: Cannot proceed without Winget." -Color Red
        Write-Host "Press any key..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Return