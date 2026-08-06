param(
    [Parameter(Mandatory = $true)]
    [string]$GodotExe
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'run_architecture_checks.ps1')
if ($LASTEXITCODE -ne 0) {
	throw 'Architecture checks failed.'
}
$isolatedAppData = Join-Path $env:TEMP (
    'OpenDesktopPet-Automated-Validation-' + [guid]::NewGuid().ToString('N')
)
$productionSave = Join-Path $env:APPDATA 'Godot\app_userdata\Open Desktop Pet\save_v2.json'
$productionHashBefore = if (Test-Path $productionSave) {
    (Get-FileHash -LiteralPath $productionSave -Algorithm SHA256).Hash
} else {
    ''
}

New-Item -ItemType Directory -Force -Path $isolatedAppData | Out-Null
$originalAppData = $env:APPDATA
try {
    $env:APPDATA = $isolatedAppData
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $gameplayOutput = & $GodotExe --headless --path $projectRoot --script 'res://tests/gameplay_state_test.gd' 2>&1
    $gameplayExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    $gameplayOutput | Write-Output
    if ($gameplayExitCode -ne 0 -or -not ($gameplayOutput -match 'GAMEPLAY_STATE_TEST_OK')) {
        throw 'Gameplay state validation failed.'
    }

    $ErrorActionPreference = 'Continue'
    $codexNotificationOutput = & $GodotExe --headless --path $projectRoot --script 'res://tests/codex_notification_receiver_test.gd' 2>&1
    $codexNotificationExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    $codexNotificationOutput | Write-Output
    if ($codexNotificationExitCode -ne 0 -or -not ($codexNotificationOutput -match 'CODEX_NOTIFICATION_RECEIVER_TEST_OK')) {
        throw 'Codex notification receiver validation failed.'
    }

    $ErrorActionPreference = 'Continue'
    $codexSettingsUiOutput = & $GodotExe --headless --path $projectRoot --script 'res://tests/codex_settings_ui_test.gd' 2>&1
    $codexSettingsUiExitCode = $LASTEXITCODE
    $codexSettingsUiOutput | Write-Output
    if ($codexSettingsUiExitCode -ne 0 -or -not ($codexSettingsUiOutput -match 'CODEX_SETTINGS_UI_TEST_OK')) {
        throw 'Codex settings UI validation failed.'
    }

    $ErrorActionPreference = 'Continue'
    $windowOutput = & $GodotExe --path $projectRoot --script 'res://tests/window_integration_test.gd' 2>&1
    $windowExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    $windowOutput | Write-Output
    if ($windowExitCode -ne 0 -or -not ($windowOutput -match 'WINDOW_INTEGRATION_TEST_OK')) {
        throw 'Window integration validation failed.'
    }
}
finally {
    $ErrorActionPreference = 'Stop'
    $env:APPDATA = $originalAppData
}

$productionHashAfter = if (Test-Path $productionSave) {
    (Get-FileHash -LiteralPath $productionSave -Algorithm SHA256).Hash
} else {
    ''
}
if ($productionHashBefore -ne $productionHashAfter) {
    throw 'Production save changed during isolated validation.'
}

Write-Output 'AUTOMATED_VALIDATION_OK'
