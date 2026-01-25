<#
.SYNOPSIS
    Interactive Windows Region and Language Configuration Tool
.DESCRIPTION
    Sets Language, Region, and System Locale with menu selection or parameters.
    Forces settings to apply to System/Welcome Screen/New Users.
.NOTES
    Author: Andrew Jones
    Modified: Improved validation and admin enforcement
#>

[CmdletBinding()]
param (
    [Parameter()][string]$LangTag,
    [Parameter()][int]$GeoID
)

# ============================================================================
# CONFIGURATION DATA
# ============================================================================

$Script:RegionConfigs = @(
    [PSCustomObject]@{ Name = "English (United States)";     LangTag = "en-US"; GeoID = 244 }
    [PSCustomObject]@{ Name = "English (United Kingdom)";    LangTag = "en-GB"; GeoID = 242 }
    [PSCustomObject]@{ Name = "English (Canada)";            LangTag = "en-CA"; GeoID = 39  }
    [PSCustomObject]@{ Name = "English (Australia)";         LangTag = "en-AU"; GeoID = 12  }
    [PSCustomObject]@{ Name = "English (New Zealand)";       LangTag = "en-NZ"; GeoID = 183 }
    [PSCustomObject]@{ Name = "English (Ireland)";           LangTag = "en-IE"; GeoID = 68  }
    [PSCustomObject]@{ Name = "English (India)";             LangTag = "en-IN"; GeoID = 94  }
    [PSCustomObject]@{ Name = "French (France)";             LangTag = "fr-FR"; GeoID = 84  }
    [PSCustomObject]@{ Name = "French (Canada)";             LangTag = "fr-CA"; GeoID = 39  }
    [PSCustomObject]@{ Name = "German (Germany)";            LangTag = "de-DE"; GeoID = 82  }
    [PSCustomObject]@{ Name = "Spanish (Spain)";             LangTag = "es-ES"; GeoID = 223 }
    [PSCustomObject]@{ Name = "Spanish (Mexico)";            LangTag = "es-MX"; GeoID = 137 }
    [PSCustomObject]@{ Name = "Italian (Italy)";             LangTag = "it-IT"; GeoID = 118 }
    [PSCustomObject]@{ Name = "Portuguese (Brazil)";         LangTag = "pt-BR"; GeoID = 21  }
    [PSCustomObject]@{ Name = "Portuguese (Portugal)";       LangTag = "pt-PT"; GeoID = 193 }
    [PSCustomObject]@{ Name = "Dutch (Netherlands)";         LangTag = "nl-NL"; GeoID = 177 }
    [PSCustomObject]@{ Name = "Japanese (Japan)";            LangTag = "ja-JP"; GeoID = 117 }
    [PSCustomObject]@{ Name = "Chinese Simplified (China)";  LangTag = "zh-CN"; GeoID = 45  }
    [PSCustomObject]@{ Name = "Chinese Traditional (Taiwan)";LangTag = "zh-TW"; GeoID = 228 }
    [PSCustomObject]@{ Name = "Korean (South Korea)";        LangTag = "ko-KR"; GeoID = 203 }
)

# ============================================================================
# FUNCTIONS
# ============================================================================

function Show-Menu {
    Clear-Host
    Write-Host "`n=== Windows Region & Language Configuration ===" -ForegroundColor Cyan
    Write-Host "Select a language/region configuration:`n" -ForegroundColor White
    
    for ($i = 0; $i -lt $Script:RegionConfigs.Count; $i++) {
        $num = $i + 1
        Write-Host ("{0,2}. {1}" -f $num, $Script:RegionConfigs[$i].Name) -ForegroundColor Yellow
    }
    
    Write-Host "`n 0. Exit" -ForegroundColor Red
    Write-Host ""
}

function Get-Selection {
    $selection = Read-Host "Enter selection (0-$($Script:RegionConfigs.Count))"
    
    # Check for exit first
    if ($selection -eq "0") {
        Write-Host "`nExiting..." -ForegroundColor Yellow
        exit 0
    }
    
    # Safe cast to integer to prevent crashes on non-numeric input
    $indexInt = $selection -as [int]

    if ($null -ne $indexInt -and $indexInt -gt 0 -and $indexInt -le $Script:RegionConfigs.Count) {
        return $Script:RegionConfigs[$indexInt - 1]
    }
    
    Write-Host "`nInvalid selection. Please enter a number between 0 and $($Script:RegionConfigs.Count)." -ForegroundColor Red
    Start-Sleep -Seconds 2
    return $null
}

function Test-LanguageInstalled {
    param ([string]$LangTag)
    $installed = Get-WinUserLanguageList | Select-Object -ExpandProperty LanguageTag
    return ($installed -contains $LangTag)
}

