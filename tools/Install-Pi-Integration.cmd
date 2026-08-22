@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_pi_integration.ps1" %*
if errorlevel 1 (
  echo.
  echo Pi notification integration installation failed.
  pause
  exit /b 1
)
echo.
echo Pi notification integration installed. Restart Pi or run /reload.
pause
