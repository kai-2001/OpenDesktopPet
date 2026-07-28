extends SceneTree

const PetStateScript = preload("res://scripts/pet_state.gd")
const PetVisualScript = preload("res://scripts/pet_visual.gd")
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
	var invalid_pack_root := "user://characters/custom"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(invalid_pack_root))
	var invalid_manifest := FileAccess.open(
		invalid_pack_root.path_join("pet.json"), FileAccess.WRITE
	)
	invalid_manifest.store_string('{"format_version":1,"actions":{}}')
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
	_assert_true(
		visual._pack_root != PetVisualScript.USER_CUSTOM_PACK_ROOT,
		"invalid external character pack must be rejected"
	)
	var default_visual := PetVisualScript.new()
	_assert_true(
		default_visual._load_pack_from(PetVisualScript.PUBLIC_PACK_ROOT),
		"public default character pack must validate and load"
	)
	_assert_equal(
		default_visual._pack_root,
		PetVisualScript.PUBLIC_PACK_ROOT,
		"public default character root"
	)
	default_visual.free()

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
	_assert_true(feed_elapsed >= 1250, "feed must wait for the real visual animation")
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
