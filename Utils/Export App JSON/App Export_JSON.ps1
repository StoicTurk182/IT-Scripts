<#
.SYNOPSIS
    Universal Winget Package Generator
    - Folder: C:\WingetExports
    - Filename: Winget_[Hostname]_[Date].json
    - Includes: Local & Web IEX Restore Commands
#>

# --- 1. Setup & Path Generation ---
Clear-Host
$Hostname = $env:COMPUTERNAME
$Date = Get-Date -Format "yyyy-MM-dd"
$ExportFolder = "C:\WingetExports"
$FileName = "Winget_$( $Hostname )_$( $Date ).json"
$OutputJsonPath = Join-Path $ExportFolder $FileName

Write-Host "--- Generating Universal Winget Package ---" -ForegroundColor Cyan

# Ensure the export folder exists
if (!(Test-Path $ExportFolder)) { 
    New-Item -ItemType Directory -Path $ExportFolder -Force | Out-Null
}

$TempExportPath = [System.IO.Path]::GetTempFileName()

# --- 2. Update and Export ---
Write-Host "Updating Winget sources..." -ForegroundColor Yellow
winget source update --disable-interactivity

Write-Host "Exporting installed apps..." -ForegroundColor Cyan
winget export -o $TempExportPath --include-versions --accept-source-agreements

if (-not (Test-Path $TempExportPath) -or (Get-Item $TempExportPath).Length -eq 0) {
    Write-Error "Export failed. Winget could not write the temporary file."
    Return
}

# --- 3. Build Command List ---
$ExportData = Get-Content $TempExportPath | ConvertFrom-Json
$Packages = $ExportData.Sources.Packages
$CommandList = @()

if ($Packages) {
    foreach ($Pkg in $Packages) {
        $ID = $Pkg.PackageIdentifier
        if ($ID -notmatch "Microsoft.Windows.|Microsoft.BioEnrollment|Microsoft.Language") {
            $CommandList += "winget install --id $ID -e --silent --accept-package-agreements --accept-source-agreements --force"
        }
    }
}

# --- 4. Create structure (Restored Web/Local Options) ---
$Payload = [Ordered]@{
    "Hostname"        = $Hostname;
    "TotalApps"       = $CommandList.Count;
    "GeneratedOn"     = $(Get-Date -Format "yyyy-MM-dd HH:mm");
    
    "_OPTION_1_LOCAL" = "If this file is on the machine, run this in PowerShell:";
    "Local_Command"   = "`$j = Get-Content -Raw '$OutputJsonPath' | ConvertFrom-Json; `$j.Commands | % { Write-Host 'Installing: ' `$_ -FG Cyan; Invoke-Expression `$_ }";

    "_OPTION_2_WEB"   = "If you uploaded this file to the web (GitHub/Gist), run this:";
    "Web_IEX_Command" = "`$j = Invoke-RestMethod 'YOUR_RAW_JSON_URL_HERE'; `$j.Commands | % { Invoke-Expression `$_ }";

    "Commands"        = $CommandList
}

# --- 5. Save and Cleanup ---
try {
    $Payload | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputJsonPath -Encoding UTF8 -Force
    
    Write-Host "`nSUCCESS! Universal JSON saved." -ForegroundColor Green
    
    # Clickable/Linkable path in modern consoles
    Write-Host "Location: " -NoNewline
    Get-Item $OutputJsonPath
}
catch {
    Write-Error "Save failed: $($_.Exception.Message)"
}
finally {
    if (Test-Path $TempExportPath) { Remove-Item $TempExportPath -Force }
}