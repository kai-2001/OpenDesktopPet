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
& (Join-Path $PSScriptRoot 'codex_integration_installer_test.ps1')
if ($LASTEXITCODE -ne 0) {
	throw 'Codex integration installer checks failed.'
}
& (Join-Path $PSScriptRoot 'codex_notify_router_test.ps1')
if ($LASTEXITCODE -ne 0) {
	throw 'Codex notification router checks failed.'
}
& (Join-Path $PSScriptRoot 'copilot_integration_installer_test.ps1')
if ($LASTEXITCODE -ne 0) {
    throw 'Copilot integration installer checks failed.'
}
& (Join-Path $PSScriptRoot 'copilot_notify_bridge_test.ps1')
if ($LASTEXITCODE -ne 0) {
    throw 'Copilot notification bridge checks failed.'
}
& (Join-Path $PSScriptRoot 'opencode_integration_installer_test.ps1')
if ($LASTEXITCODE -ne 0) {
    throw 'OpenCode integration installer checks failed.'
}
& (Join-Path $PSScriptRoot 'opencode_notify_bridge_test.ps1')
if ($LASTEXITCODE -ne 0) {
    throw 'OpenCode notification bridge checks failed.'
}
& (Join-Path $PSScriptRoot 'claude_code_integration_installer_test.ps1')
if ($LASTEXITCODE -ne 0) {
    throw 'Claude Code integration installer checks failed.'
}
& (Join-Path $PSScriptRoot 'claude_code_notify_bridge_test.ps1')
if ($LASTEXITCODE -ne 0) {
	throw 'Claude Code notification bridge checks failed.'
}
& (Join-Path $PSScriptRoot 'gemini_cli_integration_installer_test.ps1')
if ($LASTEXITCODE -ne 0) {
    throw 'Gemini CLI integration installer checks failed.'
}
& (Join-Path $PSScriptRoot 'gemini_cli_notify_bridge_test.ps1')
if ($LASTEXITCODE -ne 0) {
    throw 'Gemini CLI notification bridge checks failed.'
}
& (Join-Path $PSScriptRoot 'antigravity_cli_integration_installer_test.ps1')
if ($LASTEXITCODE -ne 0) {
    throw 'Antigravity CLI integration installer checks failed.'
}
& (Join-Path $PSScriptRoot 'antigravity_cli_notify_bridge_test.ps1')
if ($LASTEXITCODE -ne 0) {
	throw 'Antigravity CLI notification bridge checks failed.'
}
& (Join-Path $PSScriptRoot 'open_desktop_pet_uninstaller_test.ps1')
if ($LASTEXITCODE -ne 0) {
	throw 'OpenDesktopPet uninstaller checks failed.'
}
$isolatedAppData = Join-Path $env:TEMP (
    'OpenDesktopPet-Automated-Validation-' + [guid]::NewGuid().ToString('N')
)
$isolatedCodexHome = Join-Path $isolatedAppData 'codex-home'
$productionSave = Join-Path $env:APPDATA 'Godot\app_userdata\Open Desktop Pet\save_v2.json'
$productionHashBefore = if (Test-Path $productionSave) {
    (Get-FileHash -LiteralPath $productionSave -Algorithm SHA256).Hash
} else {
    ''
}

New-Item -ItemType Directory -Force -Path $isolatedAppData | Out-Null
$originalAppData = $env:APPDATA
$originalCodexHome = $env:CODEX_HOME
try {
    $env:APPDATA = $isolatedAppData
    $env:CODEX_HOME = $isolatedCodexHome
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $agentConfigurationOutput = & $GodotExe --headless --path $projectRoot --script 'res://tests/agent_configuration_check_test.gd' 2>&1
    $agentConfigurationExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    $agentConfigurationOutput | Write-Output
    if ($agentConfigurationExitCode -ne 0 -or -not ($agentConfigurationOutput -match 'AGENT_CONFIGURATION_CHECK_TEST_OK')) {
        throw 'Agent configuration check validation failed.'
    }

    $agentRuntimeOutput = & $GodotExe --headless --path $projectRoot --script 'res://tests/agent_runtime_state_test.gd' 2>&1
    $agentRuntimeExitCode = $LASTEXITCODE
    $agentRuntimeOutput | Write-Output
    if ($agentRuntimeExitCode -ne 0 -or -not ($agentRuntimeOutput -match 'AGENT_RUNTIME_STATE_TEST_OK')) {
        throw 'Agent runtime state validation failed.'
    }

    $agentRouterOutput = & $GodotExe --headless --path $projectRoot --script 'res://tests/agent_notification_router_test.gd' 2>&1
    $agentRouterExitCode = $LASTEXITCODE
    $agentRouterOutput | Write-Output
    if ($agentRouterExitCode -ne 0 -or -not ($agentRouterOutput -match 'AGENT_NOTIFICATION_ROUTER_TEST_OK')) {
        throw 'Agent notification router validation failed.'
    }

    $ErrorActionPreference = 'Continue'
    $gameplayOutput = & $GodotExe --headless --path $projectRoot --script 'res://tests/gameplay_state_test.gd' 2>&1
    $gameplayExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    $gameplayOutput | Write-Output
    if ($gameplayExitCode -ne 0 -or -not ($gameplayOutput -match 'GAMEPLAY_STATE_TEST_OK')) {
        throw 'Gameplay state validation failed.'
    }

    $ErrorActionPreference = 'Continue'
    $agentNotificationReceiverOutput = & $GodotExe --headless --path $projectRoot --script 'res://tests/local_agent_notification_receiver_test.gd' 2>&1
    $agentNotificationReceiverExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    $agentNotificationReceiverOutput | Write-Output
    if ($agentNotificationReceiverExitCode -ne 0 -or -not ($agentNotificationReceiverOutput -match 'LOCAL_AGENT_NOTIFICATION_RECEIVER_TEST_OK')) {
        throw 'Local Agent notification receiver validation failed.'
    }

    $ErrorActionPreference = 'Continue'
    $windowsActivatorOutput = & $GodotExe --headless --path $projectRoot --script 'res://tests/windows_window_activator_test.gd' 2>&1
    $windowsActivatorExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    $windowsActivatorOutput | Write-Output
    if ($windowsActivatorExitCode -ne 0 -or -not ($windowsActivatorOutput -match 'WINDOWS_WINDOW_ACTIVATOR_TEST_OK')) {
        throw 'Windows window activator validation failed.'
    }

    $ErrorActionPreference = 'Continue'
    $windowsAutostartOutput = & $GodotExe --headless --path $projectRoot --script 'res://tests/windows_autostart_service_test.gd' 2>&1
    $windowsAutostartExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    $windowsAutostartOutput | Write-Output
    if ($windowsAutostartExitCode -ne 0 -or -not ($windowsAutostartOutput -match 'WINDOWS_AUTOSTART_SERVICE_TEST_OK')) {
        throw 'Windows autostart service validation failed.'
    }

    $ErrorActionPreference = 'Continue'
    $agentSettingsUiOutput = & $GodotExe --headless --path $projectRoot --script 'res://tests/agent_settings_ui_test.gd' 2>&1
    $agentSettingsUiExitCode = $LASTEXITCODE
    $agentSettingsUiOutput | Write-Output
    if ($agentSettingsUiExitCode -ne 0 -or -not ($agentSettingsUiOutput -match 'AGENT_SETTINGS_UI_TEST_OK')) {
        throw 'Agent settings UI validation failed.'
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
    $env:CODEX_HOME = $originalCodexHome
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
