$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $projectRoot 'tools\install_claude_code_integration.ps1'
$testRoot = Join-Path $env:TEMP (
    'OpenDesktopPet-Claude-Code-Installer-Test-' + [guid]::NewGuid().ToString('N')
)
$claudeHome = Join-Path $testRoot '.claude'
$settingsPath = Join-Path $claudeHome 'settings.json'
$originalUserProfile = $env:USERPROFILE

function Assert-Installer([bool]$condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
}

try {
    New-Item -ItemType Directory -Force -Path $claudeHome | Out-Null
    $env:USERPROFILE = $testRoot
    @'
{
  "permissions": {"allow": ["Bash(git status)"]},
  "hooks": {
    "Stop": [
      {"hooks": [{"type": "command", "command": "powershell.exe -File C:\\Tools\\existing-stop.ps1"}]}
    ],
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "powershell.exe -File C:\\Tools\\existing-start.ps1"}]}
    ]
  }
}
'@ | Set-Content -LiteralPath $settingsPath -Encoding UTF8

    & $installerPath | Out-Null
    $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $stopCommands = @($settings.hooks.Stop | ForEach-Object { $_.hooks.command })
    $notificationCommands = @($settings.hooks.Notification | ForEach-Object { $_.hooks.command })
    $failureCommands = @($settings.hooks.StopFailure | ForEach-Object { $_.hooks.command })
    Assert-Installer ($stopCommands.Count -eq 2) 'Claude installer removed an existing Stop hook.'
    Assert-Installer (($stopCommands | Where-Object { $_ -like '*claude_code_notify.ps1*' }).Count -eq 1) `
        'Claude installer did not add exactly one Stop hook.'
    Assert-Installer (($notificationCommands | Where-Object { $_ -like '*claude_code_notify.ps1*' }).Count -eq 1) `
        'Claude installer did not add exactly one Notification hook.'
    Assert-Installer (($failureCommands | Where-Object { $_ -like '*claude_code_notify.ps1*' }).Count -eq 1) `
        'Claude installer did not add exactly one StopFailure hook.'
    Assert-Installer ($settings.hooks.SessionStart[0].hooks.command -like '*existing-start.ps1*') `
        'Claude installer removed an unrelated hook.'
    Assert-Installer (Test-Path -LiteralPath (Join-Path $testRoot '.open-desktop-pet\claude_code_notify.ps1')) `
        'Claude installer did not copy the notification bridge.'

    & $installerPath | Out-Null
    $reinstalled = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $reinstalledStopCommands = @($reinstalled.hooks.Stop | ForEach-Object { $_.hooks.command })
    Assert-Installer ($reinstalledStopCommands.Count -eq 2) `
        'Reinstalling Claude hooks must remain idempotent.'

    & $installerPath -Uninstall | Out-Null
    $uninstalled = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Installer ($uninstalled.hooks.Stop[0].hooks.command -like '*existing-stop.ps1*') `
        'Claude uninstall did not preserve the existing Stop hook.'
    Assert-Installer ($null -eq $uninstalled.hooks.Notification) `
        'Claude uninstall did not remove the Notification hook.'
    Assert-Installer ($null -eq $uninstalled.hooks.StopFailure) `
        'Claude uninstall did not remove the StopFailure hook.'

    Write-Output 'CLAUDE_CODE_INTEGRATION_INSTALLER_TEST_OK'
}
finally {
    $env:USERPROFILE = $originalUserProfile
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
