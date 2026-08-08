$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $projectRoot 'tools\install_gemini_cli_integration.ps1'
$testRoot = Join-Path $env:TEMP (
    'OpenDesktopPet-Gemini-CLI-Installer-Test-' + [guid]::NewGuid().ToString('N')
)
$geminiHome = Join-Path $testRoot '.gemini'
$settingsPath = Join-Path $geminiHome 'settings.json'
$originalUserProfile = $env:USERPROFILE

function Assert-Installer([bool]$condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
}

try {
    New-Item -ItemType Directory -Force -Path $geminiHome | Out-Null
    $env:USERPROFILE = $testRoot
    @'
{
  "general": {"previewFeatures": true},
  "hooks": {
    "AfterAgent": [
      {"hooks": [{"type": "command", "command": "powershell.exe -File C:\\Tools\\existing-after.ps1"}]}
    ],
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "powershell.exe -File C:\\Tools\\existing-start.ps1"}]}
    ]
  }
}
'@ | Set-Content -LiteralPath $settingsPath -Encoding UTF8

    & $installerPath | Out-Null
    $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $afterAgentCommands = @($settings.hooks.AfterAgent | ForEach-Object { $_.hooks.command })
    $notificationCommands = @($settings.hooks.Notification | ForEach-Object { $_.hooks.command })
    Assert-Installer ($afterAgentCommands.Count -eq 2) 'Gemini installer removed an existing AfterAgent hook.'
    Assert-Installer (($afterAgentCommands | Where-Object { $_ -like '*gemini_cli_notify.ps1*' }).Count -eq 1) `
        'Gemini installer did not add exactly one AfterAgent hook.'
    Assert-Installer ($settings.hooks.AfterAgent[1].hooks[0].timeout -eq 5000) `
        'Gemini installer must use a five-second hook timeout in milliseconds.'
    Assert-Installer (($notificationCommands | Where-Object { $_ -like '*gemini_cli_notify.ps1*' }).Count -eq 1) `
        'Gemini installer did not add exactly one Notification hook.'
    Assert-Installer ($settings.hooks.Notification[0].matcher -eq 'ToolPermission') `
        'Gemini installer did not limit Notification hooks to ToolPermission.'
    Assert-Installer ($settings.hooks.SessionStart[0].hooks.command -like '*existing-start.ps1*') `
        'Gemini installer removed an unrelated hook.'
    Assert-Installer ($settings.general.previewFeatures -eq $true) `
        'Gemini installer removed an unrelated setting.'
    Assert-Installer (Test-Path -LiteralPath (Join-Path $testRoot '.open-desktop-pet\gemini_cli_notify.ps1')) `
        'Gemini installer did not copy the notification bridge.'

    & $installerPath | Out-Null
    $reinstalled = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $reinstalledAfterAgentCommands = @($reinstalled.hooks.AfterAgent | ForEach-Object { $_.hooks.command })
    Assert-Installer ($reinstalledAfterAgentCommands.Count -eq 2) `
        'Reinstalling Gemini hooks must remain idempotent.'

    & $installerPath -Uninstall | Out-Null
    $uninstalled = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Installer ($uninstalled.hooks.AfterAgent[0].hooks.command -like '*existing-after.ps1*') `
        'Gemini uninstall did not preserve the existing AfterAgent hook.'
    Assert-Installer ($null -eq $uninstalled.hooks.Notification) `
        'Gemini uninstall did not remove the Notification hook.'
    Assert-Installer ($uninstalled.general.previewFeatures -eq $true) `
        'Gemini uninstall removed an unrelated setting.'

    Write-Output 'GEMINI_CLI_INTEGRATION_INSTALLER_TEST_OK'
}
finally {
    $env:USERPROFILE = $originalUserProfile
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
