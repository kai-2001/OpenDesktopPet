$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

function Read-Source([string]$relativePath) {
	return Get-Content -LiteralPath (Join-Path $projectRoot $relativePath) -Encoding utf8 -Raw
}

function Assert-Architecture([bool]$condition, [string]$message) {
	if (-not $condition) {
		throw $message
	}
}

$details = Read-Source 'scripts/details_window_controller.gd'
$main = Read-Source 'scripts/main.gd'
$state = Read-Source 'scripts/pet_state.gd'
$visual = Read-Source 'scripts/pet_visual.gd'
$profile = Read-Source 'scripts/character_pack_profile.gd'
$autostart = Read-Source 'scripts/windows_autostart_service.gd'
$runtime = Read-Source 'scripts/character_pack_runtime.gd'
$manager = Read-Source 'scripts/character_pack_manager.gd'
$windowService = Read-Source 'scripts/desktop_window_service.gd'
$hitbox = Read-Source 'scripts/pet_hitbox_calculator.gd'
$gameplay = Read-Source 'scripts/pet_gameplay_coordinator.gd'
$statsCoordinator = Read-Source 'scripts/stats_window_coordinator.gd'
$inputController = Read-Source 'scripts/pet_input_controller.gd'
$characterCoordinator = Read-Source 'scripts/character_pack_coordinator.gd'
$agentController = Read-Source 'scripts/agent_integration_controller.gd'
$agentRouter = Read-Source 'scripts/agent_notification_router.gd'
$windowsActivator = Read-Source 'native/windows/src/windows_window_activator.cpp'
$windowsExtension = Read-Source 'native/windows/windows_window_activator.gdextension'
$releasePreparation = Read-Source 'tools/prepare_windows_release.ps1'

Assert-Architecture ($details -notmatch 'host\.') `
	'DetailsWindowController must not depend on host private APIs.'
Assert-Architecture ($main -notmatch 'build_(status|settings|character)_tab\(\s*tabs,\s*self') `
	'main.gd must not pass itself as the details-window host.'
Assert-Architecture ($state -notmatch 'FileAccess|DirAccess|OS\.execute|Time\.(get_unix_time_from_system|get_date_string_from_system)') `
	'PetState must delegate persistence and system time.'
Assert-Architecture ($main -notmatch 'OS\.execute|AUTOSTART_REGISTRY_KEY|_registry_executable') `
	'main.gd must not contain Windows Registry implementation details.'
Assert-Architecture ($visual -notmatch 'func _validate_action') `
	'PetVisual must not own character-pack action validation.'
Assert-Architecture ($profile -match 'class_name CharacterPackProfile') `
	'CharacterPackProfile is missing.'
Assert-Architecture ($visual -match 'CharacterPackProfileScript') `
	'PetVisual must delegate character-pack data to CharacterPackProfile.'
Assert-Architecture ($autostart -match 'class_name WindowsAutostartService') `
	'WindowsAutostartService is missing.'
Assert-Architecture ($details -notmatch 'autostart_query_requested') `
	'DetailsWindowController must not emit autostart queries before signal wiring.'
Assert-Architecture ($main -match '(?s)_autostart_check_box = settings_refs\["autostart_check_box"\].*call_deferred\("_start_autostart_operation", "query", false\)') `
	'The initial autostart query must start after settings controls are assigned.'
Assert-Architecture ($runtime -match 'class_name CharacterPackRuntime') `
	'CharacterPackRuntime is missing.'
Assert-Architecture ($manager -match 'CharacterPackValidatorScript') `
	'CharacterPackManager must use the shared action validator.'
Assert-Architecture ($windowService -match 'class_name DesktopWindowService') `
	'DesktopWindowService is missing.'
Assert-Architecture ($main -match 'DesktopWindowServiceScript') `
	'main.gd must delegate native window primitives to DesktopWindowService.'
Assert-Architecture ($hitbox -match 'class_name PetHitboxCalculator') `
	'PetHitboxCalculator is missing.'
Assert-Architecture ($visual -match 'PetHitboxCalculatorScript') `
	'PetVisual must delegate opaque hitbox calculation.'
Assert-Architecture ($gameplay -match 'class_name PetGameplayCoordinator') `
	'PetGameplayCoordinator is missing.'
Assert-Architecture ($main -match 'PetGameplayCoordinatorScript') `
	'main.gd must delegate gameplay action coordination.'
Assert-Architecture ($statsCoordinator -match 'class_name StatsWindowCoordinator') `
	'StatsWindowCoordinator is missing.'
Assert-Architecture ($main -match 'StatsWindowCoordinatorScript') `
	'main.gd must delegate details-window construction.'
Assert-Architecture ($statsCoordinator -match 'panel\.theme = _create_details_theme\(\)') `
	'StatsWindowCoordinator must apply the complete details-window theme.'
Assert-Architecture ($inputController -match 'class_name PetInputController') `
	'PetInputController is missing.'
Assert-Architecture ($main -match 'PetInputControllerScript') `
	'main.gd must delegate input and drag state.'
Assert-Architecture ($characterCoordinator -match 'class_name CharacterPackCoordinator') `
	'CharacterPackCoordinator is missing.'
Assert-Architecture ($main -match 'CharacterPackCoordinatorScript') `
	'main.gd must delegate character-pack coordination.'
Assert-Architecture ($main -notmatch 'CharacterPackManagerScript') `
	'main.gd must not depend directly on CharacterPackManager.'
