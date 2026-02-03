# AutomatedLab - Basic Lab Definition

Lab deployment script for a domain environment with one Domain Controller, two member servers, and one Windows 10 client.

## Lab Overview

| VM Name | Operating System | Role |
|---------|------------------|------|
| DC01 | Windows Server 2022 Standard | Root Domain Controller |
| Srv01 | Windows Server 2022 Standard | Member Server |
| Srv02 | Windows Server 2022 Standard | Member Server |
| Client1 | Windows 10 Pro | Domain-joined Client |

**Network:** 192.168.10.0/24 with NAT (internet access enabled)

## Prerequisites

### Required ISOs

Place the following ISOs in `C:\LabSources\ISOs`:

- Windows Server 2022 (e.g., `en_windows_server_2022_x64_dvd_*.iso`)
- Windows 10 (e.g., `en_windows_10_consumer_editions_x64_dvd_*.iso`)

### Verify Available Operating Systems

```powershell
Get-LabAvailableOperatingSystem | Format-Table OperatingSystemName, Version
```

### Configure VM Storage Location

```powershell
# Set VM storage path
Set-PSFConfig -Module AutomatedLab -Name VmPath -Value 'A:\Lab.Local' -PassThru | Register-PSFConfig

# Verify setting
Get-PSFConfig -Module AutomatedLab -Name VmPath
```

### Enable Non-English ISO Support (if using en-GB)

```powershell
Set-PSFConfig -Module AutomatedLab -Name DoNotSkipNonNonEnglishIso -Value $true -PassThru | Register-PSFConfig
```

## Lab Definition Script

Save this as `Deploy-BasicLab.ps1`:

```powershell
<#
.SYNOPSIS
    Deploys a basic Active Directory lab environment

.DESCRIPTION
    Creates a lab with:
    - 1x Domain Controller (DC01) - Server 2022
    - 2x Member Servers (Srv01, Srv02) - Server 2022
    - 1x Windows 10 Client (Client1)
    - NAT enabled for internet access

.NOTES
    Author: Andrew Jones
    Date: 2026-02-03
    Requires: AutomatedLab module, Hyper-V
#>

#Requires -Modules AutomatedLab
#Requires -RunAsAdministrator

# ============================================================================
# LAB CONFIGURATION
# ============================================================================

$LabName = 'BasicLab'
$DomainName = 'lab.local'
$AddressSpace = '192.168.10.0/24'
$AdminPassword = 'P@ssw0rd123!'

# Operating System Names (verify with Get-LabAvailableOperatingSystem)
$ServerOS = 'Windows Server 2022 Standard (Desktop Experience)'
$ClientOS = 'Windows 10 Pro'

# ============================================================================
# LAB DEFINITION
# ============================================================================

# Create new lab definition
New-LabDefinition -Name $LabName -DefaultVirtualizationEngine HyperV

# Set domain credentials
Set-LabInstallationCredential -Username Administrator -Password $AdminPassword

# Define network with NAT (enables internet access)
Add-LabVirtualNetworkDefinition -Name $LabName -AddressSpace $AddressSpace
Add-LabNatDefinition -Name "$($LabName)NAT" -VirtualNetwork $LabName

# Define domain
Add-LabDomainDefinition -Name $DomainName -AdminUser Administrator -AdminPassword $AdminPassword

# ============================================================================
# MACHINE DEFINITIONS
# ============================================================================

# DC01 - Domain Controller
Add-LabMachineDefinition -Name DC01 `
    -Memory 2GB `
    -OperatingSystem $ServerOS `
    -Network $LabName `
    -DomainName $DomainName `
    -Roles RootDC `
    -IpAddress '192.168.10.10'

# Srv01 - Member Server
Add-LabMachineDefinition -Name Srv01 `
    -Memory 2GB `
    -OperatingSystem $ServerOS `
    -Network $LabName `
    -DomainName $DomainName `
    -IpAddress '192.168.10.21'

# Srv02 - Member Server
Add-LabMachineDefinition -Name Srv02 `
    -Memory 2GB `
    -OperatingSystem $ServerOS `
    -Network $LabName `
    -DomainName $DomainName `
    -IpAddress '192.168.10.22'

# Client1 - Windows 10 Client
Add-LabMachineDefinition -Name Client1 `
    -Memory 2GB `
    -OperatingSystem $ClientOS `
    -Network $LabName `
    -DomainName $DomainName `
    -IpAddress '192.168.10.100'

# ============================================================================
# DEPLOY LAB
# ============================================================================

Install-Lab

