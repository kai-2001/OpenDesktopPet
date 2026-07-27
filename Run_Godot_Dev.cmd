@echo off
setlocal
set "GODOT_EXE=C:\Apache24\tools\godot-4.6.3\Godot_v4.6.3-stable_win64.exe"
if not exist "%GODOT_EXE%" (
  echo Godot 4.6.3 portable editor was not found.
  echo Open this project with Godot 4.6 or update GODOT_EXE in this file.
  pause
  exit /b 1
)
cd /d "%~dp0"
echo [%date% %time%] Starting Open Desktop Pet...>>"godot-launch.log"
start "" wscript.exe "%~dp0DesktopPet.vbs"
endlocal
