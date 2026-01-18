Function Copy-ADUserGroups {
    <#
    .SYNOPSIS
    Copies Active Directory group memberships from one user to another with logging.
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0, HelpMessage="Enter the username to copy FROM (Source)")]
        [string]$SourceUser,

        [Parameter(Mandatory=$true, Position=1, HelpMessage="Enter the username to copy TO (Target)")]
        [string]$TargetUser,

        [Parameter(Mandatory=$false)]
        [string]$LogPath = ".\GroupCopyLog.txt" # Default log location (current folder)
    )

    Process {
        # --- LOGGING HELPER FUNCTION ---
        # This writes to BOTH the console (with color) and the file (with timestamp)
        function Write-Log {
            param (
                [string]$Message,
                [string]$Color = "White",
                [string]$Type = "INFO" 
            )
            $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $LogLine = "[$Timestamp] [$Type] $Message"
            
            # Write to Console
            Write-Host " $Message" -ForegroundColor $Color
            
            # Write to File
            try { Add-Content -Path $LogPath -Value $LogLine -ErrorAction SilentlyContinue } catch {}
        }

        # Clean up inputs
        $SourceUser = $SourceUser.Trim()
        $TargetUser = $TargetUser.Trim()

        Write-Log -Message "--- Starting Group Copy: $SourceUser -> $TargetUser ---" -Color Cyan

        # 1. Validate Users
        Try {
            $SourceObj = Get-ADUser -Identity $SourceUser -Properties MemberOf -ErrorAction Stop
            $TargetObj = Get-ADUser -Identity $TargetUser -ErrorAction Stop
        }
        Catch {
            Write-Log -Message "User validation failed. Check spelling." -Color Red -Type "ERROR"
            Write-Log -Message "Error Details: $($_.Exception.Message)" -Color Red -Type "ERROR"
            Return 
        }

        # 2. Get Groups
        $Groups = @($SourceObj | Select-Object -ExpandProperty MemberOf)

        if ($Groups.Count -eq 0) {
            Write-Log -Message "$SourceUser has no extra groups to copy." -Color Yellow -Type "WARN"
            Return
        }

        Write-Log -Message "Found $( $Groups.Count ) groups to copy." -Color Cyan

        # 3. Loop and Add
        foreach ($Group in $Groups) {
            # Extract pretty name
            $GroupName = ($Group -split ",")[0] -replace "CN=",""

            Try {
                Add-ADGroupMember -Identity $Group -Members $TargetUser -ErrorAction Stop
                Write-Log -Message "[SUCCESS] Added to $GroupName" -Color Green
            }
            Catch {
                if ($_.Exception.Message -like "*already a member*") {
                    Write-Log -Message "[SKIP]    Already in $GroupName" -Color Gray -Type "SKIP"
                }
                else {
                    Write-Log -Message "[ERROR]   Failed to add to $GroupName" -Color Red -Type "ERROR"
                    Write-Log -Message "          Reason: $($_.Exception.Message)" -Color Red -Type "ERROR"
                }
            }
        }
        Write-Log -Message "--- Operation Complete ---" -Color Cyan
    }
}

# Run the function (will prompt for names if not provided)
Copy-ADUserGroups