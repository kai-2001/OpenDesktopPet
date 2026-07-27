# Portable local build

`Windows Local` is the personal-use build. It embeds the active private pet
pack directly in one executable and does not include the archive, source,
validation, test, documentation, or Git history directories.

## Use it on another computer

1. Copy `OpenDesktopPet-Local.exe` to a Windows 10 or Windows 11 x64 computer.
2. Double-click the executable. Godot, .NET, Python, Apache, and this source
   repository are not required.
3. Use the pet's right-click menu to interact with it or exit.

The build is currently unsigned, so Windows SmartScreen may show a warning.
Only choose **More info > Run anyway** for a file copied from a source you
trust.

Game progress is created separately at:

`%APPDATA%\Godot\app_userdata\Open Desktop Pet\save_v2.json`

Copy that file to the same location on another computer if progress should
move with the executable.

## Distribution note

This local build contains the active private pet artwork and is intended only
for personal use. A public open-source release should use redistributable
artwork and the `Windows Public` preset instead.
