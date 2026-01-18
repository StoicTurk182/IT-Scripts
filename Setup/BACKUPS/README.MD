Backup Folder Creator Script

What does this script do?
This PowerShell script automatically creates a standardized folder structure for backing up user data. It saves time and ensures every backup looks exactly the same.

It creates a main folder named using the format: [ComputerName]_[Label]_[Date] (Example: DESKTOP-123_OldPC_18012026)

Inside that, it automatically creates these subfolders: # note if you need to add different folder just add the folder name to the script as part of the comma separated list Sage, ?????, etc 

Documents
Desktop
Download
Pictures
Music
Browser
Sage

Features
Smart Drive Detection: Accepts input like D, d:, or D:\ without crashing.

Safety Checks: Verifies the drive exists before starting.

Logging: Creates a Backup_Log.txt file inside the new folder that records every folder created and any errors.

How to Run It
Open PowerShell.

Run the script:

PowerShell

.\Create_Backup_Structure.ps1
Enter Drive Letter: Type the letter of the external drive (e.g., D or E).

Enter Label: Give it a name (e.g., Old_Laptop or JohnSmith).

If you leave this blank, it defaults to "Backup".

The Log File
Once the script finishes, check the new folder. You will see Backup_Log.txt. It contains a timestamped record of the operation:

Plaintext

[2026-01-18 10:00:00] --- Backup Structure Initialization Started ---
[2026-01-18 10:00:01] [+] Created: Documents
[2026-01-18 10:00:01] [+] Created: Desktop
...