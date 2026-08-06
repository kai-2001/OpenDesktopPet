extends SceneTree

var _main: Node


func _init() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	call_deferred("_run_test")


func _run_test() -> void:
	await process_frame
	_main.call("_show_stats_window")
	await process_frame
	await process_frame

	var stats_window := _main.find_child("StatsWindow", true, false) as Window
	var tabs := _main.find_child("DetailsTabs", true, false) as TabContainer
	var character_list := _main.find_child("CharacterList", true, false) as ItemList
	_assert_true(stats_window != null, "details window exists")
	_assert_true(tabs != null, "details tabs exist")
	_assert_true(tabs.get_tab_count() == 3, "details window has three tabs")
	_assert_true(character_list != null, "character list exists")

	var state_option := _main.find_child(
		"CodexStateOptionButton", true, false
	) as OptionButton
	var configure_button := _main.find_child(
		"CodexConfigureButton", true, false
	) as Button
	var reconnect_button := _main.find_child(
		"CodexReconnectButton", true, false
	) as Button
	_assert_true(state_option != null, "Codex state selector exists")
	_assert_true(configure_button != null, "Codex configure button exists")
	_assert_true(reconnect_button != null, "Codex reconnect button exists")
	_assert_true(state_option.selected == 1, "new settings default to closed")
	_assert_true(
		not configure_button.disabled,
		"new settings enable configure button"
	)
	_assert_true(
		reconnect_button.disabled,
		"new settings disable reconnect button"
	)

	state_option.select(1)
	state_option.item_selected.emit(1)
	await process_frame
	_assert_true(
		not configure_button.disabled,
		"closed state enables configure button"
	)
	_assert_true(
		reconnect_button.disabled,
		"closed state disables reconnect button"
	)

	state_option.select(0)
	state_option.item_selected.emit(0)
	await process_frame
	_assert_true(
		configure_button.disabled,
		"open state disables configure button"
	)
	_assert_true(
		not reconnect_button.disabled,
		"open state enables reconnect button"
	)

	tabs.current_tab = 2
	await process_frame
	_assert_true(tabs.current_tab == 2, "character tab can be selected")

	_main.call("_prepare_shutdown")
	_main.queue_free()
	print("CODEX_SETTINGS_UI_TEST_OK")
	quit()


func _assert_true(value: bool, message: String) -> void:
	if not value:
		push_error("CODEX_SETTINGS_UI_TEST_FAILED: " + message)
		quit(1)
