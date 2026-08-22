$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $projectRoot 'tools\install_pi_integration.ps1'
$testRoot = Join-Path $env:TEMP (
    'OpenDesktopPet-Pi-Installer-Test-' + [guid]::NewGuid().ToString('N')
)
$oldUserProfile = $env:USERPROFILE
$oldPiAgentDir = $env:PI_CODING_AGENT_DIR

function Assert-Installer([bool]$condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
}

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    $env:USERPROFILE = $testRoot
    $env:PI_CODING_AGENT_DIR = Join-Path $testRoot '.custom-pi\agent'

    & $installerPath | Out-Null
    $extensionPath = Join-Path $env:PI_CODING_AGENT_DIR 'extensions\open-desktop-pet.ts'
    $markerPath = Join-Path $testRoot '.open-desktop-pet\open_desktop_pet_pi_installed.txt'
    Assert-Installer (Test-Path -LiteralPath $extensionPath) `
        'Pi notification extension was not installed.'
    Assert-Installer (Test-Path -LiteralPath $markerPath) `
        'Pi install marker was not written.'
    $extensionText = Get-Content -LiteralPath $extensionPath -Raw -Encoding UTF8
    Assert-Installer ($extensionText.Contains('agent_settled')) `
        'Pi extension does not use agent_settled.'
    Assert-Installer ($extensionText.Contains('agent-error')) `
        'Pi extension does not translate settled errors.'
    Assert-Installer ($extensionText.Contains('model_provider')) `
        'Pi extension does not include model metadata.'
    Assert-Installer (-not $extensionText.Contains('openai-codex')) `
        'Pi extension still filters out non-Codex models.'
    Assert-Installer ($extensionText.Contains('pi_codex_terminal')) `
        'Pi extension does not use the normalized runtime target.'
    Assert-Installer ($extensionText.Contains('127.0.0.1')) `
        'Pi extension does not send to the local notification receiver.'
    Assert-Installer (-not $extensionText.Contains('last_assistant_message')) `
        'Pi extension must not forward assistant content.'

    & $installerPath | Out-Null
    Assert-Installer ((Get-Content -LiteralPath $extensionPath -Raw -Encoding UTF8).Contains(
        'OpenDesktopPet Pi notification extension'
    )) 'Reinstalling the Pi extension must remain idempotent.'

    & $installerPath -Uninstall | Out-Null
    Assert-Installer (-not (Test-Path -LiteralPath $extensionPath)) `
        'Pi notification extension was not removed.'
    Assert-Installer (-not (Test-Path -LiteralPath $markerPath)) `
        'Pi install marker was not removed.'

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $extensionPath) | Out-Null
    Set-Content -LiteralPath $extensionPath -Value '// existing user Pi extension' -Encoding UTF8
    & $installerPath | Out-Null
    $backupFiles = @(Get-ChildItem -LiteralPath (Split-Path -Parent $extensionPath) `
        -Filter 'open-desktop-pet.ts.open-desktop-pet-backup-*.ts' -File)
    Assert-Installer ($backupFiles.Count -eq 1) `
        'Pi installer did not back up the existing extension.'
    & $installerPath -Uninstall | Out-Null
    Assert-Installer (Test-Path -LiteralPath $extensionPath) `
        'Pi uninstall did not restore the existing extension.'
    Assert-Installer ((Get-Content -LiteralPath $extensionPath -Raw -Encoding UTF8).Contains(
        '// existing user Pi extension'
    )) 'Pi uninstall restored incorrect extension content.'
    Assert-Installer (-not (Test-Path -LiteralPath $backupFiles[0].FullName)) `
        'Pi uninstall left the restored backup behind.'

    Write-Output 'PI_INTEGRATION_INSTALLER_TEST_OK'
} finally {
    $env:USERPROFILE = $oldUserProfile
    $env:PI_CODING_AGENT_DIR = $oldPiAgentDir
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