function Apply-RegionSettings {
    param (
        [string]$LangTag,
        [int]$GeoID
    )
    
    Write-Host "`n==================================================" -ForegroundColor Cyan
    Write-Host "Applying: $LangTag (GeoID: $GeoID)" -ForegroundColor Cyan
    Write-Host "==================================================`n" -ForegroundColor Cyan
    
    if (-not (Test-LanguageInstalled -LangTag $LangTag)) {
        Write-Warning "Language pack '$LangTag' not installed!"
        Write-Host "Please install the pack via Windows Settings before continuing.`n" -ForegroundColor Yellow
        return $false
    }
    
    $success = $true
    
    # 1. User Language List
    try {
        $LangList = New-WinUserLanguageList -Language $LangTag
        Set-WinUserLanguageList -LanguageList $LangList -Force
        Write-Host "[OK] User Language: $LangTag" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to set User Language: $($_.Exception.Message)"
        $success = $false
    }
    
    # 2. Home Location
    try {
        Set-WinHomeLocation -GeoId $GeoID
        Write-Host "[OK] Location: $GeoID" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to set Home Location"
        $success = $false
    }
    
    # 3. Regional Format
    try {
        Set-Culture -CultureInfo $LangTag
        Write-Host "[OK] Regional Format: $LangTag" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to set Regional Format"
        $success = $false
    }
    
    # 4. System Locale
    try {
        Set-WinSystemLocale -SystemLocale $LangTag
        Write-Host "[OK] System Locale: $LangTag (Reboot required)" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to set System Locale"
        $success = $false
    }
    
    # 5. System-wide Propagation
    Write-Host "`nApplying to System/Welcome Screen..." -ForegroundColor Yellow
    $useLegacy = $false
    
    if (Get-Command "Copy-UserInternationalSettingsToSystem" -ErrorAction SilentlyContinue) {
        try {
            Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true
            Write-Host "[OK] Applied via Modern Cmdlet" -ForegroundColor Green
        } catch {
            Write-Warning "Modern cmdlet failed, trying legacy method..."
            $useLegacy = $true
        }
    } else {
        $useLegacy = $true
    }
    
    if ($useLegacy) {
        $xmlContent = @"
<gs:GlobalizationServices xmlns:gs="urn:longhornGlobalizationUnattend">
    <gs:UserList>
        <gs:User UserID="Current" CopySettingsToDefaultUserAcct="true" CopySettingsToSystemAcct="true"/>
    </gs:UserList>
</gs:GlobalizationServices>
"@
        $tempFile = "$env:TEMP\region_update.xml"
        # Using Unicode (UTF-16) for better compatibility with legacy control.exe
        $xmlContent | Out-File -FilePath $tempFile -Encoding Unicode
        
        try {
            Start-Process -FilePath "control.exe" -ArgumentList "intl.cpl,, /f`"$tempFile`"" -Wait -WindowStyle Hidden
            Write-Host "[OK] Applied via XML Injection (Legacy)" -ForegroundColor Green
        } catch {
            Write-Error "CRITICAL: System propagation failed!"
            $success = $false
        } finally {
            if (Test-Path $tempFile) { Remove-Item -Path $tempFile -Force }
        }
    }
    
    return $success
}

# ============================================================================
# MAIN
# ============================================================================

# Enforce admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "CRITICAL: This script requires Administrator rights to modify System Locales and the Welcome Screen."
    Write-Host "Please restart PowerShell as Administrator.`n" -ForegroundColor Red
    exit 1
}

# Parameter mode or Interactive mode
if ($LangTag -and $GeoID) {
    $config = [PSCustomObject]@{
        Name = "$LangTag / GeoID $GeoID"
        LangTag = $LangTag
        GeoID = $GeoID
    }
    
    Write-Host "`nDirect mode: $LangTag (GeoID: $GeoID)" -ForegroundColor Cyan
    $confirm = Read-Host "Apply this configuration? (Y/N)"
    
    if ($confirm -eq 'Y') {
        $result = Apply-RegionSettings -LangTag $config.LangTag -GeoID $config.GeoID
        if ($result) {
            Write-Host "`nSUCCESS - Reboot required." -ForegroundColor Green
            if ((Read-Host "Reboot now? (Y/N)") -eq 'Y') { Restart-Computer -Force }
        }
    }
} else {
    do {
        Show-Menu
        $config = Get-Selection
        
        if ($config) {
            Write-Host "`nSelected: $($config.Name)" -ForegroundColor Cyan
            if ((Read-Host "`nApply this configuration? (Y/N)") -eq 'Y') {
                $result = Apply-RegionSettings -LangTag $config.LangTag -GeoID $config.GeoID
                if ($result) {
                    Write-Host "`nSUCCESS - Reboot required." -ForegroundColor Green
                    if ((Read-Host "Reboot now? (Y/N)") -eq 'Y') { 
                        Restart-Computer -Force 
                    } else {
                        exit 0
                    }
                } else {
                    Read-Host "Errors occurred. Press Enter to return to menu"
                }
            }
        }
    } while ($true)
}