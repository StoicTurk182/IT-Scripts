# Backup_Bookmarks.ps1 - PowerShell wrapper for the batch script
$batUrl = "https://raw.githubusercontent.com/StoicTurk182/IT-Scripts/main/Utils/Bookmark_mgmt/Bookmark_Organiser_Revised/Backup_Bookmarks.bat"
$tempBat = "$env:TEMP\Backup_Bookmarks.bat"
Invoke-RestMethod -Uri $batUrl -OutFile $tempBat
& cmd.exe /c $tempBat
Remove-Item $tempBat -ErrorAction SilentlyContinue