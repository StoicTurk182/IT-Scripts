# Rename-ADUserSmart_v3 - Cmdlet Conversion and Installation Guide

Converting the AD User Rename script to a portable module that can be installed across servers.

---

## Part 1: Package Contents

The ZIP contains:

```
ADUserTools-v3.0.0.zip
├── ADUserTools/                      <-- The module (this whole folder gets installed)
│   ├── ADUserTools.psd1
│   ├── ADUserTools.psm1
│   └── Functions/
│       └── Rename-ADUserSmart.ps1
├── Install-ADUserTools.ps1           <-- Run this to install
└── Uninstall-ADUserTools.ps1         <-- Run this to remove
```

The install script expects the `ADUserTools` subfolder to sit next to it. If the module files are loose (no subfolder), the install will fail.

---

## Part 2: Install the Module

### Step 2.1: Extract the ZIP

Right-click the ZIP and select "Extract All", or use PowerShell:

```powershell
Expand-Archive -Path "C:\Users\$env:USERNAME\Downloads\ADUserTools-v3.0.0.zip" -DestinationPath "C:\Temp\ADUserTools" -Force
```

### Step 2.2: Verify Folder Structure

```powershell
Set-Location "C:\Temp\ADUserTools"
Get-ChildItem -Recurse | Select-Object FullName
```

You must see this structure:

```
C:\Temp\ADUserTools\Install-ADUserTools.ps1
C:\Temp\ADUserTools\Uninstall-ADUserTools.ps1
C:\Temp\ADUserTools\ADUserTools\
C:\Temp\ADUserTools\ADUserTools\ADUserTools.psd1
C:\Temp\ADUserTools\ADUserTools\ADUserTools.psm1
C:\Temp\ADUserTools\ADUserTools\Functions\
C:\Temp\ADUserTools\ADUserTools\Functions\Rename-ADUserSmart.ps1
```

**If the structure is flat** (no `ADUserTools` subfolder, module files sitting next to the install script), fix it:

```powershell
Set-Location "C:\Temp\ADUserTools"
New-Item -Path ".\ADUserTools" -ItemType Directory -Force
Move-Item -Path ".\ADUserTools.psd1" -Destination ".\ADUserTools\" -Force
Move-Item -Path ".\ADUserTools.psm1" -Destination ".\ADUserTools\" -Force
Move-Item -Path ".\Functions" -Destination ".\ADUserTools\" -Force
```

### Step 2.3: Run the Install Script

**Current user only:**

```powershell
Set-Location "C:\Temp\ADUserTools"
.\Install-ADUserTools.ps1
```

**All users (requires admin PowerShell):**

```powershell
Set-Location "C:\Temp\ADUserTools"
.\Install-ADUserTools.ps1 -Scope AllUsers
```

**Overwrite existing installation:**

```powershell
.\Install-ADUserTools.ps1 -Scope AllUsers -Force
```

### Step 2.4: Verify Installation

```powershell
Get-Module -ListAvailable -Name ADUserTools
```

Expected output:

```
    Directory: C:\Program Files\WindowsPowerShell\Modules

ModuleType Version    Name            ExportedCommands
---------- -------    ----            ----------------
Script     3.0.0      ADUserTools     {Rename-ADUserSmart}
```

If nothing appears, see Troubleshooting at the end of this guide.

### Step 2.5: Import and Use

Once installed to a module path, import by name:

```powershell
Import-Module ADUserTools
Rename-ADUserSmart
```

---

## Part 3: Using the Cmdlet

### Interactive Mode (No Parameters)

```powershell
Import-Module ADUserTools
Rename-ADUserSmart
```

Prompts for all values. Identical behaviour to the original script.

### With Parameters

```powershell
Rename-ADUserSmart -Identity "j.doe" -NewPrefix "john.smith" -FirstName "John" -LastName "Smith"
```

### View Help

```powershell
Get-Help Rename-ADUserSmart -Full
Get-Help Rename-ADUserSmart -Examples
```

---

## Part 4: Deploy to Other Servers

### Option A: Network Share

Copy the extracted package to a share accessible from target servers:

```powershell
$NetworkShare = "\\fileserver\IT-Tools$\PowerShell-Modules\ADUserTools"

if (-not (Test-Path $NetworkShare)) {
    New-Item -Path $NetworkShare -ItemType Directory -Force
}

Copy-Item -Path "C:\Temp\ADUserTools\*" -Destination $NetworkShare -Recurse -Force
```

**Install on a remote server (single):**

```powershell
Invoke-Command -ComputerName DC01 -ScriptBlock {
    Set-Location "\\fileserver\IT-Tools$\PowerShell-Modules\ADUserTools"
    .\Install-ADUserTools.ps1 -Scope AllUsers -Force
}
```

**Install on multiple servers:**

```powershell
$Servers = @("DC01", "DC02", "MGMT01")
$Source = "\\fileserver\IT-Tools$\PowerShell-Modules\ADUserTools"

foreach ($Server in $Servers) {
    Write-Host "Installing on $Server..." -ForegroundColor Cyan
    
    Invoke-Command -ComputerName $Server -ScriptBlock {
        param($S)
        Set-Location $S
        & "$S\Install-ADUserTools.ps1" -Scope AllUsers -Force
    } -ArgumentList $Source
}
```

