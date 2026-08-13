$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $projectRoot 'tools\install_antigravity_cli_integration.ps1'
$testRoot = Join-Path $env:TEMP (
    'OpenDesktopPet Antigravity CLI Installer Test ' + [guid]::NewGuid().ToString('N')
)
$geminiConfigHome = Join-Path $testRoot '.gemini\config'
$hooksPath = Join-Path $geminiConfigHome 'hooks.json'
$originalUserProfile = $env:USERPROFILE

function Assert-Installer([bool]$condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
}

try {
    New-Item -ItemType Directory -Force -Path $geminiConfigHome | Out-Null
    $env:USERPROFILE = $testRoot
    @'
{
  "existing": {
    "PostToolUse": [
      {"matcher": "run_command", "hooks": [{"type": "command", "command": "powershell.exe -File C:\\Tools\\existing-post.ps1"}]}
    ]
  },
  "open-desktop-pet": {
    "Stop": [
      {"type": "command", "command": "powershell.exe -File C:\\Tools\\existing-stop.ps1"}
    ],
    "PostInvocation": [
      {"type": "command", "command": "powershell.exe -File C:\\Tools\\existing-invocation.ps1"}
    ]
  }
}
'@ | Set-Content -LiteralPath $hooksPath -Encoding UTF8

    & $installerPath | Out-Null
    $settings = Get-Content -LiteralPath $hooksPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $settingsBytes = [System.IO.File]::ReadAllBytes($hooksPath)
    Assert-Installer (-not (
        $settingsBytes.Length -ge 3 -and
        $settingsBytes[0] -eq 0xEF -and
        $settingsBytes[1] -eq 0xBB -and
        $settingsBytes[2] -eq 0xBF
    )) 'Antigravity installer wrote a UTF-8 BOM.'
    $stopCommands = @($settings.'open-desktop-pet'.Stop | ForEach-Object { $_.command })
    Assert-Installer ($stopCommands.Count -eq 2) 'Antigravity installer removed an existing Stop hook.'
    Assert-Installer (($stopCommands | Where-Object { $_ -match '(?i)-EncodedCommand\s+' }).Count -eq 1) `
        'Antigravity installer did not add exactly one encoded Stop hook.'
    $desktopPetCommand = [string]$settings.'open-desktop-pet'.Stop[1].command
    $encodedCommandMatch = [regex]::Match($desktopPetCommand, '(?i)-EncodedCommand\s+([A-Za-z0-9+/=]+)$')
    Assert-Installer ($encodedCommandMatch.Success) `
        'Antigravity installer must use a PowerShell encoded command for paths with spaces.'
    $decodedInvocation = [Text.Encoding]::Unicode.GetString(
        [Convert]::FromBase64String($encodedCommandMatch.Groups[1].Value)
    )
    $expectedBridgePath = Join-Path $testRoot '.open-desktop-pet\antigravity_cli_notify.ps1'
    Assert-Installer ($decodedInvocation -eq ("& '{0}'" -f $expectedBridgePath.Replace("'", "''"))) `
        'Antigravity installer encoded an incorrect bridge invocation.'

    # Antigravity evaluates hook commands through a Windows shell. Execute the
    # generated command that way with a profile path containing spaces to prove
    # the encoded invocation still reaches the bridge and preserves stdin.
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = 'cmd.exe'
    $processInfo.Arguments = '/d /s /c "' + $desktopPetCommand + '"'
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardInput = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $hookProcess = [System.Diagnostics.Process]::Start($processInfo)
    $hookProcess.StandardInput.Write('{"fullyIdle":false}')
    $hookProcess.StandardInput.Close()
    $hookOutput = $hookProcess.StandardOutput.ReadToEnd()
    $hookError = $hookProcess.StandardError.ReadToEnd()
    $hookProcess.WaitForExit()
    Assert-Installer ($hookProcess.ExitCode -eq 0) `
        ("Antigravity encoded hook command failed: {0}" -f $hookError)
    Assert-Installer ($hookOutput -match '\{"decision":"allow"\}') `
        'Antigravity encoded hook command did not pass stdin to the bridge.'

    Assert-Installer ($desktopPetCommand -notmatch 'WindowStyle') `
        'Antigravity installer must not hide the parent PowerShell console.'
    Assert-Installer ($settings.'open-desktop-pet'.Stop[1].timeout -eq 5) `
        'Antigravity installer must use a five-second hook timeout.'
    Assert-Installer ($settings.'open-desktop-pet'.PostInvocation[0].command -like '*existing-invocation.ps1*') `
        'Antigravity installer removed an unrelated hook.'
    Assert-Installer ($settings.existing.PostToolUse[0].hooks.command -like '*existing-post.ps1*') `
        'Antigravity installer removed another hook definition.'
    Assert-Installer (Test-Path -LiteralPath (Join-Path $testRoot '.open-desktop-pet\antigravity_cli_notify.ps1')) `
        'Antigravity installer did not copy the notification bridge.'

    & $installerPath | Out-Null
    $reinstalled = Get-Content -LiteralPath $hooksPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $reinstalledStopCommands = @($reinstalled.'open-desktop-pet'.Stop | ForEach-Object { $_.command })
    Assert-Installer ($reinstalledStopCommands.Count -eq 2) `
        'Reinstalling Antigravity hooks must remain idempotent.'

    & $installerPath -Uninstall | Out-Null
    $uninstalled = Get-Content -LiteralPath $hooksPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Installer ($uninstalled.'open-desktop-pet'.Stop[0].command -like '*existing-stop.ps1*') `
        'Antigravity uninstall did not preserve the existing Stop hook.'
    Assert-Installer ($uninstalled.'open-desktop-pet'.PostInvocation[0].command -like '*existing-invocation.ps1*') `
        'Antigravity uninstall removed an unrelated hook.'

    Write-Output 'ANTIGRAVITY_CLI_INTEGRATION_INSTALLER_TEST_OK'
}
finally {
    $env:USERPROFILE = $originalUserProfile
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
