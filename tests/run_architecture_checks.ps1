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
$menu = Read-Source 'scripts/pet_menu_builder.gd'
$main = Read-Source 'scripts/main.gd'
$state = Read-Source 'scripts/pet_state.gd'
$visual = Read-Source 'scripts/pet_visual.gd'
$visualScale = Read-Source 'scripts/pet_visual_scale.gd'
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
$codexTrustService = Read-Source 'scripts/codex_hook_trust_service.gd'
$windowsActivator = Read-Source 'native/windows/src/windows_window_activator.cpp'
$windowsExtension = Read-Source 'native/windows/windows_window_activator.gdextension'
$releasePreparation = Read-Source 'tools/prepare_windows_release.ps1'
$exportPresets = Read-Source 'export_presets.cfg'

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
Assert-Architecture ($statsCoordinator -notmatch 'HSlider|create_slider_grabber_texture') `
	'The shared details theme must not style the visual-size slider globally.'
Assert-Architecture ($details -match 'visual_scale_theme\.set_stylebox\("slider", "HSlider"') `
	'The visual-size slider must own its track styling locally.'
Assert-Architecture ($details -match 'visual_scale_theme\.set_icon\(\s*"grabber", "HSlider"') `
	'The visual-size slider must use the Godot Theme icon API.'
Assert-Architecture ($details -notmatch 'set_texture|get_theme_texture') `
	'The details UI must not use nonexistent Godot Theme texture APIs.'
Assert-Architecture ($details -match 'visual_scale_slider\.gui_input\.connect') `
	'Only the visual-size slider may capture wheel input.'
Assert-Architecture ($details -notmatch 'visual_scale_panel\.gui_input\.connect') `
	'The visual-size settings row must not capture wheel input.'
Assert-Architecture ($details -match 'visual_scale_slider\.scrollable = false') `
	'The visual-size slider must pass wheel scrolling to the settings page.'
Assert-Architecture ($details -notmatch 'visual_scale_panel|visual_scale_panel_style') `
	'Visual-size controls must use the standard settings layout without a card background.'
Assert-Architecture ($details -match 'focus_mode_check_box\.text = "') `
	'The focus-mode setting must have a visible label.'
Assert-Architecture ($details -notmatch 'focus_mode_check_box\.text = .*idle') `
	'The focus-mode label must not expose implementation wording.'
Assert-Architecture ($menu -notmatch 'SIZE_SMALLER_ITEM_ID|SIZE_LARGER_ITEM_ID') `
	'The details settings must be the only visual-size adjustment surface.'
Assert-Architecture ($visualScale -match 'class_name PetVisualScale') `
	'Visual-size limits must have one shared policy module.'
Assert-Architecture ($state -match 'PetVisualScaleScript' -and $visual -match 'PetVisualScaleScript') `
	'State and rendering must share the visual-size policy.'
Assert-Architecture ($state -notmatch 'PetVisualScript') `
	'Gameplay state must not depend on the visual renderer.'
Assert-Architecture ($state -notmatch 'func change_visual_size' -and $visual -notmatch 'func change_visual_size') `
	'Obsolete incremental visual-size entry points must stay removed.'
Assert-Architecture ($visual -notmatch '_keep_frame_inside_viewport|_axis_containment_shift') `
	'Frame changes must not apply a second per-frame viewport shift.'
Assert-Architecture ($visual -match 'desktop_canvas_origin') `
	'Window resizing must preserve one desktop-space canvas anchor.'
Assert-Architecture ($visual -match 'func _activate_action_geometry') `
	'Each animation must reserve its complete geometry at the action boundary.'
Assert-Architecture ($visual -match 'func _geometry_frames_for_action') `
	'Action geometry must include every configured animation phase.'
Assert-Architecture ($visual -notmatch '_grow_window_to_fit_frame') `
	'Animation frames must not resize the native window independently.'
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
Assert-Architecture `
	($main -match '_say_configured_dialogue\("idle", 2\.5\)') `
	'Idle speech must be opt-in through character dialogue.'
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
Assert-Architecture ((Read-Source 'tools/codex_stop_notify.ps1') -match 'Test-ProcessTreeContainsVsCode') `
	'Codex notification routing must detect VS Code hosts in the process tree.'
Assert-Architecture ($agentController -match 'RUNTIME_FILE_NAME') `
	'Agent notifications must publish one runtime registration.'
Assert-Architecture ($agentController -notmatch 'func _write_bridge_files') `
	'Agent notifications must not write duplicate bridge flag files.'
Assert-Architecture ((Read-Source 'tools/codex_stop_notify.ps1') -match 'Get-OpenDesktopPetRuntime') `
	'Codex notifications must read the shared runtime registration.'
