Write-Host "Starting AnyBurn Installation..." -ForegroundColor Cyan

# Check if Winget is available
if (Get-Command winget -ErrorAction SilentlyContinue) {
    # Install AnyBurn silently with all agreements accepted
    winget install --id PowerSoftware.AnyBurn -e --silent --accept-package-agreements --accept-source-agreements
    
    if ($?) {
        Write-Host "Installation command completed." -ForegroundColor Green
    }
} else {
    Write-Error "Winget is not recognized on this system. Please update Windows or install App Installer."
}