**Verify all servers:**

```powershell
Invoke-Command -ComputerName $Servers -ScriptBlock {
    $Mod = Get-Module -ListAvailable -Name ADUserTools
    [PSCustomObject]@{
        Server    = $env:COMPUTERNAME
        Installed = [bool]$Mod
        Version   = if ($Mod) { $Mod.Version } else { "N/A" }
    }
} | Format-Table -AutoSize
```

### Option B: ZIP Copy

For isolated servers without share access:

```powershell
# Copy ZIP to target server
Copy-Item "C:\Temp\ADUserTools-v3.0.0.zip" -Destination "\\TARGETSERVER\C$\Temp\"
```

Then on the target server:

```powershell
Expand-Archive -Path "C:\Temp\ADUserTools-v3.0.0.zip" -DestinationPath "C:\Temp\ADUserTools" -Force
Set-Location "C:\Temp\ADUserTools"
.\Install-ADUserTools.ps1 -Scope AllUsers -Force
```

---

## Part 5: Uninstall

```powershell
# From the package folder
.\Uninstall-ADUserTools.ps1 -Scope Both

# Or manually
Remove-Item "$env:ProgramFiles\WindowsPowerShell\Modules\ADUserTools" -Recurse -Force
```

---

## Part 6: Update the Module

When deploying a new version:

1. Update the version in the manifest (`.psd1`)
2. Rebuild the ZIP
3. Run the install script with `-Force` on target servers

The `-Force` parameter overwrites the existing version.

---

## Troubleshooting

### Import-Module ADUserTools Does Nothing / Not Found

This means the module is not in a path PowerShell searches. Check where PowerShell looks:

```powershell
$env:PSModulePath -split ';'
```

Then check if the module folder exists in any of those paths:

```powershell
$env:PSModulePath -split ';' | ForEach-Object {
    $TestPath = Join-Path $_ "ADUserTools"
    [PSCustomObject]@{
        Path   = $TestPath
        Exists = Test-Path $TestPath
    }
} | Format-Table -AutoSize
```

If none show `True`, install with `-Scope AllUsers` from an admin PowerShell, which targets `C:\Program Files\WindowsPowerShell\Modules` (always in PSModulePath):

```powershell
.\Install-ADUserTools.ps1 -Scope AllUsers -Force
```

**If you need to import without installing** (testing from the extracted folder):

```powershell
Import-Module "C:\Temp\ADUserTools\ADUserTools\ADUserTools.psd1"
```

This works because you are giving PowerShell the full path to the manifest. `Import-Module ADUserTools` by name only works when the module is in a PSModulePath directory.

### Install Script Says "Module Source Not Found"

The `ADUserTools` subfolder is missing. The install script looks for a folder called `ADUserTools` next to itself:

```
WRONG (flat):                         CORRECT (subfolder):
C:\Temp\ADUserTools\                  C:\Temp\ADUserTools\
├── ADUserTools.psd1                  ├── ADUserTools\
├── ADUserTools.psm1                  │   ├── ADUserTools.psd1
├── Functions\                        │   ├── ADUserTools.psm1
├── Install-ADUserTools.ps1           │   └── Functions\
└── Uninstall-ADUserTools.ps1         │       └── Rename-ADUserSmart.ps1
                                      ├── Install-ADUserTools.ps1
                                      └── Uninstall-ADUserTools.ps1
```

Fix it:

```powershell
Set-Location "C:\Temp\ADUserTools"
New-Item -Path ".\ADUserTools" -ItemType Directory -Force
Move-Item -Path ".\ADUserTools.psd1" -Destination ".\ADUserTools\" -Force
Move-Item -Path ".\ADUserTools.psm1" -Destination ".\ADUserTools\" -Force
Move-Item -Path ".\Functions" -Destination ".\ADUserTools\" -Force
```

### ActiveDirectory Module Not Found

The target machine needs RSAT installed:

```powershell
# Check
Get-Module -ListAvailable -Name ActiveDirectory

# Install (Windows 10/11, requires admin)
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0

# Install (Server, requires admin)
Install-WindowsFeature -Name RSAT-AD-PowerShell
```

### Module Installed but Old Version Loads

Remove all copies and reinstall:

```powershell
Get-Module ADUserTools -ListAvailable | Select-Object Name, Version, ModuleBase

# Remove all found locations
.\Uninstall-ADUserTools.ps1 -Scope Both

# Reinstall
.\Install-ADUserTools.ps1 -Scope AllUsers -Force

# Reimport in current session
Import-Module ADUserTools -Force
```

---

## Changes from Original Script

| Item | Original Script | Module Version |
|------|----------------|----------------|
| Parameters | Identity, NewPrefix, FirstName, LastName (all optional) | Identical |
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

No logic changes. The script is wrapped in a function and packaged as a module.

---

## References

- PowerShell Modules: https://learn.microsoft.com/en-us/powershell/scripting/developer/module/how-to-write-a-powershell-script-module
- Module Manifests: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_module_manifests
- PSModulePath: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_psmodulepath
- RSAT Installation: https://learn.microsoft.com/en-us/troubleshoot/windows-server/system-management-components/remote-server-administration-tools
