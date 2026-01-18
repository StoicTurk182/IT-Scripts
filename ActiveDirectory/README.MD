Markdown# Smart AD User Rename & Email Swap Script

## Overview
This PowerShell script automates the complex process of renaming a user in Active Directory. It handles the "Identity" attributes (Login ID, UPN) and intelligently manages Email Proxy Addresses to ensure mail flow continues for the user.

It is designed to work on **Domain Controllers** or **Admin Workstations** with RSAT installed. **No local Exchange Server is required.**

## Features
* **Dual-Search:** Finds users by **Login ID** (e.g., `jsmith`) OR **Email** (e.g., `jsmith@domain.com`).
* **Complete Identity Update:** Renames:
    * First Name & Last Name
    * Display Name (CN)
    * SamAccountName (Pre-Windows 2000 Login)
    * UserPrincipalName (Office 365 Login)
* **Smart Email Swapping:**
    * **Promotes** the new email to Primary (`SMTP:`).
    * **Demotes** the old email to an Alias (`smtp:`).
    * Preserves mail flow for both addresses.
* **Safety Checks:**
    * Validates input to prevent malformed emails (e.g., `bob@@domain.com`).
    * Requires user confirmation (`Y/N`) before writing to AD.
    * Uses `Try/Catch` blocks to prevent partial "Frankenstein" updates.

## Prerequisites
1.  **Permissions:** You must be a Domain Admin or have "Account Operator" permissions in Active Directory.
2.  **PowerShell Module:** The `ActiveDirectory` module must be loaded.
    * *If running on a DC, this is already installed.*
    * *If running on Windows 10/11, ensure RSAT is installed.*

## How to Use

### 1. Run the Script
Open PowerShell as Administrator and run the script file:

```powershell
.\UPN_NameChange.ps1

(If the script is wrapped in a function, you may need to dot-source it first: . .\UPN_NameChange.ps1)

2. Follow the Prompts
Search: Enter the username (e.g., testuser) or current email.

Confirm: Verify the script found the correct person.

New Details:

Enter the New Username (Just the name part, e.g., jane.doe).

Enter First Name and Last Name.

Verify: Review the "Proposed Changes" summary.

Execute: Type Y to apply changes.

What Changed? (Example)AttributeBeforeAfterFirst NameBobJaneLast NameJonesDoeDisplay NameBob JonesJane DoeLogin IDbjonesjane.doeUPN (Login)bjones@domain.comjane.doe@domain.comEmail (Primary)SMTP:bjones@domain.comSMTP:jane.doe@domain.comEmail (Alias)(None)smtp:bjones@domain.com

Post-Script Action
If your environment syncs to Microsoft 365 (Azure AD), you must force a sync for the changes to appear in the cloud immediately:

```PowerShell
Start-ADSyncSyncCycle -PolicyType Delta

```

Troubleshooting

"User not found": Ensure you are typing the Login ID exactly as it appears in AD, or the full email address.

"Invalid type 'System.Management.Automation.PSObject'": This error occurs if the proxyAddresses are not cast as strings. Ensure you are using the latest version of this script which includes [string[]] casting.

Permission Denied: Ensure you have rights to rename objects in the specific OU where the user lives. Some "Protected Users" (like Domain Admins) cannot be modified by scripts unless specific delegation is enabled.

