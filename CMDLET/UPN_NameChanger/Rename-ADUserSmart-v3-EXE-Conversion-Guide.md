# Rename-ADUserSmart_v3 - EXE Conversion Guide

Compiling the AD User Rename script into a standalone executable.

---

## Overview

| Aspect | Detail |
|--------|--------|
| Tool | PS2EXE |
| Input | Rename-ADUserSmart-Standalone.ps1 |
| Output | Rename-ADUserSmart.exe |
| Runtime Dependency | PowerShell 5.1, ActiveDirectory module (RSAT) |
| Behaviour | Identical to original script |

The EXE wraps your script inside a compiled executable. It still requires PowerShell and the ActiveDirectory module on the target machine. It does not bundle those dependencies.

---

## What Changes from the Original Script

| Change | Reason |
|--------|--------|
| Added RSAT/AD module check at launch | Gives a clear error instead of a cryptic crash if RSAT is missing |
| Added `Read-Host` before exit | Prevents the console window from closing instantly on double-click |
| Added `Import-Module ActiveDirectory` | EXE does not inherit module auto-loading the same way a PS session does |

All script logic, parameters, prompts, and output remain identical.

---

## Step 1: Install PS2EXE

Open PowerShell:

```powershell
Install-Module -Name ps2exe -Scope CurrentUser -Force
```

Verify:

```powershell
Get-Module -ListAvailable -Name ps2exe
```

Expected output shows ps2exe listed with a version number.

Source: https://github.com/MScholtes/PS2EXE

---

## Step 2: Create the Standalone Script

The original script needs three small additions for EXE compatibility. Create the standalone version in your working directory.

Navigate to the folder:

```powershell
Set-Location "C:\Users\Administrator\Andrew J IT Labs\Andrew J IT Labs - Andrew J IT Labs\IT-Scripts\CMDLET\UPN_NameChanger"
```

Open your editor:

```powershell
code ".\Rename-ADUserSmart-Standalone.ps1"
```

Paste the following and save:

