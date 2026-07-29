# Custom Windows export template

Windows release exports use:

`build/custom-templates/windows_release_x86_64.exe`

The binary is intentionally ignored by Git. It is Godot 4.6.3-stable's
`template_release` with `engine-patches/godot-4.6.3-no-focus-overlay.patch`
applied. The patch prevents a `no_focus` main window from receiving
`WS_EX_APPWINDOW` when its native window is created, keeping the desktop pet
out of the taskbar without a runtime helper or startup flash.

Build the template from the Godot 4.6.3-stable source tree:

```powershell
git apply C:\Apache24\htdocs\SealBall_DesktopPet\engine-patches\godot-4.6.3-no-focus-overlay.patch
python -m SCons platform=windows target=template_release arch=x86_64 `
  use_mingw=yes use_llvm=yes d3d12=no production=yes lto=none -j4
```

Copy the resulting non-console template:

```powershell
Copy-Item bin\godot.windows.template_release.x86_64.llvm.exe `
  C:\Apache24\htdocs\SealBall_DesktopPet\build\custom-templates\windows_release_x86_64.exe
```

Expected SHA-256 for the current template:

`6088b821a63166d155c7f7cc176fdae5d8ba0a314ceb3290cb6ef8e8fbacda84`

Both Windows export presets reference this custom template and should fail
rather than silently switching back to the official template if it is absent.
