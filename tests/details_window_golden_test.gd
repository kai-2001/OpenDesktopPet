extends SceneTree

# Characterization test for the details window. It drives the real main scene
# through the status, settings, Agent and character tabs and records every
# control in the window (structure, text, values, toggles, visibility), the
# saved pet state and settings, installed character packs, effect overrides
# and the pet's speech. The recording is compared with tests/fixtures; run
# with ODP_RECORD_DETAILS_GOLDEN=1 to rewrite it from the current behavior.

const GOLDEN_PATH := "res://tests/fixtures/details_window_golden.txt"
const UI_SETTINGS_PATH := "user://ui_settings.cfg"
const EFFECTS_PATH := "user://character_effects.json"
const PACKS_ROOT := "user://character_packs"
const TEST_PORT := 49875
const STATE_KEYS: Array[String] = [
	"level", "xp", "coins", "affection", "hunger", "thirst", "energy", "mood",
	"visual_scale", "auto_feeder_owned", "auto_feeder_enabled",
]
# The reminders tab shows today's date; it has its own visual and logic tests.
const SKIPPED_SUBTREES: Array[String] = ["待辦"]

var _main: Node
var _output: Array[String] = []
var _previous_state: Dictionary = {}
var _last_bubble_token := 0
var _failed := false
var _previous_ui_settings := PackedByteArray()
var _had_ui_settings := false
var _archive_path := ""
var _version := ""


func _init() -> void:
	_had_ui_settings = FileAccess.file_exists(UI_SETTINGS_PATH)
	if _had_ui_settings:
		_previous_ui_settings = FileAccess.get_file_as_bytes(UI_SETTINGS_PATH)
	_version = String(ProjectSettings.get_setting("application/config/version", ""))
	var config := ConfigFile.new()
	config.set_value("character", "selected_id", "open_desktop_pet_default")
	config.set_value("codex", "port", TEST_PORT)
	config.save(UI_SETTINGS_PATH)
	_archive_path = _write_codex_pet_archive()
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_main._idle_behavior_timer.stop()
	_hold_wishes()
	await _settle()
	await _step("startup")

	_main.call("_show_stats_window")
	await _settle()
	await _step("open details window on the status tab")

	await _press(_find_text("狀態", "Button", _main.pet.get_interaction_label("feed", "餵食")))
	await _step("feed from the status tab")
	await _press(_find_text("狀態", "Button", _main.pet.get_interaction_label("water", "喝水")))
	await _step("give water from the status tab")

	_main.state.data.affection = 100
	_main.state.data.coins = 600
	_main.state.changed.emit(_main.state.get_snapshot())
	await _settle()
	await _step("reach the auto feeder requirements")
	await _press(_find_text("狀態", "Button", "購買"))
	await _step("buy the auto feeder")
	await _toggle(_find("AutoFeederToggle") as Button, true)
	await _step("turn the auto feeder on")
	await _toggle(_find("AutoFeederToggle") as Button, false)
	await _step("turn the auto feeder off")

	_main.call("_select_stats_tab", 2)
	await _settle()
	await _step("select the settings tab")
	await _select_option(_find_option_with_item("60 FPS"), 2)
	await _step("choose 60 FPS")
	await _toggle(_find_text("設定", "CheckBox", "專注模式"), true)
	await _step("turn focus mode on")
	await _toggle(_find_text("設定", "CheckBox", "保持螢幕喚醒"), true)
	await _step("keep the screen awake")
	var slider := _find("VisualScaleSlider") as HSlider
	slider.value = 1.2
	await create_timer(0.4).timeout
	await _settle()
	await _step("enlarge the pet to 120%")
	await _select_option(_find_option_with_item("深色"), 1)
	await _step("switch the details window to the dark theme")
	await _toggle(_find_text("設定", "CheckBox", "專注模式"), false)
	await _step("turn focus mode off in the rebuilt window")
	await _select_option(_find_option_with_item("深色"), 0)
	await _step("switch back to the light theme")

	_main.call("_select_stats_tab", 3)
	await _settle()
	await _step("select the Agent tab")

	_main.call("_select_stats_tab", 4)
	await _settle()
	await _step("select the character tab")
	(_find("CharacterImportDialog") as FileDialog).file_selected.emit(_archive_path)
	await _settle()
	await _step("import a Codex Pet archive")
	await _select_character("golden-codex")
	await _step("select the imported Codex Pet")
	await _press(_find("CharacterUseButton"))
	await _step("use the imported Codex Pet")

	await _click_mask_header()
	await _step("open the eye mask editor")
	(_find("MaskEffectX") as SpinBox).value = 12.0
	(_find("MaskEffectScale") as SpinBox).value = 0.5
	await _settle()
	await _step("move and resize the eye mask")
	await _press(_find("MaskEffectApplyButton"))
	await _step("apply the eye mask")
	(_find("MaskEffectFeedbackDialog") as AcceptDialog).hide()
	await _click_mask_header()
	await _step("reopen the eye mask editor")
	await _press(_find("MaskEffectResetButton"))
	await _step("reset the eye mask")
	await _click_mask_header()
	await _step("close the eye mask editor without applying")

	(_find("CharacterImportDialog") as FileDialog).file_selected.emit(_archive_path)
	await _settle()
	await _step("import the same Codex Pet again")
	await _confirm("CharacterUpdateDialog")
	await _settle()
	await _step("confirm the update")

	await _select_character("golden-codex")
	await _press(_find("CharacterDeleteButton"))
	await _step("ask to delete the active Codex Pet")
	await _confirm("CharacterDeleteDialog")
	await _settle()
	await _step("delete the active Codex Pet")

	_main.call("_destroy_stats_window")
	await _settle()
	await _step("close details window")
	_main.call("_show_stats_window", 4)
	await _settle()
	await _step("reopen details window on the character tab")

	_main.call("_prepare_shutdown")
	await _settle()
	await _step("shutdown")
	_main.free()
	_main = null
	_finish()


