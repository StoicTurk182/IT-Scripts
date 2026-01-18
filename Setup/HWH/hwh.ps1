<#
.SYNOPSIS
    Collects hardware hash for Intune Autopilot enrollment (USB/Offline friendly).
.DESCRIPTION
    Retrieves hardware hash via CIM (no module required) and saves to CSV.
    Prioritizes Network Share -> Falls back to USB/Script Local Directory.
.NOTES
    Version: 5.1
    Improved CSV consistency for bulk imports.
#>

param(
    [string]$NetworkSharePath = "\\FileServer\AutopilotHashes$",
    [string]$GroupTag = ""
)

# --- 1. Setup Environment ---
$Hostname = $env:COMPUTERNAME
$DateString = Get-Date -Format 'yyyy-MM-dd'

# Robust Base Path Detection (Handles running as script file OR selection)
if ($PSScriptRoot) {
    $BaseDir = $PSScriptRoot
} else {
    $BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
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
    # We ALWAYS create the Group Tag property, even if empty.
    # This ensures every CSV generated has identical headers.
    $HashObject = [PSCustomObject]@{
        'Device Serial Number' = $BIOS.SerialNumber
        'Windows Product ID'   = $ProductID
        'Hardware Hash'        = $DevDetail.DeviceHardwareData
        'Group Tag'            = $GroupTag
        'Assigned User'        = "" # Optional but good for template compliance
    }

    # --- 5. Determine Output Location ---
    $TargetDir = $LocalHashPath
    $SaveSuccessLocal = $false
    $SaveSuccessNetwork = $false
    $FinalPath = ""

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

    # Secondary Backup (If we wrote to network, ALSO write to USB/Local for safety)
    if ($SaveSuccessNetwork) {
        $LocalBackupFile = Join-Path -Path $LocalHashPath -ChildPath $CSVFileName
        $HashObject | Export-Csv -Path $LocalBackupFile -NoTypeInformation -Force -Encoding ASCII -ErrorAction SilentlyContinue
        Write-Host "$Hostname|SUCCESS_NETWORK|$FinalPath" -ForegroundColor Green
    }
    else {
        Write-Host "$Hostname|SUCCESS_LOCAL|$FinalPath" -ForegroundColor Cyan
    }

    exit 0

} catch {
    Write-Host "$Hostname|FAILED|$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}