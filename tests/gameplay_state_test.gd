extends SceneTree

const PetStateScript = preload("res://scripts/pet_state.gd")
const PetVisualScript = preload("res://scripts/pet_visual.gd")
const CharacterPackManagerScript = preload("res://scripts/character_pack_manager.gd")
const TEST_SAVE_PATH := "user://test_runs/gameplay_state.json"
var _failures := 0


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("user://test_runs")
	)
	for suffix: String in ["", ".tmp", ".backup"]:
		var path := ProjectSettings.globalize_path(TEST_SAVE_PATH + suffix)
		if FileAccess.file_exists(TEST_SAVE_PATH + suffix):
			DirAccess.remove_absolute(path)
	var invalid_pack_root := "user://character_packs/invalid_test_pack"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(invalid_pack_root))
	var invalid_manifest := FileAccess.open(
		invalid_pack_root.path_join("pet.json"), FileAccess.WRITE
	)
	invalid_manifest.store_string(
		'{"format_version":1,"id":"invalid_test_pack","actions":{}}'
	)
	invalid_manifest.close()

	var state := PetStateScript.new()
	state.save_path = TEST_SAVE_PATH
	var visual := PetVisualScript.new()
	visual.position = Vector2(140, 190)
	root.add_child(visual)
	root.add_child(state)
	state.action_requested.connect(visual.play_action)
	visual.action_completed.connect(state.receive_action_completed)
	await process_frame
	var directional_offsets := {"offsets": [[12.0, -3.0]]}
	visual.set_facing_direction(-1)
	_assert_equal(
		visual._frame_offset(directional_offsets, 0),
		Vector2(12.0, -3.0),
		"source-facing frame offset remains unchanged"
	)
	visual.set_facing_direction(1)
	_assert_equal(
		visual._frame_offset(directional_offsets, 0),
		Vector2(-12.0, -3.0),
		"horizontal frame offset mirrors with the character"
	)
	_test_frame_viewport_containment(visual)
	_assert_true(
		not visual._load_pack_from(invalid_pack_root),
		"invalid external character pack must be rejected"
	)
	var default_visual := PetVisualScript.new()
	_assert_true(
		default_visual._load_pack_from(PetVisualScript.PUBLIC_PACK_ROOT),
		"public default character pack must validate and load"
	)
	var duration_visual := PetVisualScript.new()
	duration_visual._actions = {
		"move": {
			"sequence": [0, 1, 2, 3],
			"behavior": "pulse",
			"pulses": 8,
			"frame_time": 0.3,
		},
	}
	_assert_true(
		is_equal_approx(duration_visual.get_action_duration("move"), 2.4),
		"pulse move duration uses pulses multiplied by frame time"
	)
	duration_visual._actions.move.erase("behavior")
	_assert_true(
		is_equal_approx(duration_visual.get_action_duration("move"), 1.2),
		"sequence move duration uses sequence length multiplied by frame time"
	)
	_assert_equal(
		default_visual._pack_root,
		PetVisualScript.PUBLIC_PACK_ROOT,
		"public default character root"
	)
	default_visual.free()
	_test_character_pack_lifecycle()

	state.data.hunger = 80.0
	state.data.thirst = 80.0
	state.data.energy = 80.0
	state.data.mood = 80.0
	state.data.affection = 0
	state.data.xp = 0
	state.data.level = 1
	state.data.coins = 20
	state.data.wish_action = ""
	state.data.next_wish_at = state._now() + 9999
	state.data.wish_expires_at = 0

	var now := state._now()
	state.data.last_decay_at = now - 1200
	var decayed: bool = state._apply_elapsed_decay(now, 48)
	_assert_true(decayed, "elapsed decay should run")
	_assert_equal(state.data.hunger, 76.0, "two hunger decay intervals")
	_assert_equal(state.data.thirst, 74.0, "two thirst decay intervals")
	_assert_equal(state.data.last_decay_at, now, "decay timestamp should retain no remainder")

	state.data.hunger = 50.0
	state.data.coins = 20
	var feed_started := Time.get_ticks_msec()
	await state.feed()
	var feed_elapsed := Time.get_ticks_msec() - feed_started
	_assert_true(feed_elapsed >= 1150, "feed must wait for the real visual animation")
	_assert_equal(state.data.coins, 18, "successful feed coin cost")
	_assert_equal(state.data.hunger, 78.0, "successful feed result")
	_assert_true(not state.is_action_busy(), "state must unlock after visual completion")
	_assert_true(not visual.is_busy(), "visual must be idle after completion")

	visual._busy = true
	var coins_before_rejection := int(state.data.coins)
	var hunger_before_rejection := float(state.data.hunger)
	await state.feed()
	_assert_equal(state.data.coins, coins_before_rejection, "rejected animation must not charge")
	_assert_equal(state.data.hunger, hunger_before_rejection, "rejected animation must not reward")
	_assert_true(not state.is_action_busy(), "rejected animation must unlock state")
	visual._busy = false

	state.data.wish_action = "sleep"
	state.data.wish_expires_at = state._now()
	_assert_true(not state.has_active_wish(), "wish expires exactly at its deadline")
	_assert_equal(state.wish_text(), "目前沒有願望", "expired wish text")

	state.data.wish_action = "feed"
	state.data.wish_expires_at = state._now() + 60
	var suffix: String = state._complete_wish("feed")
	_assert_true(not suffix.is_empty(), "matching active wish should complete")
	_assert_equal(state.data.affection, 3, "care plus wish affection reward")

	state.data.visual_scale = 1.0
	state.change_visual_size(0.1)
	_assert_equal(state.data.visual_scale, 1.1, "visual scale persistence")

	state.save_state()
	state.data.coins += 1
	state.save_state()
	_assert_true(FileAccess.file_exists(TEST_SAVE_PATH), "verified save should exist")
	_assert_true(FileAccess.file_exists(TEST_SAVE_PATH + ".backup"), "save backup should exist")
	var loaded := PetStateScript.new()
	loaded.save_path = TEST_SAVE_PATH
	loaded.load_state()
	_assert_equal(loaded.data.coins, state.data.coins, "safe save round trip")
	loaded.free()

	var profile_a := PetStateScript.new()
	profile_a.configure_profile("Profile A")
	_assert_equal(
		profile_a.save_path,
		"user://profiles/profile_a/save_v2.json",
		"character ID selects a safe profile save path"
	)
	profile_a.data.coins = 111
	profile_a.save_state()
	var profile_b := PetStateScript.new()
	profile_b.configure_profile("Profile B")
	_assert_equal(
		profile_b.data.coins,
		PetStateScript.DEFAULT_DATA.coins,
		"a different character ID starts from independent defaults"
	)
	profile_b.data.coins = 222
	profile_b.save_state()
	var reloaded_profile_a := PetStateScript.new()
	reloaded_profile_a.configure_profile("Profile A")
	_assert_equal(
		reloaded_profile_a.data.coins,
		111,
		"reloading one character ID does not read another profile"
	)
	profile_a.free()
	profile_b.free()
	reloaded_profile_a.free()
	state.queue_free()
	visual.queue_free()
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(invalid_pack_root.path_join("pet.json"))
	)
	await process_frame
	await process_frame

	if _failures > 0:
		push_error("GAMEPLAY_STATE_TEST_FAILED: %d assertion(s)" % _failures)
		quit(1)
	else:
		print("GAMEPLAY_STATE_TEST_OK")
		quit(0)