# Display summary
Show-LabDeploymentSummary
```

## Deployment

### Step 1: Open PowerShell as Administrator

```powershell
Start-Process powershell -Verb RunAs
```

### Step 2: Run the Script

```powershell
& 'C:\Path\To\Deploy-BasicLab.ps1'
```

Or paste the script content directly into an elevated PowerShell session.

## Post-Deployment

### Enable Guest Service Interface

Guest Service Interface is disabled by default. Enable it to allow file copying between host and guest:

```powershell
Get-LabVM | ForEach-Object {
    Enable-VMIntegrationService -VMName $_.Name -Name 'Guest Service Interface'
}
```

### Connect to VMs

```powershell
# Connect to specific VM
Connect-LabVM -ComputerName DC01

# Connect to all VMs
Connect-LabVM -ComputerName (Get-LabVM)
```

### Get VM Status

```powershell
Get-LabVM | Select-Object Name, OperatingSystem, IpAddress, DomainName
```

### Enter Remote Session

```powershell
Enter-LabPSSession -ComputerName DC01
```

### Run Commands on Lab VMs

```powershell
# Single VM
Invoke-LabCommand -ComputerName DC01 -ScriptBlock { Get-ADUser -Filter * }

# All VMs
Invoke-LabCommand -ComputerName (Get-LabVM) -ScriptBlock { hostname }
```

### Create Checkpoint

```powershell
Checkpoint-LabVM -All -SnapshotName 'Initial-Deploy'
```

### Restore Checkpoint

```powershell
Restore-LabVMSnapshot -All -SnapshotName 'Initial-Deploy'
```

## Lab Management

### Stop Lab

```powershell
Stop-LabVM -All
```

### Start Lab

```powershell
Start-LabVM -All
```

### Remove Lab

```powershell
Remove-Lab -Name BasicLab -Confirm:$false
```

### Import Existing Lab

```powershell
Import-Lab -Name BasicLab -NoValidation
```

## Network Configuration

### Network Types Overview

| Type | Internet Access | Host Access | Isolation | Use Case |
|------|-----------------|-------------|-----------|----------|
| Internal | No | No | Full | Security testing, isolated labs |
| Internal + NAT | Yes (outbound) | Yes | Partial | General labs with internet |
| External (Bridged) | Yes (full) | Yes | None | Production-like, DHCP from physical network |
| Private | No | No | Full | Multi-host labs |

### Option 1: Internal + NAT (Default in this guide)

Provides internet access via NAT while keeping the lab isolated. VMs can reach out but are not directly accessible from external networks.

```powershell
# In lab definition
Add-LabVirtualNetworkDefinition -Name $LabName -AddressSpace $AddressSpace
Add-LabNatDefinition -Name "$($LabName)NAT" -VirtualNetwork $LabName
```

### Option 2: Internal Only (Fully Isolated)

No internet access, fully isolated environment. Use for security testing or air-gapped scenarios.

```powershell
# In lab definition
Add-LabVirtualNetworkDefinition -Name $LabName -AddressSpace $AddressSpace
```

### Option 3: External (Bridged to Physical Network)

VMs connect directly to your physical network. They can get DHCP from your router or use static IPs in your network range.

```powershell
# Get your physical adapter name first
Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object Name, InterfaceDescription

# In lab definition - bridged to physical NIC
Add-LabVirtualNetworkDefinition -Name $LabName -AddressSpace '192.168.1.0/24' -HyperVProperties @{
    SwitchType = 'External'
    AdapterName = 'Ethernet'  # Replace with your physical adapter name
}
```

### Option 4: Multiple Networks

Create labs with separate network segments (e.g., DMZ, internal, management).

```powershell
# Define multiple networks
Add-LabVirtualNetworkDefinition -Name 'Internal' -AddressSpace '192.168.10.0/24'
Add-LabVirtualNetworkDefinition -Name 'DMZ' -AddressSpace '192.168.20.0/24'
Add-LabVirtualNetworkDefinition -Name 'Management' -AddressSpace '10.0.0.0/24'

# Add NAT to specific network
Add-LabNatDefinition -Name 'DMZ-NAT' -VirtualNetwork 'DMZ'

# Assign VMs to different networks
Add-LabMachineDefinition -Name DC01 -Network 'Internal' -IpAddress '192.168.10.10' ...
Add-LabMachineDefinition -Name WebServer -Network 'DMZ' -IpAddress '192.168.20.10' ...
Add-LabMachineDefinition -Name AdminBox -Network 'Management' -IpAddress '10.0.0.10' ...
```

### Option 5: VM with Multiple NICs

Attach a VM to multiple networks (e.g., router, firewall, or multi-homed server).

```powershell
# Define networks
Add-LabVirtualNetworkDefinition -Name 'Internal' -AddressSpace '192.168.10.0/24'
Add-LabVirtualNetworkDefinition -Name 'DMZ' -AddressSpace '192.168.20.0/24'

