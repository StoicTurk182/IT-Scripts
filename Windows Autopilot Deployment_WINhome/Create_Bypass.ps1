Function New-WinConfig {
    param (
        # Default to current directory if not specified
        [string]$TargetPath = ".\"
    )

    # 1. Check/Create Directory
    if (-not (Test-Path $TargetPath)) {
        Write-Warning "Path '$TargetPath' not found. Creating it..."
        New-Item -ItemType Directory -Force -Path $TargetPath | Out-Null
    }

    # 2. Define Paths
    $EiFile  = Join-Path -Path $TargetPath -ChildPath "ei.cfg"
    $PidFile = Join-Path -Path $TargetPath -ChildPath "pid.txt"

    # 3. Create ei.cfg
    @"
[EditionID]
Pro
[Channel]
_Default
[VL]
0
"@ | Out-File -FilePath $EiFile -Encoding ASCII

    # 4. Create pid.txt
    @"
[PID]
Value=VK7JG-NPHTM-C97JM-9MPGT-3V66T
"@ | Out-File -FilePath $PidFile -Encoding ASCII

    Write-Host "Success! Config files written to: $((Resolve-Path $TargetPath).Path)" -ForegroundColor Green
}

# --- EXECUTION SECTION ---

# 1. Run the function immediately
New-WinConfig

# 2. Pause so the window stays open (only if running interactively)
Write-Host "`nPress Enter to close this window..." -ForegroundColor Gray
Read-Host