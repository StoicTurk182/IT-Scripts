cd "C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts"
git add -A
git status
git commit -m "Add: Bookmark management toolkit v2.1 - audit, organise, backup, export & new sub menu items"
git push


cd "C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts"
Copy-Item "$env:USERPROFILE\Downloads\Export-BookmarksToHtml.ps1" ".\Utils\Bookmark_mgmt\" -Force
git add Utils/Bookmark_mgmt/Export-BookmarksToHtml.ps1
git commit -m "Update: Export-BookmarksToHtml - profile picker, interactive mode, import instructions"
git push