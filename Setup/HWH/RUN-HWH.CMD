@echo off 
SETLOCAL

REM Execute PowerShell script
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0hwh.ps1" -OutputFile "%~dp0computers.csv" -Append

PAUSE

ENDLOCAL