# VM with two NICs
Add-LabMachineDefinition -Name Router01 `
    -Memory 2GB `
    -OperatingSystem 'Windows Server 2022 Standard (Desktop Experience)' `
    -NetworkAdapter @(
        New-LabNetworkAdapterDefinition -VirtualSwitch 'Internal' -Ipv4Address '192.168.10.1'
        New-LabNetworkAdapterDefinition -VirtualSwitch 'DMZ' -Ipv4Address '192.168.20.1'
    ) `
    -Roles Routing
```

### Option 6: Router VM with Internet Access

Create a router VM that provides internet access to internal networks.

```powershell
# External network (internet facing)
Add-LabVirtualNetworkDefinition -Name 'External' -HyperVProperties @{
    SwitchType = 'External'
    AdapterName = 'Ethernet'
}

# Internal network
Add-LabVirtualNetworkDefinition -Name 'Internal' -AddressSpace '192.168.10.0/24'

# Router VM bridges both networks
Add-LabMachineDefinition -Name Router01 `
    -Memory 2GB `
    -OperatingSystem 'Windows Server 2022 Standard (Desktop Experience)' `
    -NetworkAdapter @(
        New-LabNetworkAdapterDefinition -VirtualSwitch 'External' -UseDhcp
        New-LabNetworkAdapterDefinition -VirtualSwitch 'Internal' -Ipv4Address '192.168.10.1'
    ) `
    -Roles Routing

# Internal VMs use router as gateway
Add-LabMachineDefinition -Name DC01 `
    -Network 'Internal' `
    -IpAddress '192.168.10.10' `
    -Gateway '192.168.10.1' `
    -DnsServer1 '192.168.10.10' ...
```

### Option 7: DHCP Instead of Static IPs

Let VMs get addresses from DHCP (useful with external switches or DHCP server role).

```powershell
# VM with DHCP
Add-LabMachineDefinition -Name Client1 `
    -Memory 2GB `
    -OperatingSystem 'Windows 10 Pro' `
    -Network $LabName
    # No -IpAddress parameter = DHCP
```

### Option 8: Custom DNS Configuration

Specify custom DNS servers per VM.

```powershell
Add-LabMachineDefinition -Name Srv01 `
    -Memory 2GB `
    -OperatingSystem 'Windows Server 2022 Standard (Desktop Experience)' `
    -Network $LabName `
    -IpAddress '192.168.10.21' `
    -DnsServer1 '192.168.10.10' `
    -DnsServer2 '8.8.8.8'
```

### NAT Management Commands

```powershell
# List existing NAT configurations
Get-NetNat

# Create NAT for existing lab
New-NetNat -Name 'BasicLabNAT' -InternalIPInterfaceAddressPrefix '192.168.10.0/24'

# Remove NAT
Remove-NetNat -Name 'BasicLabNAT' -Confirm:$false

# View NAT statistics
Get-NetNatStaticMapping
Get-NetNatSession
```

### Add NAT to Existing Lab

If you deployed without NAT and want to add internet access:

```powershell
# Import lab
Import-Lab -Name BasicLab

# Add NAT to existing network
New-NetNat -Name 'BasicLabNAT' -InternalIPInterfaceAddressPrefix '192.168.10.0/24'
```

### Remove NAT

```powershell
# List existing NAT
Get-NetNat

# Remove NAT
Remove-NetNat -Name 'BasicLabNAT' -Confirm:$false
```

### Verify Network Connectivity

```powershell
# Test from lab VM
Invoke-LabCommand -ComputerName DC01 -ScriptBlock {
    Test-NetConnection -ComputerName 8.8.8.8 -Port 443
} -PassThru
```

### Post-Deployment Network Fix

If NAT is configured but VMs cannot reach the internet, the default gateway and DNS forwarders may not be set. Run these commands to fix:

