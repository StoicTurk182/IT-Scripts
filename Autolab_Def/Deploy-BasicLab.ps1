<#
.SYNOPSIS
    Deploys a basic Active Directory lab environment

.DESCRIPTION
    Creates a lab with:
    - 1x Domain Controller (DC01) - Server 2022
    - 2x Member Servers (Srv01, Srv02) - Server 2022
    - 1x Windows 10 Client (Client1)

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

# Define network
Add-LabVirtualNetworkDefinition -Name $LabName -AddressSpace $AddressSpace

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
Show-LabDeploymentSummary -Detailed