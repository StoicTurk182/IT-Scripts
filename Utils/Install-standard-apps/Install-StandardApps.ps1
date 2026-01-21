<#
.SYNOPSIS
    Installs standard software using Winget.
.DESCRIPTION
    1. Sets TLS 1.2 (Required for GitHub).
    2. Checks for Admin rights.
    3. Auto-installs Winget if missing.
    4. Smart Install: Checks if app is installed; if not, installs it. If yes, upgrades it.
#>

# --- CRITICAL FIX: FORCE TLS 1.2 FOR GITHUB ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- CHECK ADMIN RIGHTS ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host " [!] ERROR: You must run this script as Administrator." -ForegroundColor Red
    Write-Host "     Right-click PowerShell and select 'Run as Administrator'." -ForegroundColor Gray
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Return
}

$AppsToInstall = @(
    "7zip.7zip",
    "Notepad++.Notepad++",
    "Adobe.Acrobat.Reader.64-bit"
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
    }
}

# --- STEP 2: INSTALL OR UPGRADE APPS ---
foreach ($AppID in $AppsToInstall) {
    Write-Host ""
    Write-Log "Processing: $AppID" -Color Yellow
    
    # 1. Attempt INSTALL first (Handles fresh installs)
    # We use Start-Process to capture the specific exit codes reliably
    $InstallProc = Start-Process -FilePath "winget" -ArgumentList "install --id $AppID --accept-package-agreements --accept-source-agreements --silent" -PassThru -Wait -NoNewWindow
    
    if ($InstallProc.ExitCode -eq 0) {
        Write-Log " [OK] Installed Successfully." -Color Green
    }
    # 2. Catch 'Already Installed' error (-1978335212) -> Switch to UPGRADE
    elseif ($InstallProc.ExitCode -eq -1978335212) { 
        Write-Log " [!] App already installed. Checking for updates..." -Color Gray
        
        $UpgradeProc = Start-Process -FilePath "winget" -ArgumentList "upgrade --id $AppID --accept-package-agreements --accept-source-agreements --silent" -PassThru -Wait -NoNewWindow
        
        if ($UpgradeProc.ExitCode -eq 0) {
            Write-Log " [OK] Upgrade Successful." -Color Green
        }
        elseif ($UpgradeProc.ExitCode -eq -1978334967) { 
            # -1978334967 means "No update available"
            Write-Log " [OK] System is already up to date." -Color Green 
        }
        else {
            Write-Log " [X] Upgrade Failed. Code: $($UpgradeProc.ExitCode)" -Color Red
        }
    }
    else {
        # Catch other random install errors
        Write-Log " [X] Install Failed. Code: $($InstallProc.ExitCode)" -Color Red
    }
}

Write-Host ""
Write-Log "--- Installation Complete ---" -Color Cyan
Write-Host "Press any key to return..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")