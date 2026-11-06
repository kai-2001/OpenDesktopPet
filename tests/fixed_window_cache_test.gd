extends SceneTree

# Reserving the fixed window decodes every frame of every action, which took
# over a second for large packs on each character switch. The measured size
# must be reused while the pack is unchanged, and measured again after any of
# its files changes.

const PetVisualScript = preload("res://scripts/pet_visual.gd")
const PACK_ID := "fixed-window-cache-test"
const PACK_ROOT := "user://character_packs/" + PACK_ID
const UI_SETTINGS_PATH := "user://ui_settings.cfg"
const GEOMETRY_CACHE_PATH := "user://character_geometry_cache.json"
const ACTIONS: Array[String] = ["idle", "pet", "eat", "drink", "sleep", "move", "drag", "work"]

var _failed := false
var _previous_ui_settings := PackedByteArray()
var _had_ui_settings := false
var _previous_cache := PackedByteArray()
var _had_cache := false


func _init() -> void:
	_had_ui_settings = FileAccess.file_exists(UI_SETTINGS_PATH)
	if _had_ui_settings:
		_previous_ui_settings = FileAccess.get_file_as_bytes(UI_SETTINGS_PATH)
	_had_cache = FileAccess.file_exists(GEOMETRY_CACHE_PATH)
	if _had_cache:
		_previous_cache = FileAccess.get_file_as_bytes(GEOMETRY_CACHE_PATH)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GEOMETRY_CACHE_PATH))
	call_deferred("_run")


func _run() -> void:
	_write_pack(Vector2i(120, 160))
	var config := ConfigFile.new()
	config.set_value("character", "selected_id", PACK_ID)
	config.save(UI_SETTINGS_PATH)

	var visual = PetVisualScript.new()
	visual.position = Vector2(140, 300)
	root.add_child(visual)
	await process_frame
	_assert_true(visual.get_character_id() == PACK_ID, "the test pack loads")
	visual.use_fixed_window(true)
	var measured_size: Vector2i = visual._base_window_size
	_assert_true(measured_size.x > 0 and measured_size.y > 0, "the first load reserves a window")
	_assert_true(
		visual._texture_cache.size() == ACTIONS.size(),
		"the first load measures every action (%d textures)" % visual._texture_cache.size()
	)

	_assert_true(visual.reload_character(), "the unchanged pack reloads")
	_assert_true(
		visual._texture_cache.size() == 1,
		"an unchanged pack reuses its measured window and loads only idle (%d textures)"
			% visual._texture_cache.size()
	)
	_assert_true(
		visual._base_window_size == measured_size,
		"the reused window matches the measured one (%s vs %s)"
			% [visual._base_window_size, measured_size]
	)

	# A larger work frame must widen the window again.
	await create_timer(1.1).timeout
	_write_action_image("work", Vector2i(260, 300))
	_assert_true(visual.reload_character(), "the changed pack reloads")
	_assert_true(
		visual._texture_cache.size() == ACTIONS.size(),
		"a changed pack is measured again (%d textures)" % visual._texture_cache.size()
	)
	_assert_true(
		visual._base_window_size.x > measured_size.x
			and visual._base_window_size.y > measured_size.y,
		"the new measurement fits the larger frame (%s vs %s)"
			% [visual._base_window_size, measured_size]
	)

	visual.queue_free()
	await process_frame
	_cleanup()
	if _failed:
		return
	print("FIXED_WINDOW_CACHE_TEST_OK")
	quit(0)


func _write_pack(frame_size: Vector2i) -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(PACK_ROOT.path_join("animations"))
	)
	var actions := {}
	for action: String in ACTIONS:
		actions[action] = {"file": "animations/%s.png" % action, "columns": 1, "sequence": [0]}
		_write_action_image(action, frame_size)
	var manifest := {
		"format_version": 1,
		"id": PACK_ID,
		"name": "Fixed Window Cache Test",
		"version": "1.0.0",
		"scale": 0.5,
		"fallback_action": "idle",
		"actions": actions,
	}
	var file := FileAccess.open(PACK_ROOT.path_join("pet.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.close()


func _write_action_image(action: String, size: Vector2i) -> void:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.4, 0.6, 0.9, 1.0))
	image.save_png(ProjectSettings.globalize_path(
		PACK_ROOT.path_join("animations/%s.png" % action)
	))


func _cleanup() -> void:
	_remove_tree(ProjectSettings.globalize_path(PACK_ROOT))
	if FileAccess.file_exists(GEOMETRY_CACHE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GEOMETRY_CACHE_PATH))
	if _had_cache:
		var cache := FileAccess.open(GEOMETRY_CACHE_PATH, FileAccess.WRITE)
		cache.store_buffer(_previous_cache)
		cache.close()
	if _had_ui_settings:
		var settings := FileAccess.open(UI_SETTINGS_PATH, FileAccess.WRITE)
		settings.store_buffer(_previous_ui_settings)
		settings.close()
	elif FileAccess.file_exists(UI_SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UI_SETTINGS_PATH))


func _remove_tree(absolute: String) -> void:
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for file_name: String in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file_name))
	for directory: String in DirAccess.get_directories_at(absolute):
		_remove_tree(absolute.path_join(directory))
	DirAccess.remove_absolute(absolute)


func _assert_true(value: bool, message: String) -> void:
	if value or _failed:
		return
	_failed = true
	_cleanup()
	push_error("FIXED_WINDOW_CACHE_TEST_FAILED: " + message)
	quit(1)
