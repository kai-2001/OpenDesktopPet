@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall_open_desktop_pet.ps1" %*
if errorlevel 1 (
  echo OpenDesktopPet uninstall finished with errors.
  pause
  exit /b 1
)
echo OpenDesktopPet uninstall is complete.
pause