func _test_frame_viewport_containment(visual: Node2D) -> void:
	var image := Image.create(240, 100, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(0, 20, 45, 60), Color.WHITE)
	image.fill_rect(Rect2i(195, 25, 45, 50), Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var action := "viewport_clamp_test"
	var file := "viewport_clamp_test.png"
	var texture_path: String = visual._pack_root.path_join(file)
	visual._actions[action] = {
		"file": file,
		"columns": 1,
		"rows": 1,
		"offsets": [[100.0, 0.0]],
		"scale": 1.0,
	}
	visual._texture_cache[texture_path] = texture
	visual.set_facing_direction(-1)
	visual._show_action_frame(action, 0)
	var bounds: Rect2 = visual._opaque_frame_bounds_in_canvas()
	var limits := visual.get_viewport().get_visible_rect().grow(
		-PetVisualScript.FRAME_VIEWPORT_PADDING
	)
	_assert_true(
		bounds.position.x >= limits.position.x - 0.01
			and bounds.end.x <= limits.end.x + 0.01,
		"separated character and prop pixels remain inside the viewport"
	)
	var interaction_polygon: PackedVector2Array = visual.get_interaction_polygon()
	var interaction_bounds := Rect2(interaction_polygon[0], Vector2.ZERO)
	for point: Vector2 in interaction_polygon:
		interaction_bounds = interaction_bounds.expand(point)
	_assert_true(
		interaction_bounds.size.x >= 230.0,
		"native window shape includes separated character and prop islands"
	)
	visual._actions.erase(action)
	visual._texture_cache.erase(texture_path)
	visual._show_action_frame("idle", visual._first_frame("idle"))


func _test_character_pack_lifecycle() -> void:
	var archive_path := "user://test_runs/test_import_pet.petpack"
	_write_test_character_archive(archive_path, "1.0.0")
	var installed: Dictionary = CharacterPackManagerScript.install_archive(
		ProjectSettings.globalize_path(archive_path)
	)
	_assert_true(bool(installed.get("ok", false)), "valid character archive installs")
	_assert_true(not bool(installed.get("updated", true)), "first import is an install")
	_assert_equal(String(installed.get("id", "")), "test_import_pet", "installed character ID")
	_write_test_character_archive(archive_path, "1.1.0")
	var updated: Dictionary = CharacterPackManagerScript.install_archive(
		ProjectSettings.globalize_path(archive_path)
	)
	_assert_true(bool(updated.get("ok", false)), "same-ID character archive updates")
	_assert_true(bool(updated.get("updated", false)), "same-ID import is reported as update")
	_assert_equal(String(updated.get("version", "")), "1.1.0", "updated package version")
	var installed_visual := PetVisualScript.new()
	_assert_true(
		installed_visual._load_pack_from(
			CharacterPackManagerScript.PACKS_ROOT.path_join("test_import_pet")
		),
		"installed character pack is accepted by the runtime loader"
	)
	_assert_equal(
		installed_visual.get_character_id(),
		"test_import_pet",
		"runtime loader reads the installed character ID"
	)
	var external_svg_path := "user://test_runs/external_character.svg"
	var external_svg := FileAccess.open(external_svg_path, FileAccess.WRITE)
	external_svg.store_buffer(FileAccess.get_file_as_bytes(
		"res://characters/public/pet.svg"
	))
	external_svg.close()
	_assert_true(
		installed_visual._load_texture(external_svg_path) != null,
		"runtime loader decodes SVG images from external character packs"
	)
	installed_visual.free()
	var profile_root := "user://profiles/test_import_pet"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(profile_root))
	var profile_marker := FileAccess.open(profile_root.path_join("save_v2.json"), FileAccess.WRITE)
	profile_marker.store_string("{}")
	profile_marker.close()
	var removed: Dictionary = CharacterPackManagerScript.remove_pack("test_import_pet")
	_assert_true(bool(removed.get("ok", false)), "installed character can be removed")
	_assert_true(
		FileAccess.file_exists(profile_root.path_join("save_v2.json")),
		"removing a character pack preserves its gameplay profile"
	)


