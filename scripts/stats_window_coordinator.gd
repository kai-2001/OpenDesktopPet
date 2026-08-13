class_name StatsWindowCoordinator
extends RefCounted

const DetailsWindowControllerScript = preload("res://scripts/details_window_controller.gd")
const AgentIntegrationControllerScript = preload("res://scripts/agent_integration_controller.gd")
const PetVisualScaleScript = preload("res://scripts/pet_visual_scale.gd")
const DEFAULT_WINDOW_SIZE := Vector2i(640, 620)
const MIN_WINDOW_SIZE := Vector2i(360, 480)

signal window_input(event: InputEvent)
signal close_requested
signal tab_selected(index: int)
signal tab_changed(index: int)

var theme_mode := "light"
var last_state_message := "尚無紀錄"
var codex_enabled := false
var codex_app_enabled := false
var terminal_codex_enabled := false
var terminal_opencode_enabled := false
var vscode_opencode_enabled := false
var opencode_app_enabled := false
var copilot_enabled := false
var claude_vscode_enabled := false
var claude_app_enabled := false
var claude_terminal_enabled := false
var gemini_terminal_enabled := false
var agy_terminal_enabled := false
var agent_port := AgentIntegrationControllerScript.DEFAULT_PORT
var codex_executable_path := ""
var codex_app_executable_path := ""
var terminal_executable_path := ""
var opencode_app_executable_path := ""
var claude_app_executable_path := ""
var autostart_supported := false
var keep_screen_on := false
var focus_mode := false
var visual_scale := PetVisualScaleScript.DEFAULT_VALUE
var interaction_label: Callable
var interaction_icon: Callable
var details_controller
var window: Window


func build(owner: Node) -> Dictionary:
	window = Window.new()
	window.name = "StatsWindow"
	window.title = "桌寵詳細狀態"
	window.size = DEFAULT_WINDOW_SIZE
	window.min_size = MIN_WINDOW_SIZE
	window.unresizable = false
	window.transient = false
	window.always_on_top = false
	window.visible = false
	window.close_requested.connect(func() -> void: close_requested.emit())
	window.window_input.connect(func(event: InputEvent) -> void: window_input.emit(event))
	owner.add_child(window)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.theme = _create_details_theme()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = _details_color("#f7f8f9", "#181818")
	panel_style.border_color = _details_color("#dce3e6", "#333333")
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", panel_style)
	window.add_child(panel)

	var root_layout := VBoxContainer.new()
	root_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_layout.add_theme_constant_override("separation", 0)
	panel.add_child(root_layout)

	var navigation_margin := MarginContainer.new()
	navigation_margin.add_theme_constant_override("margin_left", 14)
	navigation_margin.add_theme_constant_override("margin_top", 10)
	navigation_margin.add_theme_constant_override("margin_right", 14)
	navigation_margin.add_theme_constant_override("margin_bottom", 8)
	root_layout.add_child(navigation_margin)
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 8)
	navigation_margin.add_child(navigation)
	var tab_buttons: Array[Button] = []
	for tab_index: int in 4:
		var navigation_button := Button.new()
		navigation_button.text = ["狀態", "設定", "Agent", "角色"][tab_index]
		navigation_button.custom_minimum_size.y = 40
		navigation_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		navigation_button.focus_mode = Control.FOCUS_NONE
		navigation_button.pressed.connect(
			func() -> void: tab_selected.emit(tab_index)
		)
		navigation.add_child(navigation_button)
		tab_buttons.append(navigation_button)

	var tabs := TabContainer.new()
	tabs.name = "DetailsTabs"
	tabs.theme = panel.theme
	tabs.tabs_visible = false
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_layout.add_child(tabs)

	details_controller = DetailsWindowControllerScript.new()
	details_controller.theme_mode = theme_mode
	details_controller.last_state_message = last_state_message
	details_controller.codex_enabled = codex_enabled
	details_controller.codex_app_enabled = codex_app_enabled
	details_controller.terminal_codex_enabled = terminal_codex_enabled
	details_controller.terminal_opencode_enabled = terminal_opencode_enabled
	details_controller.vscode_opencode_enabled = vscode_opencode_enabled
	details_controller.opencode_app_enabled = opencode_app_enabled
	details_controller.copilot_enabled = copilot_enabled
	details_controller.claude_vscode_enabled = claude_vscode_enabled
	details_controller.claude_app_enabled = claude_app_enabled
	details_controller.claude_terminal_enabled = claude_terminal_enabled
	details_controller.gemini_terminal_enabled = gemini_terminal_enabled
	details_controller.agy_terminal_enabled = agy_terminal_enabled
	details_controller.agent_port = agent_port
	details_controller.vscode_executable_path = codex_executable_path
	details_controller.codex_app_executable_path = codex_app_executable_path
	details_controller.terminal_executable_path = terminal_executable_path
	details_controller.opencode_app_executable_path = opencode_app_executable_path
	details_controller.claude_app_executable_path = claude_app_executable_path
	details_controller.autostart_supported = autostart_supported
	details_controller.keep_screen_on = keep_screen_on
	details_controller.focus_mode = focus_mode
	details_controller.visual_scale = visual_scale
	details_controller.interaction_label = interaction_label
	details_controller.interaction_icon = interaction_icon
	var status_refs: Dictionary = details_controller.build_status_tab(tabs)
	var settings_refs: Dictionary = details_controller.build_settings_tab(tabs)
	var agent_refs: Dictionary = details_controller.build_agent_tab(tabs)
	var character_refs: Dictionary = details_controller.build_character_tab(
		tabs, window
	)
	tabs.tab_changed.connect(func(index: int) -> void: tab_changed.emit(index))
	return {
		"window": window,
		"tabs": tabs,
		"tab_buttons": tab_buttons,
		"details_controller": details_controller,
		"status_refs": status_refs,
		"settings_refs": settings_refs,
		"agent_refs": agent_refs,
		"character_refs": character_refs,
	}


