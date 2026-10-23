extends SceneTree

const ServiceScript = preload("res://scripts/update_check_service.gd")
const CoordinatorScript = preload("res://scripts/update_check_coordinator.gd")

var _failures := 0
var _settings_path := ""


func _init() -> void:
	_settings_path = "user://update-check-test-%d.cfg" % Time.get_ticks_usec()
	_test_versions()
	_test_privacy_contract()
	_test_response_evaluation()
	_test_coordinator()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_settings_path))
	if _failures > 0:
		printerr("UPDATE_CHECK_TEST_FAILED: %d assertion(s)" % _failures)
		quit(1)
		return
	print("UPDATE_CHECK_TEST_OK")
	quit(0)


func _test_versions() -> void:
	_assert_true(ServiceScript.parse_version("v0.9.6") == PackedInt32Array([0, 9, 6]), "tag parses")
	_assert_true(ServiceScript.parse_version("1.10.0") == PackedInt32Array([1, 10, 0]), "bare version parses")
	_assert_true(ServiceScript.parse_version("v1.0.0-beta").is_empty(), "pre-release tags are rejected")
	_assert_true(ServiceScript.parse_version("latest").is_empty(), "non-version tags are rejected")
	_assert_true(ServiceScript.is_newer("0.9.10", "0.9.9"), "numeric comparison, not text")
	_assert_true(ServiceScript.is_newer("1.0.0", "0.99.99"), "major version wins")
	_assert_true(not ServiceScript.is_newer("0.9.5", "0.9.5"), "same version is not newer")
	_assert_true(not ServiceScript.is_newer("0.9.4", "0.9.5"), "older version is not newer")
	_assert_true(
		ServiceScript.release_page_url("v0.9.6")
			== "https://github.com/kai-2001/OpenDesktopPet/releases/tag/v0.9.6",
		"release page is rebuilt from the version"
	)
	_assert_true(ServiceScript.release_page_url("evil").is_empty(), "invalid versions open nothing")


func _test_privacy_contract() -> void:
	var url := ServiceScript.LATEST_RELEASE_URL
	_assert_true(url.begins_with("https://api.github.com/repos/kai-2001/OpenDesktopPet/"), "fixed HTTPS endpoint")
	_assert_true(not url.contains("?") and not url.contains("#"), "no query string")
	var headers: Array = ServiceScript.REQUEST_HEADERS
	_assert_true(headers.size() == 2, "only the headers GitHub requires")
	_assert_true(headers.has("User-Agent: OpenDesktopPet"), "user agent has no version or engine")
	for header: String in headers:
		var lowered := header.to_lower()
		_assert_true(not lowered.begins_with("cookie"), "no cookies")
		_assert_true(not lowered.begins_with("authorization"), "no credentials")
		_assert_true(not header.contains(ServiceScript.current_version()), "headers omit the installed version")


func _test_response_evaluation() -> void:
	var success := HTTPRequest.RESULT_SUCCESS
	var available := ServiceScript.evaluate_response(
		success, 200, _json({"tag_name": "v99.0.0", "html_url": "https://evil.example/"}), "0.9.5"
	)
	_assert_true(available["status"] == ServiceScript.RESULT_AVAILABLE, "newer release is available")
	_assert_true(available["version"] == "99.0.0", "version is normalized")
	_assert_true(
		ServiceScript.release_page_url(available["version"]).begins_with(ServiceScript.RELEASE_PAGE_PREFIX),
		"a foreign html_url is never used"
	)
	var current := ServiceScript.evaluate_response(success, 200, _json({"tag_name": "v0.9.5"}), "0.9.5")
	_assert_true(current["status"] == ServiceScript.RESULT_UP_TO_DATE, "same release is up to date")
	var draft := ServiceScript.evaluate_response(
		success, 200, _json({"tag_name": "v99.0.0", "draft": true}), "0.9.5"
	)
	_assert_true(draft["status"] == ServiceScript.RESULT_UP_TO_DATE, "drafts are ignored")
	var prerelease := ServiceScript.evaluate_response(
		success, 200, _json({"tag_name": "v99.0.0", "prerelease": true}), "0.9.5"
	)
	_assert_true(prerelease["status"] == ServiceScript.RESULT_UP_TO_DATE, "pre-releases are ignored")
	_assert_true(
		ServiceScript.evaluate_response(success, 200, _json({"tag_name": "nightly"}), "0.9.5")["status"]
			== ServiceScript.RESULT_FAILED,
		"unexpected tags fail closed"
	)
	_assert_true(
		ServiceScript.evaluate_response(success, 403, PackedByteArray(), "0.9.5")["status"]
			== ServiceScript.RESULT_RATE_LIMITED,
		"rate limits are reported"
	)
	_assert_true(
		ServiceScript.evaluate_response(success, 500, PackedByteArray(), "0.9.5")["status"]
			== ServiceScript.RESULT_FAILED,
		"server errors fail"
	)
	_assert_true(
		ServiceScript.evaluate_response(success, 200, "not json".to_utf8_buffer(), "0.9.5")["status"]
			== ServiceScript.RESULT_FAILED,
		"invalid JSON fails"
	)
	_assert_true(
		ServiceScript.evaluate_response(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray(), "0.9.5")["status"]
			== ServiceScript.RESULT_FAILED,
		"offline fails quietly"
	)


func _test_coordinator() -> void:
	var coordinator = CoordinatorScript.new()
	coordinator.settings_path = _settings_path
	_assert_true(not coordinator.auto_check_enabled, "automatic checks are opt-in")
	_assert_true(not coordinator._is_scheduled_check_due(), "nothing is scheduled while opted out")
	coordinator.set_auto_check_enabled(true)
	_assert_true(coordinator._is_scheduled_check_due(), "first automatic check is due")
	coordinator.last_check_at = int(Time.get_unix_time_from_system()) - 60
	_assert_true(not coordinator._is_scheduled_check_due(), "automatic checks run at most daily")

	var found: Array[String] = []
	coordinator.update_found.connect(func(version: String) -> void: found.append(version))
	var newer := {"status": ServiceScript.RESULT_AVAILABLE, "version": "99.0.0"}
	coordinator.apply_result(newer, true)
	_assert_true(found == ["99.0.0"], "a new version is announced")
	coordinator.apply_result(newer, true)
	_assert_true(found.size() == 1, "automatic checks announce a version once")
	coordinator.apply_result(newer, false)
	_assert_true(found.size() == 2, "a manual check always reports")
	_assert_true(coordinator.has_update(), "update is offered")
	coordinator.skip_latest_version()
	_assert_true(not coordinator.has_update(), "a skipped version is hidden")

	var reloaded = CoordinatorScript.new()
	reloaded.settings_path = _settings_path
	reloaded.load_settings()
	_assert_true(reloaded.auto_check_enabled, "opt-in is saved")
	_assert_true(reloaded.skipped_version == "99.0.0", "skipped version is saved")
	var config := ConfigFile.new()
	config.load(_settings_path)
	_assert_true(
		config.get_section_keys("update").size() == 5,
		"only the five update fields are stored"
	)
	coordinator.free()
	reloaded.free()


func _json(data: Dictionary) -> PackedByteArray:
	return JSON.stringify(data).to_utf8_buffer()


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures += 1
		push_error("Assertion failed: " + message)
