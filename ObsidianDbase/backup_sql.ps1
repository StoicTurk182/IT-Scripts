$Date       = Get-Date -Format "yyyyMMdd-HHmm"
$LocalBak   = "C:\Temp\VaultWatch_$Date.bak"
$RemoteDest = "\\10.1.1.138\Personal-Drive\VaultWatch"

if (-not (Test-Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
}

if (-not (Test-Path $RemoteDest)) {
    New-Item -ItemType Directory -Path $RemoteDest -Force | Out-Null
}

Import-Module SqlServer

Invoke-Sqlcmd -ServerInstance "ORIONVI\SQLEXPRESS" `
              -TrustServerCertificate `
              -Query "BACKUP DATABASE VaultWatch TO DISK = '$LocalBak' WITH FORMAT, STATS = 10;"

Copy-Item -Path $LocalBak -Destination "$RemoteDest\VaultWatch_$Date.bak"
Remove-Item -Path $LocalBak
Write-Host "Backup complete: $RemoteDest\VaultWatch_$Date.bak"