extends SceneTree

const ServiceScript = preload("res://scripts/codex_hook_trust_service.gd")


func _init() -> void:
	var service = ServiceScript.new()
	var available := service.parse_status_output(
		"{\"status\":\"available\",\"message\":\"ok\",\"enabled\":true}"
	)
	_assert_true(service.is_available(available), "available Codex executable is detected")
	var trusted := service.parse_status_output(
		"diagnostic\n{\"status\":\"trusted\",\"message\":\"ok\","
		+ "\"enabled\":true,\"trust_status\":\"trusted\"}"
	)
	_assert_true(service.is_trusted(trusted), "trusted and enabled hook is ready")
	var modified := service.parse_status_output(
		"{\"status\":\"modified\",\"message\":\"changed\",\"enabled\":true}"
	)
	_assert_true(not service.is_trusted(modified), "modified hook requires review")
	_assert_true(
		String(modified.get("status", "")) == ServiceScript.STATUS_MODIFIED,
		"modified trust state is preserved"
	)
	var disabled := service.parse_status_output(
		"{\"status\":\"trusted\",\"message\":\"off\",\"enabled\":false}"
	)
	_assert_true(not service.is_trusted(disabled), "disabled trusted hook is not ready")
	var malformed := service.parse_status_output("not-json")
	_assert_true(
		String(malformed.get("status", "")) == ServiceScript.STATUS_ERROR,
		"malformed output becomes an explicit error"
	)
	print("CODEX_HOOK_TRUST_SERVICE_TEST_OK")
	quit(0)


func _assert_true(value: bool, message: String) -> void:
	if not value:
		printerr("CODEX_HOOK_TRUST_SERVICE_TEST_FAILED: " + message)
		quit(1)
