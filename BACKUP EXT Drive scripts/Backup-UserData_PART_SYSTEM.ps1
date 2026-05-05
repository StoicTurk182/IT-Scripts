<#
.SYNOPSIS
    Interactive single-user data backup. Creates a labelled folder structure on
    a chosen drive and copies a target user's standard folders, browser
    profiles, OneDrive content, Sage data, and Recycle Bins into the matching
    subfolders.
.DESCRIPTION
    Simpler single-user variant of Backup-UserData.ps1. Designed for routine
    TransWiz-style migrations where the profile state is handled separately and
    the script only needs to grab raw data into a predictable folder layout.
    Robocopy options tuned for NVMe-over-USB destinations (/MT:32 /J).

    Detects elevation mismatch: if the script was launched by elevating from a
    different user account, it warns and lets the operator pick the correct
    target profile (interactive console user vs running-as user vs manual override).
#>

# --- Script-scope state (set by Initialize-BackupFolderStructure / Resolve-TargetProfile) ---
$Script:LogFile    = $null
$Script:TargetUser = $null  # selected username (matches actual on-disk folder name)
$Script:TargetHome = $null  # full path to user profile root

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
    # If a folder already exists for this run (same hostname/label/user/timestamp),
    # append _2, _3, ... so each run gets its own folder instead of merging.
    $Hostname    = $env:COMPUTERNAME
    $DateString  = Get-Date -Format "ddMMyyyy_HHmmss"
    $BaseFolder  = "${Hostname}_${UserLabel}_${Script:TargetUser}_${DateString}"
    $RootPath    = Join-Path -Path $DriveRoot -ChildPath $BaseFolder

    $counter = 2
    while (Test-Path -Path $RootPath) {
        $RootPath = Join-Path -Path $DriveRoot -ChildPath "${BaseFolder}_${counter}"
        $counter++
    }

    $counter = 2
    while (Test-Path -Path $RootPath) {
        $RootPath = Join-Path -Path $DriveRoot -ChildPath "${BaseFolder}_${counter}"
        $counter++
    }

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
    # NOTE: $null = Read-Host required - without it the empty input string
    # leaks into the function's output stream and corrupts the return value
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
        $null = Read-Host "Press ENTER once done (or Ctrl+C to abort)"
    }

    # --- 6. Logging setup (script scope so other functions share it) ---
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

Function Resolve-TargetProfile {
    <#
    .SYNOPSIS
        Determines which user profile to back up. Detects elevation mismatch.
    .DESCRIPTION
        $env:USERNAME returns the elevated account when the script is run via
        UAC from a different user. That's almost never the user we want to back
        up - we want the interactive console user.

        Win32_ComputerSystem.UserName returns the active console user and
        survives elevation. The function lists every valid profile under
        C:\Users\ on every run, marks the detected default with an asterisk,
        and lets the operator pick by number, by typed username, or by pressing
        ENTER to accept the default. Mismatch between running-as and interactive
        is flagged but does not change the prompt flow. Sets $Script:TargetUser
        and $Script:TargetHome.
    #>

    $RunAsUser = $env:USERNAME

    # Active console user - survives elevation. Returns DOMAIN\user.
    $InteractiveRaw  = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
    $InteractiveUser = if ($InteractiveRaw) { Split-Path $InteractiveRaw -Leaf } else { $null }

    Write-Host ""
    Write-Host "Profile detection:" -ForegroundColor Cyan
    Write-Host "  Running as          : $RunAsUser"
    Write-Host "  Interactive console : $(if ($InteractiveUser) { $InteractiveUser } else { '(none detected)' })"

    # Mismatch warning (loud but non-blocking - operator still chooses below)
    if ($InteractiveUser -and $InteractiveUser -ine $RunAsUser) {
        Write-Host ""
        Write-Host "MISMATCH: script was elevated from a different account." -ForegroundColor Yellow
        Write-Host "Pick the interactive console user unless you know otherwise." -ForegroundColor Yellow
    }

    # Default suggestion: prefer interactive over running-as where they differ
    $DefaultUser = if ($InteractiveUser -and $InteractiveUser -ine $RunAsUser) { $InteractiveUser } else { $RunAsUser }

    # Always list profiles - operator can pick any of them on every run
    Write-Host ""
    Write-Host "Available profiles on this machine:" -ForegroundColor Cyan
    $Profiles = @(Get-ChildItem 'C:\Users' -Directory -Force -ErrorAction SilentlyContinue |
                  Where-Object { Test-Path (Join-Path $_.FullName 'NTUSER.DAT') })

    if (-not $Profiles -or $Profiles.Count -eq 0) {
        Write-Warning "No valid user profiles found under C:\Users"
        return $false
    }

    for ($i = 0; $i -lt $Profiles.Count; $i++) {
        $marker = if ($Profiles[$i].Name -ieq $DefaultUser) { '*' } else { ' ' }
        Write-Host ("  [{0}]{1} {2}" -f ($i + 1), $marker, $Profiles[$i].Name)
    }
    Write-Host "  (* = detected default. Press ENTER to accept, or enter a number / username)"
    Write-Host ""

    $choice = Read-Host "Target profile"

    if ([string]::IsNullOrWhiteSpace($choice)) {
        $Selected = $DefaultUser
    }
    elseif ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $Profiles.Count) {
        $Selected = $Profiles[[int]$choice - 1].Name
    }
    else {
        $Selected = $choice
    }

    # Validate against on-disk profile folder
    $ProfilePath = Join-Path 'C:\Users' $Selected
    if (-not (Test-Path -LiteralPath $ProfilePath)) {
        Write-Warning "Profile folder not found: $ProfilePath"
        return $false
    }

    # Resolve to actual on-disk casing for path correctness
    $Resolved = Get-Item -LiteralPath $ProfilePath
    $Script:TargetUser = $Resolved.Name
    $Script:TargetHome = $Resolved.FullName

    Write-Host ""
    Write-Host "Target profile: $Script:TargetUser" -ForegroundColor Green
    Write-Host "Profile path  : $Script:TargetHome" -ForegroundColor Green
    Write-Host ""

    Write-Log -Message "Target profile resolved: $Script:TargetUser" -Color Green
    Write-Log -Message "Profile path: $Script:TargetHome" -Color Gray
    Write-Log -Message "Running-as user was: $RunAsUser (interactive: $(if ($InteractiveUser) { $InteractiveUser } else { 'none' }))" -Color Gray

    return $true
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