```powershell
#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Renames an AD User, updates UPN/Mail, and demotes old Primary SMTP to an Alias.
    
.EXAMPLE
    Rename-ADUserSmart.exe -Identity "j.doe" -NewPrefix "john.smith" -FirstName "John" -LastName "Smith"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)][string]$Identity,
    [Parameter(Mandatory=$false)][string]$NewPrefix,
    [Parameter(Mandatory=$false)][string]$FirstName,
    [Parameter(Mandatory=$false)][string]$LastName
)

# --- PREREQUISITE CHECK (added for EXE) ---
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Host "ERROR: ActiveDirectory module not found." -ForegroundColor Red
    Write-Host ""
    Write-Host "This tool requires RSAT Active Directory tools." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Install on Windows 10/11:" -ForegroundColor Gray
    Write-Host "  Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Install on Windows Server:" -ForegroundColor Gray
    Write-Host "  Install-WindowsFeature -Name RSAT-AD-PowerShell" -ForegroundColor Gray
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

Import-Module ActiveDirectory -ErrorAction Stop

# --- 1. SETUP LOGGING ---
$LogDir = "$env:TEMP\ADRenameLogs"
if (!(Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$LogFile = "$LogDir\Log_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"

Start-Transcript -Path $LogFile -Append | Out-Null

Function Rename-ADUserSmart {
    param ($Id, $Prefix, $FName, $LName)

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "             AD IDENTITY UPDATE WIZARD                  " -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan

    # --- SEARCH ---
    if ([string]::IsNullOrWhiteSpace($Id)) {
        $Id = Read-Host "ENTER USERNAME OR EMAIL TO START"
    }

    Try {
        $User = Get-ADUser -Filter "UserPrincipalName -eq '$Id' -or SamAccountName -eq '$Id'" `
                           -Properties proxyAddresses, DisplayName, EmailAddress, UserPrincipalName, ProtectedFromAccidentalDeletion, GivenName, Surname `
                           -ErrorAction Stop
    }
    Catch {
        Write-Warning "Error contacting Active Directory: $($_.Exception.Message)"
        return
    }

    if (-not $User) {
        Write-Host "Status: NOT FOUND" -ForegroundColor Red
        return
    }
    
    Write-Host "Status: FOUND" -ForegroundColor Green
    Write-Host "Current Name: $($User.DisplayName)"
    Write-Host "Current UPN:  $($User.UserPrincipalName)"

    # --- INPUTS (Handles Pasting Issues) ---
    $DomainSuffix = if ($User.UserPrincipalName -match "@") { ($User.UserPrincipalName -split "@")[1] } else { Read-Host "Enter Domain (e.g. corp.com)" }

    if ([string]::IsNullOrWhiteSpace($Prefix)) {
        Write-Host "`n[TIP: Right-click to paste in most PowerShell windows]" -ForegroundColor Gray
        $Prefix = Read-Host "New Username (prefix only)" 
    }
    
    if ($Prefix -match "@") {
        Write-Warning "Invalid Input: Prefix cannot contain '@'."
        return
    }

    $NewFirstName = if ([string]::IsNullOrWhiteSpace($FName)) { Read-Host "New First Name (Enter to keep current)" } else { $FName }
    $NewLastName  = if ([string]::IsNullOrWhiteSpace($LName)) { Read-Host "New Last Name (Enter to keep current)"  } else { $LName }
    
    # Apply Defaults
    $NewFirstName = if ([string]::IsNullOrWhiteSpace($NewFirstName)) { $User.GivenName } else { $NewFirstName }
    $NewLastName  = if ([string]::IsNullOrWhiteSpace($NewLastName)) { $User.Surname } else { $NewLastName }

    $NewUPN = "$Prefix@$DomainSuffix"
    $NewDisplayName = "$NewFirstName $NewLastName"
    $NewSamAccount = $Prefix 

    # Forest-wide uniqueness check
    $Conflict = Get-ADUser -Filter "SamAccountName -eq '$NewSamAccount' -or UserPrincipalName -eq '$NewUPN'" -ErrorAction SilentlyContinue
    if ($Conflict -and $Conflict.ObjectGUID -ne $User.ObjectGUID) {
        Write-Warning "CONFLICT: The proposed username or UPN already exists for user: $($Conflict.Name)"
        return
    }

    # --- PROXY CALCULATION ---
    $EmailSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($User.proxyAddresses) {
        foreach ($addr in $User.proxyAddresses) {
            $EmailSet.Add(($addr -replace '^(SMTP|smtp):', '')) | Out-Null
        }
    }
    if ($User.EmailAddress) { $EmailSet.Add($User.EmailAddress) | Out-Null }
    
    $EmailSet.Remove($NewUPN) | Out-Null # Ensure new UPN isn't in alias list
    
    $FinalProxies = [System.Collections.Generic.List[string]]::new()
    $FinalProxies.Add("SMTP:$NewUPN") 
    foreach ($email in $EmailSet) { $FinalProxies.Add("smtp:$email") }

    # --- CONFIRMATION ---
    Write-Host "`n[ PROPOSED CHANGES ]" -ForegroundColor Magenta
    Write-Host "--------------------------------------------------------"
    Write-Host "Display Name:  $($User.DisplayName) -> $NewDisplayName"
    Write-Host "SamAccount:    $($User.SamAccountName) -> $NewSamAccount"
    Write-Host "UserPrincipal: $($User.UserPrincipalName) -> $NewUPN"
    Write-Host "Primary SMTP:  $NewUPN"
    Write-Host "Aliases:       $($EmailSet.Count) addresses preserved."
    Write-Host "--------------------------------------------------------"
    
    if ((Read-Host "Type 'Y' to apply") -ne 'Y') { return }

    # --- EXECUTION ---
    Try {
        $WasProtected = $User.ProtectedFromAccidentalDeletion
        if ($WasProtected) {
            Write-Host "Unlocking object..."
            Set-ADObject -Identity $User.DistinguishedName -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
        }

        $UserChanges = @{
            GivenName = $NewFirstName; Surname = $NewLastName; DisplayName = $NewDisplayName;
            SamAccountName = $NewSamAccount; UserPrincipalName = $NewUPN; EmailAddress = $NewUPN
        }
        
        Write-Host "Updating attributes..." -NoNewline
        Set-ADUser -Identity $User @UserChanges -Replace @{proxyAddresses = $FinalProxies.ToArray()} -ErrorAction Stop
        Write-Host "[ OK ]" -ForegroundColor Green

        Write-Host "Renaming AD Object..." -NoNewline
        Rename-ADObject -Identity $User -NewName $NewDisplayName -ErrorAction Stop
        Write-Host "[ OK ]" -ForegroundColor Green

        if ($WasProtected) {
            Write-Host "Relocking object..."
            $NewObj = Get-ADUser -Identity $NewSamAccount
            Set-ADObject -Identity $NewObj.DistinguishedName -ProtectedFromAccidentalDeletion $true -ErrorAction Stop
        }
        Write-Host "`n Success." -ForegroundColor Cyan
    }
    Catch {
        Write-Error "Error: $($_.Exception.Message)"
    }
}

