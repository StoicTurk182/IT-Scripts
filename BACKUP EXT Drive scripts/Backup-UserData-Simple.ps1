<#
.SYNOPSIS
    Interactive single-user data backup. Creates a labelled folder structure on
    a chosen drive and copies the running user's standard folders, browser
    profiles, OneDrive content, Sage data, and Recycle Bins into the matching
    subfolders.
.DESCRIPTION
    Simpler single-user variant of Backup-UserData.ps1. Designed for routine
    TransWiz-style migrations where the profile state is handled separately and
    the script only needs to grab raw data into a predictable folder layout.
    Robocopy options tuned for NVMe-over-USB destinations (/MT:32 /J).
#>

# --- Script-scope log file (set by Initialize-BackupFolderStructure) -------
$Script:LogFile = $null

Function Write-Log {
    param(
        [string]$Message,
        [string]$Color = 'White'
    )
    $TimeStamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host " $Message" -ForegroundColor $Color
    if ($Script:LogFile) {
        Add-Content -Path $Script:LogFile -Value "[$TimeStamp] $Message"
    }
}

Function Initialize-BackupFolderStructure {
    [CmdletBinding()]
    param ()

    # --- 1. Drive ---
    $InputDrive  = Read-Host "Drive letter (e.g. D, E)"
    $CleanLetter = $InputDrive -replace "[:\s\\]", ""
    $DriveRoot   = "$($CleanLetter.ToUpper()):\"
    if (-not (Test-Path -Path $DriveRoot)) {
        Write-Warning "Drive '$DriveRoot' does not exist or is not ready."
        return $null
    }

    # --- 2. Label ---
    $UserLabel = Read-Host "Backup label (e.g. old_PC, laptop)"
    if ([string]::IsNullOrWhiteSpace($UserLabel)) { $UserLabel = "Backup" }

    # --- 3. Root path ---
    $Hostname    = $env:COMPUTERNAME
    $DateString  = Get-Date -Format "ddMMyyyy"
    $FolderName  = "${Hostname}_${UserLabel}_${DateString}"
    $RootPath    = Join-Path -Path $DriveRoot -ChildPath $FolderName

    # --- 4. Create root ---
    if (-not (Test-Path -Path $RootPath)) {
        try {
            New-Item -Path $RootPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Host "Created root folder: $RootPath" -ForegroundColor Green
        } catch {
            Write-Error "Failed to create root folder. Check permissions."
            return $null
        }
    }

    # --- 5. Pre-flight: warn on running browsers / OneDrive ---
    $Procs = Get-Process -ErrorAction SilentlyContinue -Name msedge,chrome,brave,opera,vivaldi,firefox,OneDrive
    if ($Procs) {
        Write-Host ""
        Write-Host "The following processes are running and will cause locked-file errors:" -ForegroundColor Yellow
        $Procs | Sort-Object Name -Unique | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Yellow }
        Write-Host ""
        Write-Host "Recommended actions before continuing:" -ForegroundColor Yellow
        Write-Host "  - Close all browsers" -ForegroundColor Yellow
        Write-Host "  - Right-click OneDrive in system tray > Pause syncing > 8 hours" -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press ENTER once done (or Ctrl+C to abort)"
    }

    # --- 6. Logging setup (script scope so Copy-UserData shares it) ---
    $Script:LogFile = Join-Path -Path $RootPath -ChildPath "Backup_Log.txt"

    Write-Log -Message "--- Backup Structure Initialization Started ---" -Color Cyan
    Write-Log -Message "Root Path: $RootPath" -Color Gray

    # --- 7. Subfolders ---
    $Folders = @("Download","Pictures","Documents","Music","Browser","Desktop","Unsynced_Onedrive","RecycleBin")
    foreach ($Folder in $Folders) {
        $SubfolderPath = Join-Path -Path $RootPath -ChildPath $Folder
        if (-not (Test-Path -Path $SubfolderPath)) {
            New-Item -Path $SubfolderPath -ItemType Directory -Force | Out-Null
            Write-Log -Message "[+] Created: $Folder" -Color Green
        } else {
            Write-Log -Message "[-] Skipped: $Folder (Already exists)" -Color DarkGray
        }
    }

    Write-Log -Message "--- Structure Complete ---" -Color Cyan
    return $RootPath
}

