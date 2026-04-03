$tdrPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"

$tdrKeys = @("TdrLevel", "TdrDelay", "TdrDdiDelay", "TdrLimitTime", "TdrLimitCount")

$tdrLevelMap = @{
    0 = "TdrLevelOff - TDR disabled"
    1 = "TdrLevelBugcheck - Blue screen on timeout (no recovery)"
    2 = "TdrLevelRecover - Recover (default)"
    3 = "TdrLevelRecoverVerbose - Recover with debug logging"
}

Write-Host "`n=== GPU TDR Settings ===" -ForegroundColor Cyan
Write-Host "Registry path: $tdrPath`n" -ForegroundColor DarkGray

foreach ($key in $tdrKeys) {
    $value = (Get-ItemProperty -Path $tdrPath -Name $key -ErrorAction SilentlyContinue).$key

    if ($null -eq $value) {
        Write-Host "${key}: Not set (Windows default applies)" -ForegroundColor Yellow
    } else {
        if ($key -eq "TdrLevel") {
            $desc = $tdrLevelMap[$value]
            Write-Host "${key}: $value  ->  $desc" -ForegroundColor Green
        } else {
            Write-Host "${key}: $value" -ForegroundColor Green
        }
    }
}

Write-Host "`n=== Default Values (if not set) ===" -ForegroundColor Cyan
Write-Host "TdrLevel:      2 (Recover)"
Write-Host "TdrDelay:      2 seconds (GPU hang detection timeout)"
Write-Host "TdrDdiDelay:   5 seconds (DDI call timeout)"
Write-Host "TdrLimitTime:  60 seconds"
Write-Host "TdrLimitCount: 5 (resets per TdrLimitTime before bugcheck)`n"