@echo off
setlocal
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_gemini_cli_integration.ps1" %*
if errorlevel 1 (
  echo Gemini CLI notification installation failed.
  exit /b 1
)
echo Gemini CLI notification integration is ready.
pause
