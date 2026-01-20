#Requires -Modules ActiveDirectory

# --- 1. SETUP LOGGING (Universal) ---
$LogDir = "$env:TEMP\ADGroupCopyLogs"
if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$LogFile = "$LogDir\Log_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"

# Start Transcript (Captures the aesthetic output perfectly)
Start-Transcript -Path $LogFile -Append | Out-Null

Function Copy-ADUserGroupsSmart {
    param(
        [string]$SourceUser,
        [string]$TargetUser
    )

    # --- HEADER ---
    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "            AD GROUP COPY WIZARD                        " -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan

    # --- SECTION: INPUT ---
    # If parameters were not passed, ask for them now with clean spacing
    if ([string]::IsNullOrWhiteSpace($SourceUser)) {
        Write-Host "`n[ INPUT REQUIRED ]" -ForegroundColor Magenta
        $SourceUser = Read-Host "   > Enter SOURCE Username (Copy FROM) "
    }
    if ([string]::IsNullOrWhiteSpace($TargetUser)) {
        if (![string]::IsNullOrWhiteSpace($SourceUser)) { 
            # Only print header if we didn't just print it above
        } else { Write-Host "`n[ INPUT REQUIRED ]" -ForegroundColor Magenta }
        
        $TargetUser = Read-Host "   > Enter TARGET Username (Copy TO)   "
    }

    # --- SECTION: VALIDATION ---
    Write-Host "`n[ VALIDATION ]" -ForegroundColor Magenta
    
    # 1. Validate Source
    Write-Host "   Checking Source '$SourceUser' ... " -NoNewline
    Try {
        $SourceObj = Get-ADUser -Identity $SourceUser -Properties MemberOf -ErrorAction Stop
        Write-Host "[ OK ]" -ForegroundColor Green
    }
    Catch {
        Write-Host "[ FAIL ]" -ForegroundColor Red
        Write-Warning "   Could not find Source user '$SourceUser'."
        return
    }

    # 2. Validate Target
    Write-Host "   Checking Target '$TargetUser' ... " -NoNewline
    Try {
        $TargetObj = Get-ADUser -Identity $TargetUser -Properties MemberOf -ErrorAction Stop
        Write-Host "[ OK ]" -ForegroundColor Green
    }
    Catch {
        Write-Host "[ FAIL ]" -ForegroundColor Red
        Write-Warning "   Could not find Target user '$TargetUser'."
        return
    }

    # 3. Analyze Groups
    $Groups = @($SourceObj | Select-Object -ExpandProperty MemberOf)
    
    if ($Groups.Count -eq 0) {
        Write-Host "`n   [ INFO ] Source user has no group memberships to copy." -ForegroundColor Yellow
        return
    }

    # --- SECTION: CONFIRMATION ---
    Write-Host "`n[ PROPOSED ACTION ]" -ForegroundColor Magenta
    Write-Host "--------------------------------------------------------" -ForegroundColor Gray
    Write-Host "   SOURCE User      : $($SourceObj.Name)"
    Write-Host "   TARGET User      : $($TargetObj.Name)"
    Write-Host "   Groups to Copy   : $($Groups.Count)"
    Write-Host "--------------------------------------------------------" -ForegroundColor Gray

    Write-Host ""
    $Confirm = Read-Host "   >>> Type 'Y' to COPY these groups"
    if ($Confirm -ne 'Y') { 
        Write-Host "`n   [ ABORTED ] Operation cancelled by user." -ForegroundColor Yellow
        return 
    }

    # --- SECTION: EXECUTION ---
    Write-Host "`n[ EXECUTION ]" -ForegroundColor Magenta
    
    foreach ($Group in $Groups) {
        # Extract pretty name for display (Remove CN=...,OU=...)
        $GroupName = ($Group -split ",")[0] -replace "CN=",""
        
        # Calculate padding for alignment
        # We cap display name at 35 chars to keep alignment clean
        $DisplayName = if ($GroupName.Length -gt 35) { $GroupName.Substring(0,32) + "..." } else { $GroupName }
        $Padding = " " * (40 - $DisplayName.Length)

        Write-Host "   $DisplayName $Padding : " -NoNewline

        Try {
            Add-ADGroupMember -Identity $Group -Members $TargetUser -ErrorAction Stop
            Write-Host "[ COPIED ]" -ForegroundColor Green
        }
        Catch {
            if ($_.Exception.Message -like "*already a member*") {
                Write-Host "[ EXISTS ]" -ForegroundColor DarkGray
            }
            elseif ($_.Exception.Message -like "*Insufficient access rights*") {
                 Write-Host "[ ACCESS DENIED ]" -ForegroundColor Red
            }
            else {
                Write-Host "[ FAILED ]" -ForegroundColor Red
                Write-Log "Error adding to $GroupName : $($_.Exception.Message)"
            }
        }
    }

    Write-Host "`n   [ COMPLETE ] Operation finished." -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan
}

# --- MAIN EXECUTION ---
Try {
    # If variables exist (passed via command line), use them. Otherwise run interactive.
    if ($SourceUser -and $TargetUser) {
        Copy-ADUserGroupsSmart -SourceUser $SourceUser -TargetUser $TargetUser
    }
    else {
        Copy-ADUserGroupsSmart
    }
}
Finally {
    Stop-Transcript | Out-Null
    
    Write-Host "`n--------------------------------------------------" -ForegroundColor Gray
    Write-Host " LOG FILE: $LogFile" -ForegroundColor Yellow
    Write-Host " Opening log folder..." -ForegroundColor Gray
    Write-Host "--------------------------------------------------" -ForegroundColor Gray
    
    # Open folder
    Invoke-Item $LogDir
}