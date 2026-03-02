param (
    [Parameter(Mandatory=$true)]
    [string]$UserEmail,
    [string]$TagName = "Archive - 1 Year",
    [string]$PolicyName = "Archive Policy - 1 Year",
    [int]$AgeLimit = 365
)

# 1. Connection Logic
try {
    if (!(Get-ConnectionInformation)) {
        Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan
        Connect-ExchangeOnline -ErrorAction Stop
    }
} catch {
    Write-Error "Failed to connect to Exchange Online."
    return
}

# 2. Check for Existing Policy (The Graceful Exit)
$ExistingPolicy = Get-RetentionPolicy $PolicyName -ErrorAction SilentlyContinue
if ($ExistingPolicy) {
    Write-Host "INFO: Retention Policy '$PolicyName' already exists. Exiting operation to prevent overwriting." -ForegroundColor Yellow
    return # This stops the script here
}

# 3. If Policy doesn't exist, proceed with creation
try {
    # Check/Create Tag
    $ExistingTag = Get-RetentionPolicyTag $TagName -ErrorAction SilentlyContinue
    if (-not $ExistingTag) {
        New-RetentionPolicyTag -Name $TagName -Type All -AgeLimitForRetention $AgeLimit -RetentionAction MoveToArchive
        Write-Host "[+] Created Tag: $TagName" -ForegroundColor Green
    }

    # Create Policy
    New-RetentionPolicy -Name $PolicyName -RetentionPolicyTagLinks $TagName
    Write-Host "[+] Created Policy: $PolicyName" -ForegroundColor Green

    # 4. Apply to Mailbox & Kick-Start
    Enable-Mailbox -Identity $UserEmail -Archive -ErrorAction SilentlyContinue
    Set-Mailbox -Identity $UserEmail -RetentionPolicy $PolicyName -ErrorAction Stop
    
    # THE KICK-START
    Start-ManagedFolderAssistant -Identity $UserEmail
    Write-Host "[SUCCESS] Archive enabled and Folder Assistant kicked off for $UserEmail." -ForegroundColor Green

} catch {
    Write-Error "An unexpected error occurred: $_"
}