```powershell
# Import lab first
Import-Lab -Name BasicLab

# Check current IP configuration
Invoke-LabCommand -ComputerName DC01 -ScriptBlock {
    Get-NetIPConfiguration
} -PassThru

# Set default gateway on all VMs
Invoke-LabCommand -ComputerName DC01, Srv01, Srv02, Client1 -ScriptBlock {
    $adapter = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
    Remove-NetRoute -DestinationPrefix '0.0.0.0/0' -Confirm:$false -ErrorAction SilentlyContinue
    New-NetRoute -DestinationPrefix '0.0.0.0/0' -InterfaceIndex $adapter.ifIndex -NextHop '192.168.10.1'
}

# Add DNS forwarders on DC (enables internet name resolution)
Invoke-LabCommand -ComputerName DC01 -ScriptBlock {
    Add-DnsServerForwarder -IPAddress 8.8.8.8, 1.1.1.1 -ErrorAction SilentlyContinue
}

# Verify connectivity
Invoke-LabCommand -ComputerName DC01 -ScriptBlock {
    Test-NetConnection -ComputerName 8.8.8.8 -Port 443
} -PassThru
```

Expected output when working:

```
ComputerName     : 8.8.8.8
RemoteAddress    : 8.8.8.8
RemotePort       : 443
TcpTestSucceeded : True
```

### Troubleshooting Network Issues

```powershell
# Check VM network adapters
Invoke-LabCommand -ComputerName DC01 -ScriptBlock {
    Get-NetAdapter | Format-Table Name, Status, MacAddress
} -PassThru

# Check IP configuration
Invoke-LabCommand -ComputerName DC01 -ScriptBlock {
    Get-NetIPAddress -AddressFamily IPv4 | Format-Table InterfaceAlias, IPAddress, PrefixLength
} -PassThru

# Check routing table
Invoke-LabCommand -ComputerName DC01 -ScriptBlock {
    Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.NextHop -ne '0.0.0.0' } | Format-Table DestinationPrefix, NextHop, InterfaceAlias
} -PassThru

# Check DNS configuration
Invoke-LabCommand -ComputerName DC01 -ScriptBlock {
    Get-DnsClientServerAddress -AddressFamily IPv4 | Format-Table InterfaceAlias, ServerAddresses
} -PassThru

# Test DNS resolution
Invoke-LabCommand -ComputerName DC01 -ScriptBlock {
    Resolve-DnsName google.com
} -PassThru

# Check Hyper-V switch on host
Get-VMSwitch | Format-Table Name, SwitchType, NetAdapterInterfaceDescription

# Check NAT on host
Get-NetNat | Format-Table Name, InternalIPInterfaceAddressPrefix, Active
```

## IP Address Summary

| VM Name | IP Address | Role |
|---------|------------|------|
| DC01 | 192.168.10.10 | Domain Controller / DNS |
| Srv01 | 192.168.10.21 | Member Server |
| Srv02 | 192.168.10.22 | Member Server |
| Client1 | 192.168.10.100 | Windows Client |
| Gateway | 192.168.10.1 | NAT Gateway (Internet Access) |

## Credentials

| Account | Password | Use |
|---------|----------|-----|
| Administrator | P@ssw0rd123! | Local Admin |
| LAB\Administrator | P@ssw0rd123! | Domain Admin |

## Troubleshooting

### Check Lab Status

```powershell
Get-Lab | Format-List
Get-LabVM | Format-Table Name, State, OperatingSystem
```

### View Installation Logs

```powershell
Get-LabInstallationLog -Path 'C:\ProgramData\AutomatedLab\Logs'
```

### Operating System Not Found

```powershell
# List available OS names
Get-LabAvailableOperatingSystem | Select-Object OperatingSystemName

# Update script variables to match exact names
```

### ISO Language Issues

```powershell
# Enable non-English ISO support
Set-PSFConfig -Module AutomatedLab -Name DoNotSkipNonNonEnglishIso -Value $true -PassThru | Register-PSFConfig

# Re-scan ISOs
Get-LabAvailableOperatingSystem -Force
```

## Hyper-V VM Tools

### Integration Services

Check Integration Services status on lab VMs:

```powershell
# Check all VMs
Get-LabVM | ForEach-Object {
    Get-VMIntegrationService -VMName $_.Name | Select-Object VMName, Name, Enabled
}

# Check specific VM
Get-VMIntegrationService -VMName DC01
```

Enable all Integration Services:

```powershell
Get-LabVM | ForEach-Object {
    Enable-VMIntegrationService -VMName $_.Name -Name 'Guest Service Interface'
    Enable-VMIntegrationService -VMName $_.Name -Name 'Heartbeat'
    Enable-VMIntegrationService -VMName $_.Name -Name 'Key-Value Pair Exchange'
    Enable-VMIntegrationService -VMName $_.Name -Name 'Shutdown'
    Enable-VMIntegrationService -VMName $_.Name -Name 'Time Synchronization'
    Enable-VMIntegrationService -VMName $_.Name -Name 'VSS'
}
```

