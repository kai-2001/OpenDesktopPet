extends SceneTree

# Closing the pet must save and free it while the tray icon stays; showing it
# again must start a fresh pet from the save. A second launch must bring the
# running pet back instead of opening another one that shares the save.

const PetMenuBuilderScript = preload("res://scripts/pet_menu_builder.gd")
const InstanceLinkScript = preload("res://scripts/instance_link.gd")
const CjkLineBreaksScript = preload("res://scripts/cjk_line_breaks.gd")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var shell: Node = load("res://scenes/app.tscn").instantiate()
	root.add_child(shell)
	await _settle()
	_assert_true(shell.is_pet_open(), "launching opens the pet")
	_assert_true(shell._link.is_listening(), "the first copy listens for later launches")
	_assert_true(not shell.is_window_concealed(), "the pet window is on screen while the pet is open")
	if not shell.is_pet_open():
		_finish()
		return
	var first_pet: Node = shell.pet
	_assert_true(first_pet.hosted, "the shell hosts the pet")
	_assert_tray_points_at(shell, first_pet.get_tray_menu(), "the tray uses the pet's menu while it is open")

	# Closing saves progress and frees the pet; the tray stays.
	first_pet.state.data.coins = 4321
	first_pet._on_context_action(PetMenuBuilderScript.CLOSE_ITEM_ID)
	await _settle()
	_assert_true(not shell.is_pet_open(), "closing the pet frees it")
	_assert_true(not is_instance_valid(first_pet), "the closed pet leaves the tree")
	_assert_true(shell.is_window_concealed(), "closing the pet takes the window off screen")
	_assert_true(shell._link.is_listening(), "the app keeps running while the pet is closed")
	_assert_tray_points_at(shell, shell._closed_menu, "the tray offers only show and quit while closed")
	if is_instance_valid(shell._closed_menu):
		var closed_ids: Array[int] = []
		for index in shell._closed_menu.item_count:
			closed_ids.append(shell._closed_menu.get_item_id(index))
		_assert_true(
			closed_ids.has(PetMenuBuilderScript.SHOW_ITEM_ID)
				and closed_ids[closed_ids.size() - 1] == PetMenuBuilderScript.EXIT_ITEM_ID,
			"the closed tray menu shows the pet and quits"
		)

	# The tray icon brings back a fresh pet that loads the saved progress.
	shell._on_status_indicator_pressed(MOUSE_BUTTON_LEFT, Vector2i.ZERO)
	await _settle()
	_assert_true(shell.is_pet_open(), "clicking the tray icon shows the pet again")
	_assert_true(not shell.is_window_concealed(), "showing the pet brings the window back on screen")
	if shell.is_pet_open():
		_assert_equal(int(shell.pet.state.data.coins), 4321, "the shown pet loads the saved progress")
		_assert_tray_points_at(shell, shell.pet.get_tray_menu(), "the tray uses the new pet's menu")

	# A launch of the same version shows the running pet and stops there.
	_assert_equal(
		shell._on_launch_requested(InstanceLinkScript.current_version()),
		InstanceLinkScript.REPLY_STAY,
		"a second launch of the same version is told to stop"
	)
	await _settle()
	_assert_true(shell.is_pet_open(), "a second launch keeps the running pet open")

	# A real second process must stop without opening another pet.
	_check_second_process(shell)
	await _settle()
	_assert_true(shell.is_pet_open(), "the running pet stays after the second process stops")

	# An older version sees the running pet explain how to switch.
	shell.close_pet()
	await _settle()
	_assert_equal(
		shell._on_launch_requested("0.0.1"),
		InstanceLinkScript.REPLY_STAY,
		"an older launch is told to stop"
	)
	await _settle()
	_assert_true(shell.is_pet_open(), "an older launch shows a closed pet")
	if shell.is_pet_open():
		_assert_equal(
			shell.pet.startup_notice,
			shell.OLDER_VERSION_NOTICE,
			"an older launch makes the pet explain how to use the older version"
		)
		await _wait_frames(10)
		_assert_true(
			shell.pet.bubble.visible
				and shell.pet.bubble_label.text
					== CjkLineBreaksScript.insert_break_opportunities(shell.OLDER_VERSION_NOTICE),
			"the pet says the older-version notice when it appears"
		)

	_assert_equal(
		InstanceLinkScript.decide("99.0.0", InstanceLinkScript.current_version()),
		InstanceLinkScript.REPLY_YIELD,
		"a newer launch asks the running copy to exit"
	)
	_assert_equal(
		InstanceLinkScript.decide("", InstanceLinkScript.current_version()),
		InstanceLinkScript.REPLY_STAY,
		"an unreadable version never closes the running pet"
	)
	var port := InstanceLinkScript.port_for(OS.get_user_data_dir())
	_assert_true(
		port == InstanceLinkScript.port_for(OS.get_user_data_dir().to_upper())
			and port >= InstanceLinkScript.PORT_BASE
			and port < InstanceLinkScript.PORT_BASE + InstanceLinkScript.PORT_SPAN,
		"each data folder maps to one port in the pet's range"
	)

	_finish(shell)


func _check_second_process(shell: Node) -> void:
	var started := Time.get_ticks_msec()
	var pid := OS.create_process(
		OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://")]
	)
	_assert_true(pid > 0, "a second copy starts")
	if pid <= 0:
		return
	var previous_pet: Node = shell.pet
	var answered_before: int = shell._link.answered
	while OS.is_process_running(pid) and Time.get_ticks_msec() - started < 20000:
		# Keep answering the second copy while it waits for its reply.
		shell._process(0.0)
		OS.delay_msec(20)
	_assert_true(not OS.is_process_running(pid), "the second copy stops by itself")
	_assert_equal(
		shell._link.answered, answered_before + 1, "the second copy asked the running one first"
	)
	if OS.is_process_running(pid):
		OS.kill(pid)
	_assert_true(shell.pet == previous_pet, "the second copy does not replace the running pet")


func _assert_tray_points_at(shell: Node, menu: PopupMenu, label: String) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR):
		return
	_assert_true(
		is_instance_valid(shell._status_indicator)
			and is_instance_valid(menu)
			and shell._status_indicator.get_node_or_null(shell._status_indicator.menu) == menu,
		label
	)


func _settle() -> void:
	await _wait_frames(8)


func _wait_frames(count: int) -> void:
	for _i in count:
		await process_frame


func _finish(shell: Node = null) -> void:
	if shell != null:
		shell.exit_app()
	if _failures > 0:
		push_error("APP_SHELL_TEST_FAILED: %d" % _failures)
		quit(1)
		return
	print("APP_SHELL_TEST_OK")
	quit(0)


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAILED: " + label)


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failures += 1
	push_error("FAILED: %s (expected %s, got %s)" % [label, expected, actual])
