param(
    [Parameter(Mandatory = $true)]
    [string]$ExePath
)

$ErrorActionPreference = 'Stop'
$resolvedExe = (Resolve-Path -LiteralPath $ExePath).Path
$signalPath = Join-Path $env:TEMP (
    'DesktopPet-HitHost-' + [guid]::NewGuid().ToString('N') + '.txt'
)
$isolatedAppData = Join-Path $env:TEMP (
    'DesktopPet-HitTest-' + [guid]::NewGuid().ToString('N')
)
$originalAppData = $env:APPDATA
$helperProcess = $null
$petProcess = $null

Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class DesktopPetHitTestNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int X, Y;
        public POINT(int x, int y) { X = x; Y = y; }
    }
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr window, out RECT rect);
    [DllImport("user32.dll")]
    public static extern IntPtr WindowFromPoint(POINT point);
}
'@

try {
    New-Item -ItemType Directory -Path $isolatedAppData | Out-Null
    $helperProcess = Start-Process powershell.exe -PassThru -ArgumentList (
        '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $PSScriptRoot 'click_through_host.ps1'),
        '-SignalPath', $signalPath
    )
    Start-Sleep -Seconds 2
    $helperProcess.Refresh()
    if ($helperProcess.HasExited -or $helperProcess.MainWindowHandle -eq 0) {
        throw 'The background click-through host did not create a native window.'
    }

    $env:APPDATA = $isolatedAppData
    $petProcess = Start-Process -FilePath $resolvedExe -PassThru
    Start-Sleep -Seconds 2
    $petProcess.Refresh()
    if ($petProcess.HasExited -or $petProcess.MainWindowHandle -eq 0) {
        throw 'The desktop pet did not create a native window.'
    }

    $rect = New-Object DesktopPetHitTestNative+RECT
    [DesktopPetHitTestNative]::GetWindowRect(
        $petProcess.MainWindowHandle, [ref]$rect
    ) | Out-Null
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    $bubblePoint = New-Object DesktopPetHitTestNative+POINT(
        ($rect.Left + [math]::Round($width * 0.5)),
        ($rect.Top + [math]::Round($height * (89.0 / 320.0)))
    )
    $petPoint = New-Object DesktopPetHitTestNative+POINT(
        ($rect.Left + [math]::Round($width * 0.5)),
        ($rect.Top + [math]::Round($height * (190.0 / 320.0)))
    )
    $cornerPoint = New-Object DesktopPetHitTestNative+POINT(
        ($rect.Left + 5), ($rect.Top + 5)
    )

    $bubbleTarget = [DesktopPetHitTestNative]::WindowFromPoint($bubblePoint)
    $petTarget = [DesktopPetHitTestNative]::WindowFromPoint($petPoint)
    $cornerTarget = [DesktopPetHitTestNative]::WindowFromPoint($cornerPoint)
    if ($bubbleTarget -ne $petProcess.MainWindowHandle) {
        throw 'The visible speech bubble does not receive native Windows input.'
    }
    if ($cornerTarget -ne $helperProcess.MainWindowHandle) {
        throw 'A transparent window corner still intercepts native Windows input.'
    }
    if ($petTarget -ne $petProcess.MainWindowHandle) {
        throw 'The visible pet body does not receive native Windows input.'
    }
    'WINDOWS_NATIVE_HIT_TEST_OK'
} finally {
    $env:APPDATA = $originalAppData
    if ($petProcess -and -not $petProcess.HasExited) {
        Stop-Process -Id $petProcess.Id
    }
    if ($helperProcess -and -not $helperProcess.HasExited) {
        Stop-Process -Id $helperProcess.Id
    }
    if (Test-Path -LiteralPath $signalPath) {
        Remove-Item -LiteralPath $signalPath
    }
}
