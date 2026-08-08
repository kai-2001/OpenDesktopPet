@echo off
setlocal
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_claude_code_integration.ps1" %*
if errorlevel 1 (
  echo Claude Code notification installation failed.
  exit /b 1
)
echo Claude Code notification integration is ready.
pause