Assert-Architecture ((Read-Source 'tools/codex_stop_notify.ps1') -match "hook_event_name -ne 'Stop'") `
	'Codex notifications must be driven by the completed-chat Stop hook.'
Assert-Architecture ((Read-Source 'tools/install_codex_integration.ps1') -match 'Remove-LegacyNotifyIntegration') `
	'Codex Stop-hook installation must remove the obsolete notify integration.'
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
Assert-Architecture ($agentController -match 'CodexHookTrustServiceScript') `
	'Codex integration must delegate Hook trust protocol handling to a cohesive service.'
Assert-Architecture ($codexTrustService -match 'parse_status_output') `
	'Codex Hook trust status parsing must be independently testable.'
Assert-Architecture ((Read-Source 'tools/codex_hook_review.ps1') -match '(?s)Start-Process.*-WindowStyle Normal') `
	'Codex Hook review must explicitly create a visible Windows console.'
Assert-Architecture ((Read-Source 'tools/codex_hook_review.ps1') -match 'OpenDesktopPetCodexHookReview') `
	'Codex Hook review must prevent duplicate interactive windows.'
Assert-Architecture ((Read-Source 'tools/codex_hook_review.ps1') -match "TERM = 'xterm-256color'") `
	'Codex Hook review must launch its TUI with an interactive terminal mode.'
Assert-Architecture ($codexTrustService -notmatch '"-NoExit"') `
	'Codex Hook review must not leave an empty PowerShell host behind.'
Assert-Architecture ((Read-Source 'tools/codex_hook_review.ps1') -match "method = 'hooks/list'") `
	'Codex Hook trust checks must inspect the Codex-reported status.'
Assert-Architecture ((Read-Source 'tools/codex_hook_review.ps1') -match "ValidateSet\('Availability', 'Status', 'Launch', 'Review'\)") `
	'Codex Hook review must provide a separate executable availability check.'
Assert-Architecture ($agentController -match '(?s)func _run_codex_setup_task.*get_codex_availability_status\(\).*_run_codex_configuration_tool.*get_codex_hook_trust_status\(\)') `
	'Codex availability must be checked before installing or validating hooks.'
Assert-Architecture ($agentController -match '(?s)Thread\.new\(\).*_run_codex_setup_task') `
	'Codex setup and Hook status checks must not block the UI thread.'
Assert-Architecture ($agentController -notmatch 'CODEX_TRUST_POLL_INTERVALS_MS|_poll_codex_trust_monitor|_schedule_next_codex_trust_check') `
	'Codex Hook trust must not be checked by background polling.'
Assert-Architecture ($agentController -match 'func recheck_pending_codex_trust') `
	'Codex Hook trust must expose an explicit user-triggered recheck action.'
Assert-Architecture ($agentController -match 'CODEX_SETUP_SETTINGS_SECTION.*pending_target') `
	'Pending Codex notification setup must survive closing the review window or restarting the pet.'
Assert-Architecture ($agentController -match '(?s)is_trusted\(status\).*_set_codex_target_enabled\(target, true\).*codex_trust_ready\.emit') `
	'Every successful Codex trust check must enable the requested target and report success.'
Assert-Architecture ((Read-Source 'tools/codex_hook_review.ps1') -match '& \$codexExecutable --no-alt-screen') `
	'Codex Hook review must launch the interactive Codex TUI.'
Assert-Architecture ((Read-Source 'tools/codex_hook_review.ps1') -notmatch "--no-alt-screen '/hooks'") `
	'Codex Hook review must not submit /hooks as an Agent prompt.'
Assert-Architecture ((Read-Source 'tools/codex_hook_review.ps1') -match [regex]::Escape('.vscode\extensions')) `
	'Codex Hook review must support the executable bundled with the VS Code extension.'
Assert-Architecture ($main -notmatch '_reopen_codex_trust_dialog') `
	'Opening Codex Hook review must not immediately reopen the blocking trust dialog.'
Assert-Architecture ($releasePreparation -match 'codex_hook_review\.ps1') `
	'Windows releases must include the Codex Hook review helper.'
Assert-Architecture ($agentController -notmatch 'func _normalize_agent|func _target_display_name') `
	'Codex integration must not own cross-Agent display and normalization rules.'
Assert-Architecture ($agentController -match 'ClassDB\.instantiate\("WindowsWindowActivator"\)') `
	'Codex focus must use the in-process Windows GDExtension.'
Assert-Architecture ($agentController -match 'focus_executable') `
	'Codex focus must verify native window activation.'
Assert-Architecture ($agentController -notmatch 'SetForegroundWindow|AppActivate|WindowsForegroundAppMonitor') `
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
Assert-Architecture ($exportPresets -match 'exclude_filter=.*tmp/\*') `
	'The public export must exclude local temporary and test artifacts.'

& git -C $projectRoot diff --check
if ($LASTEXITCODE -ne 0) {
	throw 'git diff --check failed.'
}

Write-Output 'ARCHITECTURE_CHECKS_OK'
