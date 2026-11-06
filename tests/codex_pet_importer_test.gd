extends SceneTree

const CodexPetImporterScript = preload("res://scripts/codex_pet_importer.gd")
const CharacterPackManagerScript = preload("res://scripts/character_pack_manager.gd")
const CharacterPackProfileScript = preload("res://scripts/character_pack_profile.gd")
const CharacterEffectPreferencesScript = preload(
	"res://scripts/character_effect_preferences.gd"
)

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
	_assert_equal(int(actions.move.autonomous_weight), 4, "Codex move is eligible for autonomous actions")
	_assert_equal(int(actions.waving.sequence[0]), 24, "waving maps to the waving row")
	_assert_equal(actions.waving.sequence.size(), 4, "waving uses four Codex frames")
	_assert_equal(int(actions.review.sequence[0]), 64, "review maps to the review row")
	_assert_equal(int(actions.waiting.sequence[0]), 48, "waiting maps to the waiting row")
	_assert_equal(int(actions.failed.sequence[0]), 40, "failed maps to the failed row")
	_assert_equal(actions.failed.sequence.size(), 8, "failed uses eight Codex frames")
	_assert_equal(actions.waving.unlock, {"level": 3}, "waving unlocks at level 3")
	_assert_equal(actions.review.unlock, {"level": 6, "affection": 15}, "review unlocks at level 6 and affection 15")
	_assert_equal(actions.waiting.unlock, {"level": 10, "affection": 40}, "waiting unlocks at level 10 and affection 40")
	for event_action: String in ["agent_done", "agent_waiting", "failed"]:
		_assert_true(
			not actions[event_action].has("unlock")
				and int(actions[event_action].get("autonomous_weight", 0)) == 0,
			"%s is an event reaction: never locked and never picked autonomously" % event_action
		)
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
	profile.set_progression({"level": 1, "affection": 0})
	_assert_true(not profile.is_action_unlocked("waving"), "waving starts locked")
	_assert_true(profile.is_action_unlocked("agent_done"), "event reactions are always available")
	_assert_equal(profile.next_unlock().get("id", ""), "waving", "the next unlock shown is waving")
	profile.set_progression({"level": 10, "affection": 39})
	_assert_true(profile.is_action_unlocked("review"), "review unlocks at level 6 and affection 15")
	_assert_true(not profile.is_action_unlocked("waiting"), "waiting still needs affection 40")
	profile.set_progression({"level": 10, "affection": 40})
	_assert_true(profile.is_action_unlocked("waiting"), "waiting unlocks at level 10 and affection 40")
	_assert_equal(
		profile.effect_overrides().food.anchor[0], -31.0,
		"Codex pack can override food anchor"
	)
	var preferences_path := TEST_ROOT.path_join("character_effects.json")
	_assert_true(
		CharacterEffectPreferencesScript.set_effect(
			"codex-test-v2", "mask",
			{"anchor": [12.0, -28.0], "scale": 0.44}, preferences_path
		),
		"character effect preference saves"
	)
	var saved_effects := CharacterEffectPreferencesScript.load_for_character(
		"codex-test-v2", preferences_path
	)
	_assert_equal(saved_effects.mask.anchor[0], 12.0, "saved mask X persists")
	_assert_equal(saved_effects.mask.anchor[1], -28.0, "saved mask Y persists")
	_assert_equal(saved_effects.mask.scale, 0.44, "saved mask scale persists")
	_assert_true(
		CharacterEffectPreferencesScript.clear_effect(
			"codex-test-v2", "mask", preferences_path
		),
		"character effect preference resets"
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

	# Codex pet files may carry a mixed-case id ("Giratina"); fold it to
	# lowercase instead of rejecting the archive.
	var mixed_root := TEST_ROOT.path_join("mixed")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(mixed_root))
	_assert_true(_write_sheet(mixed_root.path_join("spritesheet.png"), 9), "mixed-case test spritesheet is created")
	_write_manifest(mixed_root, {
		"id": "Codex-Test-Mixed",
		"displayName": "Codex Mixed",
		"spritesheetPath": "spritesheet.png",
	})
	var mixed_archive := TEST_ROOT.path_join("codex-test-mixed.zip")
	_assert_true(_write_archive(mixed_archive, mixed_root), "mixed-case Codex archive is created")
	var mixed_inspection := CharacterPackManagerScript.inspect_archive(mixed_archive)
	_assert_true(bool(mixed_inspection.get("ok", false)), "mixed-case Codex id is accepted")
	_assert_equal(String(mixed_inspection.get("id", "")), "codex-test-mixed", "mixed-case Codex id is lowercased")
	_assert_equal(String(mixed_inspection.get("name", "")), "Codex Mixed", "display name keeps its case")
	var mixed_installed := CharacterPackManagerScript.install_archive(mixed_archive)
	_assert_true(bool(mixed_installed.get("ok", false)), "mixed-case Codex archive installs")
	_assert_equal(String(mixed_installed.get("id", "")), "codex-test-mixed", "mixed-case pack installs under a lowercase id")
	var mixed_profile := CharacterPackProfileScript.new()
	_assert_true(
		mixed_profile.load_pack(CharacterPackManagerScript.PACKS_ROOT.path_join("codex-test-mixed")),
		"mixed-case pack loads from its lowercase folder"
	)
	_assert_equal(mixed_profile.character_id(), "codex-test-mixed", "loaded mixed-case pack reports the lowercase id")
	_assert_true(
		_contains_id(CharacterPackManagerScript.list_installed(), "codex-test-mixed"),
		"mixed-case pack appears in the list under its lowercase id"
	)
	_assert_true(
		bool(CharacterPackManagerScript.remove_pack("codex-test-mixed").get("ok", false)),
		"mixed-case pack removes by its lowercase id"
	)

	_check_header_dimensions()

	if _failures > 0:
		push_error("CODEX_PET_IMPORTER_TEST_FAILED: %d assertion(s)" % _failures)
		quit(1)
		return
	print("CODEX_PET_IMPORTER_TEST_OK")
	quit(0)


