<#
.SYNOPSIS
    Interactive Auto-Lock Configurator.
#>

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " WINDOWS AUTO-LOCK CONFIGURATOR" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "1) Set Specific Timeout (Minutes)"
Write-Host "2) Disable Auto-Lock (Never Lock)"
Write-Host "----------------------------------------"
$Choice = Read-Host "Select an option (1 or 2)"

if ($Choice -eq "2") {
    $Seconds = 0
    $StatusValue = "0"
    $Display = "DISABLED (Never)"
} else {
    $Mins = Read-Host "Enter minutes until lock"
    $Seconds = [int]$Mins * 60
    $StatusValue = "1"
    $Display = "$Mins Minutes"
}

# --- Execution Logic ---
Write-Host "`nApplying: $Display..." -ForegroundColor Yellow

try {
    $UserPath = "HKCU:\Control Panel\Desktop"
    Set-ItemProperty -Path $UserPath -Name "ScreenSaveActive" -Value $StatusValue -Type String -Force
    Set-ItemProperty -Path $UserPath -Name "ScreenSaverIsSecure" -Value $StatusValue -Type String -Force
    Set-ItemProperty -Path $UserPath -Name "ScreenSaveTimeOut" -Value "$Seconds" -Type String -Force
    rundll32.exe user32.dll, UpdatePerUserSystemParameters
    Write-Host "[OK] User settings updated." -ForegroundColor Green
} catch { Write-Host "[!] User settings failed." -ForegroundColor Red }

if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    try {
        $MachinePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        if (!(Test-Path $MachinePath)) { New-Item -Path $MachinePath -Force | Out-Null }
        Set-ItemProperty -Path $MachinePath -Name "InactivityTimeoutSecs" -Value $Seconds -Type DWord -Force
        Write-Host "[OK] Machine policy updated." -ForegroundColor Green
    } catch { Write-Host "[!] Machine policy failed." -ForegroundColor Red }
} else {
    Write-Host "[!] Admin rights missing: Machine Policy skipped." -ForegroundColor Yellow
}

Write-Host "`nDone." -ForegroundColor Cyan