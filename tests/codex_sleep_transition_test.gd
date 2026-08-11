extends SceneTree

const PetVisualScript = preload("res://scripts/pet_visual.gd")
const TEST_ROOT := "user://test_runs/codex_sleep_transition"
var _failures := 0
var _completed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_tree(ProjectSettings.globalize_path(TEST_ROOT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_ROOT))
	var sheet_path := TEST_ROOT.path_join("spritesheet.png")
	_assert_true(_write_sheet(sheet_path), "Codex test spritesheet is created")
	var manifest_file := FileAccess.open(TEST_ROOT.path_join("pet.json"), FileAccess.WRITE)
	manifest_file.store_string(JSON.stringify({
		"id": "codex-sleep-test",
		"displayName": "Codex Sleep Test",
		"spritesheetPath": "spritesheet.png",
		"spriteVersionNumber": 1,
	}))
	manifest_file.close()

	var visual := PetVisualScript.new()
	root.add_child(visual)
	await process_frame
	_assert_true(visual._profile.load_pack(TEST_ROOT), "Codex test profile loads")
	visual._texture_cache.clear()
	visual._effect_controller.configure_for_pack(0.58)
	visual.apply_effect_override("mask", {
		"anchor": [18.0, -20.0],
	})
	visual.set_facing_direction(-1)
	visual.set_effect_preview("mask", true)
	var mask := visual._effect_controller.get_node("Mask") as Sprite2D
	var left_mask_x := mask.position.x
	visual.set_facing_direction(1)
	_assert_true(
		mask.flip_h and is_equal_approx(mask.position.x, -left_mask_x),
		"Codex preview mirrors the eye mask with the pet direction"
	)
	visual.set_effect_preview("mask", false)
	visual.action_completed.connect(_on_action_completed)

	var started_at := Time.get_ticks_msec()
	visual.play_action("sleep", 1)
	var elapsed := Time.get_ticks_msec() - started_at
	_assert_true(_completed, "Codex sleep request completes without idle animation wait")
	_assert_true(elapsed < 100, "Codex sleep transition is immediate")
	_assert_true(not visual.is_busy(), "Codex sleep transition does not leave a pending action")

	visual.start_sleep_loop()
	await process_frame
	_assert_true(visual._sleep_loop_active, "Codex sleep loop starts after state confirmation")
	_assert_equal(visual._current_action, "idle", "Codex sleep loop uses idle as its animation source")
	visual.stop_sleep_loop("drag")

	if _failures > 0:
		push_error("CODEX_SLEEP_TRANSITION_TEST_FAILED: %d assertion(s)" % _failures)
		quit(1)
		return
	print("CODEX_SLEEP_TRANSITION_TEST_OK")
	quit(0)


func _on_action_completed(_request_id: int, _action: String, success: bool) -> void:
	_completed = success


func _write_sheet(path: String) -> bool:
	var image := Image.create(1536, 1872, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	return image.save_png(ProjectSettings.globalize_path(path)) == OK


func _assert_true(value: bool, message: String) -> void:
	if value:
		return
	_failures += 1
	printerr("CODEX_SLEEP_TRANSITION_TEST_FAILED: " + message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	_assert_true(actual == expected, "%s (actual=%s expected=%s)" % [message, actual, expected])


func _remove_tree(absolute_path: String) -> void:
	if not DirAccess.dir_exists_absolute(absolute_path):
		return
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		DirAccess.remove_absolute(absolute_path.path_join(file_name))
	for folder_name: String in directory.get_directories():
		_remove_tree(absolute_path.path_join(folder_name))
	DirAccess.remove_absolute(absolute_path)
