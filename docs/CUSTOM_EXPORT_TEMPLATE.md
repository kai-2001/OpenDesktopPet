# Custom Windows export template

Windows release exports use:

`build/custom-templates/windows_release_x86_64.exe`

The binary is intentionally ignored by Git. It is Godot 4.6.3-stable's
`template_release` with `engine-patches/godot-4.6.3-no-focus-overlay.patch`
applied. The patch gives the focusable main desktop-overlay window
`WS_EX_TOOLWINDOW` instead of `WS_EX_APPWINDOW`, keeping the pet out of the
taskbar and Alt-Tab while allowing native popup menus to dismiss on focus loss.

From the Open Desktop Pet project root, set the location of a Godot
4.6.3-stable source checkout, then build the template:

```powershell
$projectRoot = (Get-Location).Path
$godotSource = (Resolve-Path ..\godot).Path
git -C $godotSource apply (
  Join-Path $projectRoot 'engine-patches\godot-4.6.3-no-focus-overlay.patch'
)
Push-Location $godotSource
try {
  python -m SCons platform=windows target=template_release arch=x86_64 `
    use_mingw=yes use_llvm=yes d3d12=no production=yes lto=none -j4
} finally {
  Pop-Location
}
```

Copy the resulting non-console template:

```powershell
$templateDirectory = Join-Path $projectRoot 'build\custom-templates'
New-Item -ItemType Directory -Force $templateDirectory | Out-Null
Copy-Item (
  Join-Path $godotSource 'bin\godot.windows.template_release.x86_64.llvm.exe'
) (Join-Path $templateDirectory 'windows_release_x86_64.exe')
```

Expected SHA-256 for the current template:

`72eb7afe441a63c3f1cfaab045a0dcc9eae1c328ff42b19999d11dbe2899e4f3`

The Windows Public export preset references this custom template and should
fail rather than silently switching back to the official template if it is
absent.
