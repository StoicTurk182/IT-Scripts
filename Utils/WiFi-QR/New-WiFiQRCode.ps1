<#
.SYNOPSIS
    Generates a static WiFi QR code image from SSID and password input.

.DESCRIPTION
    Prompts for WiFi SSID and password, builds the standard WiFi URI string,
    and generates a static QR code PNG image using the QRCoder .NET library.
    The QR code is self-contained with no dependency on external services
    and does not expire.

.EXAMPLE
    .\New-WiFiQRCode.ps1
    Prompts for SSID and password interactively, saves QR code to Desktop.

.EXAMPLE
    .\New-WiFiQRCode.ps1 -SSID "OfficeGuest" -Password (ConvertTo-SecureString "Welcome2025!" -AsPlainText -Force) -OutputPath "C:\Temp\wifi-qr.png"
    Generates QR code with specified values and output location.

.NOTES
    Author: Andrew Jones
    Version: 1.1
    Date: 2026-04-07
    Requires: PowerShell 5.1+, Internet access on first run to install QRCoder NuGet package
    Change Log:
        1.0 - Initial release
        1.1 - Password input changed from plaintext string to SecureString.
              Interactive prompt now uses Read-Host -AsSecureString.
              Plaintext password is converted only at point of use and
              cleared from memory immediately after building the WiFi string.
#>

#Requires -Version 5.1

[CmdletBinding()]
param (
    [Parameter()]
    [string]$SSID,

    [Parameter()]
    [SecureString]$Password,

    [Parameter()]
    [ValidateSet("WPA", "WEP", "nopass")]
    [string]$AuthType = "WPA",

    [Parameter()]
    [bool]$Hidden = $false,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [int]$PixelsPerModule = 20
)

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
    $colors = @{
        "INFO"    = "Cyan"
        "SUCCESS" = "Green"
        "WARNING" = "Yellow"
        "ERROR"   = "Red"
    }
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message" -ForegroundColor $colors[$Level]
}

function Install-QRCoder {
    <#
    .SYNOPSIS
        Installs the QRCoder .NET library via NuGet if not already present.
    #>

    # Register NuGet package source if missing
    if (-not (Get-PackageSource -Name "NuGet" -ErrorAction SilentlyContinue)) {
        Write-Log "Registering NuGet package source..." "INFO"
        Register-PackageSource -Name "NuGet" -Location "https://www.nuget.org/api/v2" -ProviderName NuGet -Force | Out-Null
    }

    # Install NuGet provider if missing
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Write-Log "Installing NuGet provider..." "INFO"
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    }

    # Check if QRCoder is already installed
    $package = Get-Package -Name QRCoder -ErrorAction SilentlyContinue

    if (-not $package) {
        Write-Log "Installing QRCoder library (first run only)..." "INFO"
        Install-Package -Name QRCoder -Source "NuGet" -Force -SkipDependencies | Out-Null
        Write-Log "QRCoder installed successfully." "SUCCESS"
    }

    # Locate and load the DLL
    $packagePath = (Get-Package -Name QRCoder).Source
    $packageDir = Split-Path $packagePath -Parent
    $dllPath = Get-ChildItem -Path $packageDir -Recurse -Filter "QRCoder.dll" |
        Where-Object { $_.FullName -match "net[0-9]|netstandard" } |
        Sort-Object FullName -Descending |
        Select-Object -First 1

    if (-not $dllPath) {
        # Fallback: any QRCoder.dll found
        $dllPath = Get-ChildItem -Path $packageDir -Recurse -Filter "QRCoder.dll" |
            Select-Object -First 1
    }

    if (-not $dllPath) {
        Write-Log "Could not locate QRCoder.dll. Try reinstalling: Install-Package -Name QRCoder -Force" "ERROR"
        exit 1
    }

    try {
        Add-Type -Path $dllPath.FullName -ErrorAction Stop
        Write-Log "QRCoder library loaded." "SUCCESS"
    }
    catch [System.Reflection.ReflectionTypeLoadException] {
        # Partial load is fine — the types we need are available
        Write-Log "QRCoder library loaded (partial — non-critical types skipped)." "WARNING"
    }
}

function New-WiFiQRCode {
    param (
        [string]$WifiString,
        [string]$OutFile,
        [int]$PixelsPerModule
    )

    $qrGenerator = New-Object QRCoder.QRCodeGenerator
    $qrData = $qrGenerator.CreateQrCode($WifiString, [QRCoder.QRCodeGenerator+ECCLevel]::H)
    $qrCode = New-Object QRCoder.PngByteQRCode($qrData)
    $qrBytes = $qrCode.GetGraphic($PixelsPerModule)

    [System.IO.File]::WriteAllBytes($OutFile, $qrBytes)
}

# ============================================================================
# MAIN
# ============================================================================

Write-Host "`n=== WiFi QR Code Generator ===`n" -ForegroundColor Cyan

# --- Gather input ---

if (-not $SSID) {
    $SSID = Read-Host "Enter WiFi SSID (exact, case-sensitive)"
    if ([string]::IsNullOrWhiteSpace($SSID)) {
        Write-Log "SSID cannot be empty." "ERROR"
        exit 1
    }
}

if (-not $Password) {
    $Password = Read-Host "Enter WiFi password" -AsSecureString
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    )
    if ([string]::IsNullOrWhiteSpace($plainPassword) -and $AuthType -ne "nopass") {
        Write-Log "Password cannot be empty for $AuthType networks." "ERROR"
        exit 1
    }
} else {
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    )
}

if (-not $OutputPath) {
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $safeName = ($SSID -replace '[\\/:*?"<>|]', '_')
    $OutputPath = Join-Path $desktopPath "WiFi-QR-$safeName.png"
}

# --- Build WiFi string ---

$hiddenValue = if ($Hidden) { "true" } else { "false" }
$wifiString = "WIFI:T:$AuthType;S:$SSID;P:$plainPassword;H:$hiddenValue;;"

# Clear plaintext password from memory now that WiFi string is built
$plainPassword = $null

Write-Log "WiFi string built: WIFI:T:$AuthType;S:$SSID;P:****;H:$hiddenValue;;" "INFO"

# --- Install/load QRCoder ---

Install-QRCoder

# --- Generate QR code ---

Write-Log "Generating QR code..." "INFO"

try {
    New-WiFiQRCode -WifiString $wifiString -OutFile $OutputPath -PixelsPerModule $PixelsPerModule
    Write-Log "QR code saved to: $OutputPath" "SUCCESS"
}
catch {
    Write-Log "Failed to generate QR code: $_" "ERROR"
    exit 1
}

# --- Summary ---

Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "SSID:       $SSID"
Write-Host "Auth:       $AuthType"
Write-Host "Hidden:     $hiddenValue"
Write-Host "Output:     $OutputPath"
Write-Host ""

# --- Open image ---

$openChoice = Read-Host "Open the QR code image now? (Y/N)"
if ($openChoice -match "^[Yy]") {
    Start-Process $OutputPath
}

# --- Cleanup sensitive data from memory ---

$wifiString = $null
$Password.Dispose()

Write-Host "`nDone. Print the image and scan with a phone to verify it prompts WiFi join, not a URL.`n" -ForegroundColor Green
