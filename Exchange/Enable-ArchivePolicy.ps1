# Parameters: Set the user email here or pass it when running the script
param (
    [Parameter(Mandatory=$true)]
    [string]$UserEmail,
    [string]$PolicyName = "Archive Policy - 1 Year",
    [string]$TagName = "Archive - 1 Year",
    [int]$Days = 365
)

# 1. Connect (Skip if already connected)
if (!(Get-Module -Name ExchangeOnlineManagement)) { Connect-ExchangeOnline }

Write-Host "--- Processing Configuration for $UserEmail ---" -ForegroundColor Cyan

# 2. Ensure Tag Exists
if (-not (Get-RetentionPolicyTag $TagName -ErrorAction SilentlyContinue)) {
    New-RetentionPolicyTag -Name $TagName -Type All -AgeLimitForRetention $Days -RetentionAction MoveToArchive
    Write-Host "[+] Created Tag: $TagName" -ForegroundColor Green
}

# 3. Ensure Policy Exists and includes the Tag
if (-not (Get-RetentionPolicy $PolicyName -ErrorAction SilentlyContinue)) {
    New-RetentionPolicy -Name $PolicyName -RetentionPolicyTagLinks $TagName
    Write-Host "[+] Created Policy: $PolicyName" -ForegroundColor Green
}

# 4. Enable Archive, Assign Policy, and Force Process (The "Last Step")
try {
    # Enable Archive if needed
    Enable-Mailbox -Identity $UserEmail -Archive -ErrorAction SilentlyContinue
    
    # Assign Policy
    Set-Mailbox -Identity $UserEmail -RetentionPolicy $PolicyName
    Write-Host "[+] Archive Enabled and Policy Assigned." -ForegroundColor Green

    # FINAL STEP: Force the Managed Folder Assistant to start moving items
    Start-ManagedFolderAssistant -Identity $UserEmail
    Write-Host "[!] Managed Folder Assistant Triggered. Items will begin moving shortly." -ForegroundColor Yellow
}
catch {
    Write-Error "Failed to update mailbox: $_"
}