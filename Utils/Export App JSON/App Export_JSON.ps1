# --- 1. Setup ---
Clear-Host
Write-Host "--- Generating Universal Winget Package ---" -ForegroundColor Cyan

$TempExportPath = "$env:TEMP\winget_export_temp.json"
$OutputJsonPath = "$env:USERPROFILE\Desktop\Install_Commands.json"

# Update sources
Write-Host "Updating Winget sources..." -ForegroundColor Yellow
winget source update

# --- 2. Export Raw Data ---
Write-Host "Exporting installed apps..." -ForegroundColor Cyan
winget export -o $TempExportPath --include-versions --accept-source-agreements

if (-not (Test-Path $TempExportPath)) {
    Write-Error "Export failed."
    Return
}

# --- 3. Build Command List ---
$ExportData = Get-Content $TempExportPath | ConvertFrom-Json
$Packages = $ExportData.Sources.Packages
$CommandList = @()

if ($Packages) {
    foreach ($Pkg in $Packages) {
        $ID = $Pkg.PackageIdentifier
        # Filter logic
        if ($ID -notmatch "Microsoft.Windows.|Microsoft.BioEnrollment") {
            # We add '--accept-source-agreements' to ensure IEX doesn't hang waiting for input
            $CommandList += "winget install --id $ID -e --silent --accept-package-agreements --accept-source-agreements --force"
        }
    }
}

# --- 4. Create the 'Universal' JSON Structure ---
# We use single quotes around the path variable `$env:USERPROFILE` so it does NOT expand now.
# It will expand when run on the NEW machine.

$Payload = [Ordered]@{
    "TotalApps"     = $CommandList.Count;
    
    "_OPTION_1_LOCAL" = "If this file is on your Desktop, run this:";
    "Local_Command"   = "(Get-Content -Raw `"`$env:USERPROFILE\Desktop\Install_Commands.json`" | ConvertFrom-Json).Commands | % { Invoke-Expression `$_ }";

    "_OPTION_2_WEB"   = "If you uploaded this file to the web (GitHub/Gist), run this:";
    "Web_IEX_Command" = "`$j = Invoke-RestMethod 'YOUR_RAW_JSON_URL_HERE'; `$j.Commands | % { Invoke-Expression `$_ }";

    "Commands"      = $CommandList
}

# --- 5. Save ---
$Payload | ConvertTo-Json -Depth 3 | Out-File -FilePath $OutputJsonPath -Encoding UTF8
Remove-Item $TempExportPath -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "SUCCESS! Universal JSON saved to:" -ForegroundColor Green
Write-Host " $OutputJsonPath" -ForegroundColor Yellow