func destroy() -> void:
	if is_instance_valid(window):
		window.queue_free()
	window = null
	details_controller = null


func _details_color(light: String, dark: String) -> Color:
	return Color(dark if theme_mode == "dark" else light)


func _create_details_theme() -> Theme:
	var theme := Theme.new()
	var empty_panel := StyleBoxEmpty.new()
	theme.set_stylebox("panel", "TabContainer", empty_panel)
	theme.set_stylebox("panel", "ScrollContainer", empty_panel)
	var scroll_track := StyleBoxFlat.new()
	scroll_track.bg_color = _details_color("#eef1f3", "#292929")
	scroll_track.set_corner_radius_all(6)
	scroll_track.content_margin_left = 2
	scroll_track.content_margin_right = 2
	var scroll_grabber := StyleBoxFlat.new()
	scroll_grabber.bg_color = _details_color("#b9c5c9", "#5a5a5a")
	scroll_grabber.set_corner_radius_all(6)
	scroll_grabber.content_margin_left = 2
	scroll_grabber.content_margin_right = 2
	var scroll_grabber_hover := StyleBoxFlat.new()
	scroll_grabber_hover.bg_color = _details_color("#9eafb4", "#707070")
	scroll_grabber_hover.set_corner_radius_all(6)
	var scroll_grabber_pressed := StyleBoxFlat.new()
	scroll_grabber_pressed.bg_color = _details_color("#84999f", "#858585")
	scroll_grabber_pressed.set_corner_radius_all(6)
	for scroll_type: String in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", scroll_type, scroll_track)
		theme.set_stylebox("scroll_focus", scroll_type, scroll_track)
		theme.set_stylebox("grabber", scroll_type, scroll_grabber)
		theme.set_stylebox("grabber_highlight", scroll_type, scroll_grabber_hover)
		theme.set_stylebox("grabber_pressed", scroll_type, scroll_grabber_pressed)
		theme.set_constant("minimum_grabber_size", scroll_type, 24)
	var normal := _details_style(
		_details_color("#ffffff", "#252526"),
		_details_color("#d6dee2", "#3c3c3c"), 8
	)
	var hover := _details_style(
		_details_color("#edf8fa", "#2a2d2e"),
		_details_color("#78c8d5", "#4e94ce"), 8
	)
	var pressed := _details_style(
		_details_color("#d9f0f4", "#094771"),
		_details_color("#35a9bd", "#3794ff"), 8
	)
	var disabled := _details_style(
		_details_color("#eef1f2", "#232323"),
		_details_color("#e1e6e8", "#333333"), 8
	)
	for type_name: String in ["Button", "OptionButton", "CheckBox"]:
		theme.set_stylebox("normal", type_name, normal)
		theme.set_stylebox("hover", type_name, hover)
		theme.set_stylebox("pressed", type_name, pressed)
		theme.set_stylebox("hover_pressed", type_name, pressed)
		theme.set_stylebox("focus", type_name, pressed)
		theme.set_stylebox("disabled", type_name, disabled)
		theme.set_color("font_color", type_name, _details_color("#30383c", "#cccccc"))
		theme.set_color("font_hover_color", type_name, _details_color("#176f7e", "#ffffff"))
		theme.set_color("font_pressed_color", type_name, _details_color("#145f6c", "#ffffff"))
		theme.set_color("font_hover_pressed_color", type_name, _details_color("#145f6c", "#ffffff"))
		theme.set_color("font_focus_color", type_name, _details_color("#145f6c", "#ffffff"))
		theme.set_color("font_disabled_color", type_name, _details_color("#99a3a8", "#6d6d6d"))
		theme.set_constant("align_to_largest_stylebox", type_name, 1)
		theme.set_font_size("font_size", type_name, 14)

	var list_panel := _details_style(
		_details_color("#ffffff", "#1e1e1e"),
		_details_color("#dce3e6", "#3c3c3c"), 9
	)
	var list_selected := _details_style(
		_details_color("#cfeef3", "#094771"),
		_details_color("#59b9c8", "#3794ff"), 7
	)
	var list_hover := _details_style(
		_details_color("#e7f5f7", "#2a2d2e"),
		_details_color("#a8d9e0", "#3c3c3c"), 7
	)
	var list_focus := _details_style(
		Color(0, 0, 0, 0), _details_color("#8bcbd5", "#4e94ce"), 9
	)
	theme.set_stylebox("panel", "ItemList", list_panel)
	theme.set_stylebox("selected", "ItemList", list_selected)
	theme.set_stylebox("selected_focus", "ItemList", list_selected)
	theme.set_stylebox("hovered", "ItemList", list_hover)
	theme.set_stylebox("hovered_selected", "ItemList", list_selected)
	theme.set_stylebox("focus", "ItemList", list_focus)
	theme.set_color("font_color", "ItemList", _details_color("#30383c", "#cccccc"))
	theme.set_color("font_hovered_color", "ItemList", _details_color("#164f59", "#ffffff"))
	theme.set_color("font_selected_color", "ItemList", _details_color("#103f47", "#ffffff"))
	theme.set_font_size("font_size", "ItemList", 14)

	var popup_panel := _details_style(
		_details_color("#ffffff", "#252526"),
		_details_color("#d6dee2", "#454545"), 8
	)
	var popup_hover := _details_style(
		_details_color("#dff2f5", "#094771"),
		_details_color("#91cfd8", "#3794ff"), 6
	)
	theme.set_stylebox("panel", "PopupMenu", popup_panel)
	theme.set_stylebox("hover", "PopupMenu", popup_hover)
	theme.set_color("font_color", "PopupMenu", _details_color("#30383c", "#cccccc"))
	theme.set_color("font_hover_color", "PopupMenu", _details_color("#103f47", "#ffffff"))

	var tooltip_panel := _details_style(
		_details_color("#243136", "#252526"),
		_details_color("#40545b", "#555555"), 6
	)
	theme.set_stylebox("panel", "TooltipPanel", tooltip_panel)
	theme.set_color("font_color", "TooltipLabel", Color("#f5f5f5"))
	theme.set_font_size("font_size", "TooltipLabel", 13)

	var separator := StyleBoxLine.new()
	separator.color = _details_color("#dde4e7", "#3c3c3c")
	separator.thickness = 1
	theme.set_stylebox("separator", "HSeparator", separator)
	theme.set_color("font_color", "CheckBox", _details_color("#30383c", "#cccccc"))
	theme.set_color("font_hover_color", "CheckBox", _details_color("#176f7e", "#ffffff"))
	theme.set_color("font_disabled_color", "CheckBox", _details_color("#99a3a8", "#6d6d6d"))
	theme.set_color("font_selected_color", "TabBar", Color("#ffffff"))
	theme.set_color("font_unselected_color", "TabBar", _details_color("#0f0f0f", "#9da1a6"))
	theme.set_color("font_hovered_color", "TabBar", _details_color("#0f0f0f", "#ffffff"))
	return theme

func _details_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
