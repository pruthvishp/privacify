@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%install.ps1" -StartAtLogin

echo.
if errorlevel 2 (
  echo Privacify installation was cancelled. No changes were made.
) else if errorlevel 1 (
  echo Privacify install failed. Review the message above.
) else (
  echo Privacify install completed.
)
pause
