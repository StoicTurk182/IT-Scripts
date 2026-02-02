# 1. PRE-CHECK: Wait for the server to be reachable (Times out after 30 seconds)
$Server = "Orion-i"
$Timeout = 30
$timer = [diagnostics.stopwatch]::StartNew()

Write-Host "Waiting for $Server to respond..."
while (!(Test-Connection -ComputerName $Server -Count 1 -Quiet) -and ($timer.Elapsed.TotalSeconds -lt $Timeout)) { 
    Start-Sleep -Seconds 2 
}

if ($timer.Elapsed.TotalSeconds -ge $Timeout) {
    Write-Error "Server $Server not found. Aborting mapping to prevent ghost drives."
    exit
}

# 2. Define your shares and their custom Aliases
$DriveMap = @{
    "\\Orion-i\a" = "Server_Tools"
    "\\Orion-i\o" = "VM_Lab"
    "\\Orion-i\s" = "Backup_Local"
}

# 3. Identify used letters and exclude Y and C
$UsedLetters = (Get-PSDrive -PSProvider FileSystem).Name
# 90..68 generates Z down to D. 
$AvailableLetters = 90..68 | ForEach-Object { [char]$_ } | Where-Object { 
    $UsedLetters -notcontains $_ -and $_ -ne 'Y' -and $_ -ne 'C'
}

# 4. Process Mapping
$i = 0
foreach ($Path in $DriveMap.Keys) {
    if ($i -lt $AvailableLetters.Count) {
        $Letter = $AvailableLetters[$i]
        $Label = $DriveMap[$Path]
        $DriveFull = "$($Letter):"

        # Check if this specific network path is ALREADY mapped elsewhere
        $Existing = Get-PSDrive | Where-Object { $_.DisplayRoot -eq $Path }
        
        if ($Existing) {
            Write-Host "Share $Path is already at $($Existing.Name):. Refreshing label..."
        } else {
            # Map the drive
            New-PSDrive -Name $Letter -PSProvider FileSystem -Root $Path -Persist -Scope Global -ErrorAction SilentlyContinue | Out-Null
        }

        # Apply/Refresh the Alias (Label)
        try {
            $Shell = New-Object -ComObject Shell.Application
            $Shell.NameSpace($DriveFull).Self.Name = $Label
            Write-Host "Success: [$DriveFull] -> $Label"
        } catch {
            Write-Warning "Could not set label for $DriveFull"
        }
        
        $i++
    }
}