func _hold_wishes() -> void:
	# Wishes appear at random times; keep them out of the recording.
	_main.state.data.wish_action = ""
	_main.state.data.wish_expires_at = 0
	_main.state.data.next_wish_at = int(Time.get_unix_time_from_system()) + 86400
	_main.state.changed.emit(_main.state.get_snapshot())


func _press(button: Node) -> void:
	if not button is BaseButton:
		_fail("missing button")
		return
	(button as BaseButton).pressed.emit()
	await _settle()


func _toggle(button: Node, enabled: bool) -> void:
	if not button is BaseButton:
		_fail("missing toggle")
		return
	(button as BaseButton).button_pressed = enabled
	await _settle()


func _select_option(option: OptionButton, index: int) -> void:
	if option == null:
		_fail("missing option button")
		return
	option.select(index)
	option.item_selected.emit(index)
	await _settle()


func _confirm(dialog_name: String) -> void:
	# Pressing OK closes the dialog before it reports the confirmation.
	var dialog := _find(dialog_name) as ConfirmationDialog
	dialog.hide()
	dialog.confirmed.emit()
	await _settle()


func _select_character(character_id: String) -> void:
	var list := _find("CharacterList") as ItemList
	for index in list.item_count:
		if list.get_item_text(index).ends_with("ID: " + character_id):
			list.select(index)
			list.item_selected.emit(index)
			await _settle()
			return
	_fail("character %s is not listed" % character_id)


func _click_mask_header() -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	(_find("MaskEffectHeader") as Control).gui_input.emit(click)
	await _settle()


func _settle() -> void:
	for _frame in 600:
		await process_frame
		if _main == null:
			return
		if not _main.state.is_action_busy() and not _main.pet.is_busy():
			break
	for _frame in 4:
		await process_frame


