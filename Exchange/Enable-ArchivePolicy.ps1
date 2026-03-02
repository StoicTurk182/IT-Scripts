# Enable-ArchivePolicy.ps1
# Deploys an Exchange Online archive retention policy to all user mailboxes.
# Creates the retention tag and policy if they do not exist, enables the archive
# mailbox on accounts where it is inactive, assigns the policy, and triggers the
# Managed Folder Assistant to begin processing.
#
# Author: Andrew Jones
# Version: 1.0
# Requires: ExchangeOnlineManagement module, Exchange Administrator role

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param (
    [string]$TagName    = "Archive - 1 Year",
    [string]$PolicyName = "Archive Policy - 1 Year",
    [int]$AgeDays       = 365,
    [string]$LogPath    = "$PSScriptRoot\ArchivePolicy-$(Get-Date -Format 'yyyy-MM-dd').log"
)

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO","SUCCESS","WARNING","ERROR")]
        [string]$Level = "INFO"
    )
    $colors = @{
        INFO    = "Cyan"
        SUCCESS = "Green"
        WARNING = "Yellow"
        ERROR   = "Red"
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    Write-Host $entry -ForegroundColor $colors[$Level]
    Add-Content -Path $LogPath -Value $entry
}

# ============================================================================
# MAIN
# ============================================================================

Write-Host "`n=== Exchange Online Archive Policy Deployment ===`n" -ForegroundColor Cyan
Write-Log "Script started. Tag: '$TagName' | Policy: '$PolicyName' | Age: $AgeDays days"

# 1. Connect to Exchange Online
try {
    Write-Log "Connecting to Exchange Online..."
    Connect-ExchangeOnline -ErrorAction Stop
    Write-Log "Connected to Exchange Online." -Level SUCCESS
}
catch {
    Write-Log "Failed to connect to Exchange Online: $_" -Level ERROR
    exit 1
}

# 2. Create Retention Tag (if it doesn't exist)
try {
    if (-not (Get-RetentionPolicyTag -Identity $TagName -ErrorAction SilentlyContinue)) {
        New-RetentionPolicyTag -Name $TagName `
            -Type All `
            -RetentionEnabled $true `
            -AgeLimitForRetention $AgeDays `
            -RetentionAction MoveToArchive `
            -ErrorAction Stop
        Write-Log "Created retention tag: $TagName" -Level SUCCESS
    }
    else {
        Write-Log "Retention tag '$TagName' already exists. Skipping creation." -Level INFO
    }
}
catch {
    Write-Log "Failed to create retention tag: $_" -Level ERROR
    exit 1
}

# 3. Create Retention Policy and link the tag (if it doesn't exist)
try {
    if (-not (Get-RetentionPolicy -Identity $PolicyName -ErrorAction SilentlyContinue)) {
        New-RetentionPolicy -Name $PolicyName `
            -RetentionPolicyTagLinks $TagName `
            -ErrorAction Stop
        Write-Log "Created retention policy: $PolicyName" -Level SUCCESS
    }
    else {
        Write-Log "Retention policy '$PolicyName' already exists. Skipping creation." -Level INFO
    }
}
catch {
    Write-Log "Failed to create retention policy: $_" -Level ERROR
    exit 1
}

# 4. Retrieve all user mailboxes
Write-Log "Retrieving all user mailboxes..."
try {
    $Mailboxes = Get-Mailbox -ResultSize Unlimited `
        -Filter "RecipientTypeDetails -eq 'UserMailbox'" `
        -ErrorAction Stop
    Write-Log "Found $($Mailboxes.Count) user mailbox(es)." -Level INFO
}
catch {
    Write-Log "Failed to retrieve mailboxes: $_" -Level ERROR
    exit 1
}

# 5. Process each mailbox
$successCount = 0
$errorCount   = 0

foreach ($Mailbox in $Mailboxes) {
    $upn = $Mailbox.UserPrincipalName
    Write-Log "Processing: $upn"

    try {
        # Enable archive if not already active
        if ($Mailbox.ArchiveStatus -ne "Active") {
            Enable-Mailbox -Identity $upn -Archive -ErrorAction Stop
            Write-Log "  Archive enabled for $upn" -Level SUCCESS
        }
        else {
            Write-Log "  Archive already active for $upn" -Level INFO
        }

        # Assign the retention policy
        Set-Mailbox -Identity $upn -RetentionPolicy $PolicyName -ErrorAction Stop
        Write-Log "  Retention policy '$PolicyName' assigned to $upn" -Level SUCCESS

        # Trigger Managed Folder Assistant
        Start-ManagedFolderAssistant -Identity $upn -ErrorAction Stop
        Write-Log "  Managed Folder Assistant queued for $upn" -Level SUCCESS

        $successCount++
    }
    catch {
        Write-Log "  ERROR processing $upn : $_" -Level ERROR
        $errorCount++
    }
}

# 6. Summary
Write-Log "---"
Write-Log "Deployment complete. Success: $successCount | Errors: $errorCount" -Level INFO
Write-Log "Log saved to: $LogPath"
Write-Host "`nVerification command:" -ForegroundColor Yellow
Write-Host 'Get-Mailbox -ResultSize Unlimited | Select-Object DisplayName, ArchiveStatus, RetentionPolicy | Out-GridView' -ForegroundColor White
Write-Host ""