# --- MAIN ---
Try {
    Rename-ADUserSmart -Id $Identity -Prefix $NewPrefix -FName $FirstName -LName $LastName
}
Finally {
    Stop-Transcript | Out-Null
    Write-Host "`nOpening Log: $LogFile" -ForegroundColor Yellow
    Read-Host "Press Enter to open log and exit"
    Start-Process notepad.exe -ArgumentList $LogFile
}
```

---

## Step 3: Test the Standalone Script

Run it before compiling to confirm it works:

```powershell
.\Rename-ADUserSmart-Standalone.ps1
```

The wizard should appear and prompt for input. If you get errors here, fix them before compiling. The EXE will have the same errors.

---

## Step 4: Prepare Icon (Optional)

PS2EXE only accepts `.ico` format. PNG, JPG, and BMP will not work and will cause the compilation to fail.

### If You Already Have an .ico File

No conversion needed. Place it in the same folder as your script and skip to Step 5.

### Converting PNG to ICO with PowerShell

```powershell
Add-Type -AssemblyName System.Drawing

$PngPath = ".\your-image.png"
$IcoPath = ".\Rename-ADUserSmart.ico"

$png = [System.Drawing.Image]::FromFile($PngPath)
$icon = [System.Drawing.Icon]::FromHandle($png.GetHicon())

$stream = [System.IO.FileStream]::new($IcoPath, [System.IO.FileMode]::Create)
$icon.Save($stream)
$stream.Close()
$png.Dispose()

Write-Host "Icon created: $IcoPath"
```

Replace `.\your-image.png` with the path to your PNG file.

### Converting PNG to ICO Online

Upload a PNG to one of these sites and download the `.ico`:

- https://convertico.com
- https://icoconvert.com

Save the `.ico` file into the same folder as your script.

### Verify the Icon File

```powershell
Get-Item ".\Rename-ADUserSmart.ico" | Select-Object Name, Length
```

The file should exist and have a size greater than 0.

---

## Step 5: Compile to EXE

Navigate to your script folder if not already there:

```powershell
Set-Location "C:\Users\Administrator\Andrew J IT Labs\Andrew J IT Labs - Andrew J IT Labs\IT-Scripts\CMDLET\UPN_NameChanger"
```

### Without Custom Icon

Produces an EXE with the default PowerShell icon:

```powershell
Invoke-PS2EXE -InputFile ".\Rename-ADUserSmart-Standalone.ps1" `
              -OutputFile ".\Rename-ADUserSmart.exe" `
              -Title "AD User Rename Tool" `
              -Company "Informal IT Ltd" `
              -Version "3.0.0.0" `
              -RequireAdmin `
              -x64