func _write_test_character_archive(path: String, version: String) -> void:
	var actions := {}
	for action: String in CharacterPackManagerScript.REQUIRED_ACTIONS:
		actions[action] = {
			"file": "animations/pet.png",
			"columns": 1,
			"rows": 1,
			"sequence": [0],
			"frame_time": 0.1,
		}
	var manifest := {
		"format_version": 1,
		"id": "test_import_pet",
		"name": "Test Import Pet",
		"version": version,
		"fallback_action": "idle",
		"actions": actions,
	}
	var packer := ZIPPacker.new()
	_assert_equal(packer.open(path), OK, "test character archive opens")
	_assert_equal(packer.start_file("pet.json"), OK, "test manifest entry starts")
	packer.write_file(JSON.stringify(manifest).to_utf8_buffer())
	packer.close_file()
	_assert_equal(packer.start_file("animations/pet.png"), OK, "test image entry starts")
	var test_image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	test_image.fill(Color.WHITE)
	var test_png_path := "user://test_runs/test_character.png"
	_assert_equal(test_image.save_png(test_png_path), OK, "test image is encoded as PNG")
	packer.write_file(FileAccess.get_file_as_bytes(test_png_path))
	packer.close_file()
	packer.close()


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Assertion failed: %s" % label)


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failures += 1
	push_error("Assertion failed: %s (actual=%s expected=%s)" % [label, actual, expected])
