$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $projectRoot 'tools\install_opencode_integration.ps1'
$testRoot = Join-Path $env:TEMP (
    'OpenDesktopPet-OpenCode-Installer-Test-' + [guid]::NewGuid().ToString('N')
)
$oldUserProfile = $env:USERPROFILE

function Assert-Installer([bool]$condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
}

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    $env:USERPROFILE = $testRoot

    & $installerPath | Out-Null
    $pluginPath = Join-Path $testRoot '.config\opencode\plugins\open-desktop-pet.js'
    $bridgePath = Join-Path $testRoot '.open-desktop-pet\opencode_notify.ps1'
    $markerPath = Join-Path $testRoot '.open-desktop-pet\open_desktop_pet_opencode_installed.txt'
    Assert-Installer (Test-Path -LiteralPath $pluginPath) 'OpenCode plugin was not installed.'
    Assert-Installer (Test-Path -LiteralPath $bridgePath) 'OpenCode bridge was not installed.'
    Assert-Installer (Test-Path -LiteralPath $markerPath) 'OpenCode install marker was not written.'
    $pluginText = Get-Content -LiteralPath $pluginPath -Raw -Encoding UTF8
    Assert-Installer ($pluginText.Contains('session.idle')) 'Plugin does not listen for session.idle.'
    Assert-Installer ($pluginText.Contains('agent-turn-complete')) 'Plugin does not send completion events.'
    Assert-Installer ($pluginText.Contains('node:child_process')) `
        'OpenCode plugin must use the Node-compatible child process API.'
    Assert-Installer (-not $pluginText.Contains('Bun.spawn')) `
        'OpenCode Desktop plugin must not depend on Bun.spawn.'
    $bridgeText = Get-Content -LiteralPath $bridgePath -Raw -Encoding UTF8
    Assert-Installer ($bridgeText.Contains('schema_version = 1')) `
        'The OpenCode bridge must emit the normalized payload schema.'
    Assert-Installer ($bridgeText.Contains("target_executable = 'OpenCode.exe'")) `
        'The OpenCode bridge must identify the desktop executable target.'
    $controllerText = Get-Content -LiteralPath (
        Join-Path $projectRoot 'scripts\agent_integration_controller.gd'
    ) -Raw -Encoding UTF8
    Assert-Installer (-not $controllerText.Contains(
        'base_path.path_join("OpenCode/opencode.exe")'
    )) 'OpenCode CLI must not be auto-detected as the Desktop target.'
    Assert-Installer (-not $controllerText.Contains(
        'base_path.path_join("Programs/OpenCode/opencode.exe")'
    )) 'OpenCode CLI must not be auto-detected from the generic Programs path.'
    Assert-Installer ($bridgeText.Contains('Test-OpenCodeDesktopPath')) `
        'The OpenCode bridge must validate Desktop executable path hints.'
    Assert-Installer ($bridgeText.Contains('$candidateFileName -ceq ''OpenCode.exe''')) `
        'The OpenCode bridge must recognize the explicit Desktop executable without a saved path.'
    Assert-Installer ($bridgeText.Contains('target_app = ''vscode''')) `
        'The OpenCode bridge must keep VS Code fallback routing.'

    & $installerPath | Out-Null
    Assert-Installer ((Get-Content -LiteralPath $pluginPath -Raw -Encoding UTF8).Contains(
        'OpenDesktopPet OpenCode notification plugin'
    )) 'Reinstalling the OpenCode plugin must remain idempotent.'

    & $installerPath -Uninstall | Out-Null
    Assert-Installer (-not (Test-Path -LiteralPath $pluginPath)) 'OpenCode plugin was not removed.'
    Assert-Installer (-not (Test-Path -LiteralPath $markerPath)) 'OpenCode marker was not removed.'
    Write-Output 'OPENCODE_INTEGRATION_INSTALLER_TEST_OK'
} finally {
    $env:USERPROFILE = $oldUserProfile
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
