@echo off
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_antigravity_cli_integration.ps1" %*
if errorlevel 1 (
  echo Antigravity CLI notification installation failed.
  exit /b 1
)
echo Antigravity CLI notification integration is ready.
