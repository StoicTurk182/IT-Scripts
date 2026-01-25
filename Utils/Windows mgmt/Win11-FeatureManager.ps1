# ============================================================================
# TOTAL BYPASS ELEVATION (Local Admin Fix)
# ============================================================================
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (!$IsAdmin) {
    # If the window is flashing and closing, -NoExit will keep it open so you can see the error.
    $ArgList = "-NoExit -NoProfile -ExecutionPolicy Bypass -Command `"& {Set-ExecutionPolicy Bypass -Scope Process -Force; & '$PSCommandPath'}`""
    
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList $ArgList -ErrorAction Stop
        exit
    } catch {
        Write-Error "CRITICAL: Could not launch elevated process. Check if UAC is disabled."
        Pause ; exit
    }
}

# Clear any previous warnings
Clear-Host
Write-Host "--- SESSION: LOCAL ADMIN ELEVATED ---" -ForegroundColor Green
# ============================================================================

# ============================================================================
# REMAINDER OF YOUR SCRIPT STARTS HERE
# ============================================================================
<#
.SYNOPSIS
    Win11/Server Feature Manager (DC/Admin Edition)
    Includes: 
      - Network Audit (Shares + IP Resolution)
      - GPO Force & Lock (Location Fix)
      - Verbose Update Cleaner
      - Printer Lock/Maintenance
    Runs via: iex (irm "url")
#>
#Requires -RunAsAdministrator
#Requires -Version 5.1

$Script:CapPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore"

# ============================================================================
# MASTER CONFIGURATION DATA
# ============================================================================
$Menus = [ordered]@{
    "Privacy & Capabilities" = @{
        Type = "Registry"
        Items = [ordered]@{
            # 1. SERVICE (Must be Running)
            "Location Service (lfsvc)" = @{ 
                Type="Service"; ServiceName="lfsvc"
                Check={ (Get-Service "lfsvc").Status -eq "Running" }
                On={ Set-Service "lfsvc" -StartupType Automatic; Start-Service "lfsvc" }
                Off={ Stop-Service "lfsvc" -Force; Set-Service "lfsvc" -StartupType Disabled }
            }
            # 2. SENSOR LOCK (Hardware Driver Fix)
            "Sensor Hardware Lock"     = @{ 
                Path="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}"; 
                Name="SensorPermissionState"; On=1; Off=0; RefreshExplorer=$true 
            }
            # 3. GPO FORCE & LOCK (The "Ultimate" Fix for Managed Organizations)
            "Force & Lock GPO (Ultimate)" = @{
                Type = "Script"
                Check = { 
                    $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocation" -ErrorAction SilentlyContinue).DisableLocation
                    $v -eq 0
                }
                On = {
    $Keys = @(
        @{ P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"; N="DisableLocation"; V=0 },
        @{ P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"; N="DisableWindowsLocationProvider"; V=0 },
        @{ P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; N="LetAppsAccessLocation"; V=1 }
    )
    foreach ($k in $Keys) {
        if (!(Test-Path $k.P)) { New-Item -Path $k.P -Force | Out-Null }
        Set-ItemProperty -Path $k.P -Name $k.N -Value $k.V -Type DWORD -Force
        
        # ACL LOCK: Corrected the permission strings to match the Enums exactly
        $acl = Get-Acl $k.P
        # We use 'WriteKey' and 'Delete' which covers SetValue and Subdirectory deletion
        $rule = New-Object System.Security.AccessControl.RegistryAccessRule("SYSTEM", "WriteKey, Delete", "Deny")
        $acl.AddAccessRule($rule)
        Set-Acl -Path $k.P -AclObject $acl
    }
    Out-Color " [GPO Locked]" "Green"
}
                Off = {
                    # Unlock and Delete
                    $Keys = @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors", "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy")
                    foreach ($p in $Keys) {
                        if (Test-Path $p) {
                            $acl = Get-Acl $p
                            $rules = $acl.GetAccessRules($true, $true, [System.Security.Principal.NTAccount])
                            foreach ($r in $rules) { if ($r.IdentityReference -eq "NT AUTHORITY\SYSTEM" -and $r.AccessControlType -eq "Deny") { $acl.RemoveAccessRule($r) } }
                            Set-Acl -Path $p -AclObject $acl
                            Remove-Item -Path $p -Recurse -Force
                        }
                    }
                    Out-Color " [Locks Removed]" "Yellow"
                }
            }
            
            # 4. STANDARD CONSENT
            "Location System Consent"  = @{ Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"; Name="Value"; On="Allow"; Off="Deny"; Type="String" }
            "Location User Override"   = @{ Path="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"; Name="Value"; On="Allow"; Off="Deny"; Type="String" }
            "Camera Access"            = @{ Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam"; Name="Value"; On="Allow"; Off="Deny"; Type="String" }
            "Microphone Access"        = @{ Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone"; Name="Value"; On="Allow"; Off="Deny"; Type="String" }
        }
    }
    "System Settings" = @{
        Type = "Registry"
        Items = [ordered]@{
            "Remote Desktop"       = @{ Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"; Name="fDenyTSConnections"; On=0; Off=1 }
            "RDP NLA"              = @{ Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name="UserAuthentication"; On=1; Off=0 }
            "User Account Control" = @{ Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"; Name="EnableLUA"; On=1; Off=0 }
            "SmartScreen"          = @{ Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer"; Name="SmartScreenEnabled"; On="On"; Off="Off"; Type="String" }
            "Fast Startup"         = @{ Path="HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"; Name="HiberbootEnabled"; On=1; Off=0 }
            "Clipboard History"    = @{ Path="HKCU:\SOFTWARE\Microsoft\Clipboard"; Name="EnableClipboardHistory"; On=1; Off=0 }
            "Advertising ID"       = @{ Path="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Name="Enabled"; On=1; Off=0 }
        }
    }
    "Printer Lock (Safe)" = @{
        Type = "Registry"
        Items = [ordered]@{
            "Hide Settings Page"      = @{ Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"; Name="SettingsPageVisibility"; On="hide:printers"; Off=""; Type="String"; RefreshExplorer=$true }
            "Block 'Add' Wizard"      = @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"; Name="NoAddPrinter"; On=1; Off=0; RefreshExplorer=$true }
            "Block Deleting"          = @{ Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"; Name="NoDeletePrinter"; On=1; Off=0; RefreshExplorer=$true }
            "Lock Properties Tabs"    = @{ Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"; Name="NoPrinterTabs"; On=1; Off=0; RefreshExplorer=$true }
            "Block Net Auto-Setup"    = @{ Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\NcdAutoSetup\Private"; Name="AutoSetup"; On=0; Off=1 }
        }
    }
    "Printer Maintenance" = @{
        Type = "Script"
        Items = [ordered]@{
            "Microsoft Print to PDF" = @{
                Check={ (Get-WindowsOptionalFeature -Online -FeatureName "Printing-PrintToPDFServices-Features").State -eq "Enabled" }
                On={ Enable-WindowsOptionalFeature -Online -FeatureName "Printing-PrintToPDFServices-Features" -All -NoRestart | Out-Null }
                Off={ Disable-WindowsOptionalFeature -Online -FeatureName "Printing-PrintToPDFServices-Features" -NoRestart | Out-Null }
            }
            "Microsoft XPS Writer"   = @{
                Check={ (Get-WindowsOptionalFeature -Online -FeatureName "Printing-XPSServices-Features").State -eq "Enabled" }
                On={ Enable-WindowsOptionalFeature -Online -FeatureName "Printing-XPSServices-Features" -All -NoRestart | Out-Null }
                Off={ Disable-WindowsOptionalFeature -Online -FeatureName "Printing-XPSServices-Features" -NoRestart | Out-Null }
            }
            "Print Spooler Service"  = @{
                Check={ (Get-Service "Spooler").Status -eq "Running" }
                On={ Set-Service "Spooler" -StartupType Automatic; Start-Service "Spooler" }
                Off={ Stop-Service "Spooler" -Force; Set-Service "Spooler" -StartupType Disabled }
            }
        }
    }
    "Windows Services" = @{
        Type = "Service"
        Items = [ordered]@{
            "Windows Update" = "wuauserv"; "Windows Search" = "WSearch"; "Windows Time" = "w32time"
            "Remote Desktop" = "TermService"; "WinRM" = "WinRM"; "Windows Defender" = "WinDefend"
            "Print Spooler" = "Spooler"; "BITS" = "BITS"
        }
    }
    "Firewall Profiles" = @{
        Type = "Firewall"
        Items = [ordered]@{
            "All Profiles" = "All"; "Network Discovery" = "Network Discovery"; "File Sharing" = "File and Printer Sharing"; "RDP Rule" = "Remote Desktop"
        }
    }
}

# ============================================================================
# NEW FEATURE: SYSTEM SCAN (MARKDOWN)
# ============================================================================
function Run-SystemScan {
    Write-Host "`n [!] Scanning System... (This may take a moment)" -ForegroundColor Cyan
    
    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.AppendLine("# System Audit Report")
    $null = $sb.AppendLine("**Date:** $(Get-Date)")
    $null = $sb.AppendLine("")

    # 1. HOST DETAILS
    Write-Host "  - Gathering Host Details..." -ForegroundColor Gray
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $lang = Get-UICulture
    
    $null = $sb.AppendLine("## Host Details")
    $null = $sb.AppendLine("- **Hostname:** $($cs.DNSHostName)")
    $null = $sb.AppendLine("- **Model:** $($cs.Manufacturer) $($cs.Model)")
    $null = $sb.AppendLine("- **Serial:** $($bios.SerialNumber)")
    $null = $sb.AppendLine("- **OS:** $($os.Caption) (Build $($os.BuildNumber))")
    $null = $sb.AppendLine("- **Display Language:** $($lang.DisplayName) ($($lang.Name))")
    $null = $sb.AppendLine("- **Uptime:** $([math]::Round((New-TimeSpan -Start $os.LastBootUpTime).TotalHours, 1)) Hours")
    $null = $sb.AppendLine("")

    # 2. HARDWARE SPECS
    Write-Host "  - Gathering Hardware Specs..." -ForegroundColor Gray
    $cpu = Get-CimInstance Win32_Processor
    $gpu = Get-CimInstance Win32_VideoController
    $disks = Get-CimInstance Win32_DiskDrive
    
    $null = $sb.AppendLine("## Hardware Specifications")
    $null = $sb.AppendLine("- **CPU:** $($cpu.Name)")
    $null = $sb.AppendLine("- **Memory:** $([math]::Round($cs.TotalPhysicalMemory / 1GB, 2)) GB")
    foreach ($g in $gpu) { $null = $sb.AppendLine("- **GPU:** $($g.Name)") }
    foreach ($d in $disks) { $null = $sb.AppendLine("- **Disk:** $($d.Model) ($([math]::Round($d.Size / 1GB, 0)) GB)") }
    $null = $sb.AppendLine("")

    # 3. NETWORK INFO
    Write-Host "  - Gathering Network Config..." -ForegroundColor Gray
    $null = $sb.AppendLine("## Network Configuration")
    $nets = Get-NetIPConfiguration | Where-Object { $_.IPv4Address -ne $null }
    foreach ($n in $nets) {
        $null = $sb.AppendLine("### Interface: $($n.InterfaceAlias)")
        $null = $sb.AppendLine("- **IPv4:** $($n.IPv4Address.IPAddress)")
        $null = $sb.AppendLine("- **Gateway:** $($n.IPv4DefaultGateway.NextHop)")
        $dns = ($n.DNSServer.ServerAddresses) -join ", "
        $null = $sb.AppendLine("- **DNS:** $dns")
        $null = $sb.AppendLine("- **MAC:** $($n.NetAdapter.MacAddress)")
        $null = $sb.AppendLine("")
    }

    # 4. NETWORK SHARES & MAPPED DRIVES
    Write-Host "  - Gathering Network Shares & Maps..." -ForegroundColor Gray
    $null = $sb.AppendLine("## Network Shares & Mapped Drives")
    
    # Hosted Shares
    $null = $sb.AppendLine("### Local Hosted Shares")
    $localShares = Get-SmbShare -ErrorAction SilentlyContinue | Sort-Object Name
    if ($localShares) {
        foreach ($ls in $localShares) {
            $desc = if ($ls.Description) { " ($($ls.Description))" } else { "" }
            $null = $sb.AppendLine("- **$($ls.Name):** $($ls.Path)$desc")
        }
    } else { $null = $sb.AppendLine("_No local shares hosted._") }
    $null = $sb.AppendLine("")

    # Active Connections with IP Resolution
    $null = $sb.AppendLine("### Mapped Drives & Active Connections")
    $conns = Get-SmbConnection -ErrorAction SilentlyContinue
    $maps  = Get-SmbMapping -ErrorAction SilentlyContinue
    
    if ($conns) {
        foreach ($c in $conns) {
            # Resolve IP
            $serverIP = "Resolving..."
            try { 
                $addresses = [System.Net.Dns]::GetHostAddresses($c.ServerName)
                $serverIP = ($addresses | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1).IPAddressToString
                if (!$serverIP) { $serverIP = $addresses[0].IPAddressToString }
            } catch { $serverIP = "Unresolved" }

            # Find Drive Letter
            $drive = $maps | Where-Object { $_.RemotePath -match [regex]::Escape($c.ServerName) -and $_.RemotePath -match [regex]::Escape($c.ShareName) } | Select-Object -ExpandProperty LocalPath -First 1
            $prefix = if ($drive) { "**$drive**" } else { "(UNC)" }

            $null = $sb.AppendLine("- $prefix \\$($c.ServerName)\$($c.ShareName)")
            $null = $sb.AppendLine("  - **IP Address:** $serverIP")
            $null = $sb.AppendLine("  - **Username:** $($c.UserName)")
        }
    } else { $null = $sb.AppendLine("_No active remote SMB connections._") }
    $null = $sb.AppendLine("")

    # 5. INSTALLED APPS
    Write-Host "  - Gathering Installed Applications..." -ForegroundColor Gray
    $null = $sb.AppendLine("## Installed Applications")
    $path1 = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    $path2 = "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    $apps = Get-ItemProperty $path1, $path2 -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -ne $null } | 
            Select-Object DisplayName, DisplayVersion, Publisher | 
            Sort-Object DisplayName -Unique

    foreach ($app in $apps) {
        $ver = if ($app.DisplayVersion) { " (v$($app.DisplayVersion))" } else { "" }
        $null = $sb.AppendLine("- $($app.DisplayName)$ver")
    }

    $report = $sb.ToString()
    Set-Clipboard -Value $report
    Write-Host "`n [OK] Markdown Report copied to CLIPBOARD!" -ForegroundColor Green
    Pause
}

