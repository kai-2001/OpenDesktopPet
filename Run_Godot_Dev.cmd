@echo off
setlocal
if not "%~1"=="" set "GODOT_EXE=%~1"
if not defined GODOT_EXE if exist "%~dp0..\..\tools\godot-4.6.3\Godot_v4.6.3-stable_win64.exe" set "GODOT_EXE=%~dp0..\..\tools\godot-4.6.3\Godot_v4.6.3-stable_win64.exe"
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
echo [%date% %time%] Starting Open Desktop Pet with "%GODOT_EXE%" from "%CD%"...>>"godot-launch.log"
start "" "%GODOT_EXE%" --path "%CD%"
endlocal
