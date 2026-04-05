@"
@echo off
REM Browser Bookmark Backup Script
set BACKUP_ROOT=%1
if "%BACKUP_ROOT%"=="" set BACKUP_ROOT=%USERPROFILE%\Desktop\BrowserBackup
set TIMESTAMP=%DATE:~-4%%DATE:~4,2%%DATE:~7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%
set TIMESTAMP=%TIMESTAMP: =0%
set BACKUP_DIR=%BACKUP_ROOT%\Backup_%TIMESTAMP%
mkdir "%BACKUP_DIR%\Chrome" 2>nul
mkdir "%BACKUP_DIR%\Edge" 2>nul
mkdir "%BACKUP_DIR%\Firefox" 2>nul
if exist "%LOCALAPPDATA%\Google\Chrome\User Data\Default\Bookmarks" (
    copy "%LOCALAPPDATA%\Google\Chrome\User Data\Default\Bookmarks" "%BACKUP_DIR%\Chrome\"
    echo Chrome bookmarks backed up
)
if exist "%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Bookmarks" (
    copy "%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Bookmarks" "%BACKUP_DIR%\Edge\"
    echo Edge bookmarks backed up
)
for /d %%p in ("%APPDATA%\Mozilla\Firefox\Profiles\*") do (
    if exist "%%p\bookmarkbackups" (
        xcopy "%%p\bookmarkbackups\*" "%BACKUP_DIR%\Firefox\%%~np\bookmarkbackups\" /E /I /Q
        echo Firefox bookmarks backed up from %%~np
    )
)
echo.
echo Backup complete: %BACKUP_DIR%
pause
"@ | Out-File -FilePath "$env:USERPROFILE\Desktop\BrowserBackup.bat" -Encoding ASCII

& "$env:USERPROFILE\Desktop\BrowserBackup.bat"