# ============================================================================
# NEW FEATURE: VERBOSE UPDATE CLEANER
# ============================================================================
function Clean-UpdateCache {
    Write-Host "`n=== WINDOWS UPDATE CLEANER ===" -ForegroundColor Cyan
    
    # 1. Stop Service
    Write-Host " 1. Stopping Windows Update Service (wuauserv)..." -NoNewline
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    if ((Get-Service wuauserv).Status -eq 'Stopped') { Write-Host " [STOPPED]" -ForegroundColor Green }
    else { Write-Host " [FAILED] Service stuck." -ForegroundColor Red; return }

    # 2. Delete Files (Verbose)
    $path = "C:\Windows\SoftwareDistribution\Download"
    Write-Host " 2. Cleaning Cache ($path)..." -ForegroundColor Yellow
    if (Test-Path $path) {
        $files = Get-ChildItem -Path $path -Recurse -Force
        if ($files.Count -eq 0) {
             Write-Host "    - Folder is already empty." -ForegroundColor Green
        } else {
            foreach ($f in $files) {
                try {
                    Remove-Item $f.FullName -Recurse -Force -ErrorAction Stop
                    Write-Host "    - Deleted: $($f.Name)" -ForegroundColor Gray
                } catch {
                    Write-Host "    - ERROR Deleting: $($f.Name)" -ForegroundColor Red
                }
            }
        }
    }

    # 3. Restart Service
    Write-Host " 3. Restarting Service..." -NoNewline
    Start-Service wuauserv
    if ((Get-Service wuauserv).Status -eq 'Running') { Write-Host " [RUNNING]" -ForegroundColor Green }
    else { Write-Host " [WARN] Service did not start." -ForegroundColor Yellow }
    
    Write-Host "`n[DONE] Update Cache Cleaned." -ForegroundColor Green
    Pause
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
function Out-Color ($msg, $col="Cyan", $nl=$true) { Write-Host $msg -ForegroundColor $col -NoNewline:(!$nl) }

function Get-Status {
    param($Type, $Target)
    try {
        if ($Target.Type -eq "Service") {
            $s = Get-Service $Target.ServiceName -ErrorAction SilentlyContinue
            return @{ Text="[$($s.Status)/$($s.StartType)]"; Color=if($s.Status -eq 'Running'){"Green"}else{"Red"} }
        }
        if ($Type -eq "Script" -or $Target.Check) {
            $res = & $Target.Check
            return @{ Text=if($res){"[Enabled]"}else{"[Disabled]"}; Color=if($res){"Green"}else{"Red"} }
        }
        if ($Type -eq "Registry" -or $Type -eq "DWORD" -or $Type -eq "String") {
            $curr = (Get-ItemProperty $Target.Path -Name $Target.Name -ErrorAction SilentlyContinue).($Target.Name)
            $isOn = $curr -eq $Target.On
            return @{ Text=if($isOn){"[Enabled]"}else{"[Disabled]"}; Color=if($isOn){"Green"}else{"Red"} }
        }
        if ($Type -eq "Capability") {
            $val = (Get-ItemProperty "$Script:CapPath\$Target" -Name Value -ErrorAction SilentlyContinue).Value
            return @{ Text=if($val -eq "Allow"){"[Enabled]"}else{"[Disabled]"}; Color=if($val -eq "Allow"){"Green"}else{"Red"} }
        }
        if ($Type -eq "Firewall") {
            if ($Target -eq "All") { return @{ Text="[N/A]"; Color="Gray" } }
            $r = Get-NetFirewallRule -DisplayGroup $Target -Enabled True -ErrorAction SilentlyContinue
            return @{ Text=if($r){"[Enabled]"}else{"[Disabled]"}; Color=if($r){"Green"}else{"Red"} }
        }
        if ($Type -eq "Service") {
            $s = Get-Service $Target -ErrorAction SilentlyContinue
            return @{ Text="[$($s.Status)/$($s.StartType)]"; Color=if($s.Status -eq 'Running'){"Green"}else{"Red"} }
        }
    } catch { return @{ Text="[Error]"; Color="Red" } }
}

function Set-Feature {
    param($Type, $Target, $Action) 
    try {
        if ($Type -eq "Script" -or ($Target.On -is [ScriptBlock])) {
            if ($Action) { & $Target.On } else { & $Target.Off }
            Out-Color " OK" "Green"; return $true
        }
        if ($Type -eq "Registry" -or $Type -eq "DWORD" -or $Type -eq "String") {
            $val = if($Action){$Target.On}else{$Target.Off}
            $regType = if($Target.Type -eq "String"){"REG_SZ"}else{"REG_DWORD"}
            $cmdPath = $Target.Path.Replace("HKLM:", "HKLM").Replace("HKCU:", "HKCU")
            $proc = Start-Process reg.exe -ArgumentList "add `"$cmdPath`" /v `"$($Target.Name)`" /t $regType /d `"$val`" /f" -NoNewWindow -PassThru -Wait
            if ($proc.ExitCode -eq 0) {
                Out-Color " OK" "Green"; if ($Target.RefreshExplorer) { return $true }
            } else { throw "REG Command failed." }
        }
        if ($Type -eq "Capability") {
            $val = if($Action){"Allow"}else{"Deny"}
            $cmdPath = "$Script:CapPath\$Target".Replace("HKLM:","HKLM")
            $proc = Start-Process reg.exe -ArgumentList "add `"$cmdPath`" /v Value /t REG_SZ /d `"$val`" /f" -Wait -PassThru -NoNewWindow
            if ($proc.ExitCode -eq 0) { Out-Color " OK" "Green" } else { throw "Access Denied" }
        }
        if ($Type -eq "Service") {
            if ($Action) { Set-Service $Target -StartupType Automatic; Start-Service $Target } 
            else { Stop-Service $Target -Force; Set-Service $Target -StartupType Disabled }
            Out-Color " OK" "Green"
        }
        if ($Type -eq "Firewall") {
             if ($Target -eq "All") { $s = if($Action){"on"}else{"off"}; netsh advfirewall set allprofiles state $s | Out-Null } 
             else { $s = if($Action){"yes"}else{"no"}; netsh advfirewall firewall set rule group="$Target" new enable=$s | Out-Null }
             Out-Color " OK" "Green"
        }
    } catch { Out-Color " FAILED: $($_.Exception.Message)" "Red" }
    return $false
}

function Restart-Explorer {
    Write-Host "`n [!] Policies updated. Restarting Explorer..." -ForegroundColor Magenta
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    if (!(Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer }
}

# ============================================================================
# UI LOGIC
# ============================================================================
function Show-SubMenu {
    param($Title, $Config)
    while ($true) {
        Clear-Host; Out-Color "=== $Title ===" "Magenta"
        $i = 1; $keys = @($Config.Items.Keys)
        foreach ($k in $keys) {
            $stat = Get-Status -Type $Config.Type -Target $Config.Items[$k]
            Write-Host "$($i.ToString().PadLeft(2)) " -NoNewline -ForegroundColor Yellow
            Write-Host "$k".PadRight(25) -NoNewline
            Out-Color $stat.Text $stat.Color
            $i++
        }
        Write-Host "`n [A] Enable All  [D] Disable All  [0] Back" -ForegroundColor Gray
        $c = Read-Host " Select"
        $needsRefresh = $false
        if ($c -eq "0") { return }
        if ($c -match "A|D") {
            $act = ($c -eq "A"); $keys | ForEach-Object { 
                Write-Host " Setting $_..." -NoNewline
                if (Set-Feature -Type $Config.Type -Target $Config.Items[$_] -Action $act) { $needsRefresh = $true }
            }
            if ($needsRefresh) { Restart-Explorer } else { Pause }
        }
        elseif ($c -as [int] -and $c -le $keys.Count) {
            $k = $keys[$c-1]; Write-Host "`n Selected: $k" -ForegroundColor Cyan
            $act = Read-Host " [1] Enable  [0] Disable"
            if ($act -match "[01]") {
                Write-Host " Applying..." -NoNewline
                if (Set-Feature -Type $Config.Type -Target $Config.Items[$k] -Action ($act -eq "1")) { $needsRefresh = $true }
                if ($needsRefresh) { Restart-Explorer } else { Pause }
            }
        }
    }
}

function Show-QuickCommands {
    Clear-Host; Out-Color "=== Quick Commands ===" "Magenta"
    $cmds = @{
        "1"=@{N="Sync Time";C={w32tm /resync /force}}
        "2"=@{N="Flush DNS";C={ipconfig /flushdns}}
        "3"=@{N="Reset Winsock";C={netsh winsock reset}}
        "4"=@{N="SFC Scan";C={sfc /scannow}}
        "5"=@{N="Clean Update Cache";C={Clean-UpdateCache}}
        "6"=@{N="Restart Explorer";C={Stop-Process -Name explorer -Force}}
    }
    $cmds.Keys | Sort-Object | % { Write-Host " [$_] $($cmds[$_].N)" -ForegroundColor Yellow }
    $c = Read-Host "`n Select (0 to Back)"; if($cmds[$c]){ & $cmds[$c].C; Pause }
}

# ============================================================================
# MAIN LOOP
# ============================================================================

while ($true) {
    Clear-Host; Out-Color "=== Win11 Feature & Printer Manager ===" "Cyan"
    $i=1; $Menus.Keys | % { Write-Host " [$i] $_" -ForegroundColor Yellow; $i++ }
    Write-Host " [R] System Scan (Copy to Clipboard)" -ForegroundColor Magenta
    Write-Host " [Q] Quick Commands`n [0] Exit" -ForegroundColor Gray
    
    $sel = Read-Host " Select"
    if ($sel -eq "0") { break }
    if ($sel -eq "Q") { Show-QuickCommands; continue }
    if ($sel -eq "R") { Run-SystemScan; continue }
    
    $menuKeys = @($Menus.Keys)
    if ($sel -as [int] -and $sel -le $menuKeys.Count) {
        $key = $menuKeys[$sel-1]
        Show-SubMenu -Title $key -Config $Menus[$key]
    }
}