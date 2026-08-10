extends SceneTree

const CodexPetImporterScript = preload("res://scripts/codex_pet_importer.gd")
const CharacterPackManagerScript = preload("res://scripts/character_pack_manager.gd")
const CharacterPackProfileScript = preload("res://scripts/character_pack_profile.gd")

const TEST_ROOT := "user://test_runs/codex_pet_importer"
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_tree(ProjectSettings.globalize_path(TEST_ROOT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_ROOT))

	var v2_root := TEST_ROOT.path_join("v2")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(v2_root))
	var v2_sheet := v2_root.path_join("spritesheet.png")
	_assert_true(_write_sheet(v2_sheet, 11), "v2 test spritesheet is created")
	_write_manifest(v2_root, {
		"id": "codex-test-v2",
		"displayName": "Codex 測試角色",
		"description": "A Codex test pet.",
		"spritesheetPath": "spritesheet.png",
		"spriteVersionNumber": 2,
	})
	_write_options(v2_root, {
		"behavior": {"autonomous_chance": 0.25},
		"effects": {
			"food": {"anchor": [-31.0, 14.0], "scale": 0.52},
		},
	})

	var importer := CodexPetImporterScript.normalize(v2_root, _read_manifest(v2_root))
	_assert_true(bool(importer.get("ok", false)), "Codex v2 manifest normalizes")
	var actions: Dictionary = importer.get("actions", {})
	_assert_true(actions.has_all(["idle", "running", "jumping", "eat", "drink", "sleep", "work"]), "Codex actions are mapped")
	_assert_equal(int(actions.pet.sequence[0]), 32, "pet maps to jumping row")
	_assert_equal(int(actions.move.sequence[0]), 8, "move maps to running-right row")
	_assert_equal(int(actions.drag.sequence[0]), 8, "drag maps to running-right row")
	_assert_equal(int(actions.move.autonomous_weight), 1, "Codex move is eligible for autonomous actions")
	_assert_equal(int(actions.work.sequence[0]), 56, "work maps to running row")
	_assert_equal(actions.idle.sequence.size(), 6, "idle uses six Codex frames")
	_assert_equal(actions.jumping.sequence.size(), 5, "jumping uses five Codex frames")
	_assert_equal(actions.work.sequence.size(), 6, "running work uses six Codex frames")
	_assert_equal(float(actions.idle.frame_time), 0.25, "Codex idle uses 250ms per frame")
	_assert_equal(float(actions.idle.idle_interval), 0.25, "Codex idle switches every 250ms")
	_assert_equal(float(actions.work.frame_time), 0.25, "Codex work uses 250ms per frame")
	_assert_equal(int(actions.idle.rows), 11, "v2 keeps the 11-row atlas geometry")

	var profile := CharacterPackProfileScript.new()
	_assert_true(profile.load_pack(v2_root), "profile loads normalized Codex v2 pack")
	_assert_true(profile.is_codex_pet(), "normalized Codex profile is identified as Codex")
	_assert_equal(profile.character_id(), "codex-test-v2", "profile preserves Codex id")
	_assert_equal(profile.character_name(), "Codex 測試角色", "profile uses displayName")
	_assert_true(profile.has_action("jumping"), "profile exposes jumping action")
	_assert_equal(profile.autonomous_chance(), 0.25, "Codex pack can set move chance")
	_assert_equal(
		profile.effect_overrides().food.anchor[0], -31.0,
		"Codex pack can override food anchor"
	)

	var v1_root := TEST_ROOT.path_join("v1")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(v1_root))
	var v1_sheet := v1_root.path_join("spritesheet.png")
	_assert_true(_write_sheet(v1_sheet, 9), "v1 test spritesheet is created")
	_write_manifest(v1_root, {
		"id": "codex-test-v1",
		"displayName": "Codex V1",
		"description": "A Codex v1 test pet.",
		"spritesheetPath": "spritesheet.png",
	})
	var archive_path := TEST_ROOT.path_join("codex-test-v1.zip")
	_assert_true(_write_archive(archive_path, v1_root), "Codex archive is created")
	var inspection := CharacterPackManagerScript.inspect_archive(archive_path)
	_assert_true(bool(inspection.get("ok", false)), "Codex archive is detected by importer")
	_assert_equal(String(inspection.get("id", "")), "codex-test-v1", "archive keeps Codex id")
	_assert_equal(String(inspection.get("source_format", "")), "codex-pet", "archive reports Codex source format")

	var installed := CharacterPackManagerScript.install_archive(archive_path)
	_assert_true(bool(installed.get("ok", false)), "Codex archive installs")
	var installed_root := CharacterPackManagerScript.PACKS_ROOT.path_join("codex-test-v1")
	var installed_profile := CharacterPackProfileScript.new()
	_assert_true(installed_profile.load_pack(installed_root), "installed Codex archive loads")
	_assert_true(installed_profile.is_codex_pet(), "installed Codex profile remains identified as Codex")
	var listed := CharacterPackManagerScript.list_installed()
	_assert_true(_contains_id(listed, "codex-test-v1"), "installed Codex pack appears in list")
	var removed := CharacterPackManagerScript.remove_pack("codex-test-v1")
	_assert_true(bool(removed.get("ok", false)), "installed Codex pack removes")

	if _failures > 0:
		push_error("CODEX_PET_IMPORTER_TEST_FAILED: %d assertion(s)" % _failures)
		quit(1)
		return
	print("CODEX_PET_IMPORTER_TEST_OK")
	quit(0)


func _write_sheet(path: String, rows: int) -> bool:
	var image := Image.create(1536, rows * 208, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	return image.save_png(ProjectSettings.globalize_path(path)) == OK


func _write_manifest(root: String, manifest: Dictionary) -> void:
	var file := FileAccess.open(root.path_join("pet.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))


func _read_manifest(root: String) -> Dictionary:
	var file := FileAccess.open(root.path_join("pet.json"), FileAccess.READ)
	return JSON.parse_string(file.get_as_text()) as Dictionary


func _write_options(root: String, options: Dictionary) -> void:
	var file := FileAccess.open(root.path_join("open_desktop_pet.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(options))


func _write_archive(path: String, root: String) -> bool:
	var packer := ZIPPacker.new()
	if packer.open(ProjectSettings.globalize_path(path)) != OK:
		return false
	var manifest_bytes := FileAccess.get_file_as_bytes(root.path_join("pet.json"))
	if packer.start_file("pet.json") != OK:
		packer.close()
		return false
	packer.write_file(manifest_bytes)
	packer.close_file()
	if packer.start_file("spritesheet.png") != OK:
		packer.close()
		return false
	packer.write_file(FileAccess.get_file_as_bytes(root.path_join("spritesheet.png")))
	packer.close_file()
	packer.close()
	return true


func _assert_true(value: bool, message: String) -> void:
	if value:
		return
	_failures += 1
	printerr("CODEX_PET_IMPORTER_TEST_FAILED: " + message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	_assert_true(actual == expected, "%s (actual=%s expected=%s)" % [message, actual, expected])


func _contains_id(entries: Array[Dictionary], expected_id: String) -> bool:
	for entry: Dictionary in entries:
		if String(entry.get("id", "")) == expected_id:
			return true
	return false


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
