extends SceneTree

# A failed Codex hook query (for example a slow app-server start) is not an
# answer about trust. The pet must retry it, and when it still fails, report
# that the check failed instead of asking the user to trust hooks that may
# already be trusted.

const RecordingControllerScript = preload(
	"res://tests/support/recording_agent_integration_controller.gd"
)
const FakeCodexHookTrustServiceScript = preload(
	"res://tests/support/fake_codex_hook_trust_service.gd"
)
const UI_SETTINGS_PATH := "user://ui_settings.cfg"
const TEST_PORT := 49874

var _failed := false
var _previous_ui_settings := PackedByteArray()
var _had_ui_settings := false
var _signals: Array[String] = []


func _init() -> void:
	_had_ui_settings = FileAccess.file_exists(UI_SETTINGS_PATH)
	if _had_ui_settings:
		_previous_ui_settings = FileAccess.get_file_as_bytes(UI_SETTINGS_PATH)
	RecordingControllerScript.home_root = ProjectSettings.globalize_path(
		"user://codex-trust-check-" + str(Time.get_ticks_usec())
	)
	call_deferred("_run")


func _run() -> void:
	var controller = await _enable_codex(1, 0, true)
	_assert_true(controller.codex_enabled, "one failed status query is retried")
	_assert_true(_signals.has("codex_trust_ready"), "the retried check reports success")
	_assert_true(not _signals.has("codex_trust_required"), "a retried success never asks for trust")
	_assert_true(
		_count_calls("trust query_status") == 2,
		"the failed status query runs exactly once more"
	)
	controller.shutdown()

	controller = await _enable_codex(2, 0, true)
	_assert_true(not controller.codex_enabled, "Codex stays off while its status is unknown")
	_assert_true(
		not controller.has_pending_codex_trust(),
		"an unknown status does not start the trust flow"
	)
	_assert_true(
		_signals.has("codex_status_check_failed"),
		"a status query that keeps failing is reported as a failed check"
	)
	_assert_true(
		not _signals.has("codex_trust_required"),
		"a failed check never asks the user to trust the hooks"
	)
	controller.shutdown()

	controller = await _enable_codex(0, 2, true)
	_assert_true(not controller.codex_enabled, "Codex stays off when availability is unknown")
	_assert_true(
		_signals.has("codex_status_check_failed"),
		"an availability query that keeps failing is reported as a failed check"
	)
	_assert_true(
		not _signals.has("codex_unavailable"),
		"a failed availability query does not claim Codex is missing"
	)
	controller.shutdown()

	controller = await _enable_codex(0, 0, false)
	_assert_true(
		_signals.has("codex_trust_required"),
		"an untrusted answer still asks the user to trust the hooks"
	)
	_assert_true(controller.has_pending_codex_trust(), "an untrusted answer waits for trust")
	FakeCodexHookTrustServiceScript.status_errors = 2
	_signals.clear()
	_assert_true(controller.recheck_pending_codex_trust(), "recheck starts")
	await _wait_for_setup(controller)
	_assert_true(
		_signals.has("codex_status_check_failed"),
		"a recheck that keeps failing is reported as a failed check"
	)
	_assert_true(
		not _signals.has("codex_trust_required"),
		"a failed recheck does not repeat the trust instructions"
	)
	_assert_true(
		controller.has_pending_codex_trust(),
		"a failed recheck keeps the pending target so the user can check again"
	)
	controller.shutdown()

	_restore_ui_settings()
	if _failed:
		return
	print("CODEX_TRUST_CHECK_TEST_OK")
	quit(0)


func _enable_codex(status_errors: int, availability_errors: int, trusted: bool):
	RecordingControllerScript.reset_log()
	RecordingControllerScript.installer_succeeds = true
	RecordingControllerScript.configured = {"install_codex_integration.ps1": true}
	FakeCodexHookTrustServiceScript.available = true
	FakeCodexHookTrustServiceScript.trusted = trusted
	FakeCodexHookTrustServiceScript.status_errors = status_errors
	FakeCodexHookTrustServiceScript.availability_errors = availability_errors
	_signals.clear()
	var controller = RecordingControllerScript.new()
	controller.port = TEST_PORT
	for signal_name: String in [
		"codex_trust_ready",
		"codex_trust_required",
		"codex_unavailable",
		"configuration_failed",
		"codex_status_check_failed",
	]:
		if controller.has_signal(signal_name):
			controller.connect(
				signal_name,
				func(_a = null, _b = null, _c = null) -> void: _signals.append(signal_name)
			)
	controller.set_channel_enabled("codex", true)
	await _wait_for_setup(controller)
	return controller


func _wait_for_setup(controller) -> void:
	for _frame in 300:
		await process_frame
		controller.poll()
		if not controller.is_codex_setup_busy():
			return
	_assert_true(false, "Codex setup finished")


func _count_calls(entry: String) -> int:
	var count := 0
	for logged: String in RecordingControllerScript.take_log():
		if logged.ends_with(entry):
			count += 1
	return count


func _restore_ui_settings() -> void:
	if _had_ui_settings:
		var file := FileAccess.open(UI_SETTINGS_PATH, FileAccess.WRITE)
		file.store_buffer(_previous_ui_settings)
		file.close()
	elif FileAccess.file_exists(UI_SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UI_SETTINGS_PATH))


func _assert_true(value: bool, message: String) -> void:
	if value or _failed:
		return
	_failed = true
	_restore_ui_settings()
	push_error("CODEX_TRUST_CHECK_TEST_FAILED: " + message)
	quit(1)
