extends SceneTree

const RouterScript = preload("res://scripts/agent_notification_router.gd")
const ControllerScript = preload("res://scripts/agent_integration_controller.gd")

var _received_notifications: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_assert_equal(RouterScript.normalize_agent("copilot_vscode"), "copilot")
	_assert_equal(RouterScript.normalize_agent("opencode"), "opencode")
	_assert_equal(RouterScript.normalize_agent("claude_code"), "claude")
	_assert_equal(RouterScript.normalize_agent("antigravity_cli"), "agy")
	_assert_equal(RouterScript.normalize_agent("agy"), "agy")
	_assert_equal(RouterScript.normalize_agent("gemini_cli"), "gemini")
	_assert_equal(RouterScript.normalize_agent("codex_vscode"), "codex")
	_assert_equal(RouterScript.normalize_agent("pi"), "pi")
	_assert_equal(
		RouterScript.normalize_target_app("opencode-desktop"),
		RouterScript.TARGET_OPENCODE_APP
	)
	_assert_equal(RouterScript.normalize_target_app("shell"), RouterScript.TARGET_TERMINAL)
	_assert_equal(
		RouterScript.normalize_target_app("claude-desktop"),
		RouterScript.TARGET_CLAUDE_APP
	)
	_assert_equal(RouterScript.normalize_target_app("unknown"), RouterScript.TARGET_VSCODE)

	var enabled_by_key := {
		"codex_vscode": true,
		"codex_app": false,
		"codex_terminal": false,
		"copilot": true,
		"opencode_terminal": false,
		"opencode_vscode": true,
		"opencode_app": false,
		"claude_terminal": false,
		"claude_vscode": true,
		"claude_app": false,
		"gemini_terminal": true,
		"agy_terminal": true,
		"pi_codex_terminal": true,
	}
	_assert_true(
		RouterScript.is_notification_enabled(
			"codex_vscode", "codex", RouterScript.TARGET_VSCODE, enabled_by_key
		),
		"Codex VS Code route is enabled"
	)
	_assert_true(
		RouterScript.is_notification_enabled(
			"copilot_vscode", "copilot", RouterScript.TARGET_VSCODE, enabled_by_key
		),
		"Copilot route is enabled"
	)
	_assert_true(
		RouterScript.is_notification_enabled(
			"opencode", "opencode", RouterScript.TARGET_VSCODE, enabled_by_key
		),
		"OpenCode VS Code route is enabled"
	)
	_assert_true(
		RouterScript.is_notification_enabled(
			"claude_code", "claude", RouterScript.TARGET_VSCODE, enabled_by_key
		),
		"Claude Code VS Code route is enabled"
	)
	_assert_true(
		not RouterScript.is_notification_enabled(
			"opencode", "opencode", RouterScript.TARGET_TERMINAL, enabled_by_key
		),
		"OpenCode terminal route remains independently disabled"
	)
	_assert_true(
		RouterScript.is_notification_enabled(
			"gemini_cli", "gemini", RouterScript.TARGET_TERMINAL, enabled_by_key
		),
		"Gemini CLI terminal route is enabled"
	)
	_assert_true(
		RouterScript.is_notification_enabled(
			"antigravity_cli", "agy", RouterScript.TARGET_TERMINAL, enabled_by_key
		),
		"Antigravity CLI terminal route is enabled"
	)
	_assert_true(
		RouterScript.is_notification_enabled(
			"pi", "codex", RouterScript.TARGET_TERMINAL, enabled_by_key
		),
		"Pi terminal route is enabled"
	)

	var controller = ControllerScript.new()
	controller.claude_app_enabled = true
	controller.notification_received.connect(_on_notification_received)
	controller._handle_notification({
		"type": "agent-error",
		"source": "claude_code",
		"agent": "claude",
		"target_app": RouterScript.TARGET_CLAUDE_APP,
		"event_id": "claude:app:error-test",
	})
	_assert_equal(_received_notifications.size(), 1)
	_assert_equal(_received_notifications[0].reaction_action, "idle")
	_assert_equal(_received_notifications[0].target_app, RouterScript.TARGET_CLAUDE_APP)
	_assert_equal(_received_notifications[0].agent, "claude")
	_assert_true(
		String(_received_notifications[0].message).contains("發生錯誤"),
		"agent-error should emit an error notification"
	)
	controller.pi_codex_enabled = true
	controller._handle_notification({
		"type": "agent-turn-complete",
		"source": "pi",
		"agent": "pi",
		"target_app": RouterScript.TARGET_TERMINAL,
		"event_id": "pi:test:complete",
	})
	_assert_equal(_received_notifications.size(), 2)
	_assert_true(
		String(_received_notifications[1].message).contains("Pi"),
		"Pi completion should identify the Pi source"
	)
	print("AGENT_NOTIFICATION_ROUTER_TEST_OK")
	quit(0)


func _on_notification_received(
	message: String, reaction_action: String, target_app: String, agent: String
) -> void:
	_received_notifications.append({
		"message": message,
		"reaction_action": reaction_action,
		"target_app": target_app,
		"agent": agent,
	})


func _assert_equal(actual: Variant, expected: Variant) -> void:
	if actual != expected:
		_fail("expected %s, got %s" % [str(expected), str(actual)])


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)


func _fail(message: String) -> void:
	printerr("AGENT_NOTIFICATION_ROUTER_TEST_FAILED: " + message)
	quit(1)