### Enhanced Session Mode

Enable Enhanced Session Mode on the Hyper-V host:

```powershell
# Check current setting
Get-VMHost | Select-Object EnableEnhancedSessionMode

# Enable Enhanced Session Mode
Set-VMHost -EnableEnhancedSessionMode $true
```

Enable on specific VM:

```powershell
Set-VM -VMName DC01 -EnhancedSessionTransportType HvSocket
```

### VMConnect Settings (AutomatedLab)

Configure default VMConnect behaviour:

```powershell
# Set default resolution
Set-PSFConfig -Module AutomatedLab -Name VMConnectDesktopSize -Value @(1920, 1080) -PassThru | Register-PSFConfig

# Enable full screen mode
Set-PSFConfig -Module AutomatedLab -Name VMConnectFullScreen -Value $true -PassThru | Register-PSFConfig

# Use all monitors
Set-PSFConfig -Module AutomatedLab -Name VMConnectUseAllMonitors -Value $true -PassThru | Register-PSFConfig

# Redirect local drives (* for all, or semicolon-separated e.g., 'C;D')
Set-PSFConfig -Module AutomatedLab -Name VMConnectRedirectedDrives -Value '*' -PassThru | Register-PSFConfig

# Enable config file writing
Set-PSFConfig -Module AutomatedLab -Name VMConnectWriteConfigFile -Value $true -PassThru | Register-PSFConfig
```

### Copy Files to VM

Using Hyper-V (requires Guest Service Interface enabled):

```powershell
# Copy file to VM
Copy-VMFile -VMName DC01 -SourcePath 'C:\Scripts\Install.ps1' -DestinationPath 'C:\Temp\Install.ps1' -FileSource Host -CreateFullPath
```

Using AutomatedLab:

```powershell
# Copy to single VM
Copy-LabFileItem -Path 'C:\Scripts\Install.ps1' -ComputerName DC01 -DestinationFolderPath 'C:\Temp'

# Copy to all VMs
Copy-LabFileItem -Path 'C:\Scripts\Install.ps1' -ComputerName (Get-LabVM) -DestinationFolderPath 'C:\Temp'
```

### VM Checkpoints

Create checkpoint:

```powershell
# Single VM
Checkpoint-VM -VMName DC01 -SnapshotName 'Pre-Config'

# All lab VMs (AutomatedLab)
Checkpoint-LabVM -All -SnapshotName 'Pre-Config'
```

List checkpoints:

```powershell
Get-VMSnapshot -VMName DC01
```

Restore checkpoint:

```powershell
# Single VM
Restore-VMSnapshot -VMName DC01 -Name 'Pre-Config' -Confirm:$false

# All lab VMs (AutomatedLab)
Restore-LabVMSnapshot -All -SnapshotName 'Pre-Config'
```

Remove checkpoint:

```powershell
Remove-VMSnapshot -VMName DC01 -Name 'Pre-Config'
```

### VM Resource Management

Check current resources:

```powershell
Get-LabVM | ForEach-Object {
    Get-VM -Name $_.Name | Select-Object Name, 
        @{N='MemoryGB';E={$_.MemoryAssigned/1GB}},
        @{N='CPUCount';E={$_.ProcessorCount}},
        State
}
```

Modify VM resources (VM must be off):

```powershell
# Stop VM first
Stop-VM -VMName Srv01

# Change memory
Set-VMMemory -VMName Srv01 -StartupBytes 4GB

# Change CPU count
Set-VMProcessor -VMName Srv01 -Count 2

# Start VM
Start-VM -VMName Srv01
```

### Export and Import VMs

Export VM:

```powershell
Export-VM -VMName DC01 -Path 'D:\Exports'
```

Import VM:

```powershell
Import-VM -Path 'D:\Exports\DC01\Virtual Machines\*.vmcx' -Copy -GenerateNewId
```

### Integration Services Reference

| Service | Purpose |
|---------|---------|
| Guest Service Interface | File copy between host and guest |
| Heartbeat | Reports VM health to host |
| Key-Value Pair Exchange | Registry-based data exchange |
| Shutdown | Allows graceful shutdown from host |
| Time Synchronization | Syncs guest time with host |
| VSS | Volume Shadow Copy for backups |

## References

- AutomatedLab Documentation: https://automatedlab.org/en/latest/
- AutomatedLab Wiki - Create New Lab: https://automatedlab.org/en/latest/Wiki/Basic/createnewlab/
- AutomatedLab GitHub: https://github.com/AutomatedLab/AutomatedLab
