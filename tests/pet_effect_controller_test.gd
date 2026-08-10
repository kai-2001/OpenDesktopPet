extends SceneTree

const EffectControllerScript = preload("res://scripts/pet_effect_controller.gd")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var controller = EffectControllerScript.new()
	root.add_child(controller)
	await process_frame

	for asset_path: String in [
		"res://assets/effects/food.png",
		"res://assets/effects/water_cup.png",
		"res://assets/effects/eye_mask.png",
		"res://assets/effects/zzz.png",
	]:
		var image := Image.load_from_file(ProjectSettings.globalize_path(asset_path))
		_assert_true(image != null and not image.is_empty(), "effect image loads: " + asset_path)
		if image != null and not image.is_empty():
			_assert_true(
				image.get_pixel(0, 0).a < 0.01,
				"effect image has transparent corner: " + asset_path
			)

	var food := controller.get_node_or_null("Food") as Sprite2D
	var water := controller.get_node_or_null("Water") as Sprite2D
	var mask := controller.get_node_or_null("Mask") as Sprite2D
	var zzz := controller.get_node_or_null("Zzz") as Sprite2D
	_assert_true(food != null and water != null and mask != null and zzz != null, "effect sprites are created")
	_assert_true(not food.visible and not water.visible and not mask.visible and not zzz.visible, "effects start hidden")
	controller.configure_for_pack(0.58)
	_assert_true(is_equal_approx(food.position.x, 0.0) and food.scale.x < 0.45, "effects center and scale with Codex-sized packs")
	_assert_true(is_equal_approx(mask.position.y, -11.6) and is_equal_approx(mask.scale.x, 0.38 * 0.58), "eye mask is slightly above center and enlarged")
	var editor_mask: Dictionary = controller.effect_editor_definition("mask")
	_assert_true(
		is_equal_approx(float(editor_mask.anchor[1]), -20.0)
			and is_equal_approx(float(editor_mask.scale), 0.38),
		"editor exposes unscaled mask layout"
	)
	controller.set_preview("mask", true)
	await process_frame
	_assert_true(mask.visible, "mask preview shows immediately")
	controller.set_preview("mask", false)
	_assert_true(not mask.visible, "mask preview hides cleanly")
	var custom_food_path := "user://test_runs/pet_effect_custom_food.png"
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("user://test_runs")
	)
	var custom_food := FileAccess.open(custom_food_path, FileAccess.WRITE)
	custom_food.store_buffer(FileAccess.get_file_as_bytes("res://assets/effects/food.png"))
	custom_food.close()
	controller.configure_for_pack(0.58, {
		"food": {"file": custom_food_path, "anchor": [-28.0, 12.0]},
	})
	_assert_true(food.texture != null, "per-pack effect image can be loaded")
	_assert_true(is_equal_approx(food.position.x, -16.24), "per-pack effect anchor overrides default")

	controller.play_for_action("eat")
	await process_frame
	_assert_true(food.visible, "food effect starts for eat")
	var food_anchor := food.position
	await create_timer(0.3).timeout
	_assert_true(
		is_equal_approx(food.position.x, food_anchor.x)
			and is_equal_approx(food.position.y, food_anchor.y),
		"food effect tilts in place without horizontal movement"
	)
	await create_timer(2.0).timeout
	_assert_true(not food.visible, "food effect fades out")

	controller.configure_for_pack(0.58, {
		"food": {"file": custom_food_path, "anchor": [-28.0, 12.0], "sway": 12.0},
	})
	controller.play_for_action("eat")
	await process_frame
	var moving_food_x := food.position.x
	await create_timer(0.2).timeout
	_assert_true(
		not is_equal_approx(food.position.x, moving_food_x),
		"food effect can move horizontally when sway is configured"
	)

	controller.play_for_action("drink")
	await process_frame
	_assert_true(water.visible, "water effect starts for drink")

	controller.start_sleep()
	await process_frame
	_assert_true(mask.visible, "sleep mask starts")
	await create_timer(0.2).timeout
	_assert_true(zzz.visible, "zzz effect starts")
	controller.stop_sleep()
	_assert_true(not mask.visible and not zzz.visible, "sleep effects stop")

	if _failures > 0:
		push_error("PET_EFFECT_CONTROLLER_TEST_FAILED: %d assertion(s)" % _failures)
		quit(1)
		return
	print("PET_EFFECT_CONTROLLER_TEST_OK")
	quit(0)


func _assert_true(value: bool, message: String) -> void:
	if value:
		return
	_failures += 1
	printerr("PET_EFFECT_CONTROLLER_TEST_FAILED: " + message)
