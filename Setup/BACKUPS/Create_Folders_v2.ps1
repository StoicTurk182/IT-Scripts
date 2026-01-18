Function Initialize-BackupFolderStructure {
    [CmdletBinding()]
    param ()
    
    # --- 1. Robust Drive Input ---
    $InputDrive = Read-Host "Drive letter (e.g. D, E)"
    $CleanLetter = $InputDrive -replace "[:\s\\]",""
    $DriveRoot = "$($CleanLetter.ToUpper()):\"

    # Validate Drive
    if (-not (Test-Path -Path $DriveRoot)) {
        Write-Warning "Drive '$DriveRoot' does not exist or is not ready."
        return $null
    }

    # --- 2. Prompt for Label ---
    $UserLabel = Read-Host "Backup label (e.g. old_PC, laptop)"
    if ([string]::IsNullOrWhiteSpace($UserLabel)) { $UserLabel = "Backup" }
    
    # --- 3. Construct Root Path ---
    $Hostname = $env:COMPUTERNAME
    $DateString = Get-Date -Format "ddMMyyyy"
    $FolderName = "${Hostname}_${UserLabel}_${DateString}"
    $RootPath = Join-Path -Path $DriveRoot -ChildPath $FolderName
    
    # --- 4. Create Root Directory ---
    if (-not (Test-Path -Path $RootPath)) {
        Try {
            New-Item -Path $RootPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Host "Created root folder: $RootPath" -ForegroundColor Green
        }
        Catch {
            Write-Error "Failed to create root folder. Check permissions."
            return $null
        }
    }

    # --- 5. LOGGING SETUP ---
    # We define the log file location inside the new folder
    $LogFile = Join-Path -Path $RootPath -ChildPath "Backup_Log.txt"

    # Helper function to write to BOTH Console and File at the same time
    Function Write-Log {
        param (
            [string]$Message,
            [string]$Color = "White"
        )
        $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $LogLine = "[$TimeStamp] $Message"
        
        # Write to Console
        Write-Host " $Message" -ForegroundColor $Color
        
        # Write to File
        Add-Content -Path $LogFile -Value $LogLine
    }

    Write-Log -Message "--- Backup Structure Initialization Started ---" -Color Cyan
    Write-Log -Message "Root Path: $RootPath" -Color Gray

    # --- 6. Create Subfolders ---
    $Folders = @("Download", "Pictures", "Documents", "Music", "Browser", "Desktop", "Sage")
    
    foreach ($Folder in $Folders) {
        $SubfolderPath = Join-Path -Path $RootPath -ChildPath $Folder
        
        if (-not (Test-Path -Path $SubfolderPath)) {
            New-Item -Path $SubfolderPath -ItemType Directory -Force | Out-Null
            Write-Log -Message "[+] Created: $Folder" -Color Green
        }
        else {
            Write-Log -Message "[-] Skipped: $Folder (Already exists)" -Color DarkGray
        }
    }
    
    Write-Log -Message "--- Structure Complete ---" -Color Cyan
    
    return $RootPath
}

# --- Usage ---
$BackupPath = Initialize-BackupFolderStructure

if ($BackupPath) {
    Write-Host "`nLog file located at: $BackupPath\Backup_Log.txt" -ForegroundColor Yellow
}