func _step(title: String) -> void:
	_output.append("## " + title)
	if _main != null and _main._bubble_token != _last_bubble_token:
		_last_bubble_token = _main._bubble_token
		if _main.bubble.visible:
			_output.append("  say " + _normalize(_main.bubble_label.text.replace(char(0x200B), "")))
		else:
			_output.append("  bubble hidden")
	var current := _capture_state()
	var keys := current.keys()
	keys.sort()
	for key: String in keys:
		if not _previous_state.has(key) or _previous_state[key] != current[key]:
			_output.append(("  %s = %s" % [key, current[key]]).strip_edges(false, true))
	var removed: Array = []
	for key: String in _previous_state.keys():
		if not current.has(key):
			removed.append(key)
	removed.sort()
	for key: String in removed:
		_output.append("  %s removed" % key)
	_previous_state = current


func _capture_state() -> Dictionary:
	var captured := {}
	var snapshot: Dictionary = _main.state.get_snapshot()
	for key: String in STATE_KEYS:
		captured["state." + key] = str(snapshot.get(key))
	captured["pet.character"] = String(_main.pet.get_character_id())
	captured["engine.max_fps"] = str(Engine.max_fps)
	captured["state.auto_care_quiet"] = str(_main.state.auto_care_quiet)

	var config := ConfigFile.new()
	if config.load(UI_SETTINGS_PATH) == OK:
		for section: String in config.get_sections():
			for key: String in config.get_section_keys(section):
				captured["settings.%s.%s" % [section, key]] = str(config.get_value(section, key))
	captured["effects"] = (
		FileAccess.get_file_as_string(EFFECTS_PATH).strip_edges()
		if FileAccess.file_exists(EFFECTS_PATH) else "missing"
	)
	var packs := PackedStringArray()
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(PACKS_ROOT)):
		packs = DirAccess.get_directories_at(ProjectSettings.globalize_path(PACKS_ROOT))
	packs.sort()
	captured["packs"] = ",".join(packs)

	if not is_instance_valid(_main._stats_window):
		captured["window"] = "closed"
		return captured
	_capture_node(_main._stats_window, "window", captured)
	return captured


func _capture_node(node: Node, path: String, captured: Dictionary) -> void:
	captured[path] = _describe(node)
	if String(node.name) in SKIPPED_SUBTREES:
		return
	var index := 0
	for child: Node in node.get_children():
		_capture_node(child, "%s/%d:%s" % [path, index, child.get_class()], captured)
		index += 1


func _describe(node: Node) -> String:
	var parts: Array[String] = []
	var node_name := String(node.name)
	if not node_name.begins_with("@"):
		parts.append("name=" + node_name)
	if node is CanvasItem:
		parts.append("visible=%s" % (node as CanvasItem).visible)
	if node is Window:
		parts.append("visible=%s" % (node as Window).visible)
		if node is AcceptDialog:
			parts.append("text=" + _flat((node as AcceptDialog).dialog_text))
	if node is Label:
		parts.append("text=" + _flat((node as Label).text))
		if (node as Label).has_theme_color_override("font_color"):
			parts.append("color=" + (node as Label).get_theme_color("font_color").to_html())
	if node is BaseButton:
		var button := node as BaseButton
		parts.append("disabled=%s pressed=%s" % [button.disabled, button.button_pressed])
		if node is Button:
			parts.append("text=" + _flat((node as Button).text))
		if not button.tooltip_text.is_empty():
			parts.append("tooltip=" + _flat(button.tooltip_text))
	if node is OptionButton:
		parts.append("selected=%d" % (node as OptionButton).selected)
	if node is Range:
		parts.append("value=%s" % str((node as Range).value))
	if node is SpinBox:
		parts.append("editable=%s" % (node as SpinBox).editable)
	if node is LineEdit:
		parts.append("text=%s editable=%s" % [_flat((node as LineEdit).text), (node as LineEdit).editable])
	if node is ItemList:
		var list := node as ItemList
		var items: Array[String] = []
		for index in list.item_count:
			items.append(("*" if list.is_selected(index) else "") + _flat(list.get_item_text(index)))
		parts.append("items=" + " | ".join(items))
	if node is TabContainer:
		parts.append("current=%d" % (node as TabContainer).current_tab)
	return _normalize(" ".join(parts))


