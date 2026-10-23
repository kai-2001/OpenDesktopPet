class_name UpdateCheckCoordinator
extends Node

## Owns the single GitHub release request, its schedule, and the few local
## settings it needs. Automatic checks are opt-in; a manual check only runs
## when the user presses the button. See UpdateCheckService for what the
## request contains.

const UpdateCheckServiceScript = preload("res://scripts/update_check_service.gd")
const UI_SETTINGS_PATH := "user://ui_settings.cfg"
const SETTINGS_SECTION := "update"
const AUTO_CHECK_INTERVAL_SECONDS := 24 * 60 * 60
const STARTUP_CHECK_DELAY_SECONDS := 30.0

const STATE_IDLE := "idle"
const STATE_CHECKING := "checking"

signal state_changed
signal update_found(version: String)

var auto_check_enabled := false
var skipped_version := ""
var notified_version := ""
var latest_version := ""
var last_check_at := 0
var last_result := ""
var state := STATE_IDLE
# Tests point this at a throwaway file so they never touch real settings.
var settings_path := UI_SETTINGS_PATH
var _request: HTTPRequest
var _startup_timer: Timer
var _automatic_request := false


func _ready() -> void:
	load_settings()
	_request = HTTPRequest.new()
	_request.name = "GitHubReleaseRequest"
	_request.use_threads = true
	_request.max_redirects = 0
	_request.body_size_limit = UpdateCheckServiceScript.MAX_RESPONSE_BYTES
	_request.timeout = UpdateCheckServiceScript.REQUEST_TIMEOUT_SECONDS
	add_child(_request)
	_request.request_completed.connect(_on_request_completed)
	_startup_timer = Timer.new()
	_startup_timer.one_shot = true
	_startup_timer.wait_time = STARTUP_CHECK_DELAY_SECONDS
	add_child(_startup_timer)
	_startup_timer.timeout.connect(_run_scheduled_check)
	# Tests run headless and must never reach the network on their own.
	if DisplayServer.get_name() != "headless":
		_startup_timer.start()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return
	auto_check_enabled = bool(config.get_value(SETTINGS_SECTION, "auto_check", false))
	skipped_version = String(config.get_value(SETTINGS_SECTION, "skipped_version", ""))
	notified_version = String(config.get_value(SETTINGS_SECTION, "notified_version", ""))
	latest_version = String(config.get_value(SETTINGS_SECTION, "latest_version", ""))
	last_check_at = int(config.get_value(SETTINGS_SECTION, "last_check_at", 0))
	# A version saved before the user upgraded is no longer an update.
	if not UpdateCheckServiceScript.is_newer(
		latest_version, UpdateCheckServiceScript.current_version()
	):
		latest_version = ""


func set_auto_check_enabled(value: bool) -> void:
	auto_check_enabled = value
	_save_settings()
	state_changed.emit()


## Starts a check unless one is already running. Automatic checks respect the
## opt-in setting and the daily limit; manual checks always run.
func check_now(automatic := false) -> bool:
	if state == STATE_CHECKING or _request == null:
		return false
	if automatic and not _is_scheduled_check_due():
		return false
	var error := _request.request(
		UpdateCheckServiceScript.LATEST_RELEASE_URL,
		PackedStringArray(UpdateCheckServiceScript.REQUEST_HEADERS),
		HTTPClient.METHOD_GET
	)
	if error != OK:
		last_result = UpdateCheckServiceScript.RESULT_FAILED
		state_changed.emit()
		return false
	_automatic_request = automatic
	state = STATE_CHECKING
	state_changed.emit()
	return true


func skip_latest_version() -> void:
	if latest_version.is_empty():
		return
	skipped_version = latest_version
	_save_settings()
	state_changed.emit()


func has_update() -> bool:
	return not latest_version.is_empty() and latest_version != skipped_version


func release_page_url() -> String:
	return UpdateCheckServiceScript.release_page_url(latest_version)


func status_text() -> String:
	if state == STATE_CHECKING:
		return "正在向 GitHub 查詢最新版本…"
	if has_update():
		return "有新版本 v%s 可以下載。" % latest_version
	match last_result:
		UpdateCheckServiceScript.RESULT_UP_TO_DATE:
			return "已是最新版本。"
		UpdateCheckServiceScript.RESULT_AVAILABLE:
			return "已略過 v%s，之後有更新的版本會再提示。" % skipped_version
		UpdateCheckServiceScript.RESULT_RATE_LIMITED:
			return "GitHub 暫時限制查詢次數，請稍後再試。"
		UpdateCheckServiceScript.RESULT_FAILED:
			return "無法連線到 GitHub，請確認網路後再試。"
	if last_check_at > 0:
		return "上次檢查：%s" % Time.get_datetime_string_from_unix_time(
			last_check_at + _local_offset_seconds(), true
		)
	return "尚未檢查。"


func apply_result(evaluation: Dictionary, automatic: bool) -> void:
	state = STATE_IDLE
	last_result = String(evaluation.get("status", UpdateCheckServiceScript.RESULT_FAILED))
	if last_result == UpdateCheckServiceScript.RESULT_AVAILABLE \
			or last_result == UpdateCheckServiceScript.RESULT_UP_TO_DATE:
		last_check_at = int(Time.get_unix_time_from_system())
	if last_result == UpdateCheckServiceScript.RESULT_AVAILABLE:
		latest_version = String(evaluation.get("version", ""))
	elif last_result == UpdateCheckServiceScript.RESULT_UP_TO_DATE:
		latest_version = ""
	var should_notify := has_update() and (
		not automatic or latest_version != notified_version
	)
	if should_notify:
		notified_version = latest_version
	_save_settings()
	state_changed.emit()
	if should_notify:
		update_found.emit(latest_version)


func _is_scheduled_check_due() -> bool:
	if not auto_check_enabled:
		return false
	var now := int(Time.get_unix_time_from_system())
	return last_check_at <= 0 or now - last_check_at >= AUTO_CHECK_INTERVAL_SECONDS


func _run_scheduled_check() -> void:
	check_now(true)


func _on_request_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	apply_result(
		UpdateCheckServiceScript.evaluate_response(
			result, response_code, body, UpdateCheckServiceScript.current_version()
		),
		_automatic_request
	)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(settings_path)
	config.set_value(SETTINGS_SECTION, "auto_check", auto_check_enabled)
	config.set_value(SETTINGS_SECTION, "skipped_version", skipped_version)
	config.set_value(SETTINGS_SECTION, "notified_version", notified_version)
	config.set_value(SETTINGS_SECTION, "latest_version", latest_version)
	config.set_value(SETTINGS_SECTION, "last_check_at", last_check_at)
	config.save(settings_path)


func _local_offset_seconds() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
