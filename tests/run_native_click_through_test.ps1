param(
    [string]$GodotPath = 'C:\Apache24\tools\godot-4.6.3\Godot_v4.6.3-stable_win64.exe',
    [int[]]$Fps = @(15, 30, 60),
    [double[]]$Scale = @(0.5, 1.0, 1.5),
    [string]$ScreenshotDir = ''
)

# Opens real desktop pet windows and moves the real cursor. Every run uses
# isolated APPDATA, USERPROFILE and CODEX_HOME folders.

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class ClickThroughNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; public POINT(int x, int y) { X = x; Y = y; } }
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT point);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr window, uint flags);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
}
'@
[ClickThroughNative]::SetProcessDPIAware() | Out-Null

$failures = New-Object System.Collections.Generic.List[string]
$originalCursor = New-Object ClickThroughNative+POINT
[ClickThroughNative]::GetCursorPos([ref]$originalCursor) | Out-Null
$originalEnv = @{ APPDATA = $env:APPDATA; USERPROFILE = $env:USERPROFILE; CODEX_HOME = $env:CODEX_HOME }
$hostColor = [System.Drawing.Color]::FromArgb(35, 45, 55)

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) {
        $script:failures.Add($message)
        Write-Output "FAIL $message"
    }
}

function Get-OwnerProcessId([int[]]$point) {
    $target = [ClickThroughNative]::WindowFromPoint(
        (New-Object ClickThroughNative+POINT($point[0], $point[1]))
    )
    $root = [ClickThroughNative]::GetAncestor($target, 2)
    $processId = [uint32]0
    [ClickThroughNative]::GetWindowThreadProcessId($root, [ref]$processId) | Out-Null
    return [int]$processId
}

function Move-Cursor([int[]]$point) {
    [ClickThroughNative]::SetCursorPos($point[0], $point[1]) | Out-Null
    # The pet updates input state once per rendered frame; 15 FPS needs ~67 ms.
    Start-Sleep -Milliseconds 250
}