func _find(node_name: String) -> Node:
	if _main == null or not is_instance_valid(_main._stats_window):
		return null
	return _main._stats_window.find_child(node_name, true, false)


func _find_text(tab_name: String, type_name: String, text: String) -> Node:
	var tab := _find(tab_name)
	if tab == null:
		return null
	for node: Node in tab.find_children("*", type_name, true, false):
		if node is Button and (node as Button).text.contains(text):
			return node
	return null


func _find_option_with_item(item_text: String) -> OptionButton:
	var tab := _find("設定")
	if tab == null:
		return null
	for node: Node in tab.find_children("*", "OptionButton", true, false):
		var option := node as OptionButton
		for index in option.item_count:
			if option.get_item_text(index) == item_text:
				return option
	return null


func _flat(text: String) -> String:
	return text.replace("\n", "\\n")


func _normalize(text: String) -> String:
	var normalized := text
	if not _version.is_empty():
		normalized = normalized.replace(_version, "<version>")
	return normalized.replace(_archive_path, "<archive>")


func _write_codex_pet_archive() -> String:
	var archive := ProjectSettings.globalize_path("user://details-golden-codex-pet.zip")
	var image := Image.create(1536, 1872, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.85, 0.35, 0.3, 1.0))
	var packer := ZIPPacker.new()
	packer.open(archive)
	packer.start_file("pet.json")
	packer.write_file(JSON.stringify({
		"id": "golden-codex",
		"displayName": "Golden Codex",
		"spritesheetPath": "spritesheet.png",
		"spriteVersionNumber": 1,
	}).to_utf8_buffer())
	packer.close_file()
	packer.start_file("spritesheet.png")
	packer.write_file(image.save_png_to_buffer())
	packer.close_file()
	packer.close()
	return archive


func _restore_ui_settings() -> void:
	if _had_ui_settings:
		var file := FileAccess.open(UI_SETTINGS_PATH, FileAccess.WRITE)
		file.store_buffer(_previous_ui_settings)
		file.close()
	elif FileAccess.file_exists(UI_SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UI_SETTINGS_PATH))


func _finish() -> void:
	_restore_ui_settings()
	var recorded := "\n".join(_output) + "\n"
	if OS.get_environment("ODP_RECORD_DETAILS_GOLDEN") == "1":
		var file := FileAccess.open(GOLDEN_PATH, FileAccess.WRITE)
		file.store_string(recorded)
		file.close()
		print("DETAILS_WINDOW_GOLDEN_RECORDED")
		quit(0)
		return
	var expected := FileAccess.get_file_as_string(GOLDEN_PATH).replace("\r\n", "\n")
	if expected != recorded:
		var expected_lines := expected.split("\n")
		var recorded_lines := recorded.split("\n")
		for index in maxi(expected_lines.size(), recorded_lines.size()):
			var expected_line := expected_lines[index] if index < expected_lines.size() else "<end>"
			var recorded_line := recorded_lines[index] if index < recorded_lines.size() else "<end>"
			if expected_line != recorded_line:
				push_error("first difference at line %d" % (index + 1))
				push_error("expected: " + expected_line)
				push_error("actual:   " + recorded_line)
				break
		var actual_path := ProjectSettings.globalize_path("user://details_window_golden.actual.txt")
		var actual_file := FileAccess.open(actual_path, FileAccess.WRITE)
		actual_file.store_string(recorded)
		actual_file.close()
		_fail("details window behavior changed; actual output: " + actual_path)
		return
	if _failed:
		return
	print("DETAILS_WINDOW_GOLDEN_TEST_OK")
	quit(0)


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	_restore_ui_settings()
	push_error("DETAILS_WINDOW_GOLDEN_TEST_FAILED: " + message)
	quit(1)
