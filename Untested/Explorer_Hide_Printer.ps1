# --- Script 1: Printer Restriction Manager ---
Write-Host "PRINTER POLICY MANAGER" -ForegroundColor Cyan
Write-Host "1. Enable (Restrict Printer Addition)"
Write-Host "2. Disable (Remove Restriction / Clean Registry)"
$Choice = Read-Host "Select (1 or 2)"

$Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"

if ($Choice -eq "1") {
    if (!(Test-Path $Path)) { 
        New-Item $Path -Force | Out-Null
        Write-Host "[+] Created missing Explorer folder." -ForegroundColor Gray
    }
    Set-ItemProperty $Path -Name "NoAddPrinter" -Value 1 -Type DWord -Force
    Write-Host "[DECLARATION] Printer Restriction: ENABLED" -ForegroundColor Green
} 
elseif ($Choice -eq "2") {
    if (Test-Path $Path) {
        Remove-ItemProperty $Path -Name "NoAddPrinter" -ErrorAction SilentlyContinue
        Write-Host "[DECLARATION] Printer Entry: DELETED (Reverted to default)" -ForegroundColor Yellow
    }
}