function Wait-Report([string]$path) {
    $deadline = (Get-Date).AddSeconds(30)
    while (-not (Test-Path -LiteralPath $path)) {
        if ((Get-Date) -gt $deadline) { throw "Timed out waiting for $path" }
        Start-Sleep -Milliseconds 100
    }
    Start-Sleep -Milliseconds 100
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Test-ColorNear([System.Drawing.Color]$a, [System.Drawing.Color]$b) {
    return [math]::Abs($a.R - $b.R) -le 6 -and [math]::Abs($a.G - $b.G) -le 6 -and [math]::Abs($a.B - $b.B) -le 6
}

$hostSignal = Join-Path $env:TEMP ('ODP-ClickHost-' + [guid]::NewGuid().ToString('N') + '.txt')
$hostProcess = Start-Process powershell.exe -PassThru -ArgumentList (
    '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $PSScriptRoot 'click_through_host.ps1'),
    '-SignalPath', $hostSignal
)
Start-Sleep -Seconds 2

try {
    foreach ($fpsValue in $Fps) {
        foreach ($scaleValue in $Scale) {
            $label = "fps=$fpsValue scale=$scaleValue"
            $root = Join-Path $env:TEMP ('ODP-isolated-' + [guid]::NewGuid().ToString('N'))
            $signalDir = Join-Path $root 'signals'
            New-Item -ItemType Directory -Force "$root\appdata", "$root\profile", "$root\codex", $signalDir | Out-Null
            $env:APPDATA = "$root\appdata"; $env:USERPROFILE = "$root\profile"; $env:CODEX_HOME = "$root\codex"
            if (Test-Path -LiteralPath $hostSignal) { Remove-Item -LiteralPath $hostSignal }
            $pet = Start-Process -FilePath $GodotPath -PassThru -ArgumentList (
                '--path', "`"$projectRoot`"",
                '--script', 'res://tests/native_click_through_probe.gd',
                '--', "--fps=$fpsValue", "--scale=$scaleValue", "--signal-dir=`"$signalDir`""
            )
            try {
                $report = Wait-Report (Join-Path $signalDir 'bubble.json')
                Assert-True ([bool]$report.native) "$label native click-through is active"
                Assert-True ([bool]$report.unclipped_region) "$label no clipping window region is applied"
                Assert-True ($report.fps -eq $fpsValue) "$label target FPS applied"
                Assert-True ([math]::Abs($report.scale - $scaleValue) -lt 0.05) "$label visual scale applied ($($report.scale))"

                if ($report.bubble.Count -ne 2 -or $report.empty.Count -ne 2 -or $report.pet.Count -ne 2) {
                    throw "$label probe could not find test points: $($report | ConvertTo-Json -Compress)"
                }
                Move-Cursor $report.bubble
                Assert-True ((Get-OwnerProcessId $report.bubble) -eq $pet.Id) "$label speech bubble receives input"
                Move-Cursor $report.pet
                Assert-True ((Get-OwnerProcessId $report.pet) -eq $pet.Id) "$label pet pixels receive input"
                Move-Cursor $report.empty
                Assert-True ((Get-OwnerProcessId $report.empty) -eq $hostProcess.Id) "$label empty transparent pixels pass input through"
                if ($report.outline_gap.Count -eq 2) {
                    # Soft edges and gaps inside the outline must not hand presses to the desktop.
                    Move-Cursor $report.outline_gap
                    Assert-True ((Get-OwnerProcessId $report.outline_gap) -eq $pet.Id) "$label transparent gaps inside the sprite outline stay clickable"
                }

                $w = $report.window
                $bitmap = New-Object System.Drawing.Bitmap($w[2], $w[3])
                $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
                $graphics.CopyFromScreen($w[0], $w[1], 0, 0, $bitmap.Size)
                $emptyColor = $bitmap.GetPixel($report.empty[0] - $w[0], $report.empty[1] - $w[1])
                $petColor = $bitmap.GetPixel($report.pet[0] - $w[0], $report.pet[1] - $w[1])
                $bubbleColor = $bitmap.GetPixel($report.bubble[0] - $w[0], $report.bubble[1] - $w[1])
                Assert-True (Test-ColorNear $emptyColor $hostColor) "$label transparent pixels show the window behind ($emptyColor)"
                Assert-True (-not (Test-ColorNear $petColor $hostColor)) "$label pet pixels are drawn"
                Assert-True (-not (Test-ColorNear $bubbleColor $hostColor)) "$label speech bubble is drawn"
                if ($ScreenshotDir) {
                    New-Item -ItemType Directory -Force $ScreenshotDir | Out-Null
                    $bitmap.Save((Join-Path $ScreenshotDir "fps$fpsValue-scale$scaleValue.png"))
                }
                $graphics.Dispose(); $bitmap.Dispose()

                New-Item -ItemType File (Join-Path $signalDir 'hide-bubble') | Out-Null
                $report = Wait-Report (Join-Path $signalDir 'pet.json')
                if ($report.former_bubble.Count -ne 2) {
                    Write-Output "SKIP $label hidden speech check: the pet outline covers the whole bubble"
                } else {
                    Move-Cursor $report.former_bubble
                    Assert-True ((Get-OwnerProcessId $report.former_bubble) -eq $hostProcess.Id) "$label hidden speech area passes input through"
                }

                # Drag the pet 120 px right and 60 px up, then release.
                Move-Cursor $report.pet
                [ClickThroughNative]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
                for ($step = 1; $step -le 12; $step++) {
                    [ClickThroughNative]::SetCursorPos($report.pet[0] + $step * 10, $report.pet[1] - $step * 5) | Out-Null
                    Start-Sleep -Milliseconds 30
                }
                Start-Sleep -Milliseconds 200
                [ClickThroughNative]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
                Start-Sleep -Milliseconds 500
                Assert-True (-not (Test-Path -LiteralPath $hostSignal)) "$label drag does not leak a click to the window behind"
                New-Item -ItemType File (Join-Path $signalDir 'after-drag') | Out-Null
                $after = Wait-Report (Join-Path $signalDir 'after.json')
                Assert-True ($after.window[0] -ne $w[0] -or $after.window[1] -ne $w[1]) "$label drag moves the pet window"
                Move-Cursor $after.pet
                Assert-True ((Get-OwnerProcessId $after.pet) -eq $pet.Id) "$label pet stays clickable after the drag"

                # A real click on an empty pixel must land on the window behind.
                $emptyAfterDrag = $after.empty
                Move-Cursor $emptyAfterDrag
                [ClickThroughNative]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
                [ClickThroughNative]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
                Start-Sleep -Milliseconds 400
                Assert-True (Test-Path -LiteralPath $hostSignal) "$label click on transparent pixel reaches the window behind"

                New-Item -ItemType File (Join-Path $signalDir 'done') | Out-Null
                if (-not $pet.WaitForExit(5000)) { Stop-Process -Id $pet.Id }
                Write-Output "CHECKED $label"
            } finally {
                if (-not $pet.HasExited) { Stop-Process -Id $pet.Id }
                $env:APPDATA = $originalEnv.APPDATA; $env:USERPROFILE = $originalEnv.USERPROFILE; $env:CODEX_HOME = $originalEnv.CODEX_HOME
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
} finally {
    [ClickThroughNative]::SetCursorPos($originalCursor.X, $originalCursor.Y) | Out-Null
    if (-not $hostProcess.HasExited) { Stop-Process -Id $hostProcess.Id }
    if (Test-Path -LiteralPath $hostSignal) { Remove-Item -LiteralPath $hostSignal }
}

if ($failures.Count -gt 0) {
    Write-Output "NATIVE_CLICK_THROUGH_FAILED ($($failures.Count))"
    exit 1
}
Write-Output 'NATIVE_CLICK_THROUGH_TEST_OK'