Function Clear-HiddenSystemAttrs {
    <#
    .SYNOPSIS
        Strips Hidden and System attributes from a path and everything beneath it.
    .DESCRIPTION
        Robocopy's /A-:SH only acts on files, not directories. When mirroring a
        source like $Recycle.Bin (which is system+hidden) the destination dirs
        inherit those attributes and are invisible in Explorer by default.
        This walks the tree post-copy and clears Hidden+System on dirs and files.
    #>
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }

    $hidden = [IO.FileAttributes]::Hidden
    $system = [IO.FileAttributes]::System

    $items  = @(Get-Item     -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
    $items += @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue)

    foreach ($i in $items) {
        if ($null -eq $i) { continue }
        try {
            $i.Attributes = ($i.Attributes -band -bnot $hidden) -band -bnot $system
        } catch {
            # Some items may refuse attribute changes (reparse points, ACL-locked)
        }
    }
}

Function Copy-UserData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    Write-Log -Message "--- Data Copy Started ---" -Color Cyan
    Write-Log -Message "Source user: $Script:TargetUser" -Color Gray
    Write-Log -Message "Source home: $Script:TargetHome" -Color Gray

    # Warn on running browsers (locked DBs may copy partially even with /B)
    $Procs = Get-Process -ErrorAction SilentlyContinue -Name msedge,chrome,brave,opera,vivaldi,firefox
    if ($Procs) {
        Write-Log -Message "[!] Browsers running: $(($Procs.Name | Sort-Object -Unique) -join ', '). Close them for clean browser backup." -Color Yellow
    }

    # Standard folders -> matching subfolders
    $Map = @(
        @{ Sub = 'Desktop';   Src = (Join-Path $Script:TargetHome 'Desktop')   }
        @{ Sub = 'Documents'; Src = (Join-Path $Script:TargetHome 'Documents') }
        @{ Sub = 'Download';  Src = (Join-Path $Script:TargetHome 'Downloads') }
        @{ Sub = 'Pictures';  Src = (Join-Path $Script:TargetHome 'Pictures')  }
        @{ Sub = 'Music';     Src = (Join-Path $Script:TargetHome 'Music')     }
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
        Invoke-Robo -Source      (Join-Path $Script:TargetHome $b.Path) `
                    -Destination (Join-Path $RootPath "Browser\$($b.Name)") `
                    -Label       "Browser-$($b.Name)" `
                    -Extra       (@('/B') + $CacheExclude)
    }

    # OneDrive folders -> Unsynced_Onedrive\<folder>\  (skip cloud-only placeholders)
    Get-ChildItem $Script:TargetHome -Directory -Filter 'OneDrive*' -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            Invoke-Robo -Source      $_.FullName `
                        -Destination (Join-Path $RootPath "Unsynced_Onedrive\$($_.Name)") `
                        -Label       "OneDrive-$($_.Name)" `
                        -Extra       @('/XA:O')
        }

    # Sage data -> Sage\<source-path-leaf>\  (best-guess locations)
    $SageSources = @(
        'C:\ProgramData\Sage\Accounts'
        (Join-Path $Script:TargetHome 'Documents\Sage')
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
    # Source $Recycle.Bin and its SID subfolders are System+Hidden.
    # /A-:SH strips those from copied FILES; Clear-HiddenSystemAttrs handles DIRS
    # post-copy so the destination is browsable in Explorer.
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
        $RBDst = Join-Path $RootPath "RecycleBin\$letter"

        Invoke-Robo -Source      $RBSrc `
                    -Destination $RBDst `
                    -Label       "RecycleBin-$letter" `
                    -Extra       @('/A-:SH','/B')

        # Strip Hidden+System from the directory tree (Robocopy /A-:SH = files only)
        Write-Log -Message "[>] Clearing Hidden/System attrs on RecycleBin-$letter" -Color DarkCyan
        Clear-HiddenSystemAttrs -Path $RBDst
        Write-Log -Message "[+] Attrs cleared on RecycleBin-$letter" -Color Green
    }

    Write-Log -Message "--- Data Copy Complete ---" -Color Cyan
}

# --- Usage -----------------------------------------------------------------
if (Resolve-TargetProfile) {
    $BackupPath = Initialize-BackupFolderStructure
    if ($BackupPath) {
        Copy-UserData -RootPath $BackupPath
        Write-Host "`nLog file located at: $BackupPath\Backup_Log.txt" -ForegroundColor Yellow
    }
} else {
    Write-Host "Aborting - target profile could not be resolved." -ForegroundColor Red
}