```

### With Custom Icon

Replace the `-IconFile` value with the filename of your `.ico`:

```powershell
Invoke-PS2EXE -InputFile ".\Rename-ADUserSmart-Standalone.ps1" `
              -OutputFile ".\Rename-ADUserSmart.exe" `
              -IconFile ".\120px-Isis_triglavian.ico" `
              -Title "AD User Rename Tool" `
              -Company "Informal IT Ltd" `
              -Version "3.0.0.0" `
              -RequireAdmin `
              -x64
```

Expected output:

```
PS2EXE-GUI v0.5.0.29 by Ingo Karstein, reworked and enhanced by Markus Scholtes

Reading input file '.\Rename-ADUserSmart-Standalone.ps1'
Compiling file...
Output file '.\Rename-ADUserSmart.exe' written
```

### Verify the EXE

```powershell
Get-Item ".\Rename-ADUserSmart.exe" | Select-Object Name, Length, LastWriteTime
```

Check embedded metadata:

```powershell
(Get-Item ".\Rename-ADUserSmart.exe").VersionInfo | Format-List ProductName, FileDescription, CompanyName, ProductVersion
```

---

## Step 6: Test the EXE

### Interactive (Double-Click)

Navigate to the folder in Explorer and double-click `Rename-ADUserSmart.exe`. A console window opens with the AD Identity Update Wizard prompts.

### Interactive (Command Line)

```powershell
.\Rename-ADUserSmart.exe
```

### With Parameters

```powershell
.\Rename-ADUserSmart.exe -Identity "j.doe" -NewPrefix "john.smith" -FirstName "John" -LastName "Smith"
```

From Command Prompt:

```cmd
Rename-ADUserSmart.exe -Identity "j.doe" -NewPrefix "john.smith" -FirstName "John" -LastName "Smith"
```

---

## Step 7: Deploy

### Copy to Network Share

```powershell
$Destination = "\\fileserver\IT-Tools$\ADTools"

if (-not (Test-Path $Destination)) {
    New-Item -Path $Destination -ItemType Directory -Force
}

Copy-Item ".\Rename-ADUserSmart.exe" -Destination $Destination -Force
Write-Host "Deployed to: $Destination"
```

### Create Desktop Shortcut

```powershell
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:PUBLIC\Desktop\AD User Rename.lnk")
$Shortcut.TargetPath = "\\fileserver\IT-Tools$\ADTools\Rename-ADUserSmart.exe"
$Shortcut.Description = "Rename AD users with UPN and email management"
$Shortcut.Save()
```

### Copy to Individual Servers

```powershell
$Servers = @("DC01", "DC02", "MGMT01")

foreach ($Server in $Servers) {
    $Target = "\\$Server\C$\Tools"
    
    if (-not (Test-Path $Target)) {
        New-Item -Path $Target -ItemType Directory -Force
    }
    
    Copy-Item ".\Rename-ADUserSmart.exe" -Destination $Target -Force
    Write-Host "Copied to: $Target" -ForegroundColor Green
}
```

---

## Recompiling After Changes

If you edit the script, test it first then recompile:

```powershell
# Test the script
.\Rename-ADUserSmart-Standalone.ps1

# Recompile (overwrites existing EXE)
Invoke-PS2EXE -InputFile ".\Rename-ADUserSmart-Standalone.ps1" `
              -OutputFile ".\Rename-ADUserSmart.exe" `
              -IconFile ".\120px-Isis_triglavian.ico" `
              -Title "AD User Rename Tool" `
              -Company "Informal IT Ltd" `
              -Version "3.0.0.0" `
              -RequireAdmin `
              -x64
