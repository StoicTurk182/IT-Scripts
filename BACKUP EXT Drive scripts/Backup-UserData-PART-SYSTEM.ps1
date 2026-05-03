<#
.SYNOPSIS
    Robocopy user data preservation to an NVMe USB drive.
.DESCRIPTION
    Run from the external drive on a live target machine (or against a slaved disk
    via -SourceRoot). Captures all non-system user profiles' standard folders,
    every OneDrive* sync root, browser profiles (Edge/Chrome/Brave/Vivaldi/Opera/Firefox)
    plus DPAPI master keys for password decryption, and the raw $Recycle.Bin from
    every fixed drive into <ScriptDrive>\BACKUPS\<HOSTNAME>_<TIMESTAMP>\.
    Robocopy options are tuned for NVMe-over-USB destinations (/MT:32 /J).
.PARAMETER SourceRoot
    Drive root to read from. Defaults to $env:SystemDrive\. Use 'D:\' for a slaved disk.
.PARAMETER DestinationRoot
    Backup root. Defaults to <ScriptDrive>\BACKUPS.
.EXAMPLE
    .\Backup-UserData.ps1
.EXAMPLE
    .\Backup-UserData.ps1 -SourceRoot 'D:\'
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$SourceRoot = "$env:SystemDrive\",
    [string]$DestinationRoot
)

$ErrorActionPreference = 'Continue'

# --- Paths ---------------------------------------------------------------
if (-not $DestinationRoot) {
    $ScriptDrive = if ($PSScriptRoot) { (Get-Item $PSScriptRoot).PSDrive.Root } else { (Get-Location).Drive.Root }
    $DestinationRoot = Join-Path $ScriptDrive 'BACKUPS'
}

$Hostname  = $env:COMPUTERNAME
$Stamp     = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$RunFolder = Join-Path $DestinationRoot "${Hostname}_${Stamp}"
$Summary   = Join-Path $RunFolder '_summary.log'
$VerifyCsv = Join-Path $RunFolder '_verification.csv'

if ((Split-Path $DestinationRoot -Qualifier) -ieq $env:SystemDrive) {
    Write-Warning "Destination is on the system drive. Aborting."
    exit 1
}

New-Item -ItemType Directory -Path $RunFolder -Force | Out-Null

$Verification = New-Object System.Collections.Generic.List[object]

function Log {
    param([string]$Msg, [ValidateSet('INFO','OK','WARN','ERR')] [string]$L = 'INFO')
    $color = @{ INFO='Cyan'; OK='Green'; WARN='Yellow'; ERR='Red' }[$L]
    $line  = "[$(Get-Date -Format 'HH:mm:ss')] [$L] $Msg"
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $Summary -Value $line
}