## Listing packs reads every Codex spritesheet's size. The size must come from
## the file header, so files are cut right after it: decoding them would fail.
func _check_header_dimensions() -> void:
	var header_root := TEST_ROOT.path_join("headers")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(header_root))
	for size: Vector2i in [Vector2i(1536, 1872), Vector2i(1001, 777)]:
		var transparent := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		transparent.fill(Color(0.2, 0.4, 0.6, 0.5))
		var opaque := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
		opaque.fill(Color(0.2, 0.4, 0.6))
		var cases := {
			"png": func(path: String) -> Error: return transparent.save_png(path),
			"webp-lossless": func(path: String) -> Error: return transparent.save_webp(path, false),
			"webp-lossy-alpha": func(path: String) -> Error: return transparent.save_webp(path, true, 0.8),
			"webp-lossy": func(path: String) -> Error: return opaque.save_webp(path, true, 0.8),
		}
		for label: String in cases:
			var extension := "png" if label == "png" else "webp"
			var path := header_root.path_join("%s-%dx%d.%s" % [label, size.x, size.y, extension])
			var absolute := ProjectSettings.globalize_path(path)
			_assert_true((cases[label] as Callable).call(absolute) == OK, "%s test image is written" % label)
			var bytes := FileAccess.get_file_as_bytes(path)
			var cut := FileAccess.open(path, FileAccess.WRITE)
			cut.store_buffer(bytes.slice(0, 64))
			cut.close()
			_assert_equal(
				CodexPetImporterScript._read_dimensions(path),
				size,
				"%s size is read from the header alone (%dx%d)" % [label, size.x, size.y]
			)
	var jpeg_path := header_root.path_join("fallback.jpg")
	var jpeg := Image.create(320, 240, false, Image.FORMAT_RGB8)
	jpeg.fill(Color(0.8, 0.2, 0.2))
	jpeg.save_jpg(ProjectSettings.globalize_path(jpeg_path))
	_assert_equal(
		CodexPetImporterScript._read_dimensions(jpeg_path),
		Vector2i(320, 240),
		"formats without a header reader still report their decoded size"
	)
	var broken_path := header_root.path_join("broken.png")
	var broken := FileAccess.open(broken_path, FileAccess.WRITE)
	broken.store_buffer(PackedByteArray([0x89, 0x50, 0x4E, 0x47]))
	broken.close()
	_assert_equal(
		CodexPetImporterScript._read_dimensions(broken_path),
		Vector2i.ZERO,
		"a damaged spritesheet reports no size"
	)


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
