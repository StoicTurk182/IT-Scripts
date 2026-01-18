How to use this
Once you have run the code block above (pasted it into PowerShell and hit Enter), the function is loaded into your memory. You can now use it in three different ways:

1. The "Lazy" Way (Prompts you) Type the command and hit enter. It will ask for the names because they are mandatory.

PowerShell

Copy-ADUserGroups
2. The "Standard" Way (Positional) Type the command followed by Source then Target.

PowerShell

Copy-ADUserGroups emma nicole
3. The "Explicit" Way Type the parameter names for clarity.

PowerShell

Copy-ADUserGroups -SourceUser emma -TargetUser nicole
How to make this permanent (So you don't have to paste it every time)
If you close your PowerShell window, this function will disappear. To keep it forever:

Type notepad $PROFILE in your PowerShell window and hit Enter. (If it asks to create a file, say Yes).

Paste the Function Code block from above into that text file.

Save and close Notepad.

Close PowerShell and reopen it.

Now, Copy-ADUserGroups is a permanent command on your computer!



Option 1: Load the Function into Memory (Dot Sourcing)
If you want to load the function so you can type Copy-ADUserGroups whenever you want in that window, you must run the script with a dot and a space at the beginning.

Type this exactly:

PowerShell

. Z:\migrate_user_group_memberships_param.ps1
(Note the period . followed by a space before the file path).

Now, the function is loaded into your current session, and you can type Copy-ADUserGroups.

Option 2: Make the Script Run Automatically
If you just want to double-click or run the script file and have it ask you for names immediately (without you having to type Copy-ADUserGroups afterward), you need to edit your .ps1 file.

Open Z:\migrate_user_group_memberships_param.ps1 in a text editor (like Notepad or ISE).

Go to the very bottom of the file (after the closing } bracket of the function).

Add this single line to the end:

PowerShell

Copy-ADUserGroups
Save the file.

Now, when you run Z:\migrate_user_group_memberships_param.ps1, it will define the function and immediately run it for you.