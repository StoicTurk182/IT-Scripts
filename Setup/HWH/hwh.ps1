<#
.SYNOPSIS
    Collects hardware hash for Intune Autopilot enrollment (USB/Offline friendly).
.DESCRIPTION
    Retrieves hardware hash via CIM (no module required) and saves to CSV.
    Prioritizes Network Share -> Falls back to USB/Script Local Directory -> Falls back to C:\AutopilotHashes (IEX mode).
.NOTES
    Version: 5.2 (IEX Compatible)
#>

param(
    [string]$NetworkSharePath = "\\FileServer\AutopilotHashes$",
    [string]$GroupTag = ""
)

# --- 1. Setup Environment ---
$Hostname = $env:COMPUTERNAME
$DateString = Get-Date -Format 'yyyy-MM-dd'

# --- ROBUST PATH DETECTION (The Fix) ---
if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    # Scenario A: Running from a physical file (e.g., USB stick)
    $BaseDir = $PSScriptRoot
}
elseif (-not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)) {
    # Scenario B: Running as a selected block in ISE/VSCode
    $BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
else {
    # Scenario C: Running via IEX (Memory)
    # We default to a safe, persistent folder on the C: drive so the CSV isn't lost.
    $BaseDir = "$env:SystemDrive\AutopilotData"
}

# Define Paths
$LocalHashPath = Join-Path -Path $BaseDir -ChildPath "Hashes"
$NetworkOutputPath = Join-Path -Path $NetworkSharePath -ChildPath $DateString
$CSVFileName = "AutopilotHash_$Hostname.csv"

# --- 2. Helper Function ---
function Ensure-Directory {
    param([string]$Path)
    try {
        if (-not (Test-Path -Path $Path)) {
            New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
        }
        return $true
    } catch {
        return $false
    }
}

try {
    # --- 3. Gather Hardware Data (The Lightweight Way) ---
    $BIOS = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
    $ProductID = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop).ProductId
    
    # Retrieve Hash directly from WMI/CIM
    $DevDetail = Get-CimInstance -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'" -ErrorAction Stop
    
    if ($null -eq $DevDetail -or $null -eq $DevDetail.DeviceHardwareData) {
        throw "Hardware hash could not be retrieved via CIM."
    }

    # --- 4. Create Standardized Object ---
    $HashObject = [PSCustomObject]@{
        'Device Serial Number' = $BIOS.SerialNumber
        'Windows Product ID'   = $ProductID
        'Hardware Hash'        = $DevDetail.DeviceHardwareData
        'Group Tag'            = $GroupTag
        'Assigned User'        = "" 
    }

    # --- 5. Determine Output Location ---
    $TargetDir = $LocalHashPath
    $SaveSuccessNetwork = $false

    # Try Network First
    if (Test-Path -Path $NetworkSharePath) {
        if (Ensure-Directory -Path $NetworkOutputPath) {
            $TargetDir = $NetworkOutputPath
            $SaveSuccessNetwork = $true
        }
    }

    # Ensure Local Path exists regardless (as backup)
    Ensure-Directory -Path $LocalHashPath | Out-Null

    # --- 6. Export ---
    
    # Primary Export (Network if available, otherwise Local)
    $FinalPath = Join-Path -Path $TargetDir -ChildPath $CSVFileName
    $HashObject | Export-Csv -Path $FinalPath -NoTypeInformation -Force -Encoding ASCII -ErrorAction Stop

    # Secondary Backup (Network Success? Still save a local copy!)
    if ($SaveSuccessNetwork) {
        $LocalBackupFile = Join-Path -Path $LocalHashPath -ChildPath $CSVFileName
        $HashObject | Export-Csv -Path $LocalBackupFile -NoTypeInformation -Force -Encoding ASCII -ErrorAction SilentlyContinue
        Write-Host "$Hostname|SUCCESS_NETWORK|$FinalPath" -ForegroundColor Green
        Write-Host "  (Local Backup saved to: $LocalBackupFile)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "$Hostname|SUCCESS_LOCAL|$FinalPath" -ForegroundColor Cyan
    }

    exit 0

} catch {
    Write-Host "$Hostname|FAILED|$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}