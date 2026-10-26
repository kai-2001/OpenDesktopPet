extends SceneTree

const CatalogScript = preload("res://scripts/agent_channel_catalog.gd")
const ControllerScript = preload("res://scripts/agent_integration_controller.gd")
const RouterScript = preload("res://scripts/agent_notification_router.gd")

const UI_SETTINGS_PATH := "user://ui_settings.cfg"
const TEST_PORT := 49873

var _failed := false
var _previous_ui_settings := PackedByteArray()
var _had_ui_settings := false


func _init() -> void:
	# Switching channels saves ui_settings.cfg; keep the user's copy intact.
	_had_ui_settings = FileAccess.file_exists(UI_SETTINGS_PATH)
	if _had_ui_settings:
		_previous_ui_settings = FileAccess.get_file_as_bytes(UI_SETTINGS_PATH)
	call_deferred("_run")


func _run() -> void:
	_check_unique_fields()
	_check_references()
	_check_router_keys()
	_check_controller_switches()
	_restore_ui_settings()
	if _failed:
		return
	print("AGENT_CHANNEL_CATALOG_TEST_OK")
	quit(0)


func _check_unique_fields() -> void:
	for field: String in ["id", "property", "settings_section", "runtime_key", "node_name"]:
		var seen := {}
		for channel: Dictionary in CatalogScript.CHANNELS:
			var value := String(channel[field])
			_assert_true(not value.is_empty(), "%s is set for every channel" % field)
			_assert_true(not seen.has(value), "%s %s is used once" % [field, value])
			seen[value] = true
	var target_seen := {}
	for target: Dictionary in CatalogScript.TARGETS:
		var target_id := String(target["target"])
		_assert_true(not target_seen.has(target_id), "target %s is listed once" % target_id)
		target_seen[target_id] = true


func _check_references() -> void:
	var targets := {}
	for target: Dictionary in CatalogScript.TARGETS:
		targets[target["target"]] = true
	var controller = ControllerScript.new()
	for target: Dictionary in CatalogScript.TARGETS:
		_assert_true(
			controller.get(target["property"]) is String,
			"target %s maps to a controller path field" % target["target"]
		)
	for setup: String in CatalogScript.SETUPS:
		var installer := String(CatalogScript.SETUPS[setup]["installer"])
		_assert_true(
			FileAccess.file_exists("res://tools/" + installer),
			"setup %s installer %s ships in tools/" % [setup, installer]
		)
	for channel: Dictionary in CatalogScript.CHANNELS:
		_assert_true(
			targets.has(channel["target"]),
			"channel %s uses a listed target" % channel["id"]
		)
		_assert_true(
			CatalogScript.SETUPS.has(channel["setup"]),
			"channel %s uses a listed setup" % channel["id"]
		)
		_assert_true(
			controller.get(channel["property"]) is bool,
			"channel %s maps to a controller switch" % channel["id"]
		)


func _check_router_keys() -> void:
	# Every runtime key must be reachable by some notification, and every key
	# the router can produce must have a switch, or notifications get lost.
	var routed := {}
	for source: String in ["codex", "copilot", "opencode", "claude", "gemini", "agy", "pi"]:
		for target: Dictionary in CatalogScript.TARGETS:
			routed[RouterScript.notification_key(source, source, target["target"])] = true
	var catalog_keys := {}
	for channel: Dictionary in CatalogScript.CHANNELS:
		catalog_keys[channel["runtime_key"]] = true
		_assert_true(
			routed.has(channel["runtime_key"]),
			"router can deliver %s notifications" % channel["runtime_key"]
		)
	for key: String in routed:
		_assert_true(catalog_keys.has(key), "router key %s has a switch" % key)


func _check_controller_switches() -> void:
	# Headless runs skip installers, so each switch must flip only its own field.
	for channel: Dictionary in CatalogScript.CHANNELS:
		var controller = ControllerScript.new()
		controller.port = TEST_PORT
		# Valid paths keep enabling a channel from starting executable detection.
		for target: Dictionary in CatalogScript.TARGETS:
			controller.set(target["property"], OS.get_executable_path())
		controller.set_channel_enabled(channel["id"], true)
		for other: Dictionary in CatalogScript.CHANNELS:
			var expected: bool = other["id"] == channel["id"]
			_assert_true(
				controller.is_channel_enabled(other["id"]) == expected,
				"enabling %s leaves %s %s" % [channel["id"], other["id"], expected]
			)
			_assert_true(
				bool(controller._runtime_enabled_targets()[other["runtime_key"]]) == expected,
				"enabling %s publishes %s as %s" % [channel["id"], other["runtime_key"], expected]
			)
		_assert_true(controller.is_any_enabled(), "%s counts as enabled" % channel["id"])
		controller.set_channel_enabled(channel["id"], false)
		_assert_true(not controller.is_any_enabled(), "%s turns off again" % channel["id"])
		controller.shutdown()


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
	push_error("AGENT_CHANNEL_CATALOG_TEST_FAILED: " + message)
	quit(1)
