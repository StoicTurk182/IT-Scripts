<#
.SYNOPSIS
    Universal Winget Package Generator (Corrected Flags)
#>

# --- 1. Setup ---
Clear-Host
Write-Host "--- Generating Universal Winget Package ---" -ForegroundColor Cyan

$OutputJsonPath = "C:\temp_winget_commands.json"
if (-not (Test-Path "C:\")) { $OutputJsonPath = "$env:PUBLIC\Documents\Install_Commands.json" }

$TempExportPath = [System.IO.Path]::GetTempFileName()

# --- 2. Update and Export ---
Write-Host "Updating Winget sources..." -ForegroundColor Yellow
# 'source update' only needs interactivity disabled to prevent hanging
winget source update --disable-interactivity

Write-Host "Exporting installed apps..." -ForegroundColor Cyan
# Only '--accept-source-agreements' is valid for export
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
            # HERE is where we keep both agreement flags for the NEW machine
            $CommandList += "winget install --id $ID -e --silent --accept-package-agreements --accept-source-agreements --force"
        }
    }
}

# --- 4. Create structure ---
$Payload = [Ordered]@{
    "TotalApps"       = $CommandList.Count;
    "GeneratedOn"     = $(Get-Date -Format "yyyy-MM-dd HH:mm");
    "Local_Command"   = "`$j = Get-Content -Raw '$OutputJsonPath' | ConvertFrom-Json; `$j.Commands | % { Write-Host 'Installing: ' `$_ -FG Cyan; Invoke-Expression `$_ }";
    "Commands"        = $CommandList
}

# --- 5. Save and Cleanup ---
try {
    $Payload | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputJsonPath -Encoding UTF8 -Force
    Write-Host "`nSUCCESS! Universal JSON saved to: $OutputJsonPath" -ForegroundColor Green
}
catch {
    Write-Error "Save failed: $($_.Exception.Message)"
}
finally {
    if (Test-Path $TempExportPath) { Remove-Item $TempExportPath -Force }
}