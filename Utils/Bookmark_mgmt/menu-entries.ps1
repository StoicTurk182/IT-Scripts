# ============================================================================
# Add these entries to $Script:MenuStructure in Menu.ps1
# Place under an existing category or create a new "Bookmark Management" one
# ============================================================================

# Option A - Add to an existing "Utilities" category:
"Utilities" = @(
    @{ Name = "Create Backup Folders";     Path = "Utils/BACKUPS/Create_Folders_v2.ps1";                             Description = "Create backup folder structure for migrations" }
    @{ Name = "Bookmark Audit";            Path = "Utils/Bookmark_mgmt/Check-Bookmarks-Parallel.ps1";               Description = "Check all bookmarks for dead links in parallel (requires PS7)" }
    @{ Name = "Bookmark Organiser";        Path = "Utils/Bookmark_mgmt/Organise-Bookmarks.ps1";                     Description = "Clean and sort Edge bookmarks into folders" }
    @{ Name = "Bookmark HTML Export";      Path = "Utils/Bookmark_mgmt/Export-BookmarksToHtml.ps1";                 Description = "Export organised bookmarks to HTML for browser import" }
)

# Option B - New dedicated category:
"Bookmark Management" = @(
    @{ Name = "1. Audit - Check Dead Links";  Path = "Utils/Bookmark_mgmt/Check-Bookmarks-Parallel.ps1";  Description = "Parallel HTTP check of all bookmarks. Produces CSV report. Requires PS7." }
    @{ Name = "2. Organise - Clean and Sort"; Path = "Utils/Bookmark_mgmt/Organise-Bookmarks.ps1";        Description = "Remove dead links, deduplicate, sort into folders. Optionally ingests audit CSV." }
    @{ Name = "3. Export to HTML";            Path = "Utils/Bookmark_mgmt/Export-BookmarksToHtml.ps1";    Description = "Export cleaned bookmarks to Netscape HTML for browser import." }
)

# ============================================================================
# IMPORTANT - Script file locations
# The Path value is relative to your GitHub repo root.
# Adjust the path to match where you put the scripts in the repo.
# e.g. if your repo root is IT-Scripts/ and scripts are in:
#   IT-Scripts/Utils/Bookmark_mgmt/Check-Bookmarks-Parallel.ps1
# then Path = "Utils/Bookmark_mgmt/Check-Bookmarks-Parallel.ps1"
# ============================================================================

# ============================================================================
# HOW THE MENU LAUNCHES THESE SCRIPTS
# The menu does: iex (irm "https://raw.githubusercontent.com/.../Path")
# Both scripts now detect they are running under iex and prompt interactively.
#
# Audit flow via menu:
#   User selects "Bookmark Audit"
#   Script prompts: bookmark file path, throttle limit, timeout
#   Runs checks, saves CSV to Desktop
#   User opens CSV, fills FolderOverride / DeleteFlag columns
#
# Organiser flow via menu:
#   User selects "Bookmark Organiser"
#   Script prompts: bookmark file path, audit CSV path (optional), WhatIf, remove outcomes
#   Runs cleanup, writes Bookmarks file, saves report CSV to Desktop
# ============================================================================
