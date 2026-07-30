@echo off
setlocal
if not "%~1"=="" set "GODOT_EXE=%~1"
if not defined GODOT_EXE set "GODOT_EXE=godot"
if exist "%GODOT_EXE%" goto launch
where "%GODOT_EXE%" >nul 2>nul
if errorlevel 1 (
  echo Godot 4.6 was not found.
  echo Add Godot to PATH, set GODOT_EXE, or pass its path as the first argument.
  pause
  exit /b 1
)

:launch
cd /d "%~dp0"
echo [%date% %time%] Starting Open Desktop Pet...>>"godot-launch.log"
start "" "%GODOT_EXE%" --path "%CD%"
endlocal
