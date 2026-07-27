extends SceneTree

const PetStateScript = preload("res://scripts/pet_state.gd")


func _init() -> void:
	var state := PetStateScript.new()
	root.add_child(state)
	await process_frame

	state.data.hunger = 80.0
	state.data.thirst = 80.0
	state.data.energy = 80.0
	state.data.mood = 80.0
	state.data.affection = 0
	state.data.xp = 0
	state.data.level = 1
	state.data.wish_action = ""
	state.data.next_wish_at = 0
	state.data.wish_expires_at = 0

	state._decay_accumulator = 0.0
	state._process(600.0)
	_assert_equal(state.data.hunger, 78.0, "hunger decay")
	_assert_equal(state.data.thirst, 77.0, "thirst decay")
	_assert_equal(state.data.energy, 80.0, "energy should not decay naturally")

	state.data.wish_action = "feed"
	state.data.wish_expires_at = state._now() + 60
	var suffix: String = state._complete_wish("feed")
	_assert_true(not suffix.is_empty(), "matching care should complete a wish")
	_assert_equal(state.data.affection, 2, "wish affection reward")
	_assert_equal(state.data.xp, 2, "wish XP reward")

	state.data.wish_action = ""
	state.data.next_wish_at = state._now() - 1
	state._update_wish()
	_assert_true(not String(state.data.wish_action).is_empty(), "due wish should be generated")
	_assert_true(int(state.data.wish_expires_at) > state._now(), "wish should have an expiry")

	state.save_state()
	var loaded := PetStateScript.new()
	loaded.load_state()
	_assert_equal(loaded.data.affection, state.data.affection, "affection save migration")
	_assert_equal(loaded.data.wish_action, state.data.wish_action, "wish save persistence")

	print("GAMEPLAY_STATE_TEST_OK")
	quit(0)


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		return
	push_error("Assertion failed: %s" % label)
	quit(1)


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	push_error("Assertion failed: %s (actual=%s expected=%s)" % [label, actual, expected])
	quit(1)