Function Invoke-Robo {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$Label,
        [string[]]$Extra = @()
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Log -Message "[-] Skip ${Label}: source not present" -Color DarkGray
        return
    }

    New-Item -Path $Destination -ItemType Directory -Force | Out-Null
    $RoboLog = Join-Path (Split-Path $Destination -Parent) "$(Split-Path $Destination -Leaf).log"

    # NVMe-tuned: /MT:32 = 32 threads, /J = unbuffered I/O for large files
    $RoboArgs = @(
        "`"$Source`"", "`"$Destination`"",
        '/E', '/COPY:DAT', '/DCOPY:T',
        '/J', '/MT:32',
        '/R:2', '/W:5',
        '/XJ', '/NP', '/NDL',
        "/LOG:`"$RoboLog`""
    ) + $Extra

    Write-Log -Message "[>] Copying ${Label}" -Color Cyan
    $exit = (Start-Process robocopy.exe -ArgumentList $RoboArgs -NoNewWindow -Wait -PassThru).ExitCode

    if ($exit -lt 8) {
        Write-Log -Message "[+] Done ${Label} (exit=$exit)" -Color Green
    } else {
        Write-Log -Message "[!] Errors ${Label} (exit=$exit) - see $RoboLog" -Color Red
    }
}

Function Copy-UserData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    Write-Log -Message "--- Data Copy Started ---" -Color Cyan
    Write-Log -Message "Source user: $env:USERNAME" -Color Gray

    # Warn on running browsers (locked DBs may copy partially even with /B)
    $Procs = Get-Process -ErrorAction SilentlyContinue -Name msedge,chrome,brave,opera,vivaldi,firefox
    if ($Procs) {
        Write-Log -Message "[!] Browsers running: $(($Procs.Name | Sort-Object -Unique) -join ', '). Close them for clean browser backup." -Color Yellow
    }

    # Standard folders -> matching subfolders
    $Map = @(
        @{ Sub = 'Desktop';   Src = (Join-Path $env:USERPROFILE 'Desktop')   }
        @{ Sub = 'Documents'; Src = (Join-Path $env:USERPROFILE 'Documents') }
        @{ Sub = 'Download';  Src = (Join-Path $env:USERPROFILE 'Downloads') }
        @{ Sub = 'Pictures';  Src = (Join-Path $env:USERPROFILE 'Pictures')  }
        @{ Sub = 'Music';     Src = (Join-Path $env:USERPROFILE 'Music')     }
    )
    foreach ($m in $Map) {
        Invoke-Robo -Source      $m.Src `
                    -Destination (Join-Path $RootPath $m.Sub) `
                    -Label       $m.Sub
    }

    # Browser data -> Browser\<browser>\
    $Browsers = @(
        @{ Name = 'Edge';    Path = 'AppData\Local\Microsoft\Edge\User Data' }
        @{ Name = 'Chrome';  Path = 'AppData\Local\Google\Chrome\User Data' }
        @{ Name = 'Brave';   Path = 'AppData\Local\BraveSoftware\Brave-Browser\User Data' }
        @{ Name = 'Firefox'; Path = 'AppData\Roaming\Mozilla\Firefox' }
    )
    $CacheExclude = @('/XD','Cache','GPUCache','Crashpad','ShaderCache','GrShaderCache')
    foreach ($b in $Browsers) {
        Invoke-Robo -Source      (Join-Path $env:USERPROFILE $b.Path) `
                    -Destination (Join-Path $RootPath "Browser\$($b.Name)") `
                    -Label       "Browser-$($b.Name)" `
                    -Extra       (@('/B') + $CacheExclude)
    }

    # OneDrive folders -> Unsynced_Onedrive\<folder>\  (skip cloud-only placeholders)
    Get-ChildItem $env:USERPROFILE -Directory -Filter 'OneDrive*' -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            Invoke-Robo -Source      $_.FullName `
                        -Destination (Join-Path $RootPath "Unsynced_Onedrive\$($_.Name)") `
                        -Label       "OneDrive-$($_.Name)" `
                        -Extra       @('/XA:O')
        }

    # Sage data -> Sage\<source-path-leaf>\  (best-guess locations)
    $SageSources = @(
        'C:\ProgramData\Sage\Accounts'
        (Join-Path $env:USERPROFILE 'Documents\Sage')
        'C:\Users\Public\Documents\Sage'
    )
    foreach ($s in $SageSources) {
        if (Test-Path -LiteralPath $s) {
            $leaf   = Split-Path $s -Leaf
            $parent = Split-Path (Split-Path $s -Parent) -Leaf
            Invoke-Robo -Source      $s `
                        -Destination (Join-Path $RootPath "Sage\${parent}_${leaf}") `
                        -Label       "Sage-$leaf"
        }
    }

    # Recycle Bin per fixed drive -> RecycleBin\<letter>\
    # /A-:SH clears System+Hidden attrs on dest (so it's browsable in Explorer)
    # /B = backup mode for reading other-user SID folders if running elevated
    # Guard skips the destination drive itself - prevents copying RecycleBin\W into W:\
    $DestDriveLetter = (Split-Path $RootPath -Qualifier).TrimEnd(':')
    $FixedDrives = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' |
                   Select-Object -ExpandProperty DeviceID
    foreach ($d in $FixedDrives) {
        $letter = $d.TrimEnd(':')
        if ($letter -ieq $DestDriveLetter) {
            Write-Log -Message "[-] Skip RecycleBin-${letter}: destination drive" -Color DarkGray
            continue
        }
        $RBSrc = Join-Path "$d\" '$Recycle.Bin'
        Invoke-Robo -Source      $RBSrc `
                    -Destination (Join-Path $RootPath "RecycleBin\$letter") `
                    -Label       "RecycleBin-$letter" `
                    -Extra       @('/A-:SH','/B')
    }

    Write-Log -Message "--- Data Copy Complete ---" -Color Cyan
}

# --- Usage -----------------------------------------------------------------
$BackupPath = Initialize-BackupFolderStructure
if ($BackupPath) {
    Copy-UserData -RootPath $BackupPath
    Write-Host "`nLog file located at: $BackupPath\Backup_Log.txt" -ForegroundColor Yellow
}