Assert-Architecture ($main -notmatch '_agent_notification_queue') `
	'Agent notifications must replace the active bubble instead of queueing.'
Assert-Architecture ($agentController -match '_focus_target\(TARGET_VSCODE\)') `
	'Codex focus must route VS Code notifications to the configured VS Code target.'
Assert-Architecture ($agentController -match '"--reuse-window"') `
	'Codex focus must reuse the selected VS Code window.'
Assert-Architecture ($agentController -match 'TARGET_CODEX_APP') `
	'Codex integration must define a separate Codex App target.'
Assert-Architecture ($agentController -match 'TARGET_TERMINAL') `
	'Codex integration must define a separate terminal target.'
Assert-Architecture ($agentController -match 'TARGET_OPENCODE_APP') `
	'Codex integration must define a separate OpenCode Desktop target.'
Assert-Architecture ($agentController -match 'TARGET_CLAUDE_APP') `
	'Codex integration must define a separate Claude Desktop target.'
Assert-Architecture ($agentController -match '_detect_claude_app_from_appx') `
	'Claude Desktop detection must support Microsoft Store Appx installations.'
Assert-Architecture ($agentController -match 'terminal_opencode_enabled') `
	'Codex integration must keep OpenCode terminal state separate from Codex.'
Assert-Architecture ($agentController -match '_run_opencode_configuration_tool') `
	'Codex integration must configure OpenCode through its installer.'
Assert-Architecture ($agentController -match '_run_claude_code_configuration_tool') `
	'Codex integration must configure Claude Code through its installer.'
Assert-Architecture ($agentController -match 'claude_vscode_enabled') `
	'Codex integration must keep Claude Code VS Code state separate.'
Assert-Architecture ($agentController -match 'claude_terminal_enabled') `
	'Codex integration must keep Claude Code terminal state separate.'
Assert-Architecture ($agentController -match 'gemini_terminal_enabled') `
	'Codex integration must keep Gemini CLI terminal state separate.'
Assert-Architecture ($agentController -match '_run_gemini_cli_configuration_tool') `
	'Codex integration must configure Gemini CLI through its installer.'
Assert-Architecture ((Read-Source 'tools/codex_notify.ps1') -match 'Get-ProcessTreeContainsVsCode') `
	'Codex notification routing must detect VS Code hosts in the process tree.'
Assert-Architecture ($agentController -match 'agy_terminal_enabled') `
	'Codex integration must keep Antigravity CLI terminal state separate.'
Assert-Architecture ($agentController -match '_run_antigravity_cli_configuration_tool') `
	'Codex integration must configure Antigravity CLI through its installer.'
Assert-Architecture ($agentRouter -match 'gemini_terminal') `
	'Agent notification routing must define a Gemini CLI terminal target.'
Assert-Architecture ($agentRouter -match 'agy_terminal') `
	'Agent notification routing must define an Antigravity CLI terminal target.'
Assert-Architecture ($agentController -match 'AgentNotificationRouterScript\.is_notification_enabled') `
	'Codex notifications must be filtered by source target and enabled state.'
Assert-Architecture ($agentRouter -match 'class_name AgentNotificationRouter') `
	'Agent notification routing rules must have their own cohesive module.'
Assert-Architecture ($agentController -match 'AgentNotificationRouterScript') `
	'Codex integration must delegate Agent routing rules to the shared router.'
Assert-Architecture ($agentController -notmatch 'func _normalize_agent|func _target_display_name') `
	'Codex integration must not own cross-Agent display and normalization rules.'
Assert-Architecture ($agentController -match 'ClassDB\.instantiate\("WindowsWindowActivator"\)') `
	'Codex focus must use the in-process Windows GDExtension.'
Assert-Architecture ($agentController -match 'focus_executable') `
	'Codex focus must verify native window activation.'
Assert-Architecture ($agentController -notmatch 'SetForegroundWindow|AppActivate|EncodedCommand|WindowsForegroundAppMonitor') `
	'Codex runtime integration must not launch a PowerShell foreground helper.'
Assert-Architecture ($windowsActivator -match 'QueryFullProcessImageNameW') `
	'The native activator must match windows by configured executable path.'
Assert-Architecture ($windowsActivator -match 'SetForegroundWindow') `
	'The native activator must use the Win32 foreground API in-process.'
Assert-Architecture ($windowsActivator -match 'is_executable_foreground') `
	'The native activator must support a one-shot foreground check.'
Assert-Architecture ($windowsActivator -notmatch 'powershell|cmd\.exe|CreateProcess') `
	'The native activator must not launch a shell or helper process.'
Assert-Architecture ($main -match 'AGENT_FOREGROUND_NOTIFICATION_DURATION_SECONDS := 3\.0') `
	'Codex notifications must use a three-second foreground duration.'
Assert-Architecture ($windowsExtension -match 'windows\.debug\.x86_64') `
	'The Windows GDExtension must provide an x64 debug library.'
Assert-Architecture ($windowsExtension -match 'windows\.release\.x86_64') `
	'The Windows GDExtension must provide an x64 release library.'
Assert-Architecture ($releasePreparation -match [regex]::Escape('open_desktop_pet_windows.windows.template_release.x86_64.dll')) `
	'The release package must include the native Windows GDExtension.'

& git -C $projectRoot diff --check
if ($LASTEXITCODE -ne 0) {
	throw 'git diff --check failed.'
}

Write-Output 'ARCHITECTURE_CHECKS_OK'
