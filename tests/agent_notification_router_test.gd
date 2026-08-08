extends SceneTree

const RouterScript = preload("res://scripts/agent_notification_router.gd")


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
	print("AGENT_NOTIFICATION_ROUTER_TEST_OK")
	quit(0)


func _assert_equal(actual: Variant, expected: Variant) -> void:
	if actual != expected:
		_fail("expected %s, got %s" % [str(expected), str(actual)])


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)


func _fail(message: String) -> void:
	printerr("AGENT_NOTIFICATION_ROUTER_TEST_FAILED: " + message)
	quit(1)