function Copy-Source {
    param(
        [string]$Src,
        [string]$Dst,
        [string]$Label,
        [string[]]$Extra = @()
    )
    if (-not (Test-Path -LiteralPath $Src)) {
        Log "[$Label] Skip (not present): $Src" WARN
        return
    }

    New-Item -ItemType Directory -Path $Dst -Force | Out-Null
    $LogPath = Join-Path (Split-Path $Dst -Parent) "$(Split-Path $Dst -Leaf).log"

    # NVMe-tuned: /MT:32 = 32 threads, /J = unbuffered I/O for large files
    $Args = @(
        "`"$Src`"", "`"$Dst`"",
        '/E', '/COPY:DAT', '/DCOPY:T',
        '/J', '/MT:32',
        '/R:2', '/W:5',
        '/XJ', '/NP', '/NDL',
        "/LOG:`"$LogPath`""
    ) + $Extra

    Log "[$Label] $Src -> $Dst"
    $exit = (Start-Process robocopy.exe -ArgumentList $Args -NoNewWindow -Wait -PassThru).ExitCode
    $level = if ($exit -lt 8) { 'OK' } else { 'ERR' }
    Log "[$Label] Exit=$exit" $level

    $sCount = (Get-ChildItem -LiteralPath $Src -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    $dCount = (Get-ChildItem -LiteralPath $Dst -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    $Verification.Add([pscustomobject]@{
        Label = $Label; Source = $Src; Destination = $Dst
        SourceFiles = $sCount; DestFiles = $dCount
        Match = ($sCount -eq $dCount); ExitCode = $exit
    })
}

# --- Pre-flight ----------------------------------------------------------
Log "Host: $Hostname | Source: $SourceRoot | Dest: $RunFolder"

# Warn on running browsers (locked DBs may copy partially even with /B)
$BrowserProcs = Get-Process -ErrorAction SilentlyContinue -Name msedge,chrome,brave,opera,vivaldi,firefox
if ($BrowserProcs) {
    Log "Running browsers detected: $(($BrowserProcs.Name | Sort-Object -Unique) -join ', '). Locked DB files may copy partially. Recommend closing all browsers and re-running." WARN
}

$UsersRoot = Join-Path $SourceRoot 'Users'
if (-not (Test-Path -LiteralPath $UsersRoot)) { Log "Users folder missing: $UsersRoot" ERR; exit 1 }

$ExcludeProfiles = 'Public','Default','Default User','All Users','WDAGUtilityAccount','defaultuser0'
$Profiles = Get-ChildItem -LiteralPath $UsersRoot -Directory -Force |
            Where-Object { $_.Name -notin $ExcludeProfiles }

$FixedDrives = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' |
               Select-Object -ExpandProperty DeviceID

Log "Profiles: $($Profiles.Name -join ', ')"
Log "Fixed drives: $($FixedDrives -join ', ')"

# --- Definitions ---------------------------------------------------------
$StandardFolders = 'Desktop','Documents','Downloads','Pictures','Videos','Music','Favorites'

$BrowserPaths = @(
    @{ Name = 'Edge';    Path = 'AppData\Local\Microsoft\Edge\User Data' }
    @{ Name = 'Chrome';  Path = 'AppData\Local\Google\Chrome\User Data' }
    @{ Name = 'Brave';   Path = 'AppData\Local\BraveSoftware\Brave-Browser\User Data' }
    @{ Name = 'Vivaldi'; Path = 'AppData\Local\Vivaldi\User Data' }
    @{ Name = 'Opera';   Path = 'AppData\Roaming\Opera Software\Opera Stable' }
    @{ Name = 'Firefox'; Path = 'AppData\Roaming\Mozilla\Firefox' }
)

# Cache dirs to skip inside browser User Data (large, useless for migration)
$BrowserCacheExclude = @('/XD','Cache','GPUCache','Crashpad','ShaderCache','GrShaderCache')

# DPAPI master keys + Windows Credential Manager - required to decrypt
# Chromium-saved passwords offline
$DPAPIPaths = @(
    'AppData\Roaming\Microsoft\Protect'
    'AppData\Local\Microsoft\Credentials'
    'AppData\Roaming\Microsoft\Credentials'
)

# --- Copy per profile ----------------------------------------------------
foreach ($p in $Profiles) {
    $UserDst = Join-Path $RunFolder $p.Name
    Log "===== $($p.Name) ====="

    # Standard folders
    foreach ($f in $StandardFolders) {
        Copy-Source -Src (Join-Path $p.FullName $f) `
                    -Dst (Join-Path $UserDst $f) `
                    -Label "$($p.Name)\$f"
    }

    # OneDrive (/XA:O excludes cloud-only placeholders)
    Get-ChildItem -LiteralPath $p.FullName -Directory -Filter 'OneDrive*' -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            Copy-Source -Src $_.FullName `
                        -Dst (Join-Path $UserDst $_.Name) `
                        -Label "$($p.Name)\$($_.Name)" `
                        -Extra @('/XA:O')
        }

    # Browsers (/B = backup mode for locked files; cache dirs excluded)
    foreach ($b in $BrowserPaths) {
        Copy-Source -Src (Join-Path $p.FullName $b.Path) `
                    -Dst (Join-Path $UserDst "Browsers\$($b.Name)") `
                    -Label "$($p.Name)\Browser-$($b.Name)" `
                    -Extra (@('/B') + $BrowserCacheExclude)
    }

    # DPAPI master keys + Credential Manager
    foreach ($dp in $DPAPIPaths) {
        $leaf = ($dp -replace '\\','_')
        Copy-Source -Src (Join-Path $p.FullName $dp) `
                    -Dst (Join-Path $UserDst "Secrets\$leaf") `
                    -Label "$($p.Name)\Secrets-$leaf" `
                    -Extra @('/B')
    }
}

# --- Recycle Bin per fixed drive -----------------------------------------
Log "===== Recycle Bins ====="
foreach ($d in $FixedDrives) {
    $letter = $d.TrimEnd(':')
    Copy-Source -Src (Join-Path "$d\" '$Recycle.Bin') `
                -Dst (Join-Path $RunFolder "RecycleBin_$letter") `
                -Label "RecycleBin_$letter" `
                -Extra @('/A-:SH')
}

# --- Verify --------------------------------------------------------------
$Verification | Export-Csv -Path $VerifyCsv -NoTypeInformation -Encoding UTF8

$mismatch = $Verification | Where-Object { -not $_.Match }
if ($mismatch) {
    Log "$($mismatch.Count) source(s) had file count mismatches. See _verification.csv." WARN
} else {
    Log "All file counts match." OK
}

$failed = $Verification | Where-Object { $_.ExitCode -ge 8 }
if ($failed) { Log "$($failed.Count) source(s) had Robocopy errors (exit >= 8)." ERR }
else         { Log "No fatal Robocopy errors." OK }

Write-Host "`nBackup folder: $RunFolder"   -ForegroundColor Cyan
Write-Host "Summary log:   $Summary"       -ForegroundColor Cyan
Write-Host "Verification:  $VerifyCsv`n"   -ForegroundColor Cyan
Write-Host "NOTE: Browser backups + Secrets folder contain DPAPI-encrypted credentials." -ForegroundColor Yellow
Write-Host "      Keep this drive secure (BitLocker-To-Go) and wipe after migration." -ForegroundColor Yellow