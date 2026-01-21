<#
.SYNOPSIS
    Sets the Windows Auto-Lock timeout for both Current User and Local Machine.
    Compatible with IEX (Invoke-Expression) and local execution.
.PARAMETER Minutes
    The number of minutes to wait before locking. Default is 5.
.EXAMPLE
    .\Set-AutoLock.ps1
    Sets auto-lock to default 5 minutes.
.EXAMPLE
    .\Set-AutoLock.ps1 -Minutes 10
    Sets auto-lock to 10 minutes.
.NOTES
    Author: Andrew Jones
    Version: 1.0
    Requires: PowerShell 5.1+
    Admin rights required for machine-wide policy settings.
#>
param (
    [int]$Minutes = 5
)

# Convert Minutes to Seconds
$Seconds = $Minutes * 60

Write-Host "----------------------------------------------------" -ForegroundColor Cyan
Write-Host " Config using: $Minutes Minutes ($Seconds Seconds)" -ForegroundColor Cyan
Write-Host "----------------------------------------------------" -ForegroundColor Gray

# --- PART 1: Current User Settings (The "Soft" Lock) ---
# This sets the screensaver timeout and forces the password requirement on resume.
try {
    Write-Host "Setting Current User (Screensaver) config..." -NoNewline
    $UserPath = "HKCU:\Control Panel\Desktop"
    
    # 1. Enable Screensaver logic (even if set to "None", this activates the timer)
    Set-ItemProperty -Path $UserPath -Name "ScreenSaveActive" -Value "1" -Type String -Force
    # 2. Force 'On resume, display logon screen'
    Set-ItemProperty -Path $UserPath -Name "ScreenSaverIsSecure" -Value "1" -Type String -Force
    # 3. Set the timeout duration
    Set-ItemProperty -Path $UserPath -Name "ScreenSaveTimeOut" -Value "$Seconds" -Type String -Force
    
    # Refresh user parameters immediately
    [void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
    rundll32.exe user32.dll, UpdatePerUserSystemParameters
    Write-Host " [OK]" -ForegroundColor Green
}
catch {
    Write-Host " [FAILED] - $_" -ForegroundColor Red
}

# --- PART 2: Local Machine Security Policy (The "Hard" Lock) ---
# This sets the 'Interactive logon: Machine inactivity limit'.
# Requires ADMIN privileges.
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if ($IsAdmin) {
    try {
        Write-Host "Setting Machine Policy (Inactivity Limit)..." -NoNewline
        $MachinePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        
        if (!(Test-Path $MachinePath)) { New-Item -Path $MachinePath -Force | Out-Null }
        
        # Set InactivityTimeoutSecs
        Set-ItemProperty -Path $MachinePath -Name "InactivityTimeoutSecs" -Value $Seconds -Type DWord -Force
        Write-Host " [OK]" -ForegroundColor Green
    }
    catch {
        Write-Host " [FAILED] - $_" -ForegroundColor Red
    }
}
else {
    Write-Host "Skipping Machine Policy (Requires 'Run as Administrator')" -ForegroundColor Yellow
}

Write-Host "----------------------------------------------------" -ForegroundColor Gray
Write-Host "Done. Auto-lock set to $Minutes minutes." -ForegroundColor Cyan