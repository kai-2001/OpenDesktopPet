@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_codex_integration.ps1" %*
if errorlevel 1 (
  echo.
  echo Codex integration installation failed.
  pause
  exit /b 1
)
echo.
echo Codex integration installed. Restart VS Code or Codex.
pause
