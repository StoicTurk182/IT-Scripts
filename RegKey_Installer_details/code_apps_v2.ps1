<#
.SYNOPSIS
    Export all installed applications (HKLM and HKCU) with Intune detection details to CSV
.PARAMETER OutputPath
    Path where the CSV file will be saved (optional)
#>

param(
    [string]$OutputPath = "C:\Temp\IntuneAppDetection_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
)

# Ensure output directory exists
$OutputDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
}

# Registry paths to check - HKLM (machine) and HKCU (user)
$UninstallPaths = @(
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*";          Hive = "HKLM"; Is32Bit = $false  }
    @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"; Hive = "HKLM"; Is32Bit = $true   }
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*";          Hive = "HKCU"; Is32Bit = $false  }
)

Write-Host "`nScanning installed applications (HKLM + HKCU)..." -ForegroundColor Cyan

$AllApps = @()

foreach ($Entry in $UninstallPaths) {
    try {
        $Apps = Get-ItemProperty $Entry.Path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            Sort-Object DisplayName

        foreach ($App in $Apps) {
            $KeyName = $App.PSChildName
            $Is32Bit = $Entry.Is32Bit
            $Hive    = $Entry.Hive

            # Build clean Intune key path (no hive prefix — Intune infers from install behavior)
            if ($Hive -eq "HKLM") {
                $IntuneKeyPath = if ($Is32Bit) {
                    "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$KeyName"
                } else {
                    "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$KeyName"
                }
            } else {
                # HKCU — Intune infers hive from User install behavior, path only
                $IntuneKeyPath = "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$KeyName"
            }

            $AllApps += [PSCustomObject]@{
                'Application Name'       = $App.DisplayName
                'Version'                = $App.DisplayVersion
                'Publisher'              = $App.Publisher
                'Install Date'           = $App.InstallDate
                'Install Location'       = $App.InstallLocation
                'Registry Hive'          = $Hive
                'Install Context'        = if ($Hive -eq "HKCU") { "User" } else { "System" }
                'Intune Rule Type'       = 'Registry'
                'Intune Key Path'        = $IntuneKeyPath
                'Intune Value Name'      = 'DisplayName'
                'Intune Detection Method'= 'String comparison'
                'Intune Operator'        = 'Equals'
                'Intune Value'           = $App.DisplayName
                'Is 32-bit App on 64-bit'= if ($Is32Bit) { "Yes" } else { "No" }
                'Registry Key Name'      = $KeyName
                'Uninstall String'       = $App.UninstallString
                'Quiet Uninstall String' = $App.QuietUninstallString
                'MSI Product Code'       = if ($KeyName -match '^\{[A-F0-9-]+\}$') { $KeyName } else { "N/A" }
                'Full Registry Path'     = $App.PSPath -replace 'Microsoft.PowerShell.Core\\Registry::', ''
            }
        }
    }
    catch {
        Write-Warning "Error accessing $($Entry.Path) : $_"
    }
}

# Remove duplicates - deduplicate on Application Name + Hive combination
# (same app can appear in both HKLM and HKCU if installed both ways)
$UniqueApps = $AllApps | Sort-Object 'Application Name', 'Registry Hive' -Unique

$hklmCount = ($UniqueApps | Where-Object { $_.'Registry Hive' -eq 'HKLM' }).Count
$hkcuCount = ($UniqueApps | Where-Object { $_.'Registry Hive' -eq 'HKCU' }).Count

Write-Host "Found $($UniqueApps.Count) unique installed applications" -ForegroundColor Green
Write-Host "  HKLM (System/Machine): $hklmCount" -ForegroundColor White
Write-Host "  HKCU (User):           $hkcuCount" -ForegroundColor White

# Export to CSV
$UniqueApps | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "`nSuccessfully exported to: $OutputPath" -ForegroundColor Green
Write-Host "`nFile contains columns:" -ForegroundColor Yellow
Write-Host "  - Application Name, Version, Publisher" -ForegroundColor White
Write-Host "  - Registry Hive (HKLM/HKCU) and Install Context (System/User)" -ForegroundColor White
Write-Host "  - Intune Detection Rule (Key Path, Value Name, Operator, Value)" -ForegroundColor White
Write-Host "  - Uninstall Strings" -ForegroundColor White
Write-Host "  - MSI Product Code (if applicable)" -ForegroundColor White
Write-Host "  - Full Registry Paths" -ForegroundColor White

# Display preview
Write-Host "`nPreview (first 10 apps):" -ForegroundColor Cyan
$UniqueApps | Select-Object 'Application Name', 'Version', 'Registry Hive', 'Install Context', 'Intune Key Path' -First 10 | Format-Table -AutoSize

$OpenFile = Read-Host "`nOpen CSV file now? (Y/N)"
if ($OpenFile -eq 'Y' -or $OpenFile -eq 'y') {
    Start-Process $OutputPath
}