```

---

## PS2EXE Parameters Reference

| Parameter | Purpose | Example |
|-----------|---------|---------|
| `-InputFile` | Source .ps1 file | `".\Script.ps1"` |
| `-OutputFile` | Target .exe path | `".\Script.exe"` |
| `-IconFile` | Custom .ico file (must be .ico format) | `".\icon.ico"` |
| `-NoConsole` | `$false` keeps console window (needed for Read-Host) | `-NoConsole:$false` |
| `-RequireAdmin` | Embeds UAC admin manifest | `-RequireAdmin` |
| `-x64` | 64-bit executable | `-x64` |
| `-x86` | 32-bit executable | `-x86` |
| `-Title` | Window title / file properties | `-Title "My Tool"` |
| `-Description` | File description in properties | `-Description "Does things"` |
| `-Company` | Company name in properties | `-Company "Contoso"` |
| `-Product` | Product name in properties | `-Product "ToolSuite"` |
| `-Version` | Version in properties | `-Version "1.0.0.0"` |
| `-Copyright` | Copyright in properties | `-Copyright "(c) 2026"` |

---

## Troubleshooting

### EXE Window Closes Immediately

The standalone script includes `Read-Host "Press Enter to open log and exit"` before the final Notepad call. If this is missing, the window will flash and close.

If compiling your own modified version, ensure the script ends with a `Read-Host` or pause equivalent.

### ActiveDirectory Module Not Found

The EXE cannot bundle PowerShell modules. RSAT must be installed on the target machine:

```powershell
# Windows 10/11
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0

# Windows Server
Install-WindowsFeature -Name RSAT-AD-PowerShell
```

### Antivirus Blocks the EXE

PS2EXE executables are sometimes flagged as false positives because the compilation pattern matches some malware heuristics. Solutions:

1. Sign the EXE with a code signing certificate (best option)
2. Add an antivirus exclusion for the EXE path or folder
3. Distribute as the `.ps1` script instead using the cmdlet module approach

### EXE Does Not Accept Parameters

Parameters must be passed with the `-` prefix:

```cmd
REM WRONG
Rename-ADUserSmart.exe j.doe john.smith

REM CORRECT
Rename-ADUserSmart.exe -Identity "j.doe" -NewPrefix "john.smith"
```

### Cannot Run from Network Share

Some environments block EXE execution from UNC paths. Copy the EXE locally first:

```powershell
Copy-Item "\\fileserver\IT-Tools$\ADTools\Rename-ADUserSmart.exe" -Destination "C:\Temp\"
& "C:\Temp\Rename-ADUserSmart.exe"
```

### Icon Not Showing on EXE

- PS2EXE only accepts `.ico` format. PNG, JPG, BMP will cause errors or be ignored.
- If the icon appears as the old/default icon after recompiling, Windows Explorer is caching the old icon. Clear it:

```cmd
ie4uinit.exe -show
```

Or restart Explorer:

```powershell
Stop-Process -Name explorer -Force
Start-Process explorer
```

### PS2EXE Not Found

If `Invoke-PS2EXE` is not recognised after installing:

```powershell
Import-Module ps2exe
```

If still not found, reinstall:

```powershell
Install-Module -Name ps2exe -Scope CurrentUser -Force
```

---

## Changes from Original Script

| Item | Original v3 Script | Standalone EXE Version |
|------|--------------------|------------------------|
| Parameters | Identity, NewPrefix, FirstName, LastName | Identical |
| Interactive prompts | Prompts when parameters empty | Identical |
| AD search | UPN or SamAccountName filter | Identical |
| Domain extraction | Splits UPN at @ | Identical |
| Prefix validation | Rejects @ character | Identical |
| Conflict check | Forest-wide SamAccountName/UPN | Identical |
| Proxy handling | HashSet dedup, preserves aliases | Identical |
| Deletion protection | Removes, changes, restores | Identical |
| Logging | `$env:TEMP\ADRenameLogs` with transcript | Identical |
| Log viewer | Opens Notepad with log file | Identical |
| Confirmation | Type Y to apply | Identical |
| RSAT check | None | Added - shows install instructions if missing |
| Exit behaviour | Script ends | Added - waits for Enter before closing window |
| Module import | Implicit | Added - explicit `Import-Module ActiveDirectory` |

---

## References

- PS2EXE GitHub: https://github.com/MScholtes/PS2EXE
- PS2EXE PowerShell Gallery: https://www.powershellgallery.com/packages/ps2exe
- RSAT Installation: https://learn.microsoft.com/en-us/troubleshoot/windows-server/system-management-components/remote-server-administration-tools
