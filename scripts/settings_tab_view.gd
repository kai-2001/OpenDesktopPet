class_name SettingsTabView
extends "res://scripts/details_tab_view.gd"

const PetVisualScaleScript = preload("res://scripts/pet_visual_scale.gd")
const UpdateCheckServiceScript = preload("res://scripts/update_check_service.gd")
const TARGET_FPS_OPTIONS := [15, 30, 60]

signal target_fps_selected(index: int)
signal details_theme_selected(index: int)
signal autostart_toggled(enabled: bool)
signal keep_screen_on_toggled(enabled: bool)
signal focus_mode_toggled(enabled: bool)
signal update_auto_check_toggled(enabled: bool)
signal update_check_requested
signal update_release_page_requested
signal update_skip_requested
signal visual_scale_previewed(value: float)
signal visual_scale_changed(value: float)

var autostart_supported := false
var keep_screen_on := false
var focus_mode := false
var visual_scale := PetVisualScaleScript.DEFAULT_VALUE


func build(tabs: TabContainer) -> Dictionary:
	var settings_scroll := ScrollContainer.new()
	settings_scroll.name = "設定"
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(settings_scroll)

	var settings_margin := MarginContainer.new()
	settings_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_margin.add_theme_constant_override("margin_left", 24)
	settings_margin.add_theme_constant_override("margin_top", 20)
	settings_margin.add_theme_constant_override("margin_right", 24)
	settings_margin.add_theme_constant_override("margin_bottom", 20)
	settings_scroll.add_child(settings_margin)

	var settings_content := VBoxContainer.new()
	settings_content.add_theme_constant_override("separation", 16)
	settings_margin.add_child(settings_content)

	var settings_title: Label = _new_label(
		"桌寵設定", 24, _details_color("#20272b", "#f0f0f0")
	)
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_content.add_child(settings_title)

	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", 12)
	var fps_label: Label = _new_label(
		"桌寵幀率（FPS）", 16, _details_color("#30383c", "#d4d4d4")
	)
	fps_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_row.add_child(fps_label)
	var fps_option_button := OptionButton.new()
	for fps: int in TARGET_FPS_OPTIONS:
		fps_option_button.add_item("%d FPS" % fps, fps)
	fps_option_button.select(fps_option_button.get_item_index(Engine.max_fps))
	fps_option_button.custom_minimum_size = Vector2(120, 40)
	fps_option_button.item_selected.connect(
		func(index: int) -> void: target_fps_selected.emit(index)
	)
	fps_row.add_child(fps_option_button)
	settings_content.add_child(fps_row)

	var fps_hint: Label = _new_label(
		"控制整個桌寵的更新率（15–60）；30 FPS 適合日常使用，降低可省電。",
		13,
		_details_color("#68747a", "#9da1a6")
	)
	fps_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_content.add_child(fps_hint)
	settings_content.add_child(HSeparator.new())

	var theme_row := HBoxContainer.new()
	theme_row.add_theme_constant_override("separation", 12)
	var theme_label: Label = _new_label(
		"詳細面板主題", 16, _details_color("#30383c", "#d4d4d4")
	)
	theme_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme_row.add_child(theme_label)
	var details_theme_option_button := OptionButton.new()
	details_theme_option_button.add_item("淺色", 0)
	details_theme_option_button.add_item("深色", 1)
	details_theme_option_button.select(
		1 if theme_mode == "dark" else 0
	)
	details_theme_option_button.custom_minimum_size = Vector2(120, 40)
	details_theme_option_button.item_selected.connect(
		func(index: int) -> void: details_theme_selected.emit(index)
	)
	theme_row.add_child(details_theme_option_button)
	settings_content.add_child(theme_row)

	var theme_hint: Label = _new_label(
		"切換詳細面板的完整配色；設定會自動保存。",
		13,
		_details_color("#68747a", "#9da1a6")
	)
	settings_content.add_child(theme_hint)
	settings_content.add_child(HSeparator.new())

	var visual_scale_content := VBoxContainer.new()
	visual_scale_content.add_theme_constant_override("separation", 8)

	var visual_scale_value_label: Label = _new_label(
		"100%", 15, _details_color("#238b9d", "#4fc1ff")
	)
	visual_scale_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_scale_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	visual_scale_value_label.custom_minimum_size.x = 64
	visual_scale_value_label.text = "%d%%" % roundi(visual_scale * 100.0)
	var visual_scale_label: Label = _new_label(
		"桌寵大小", 16, _details_color("#30383c", "#d4d4d4")
	)
	visual_scale_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_scale_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var visual_scale_row := HBoxContainer.new()
	visual_scale_row.add_theme_constant_override("separation", 12)
	visual_scale_row.mouse_filter = Control.MOUSE_FILTER_PASS
	visual_scale_row.add_child(visual_scale_label)
	visual_scale_row.add_child(visual_scale_value_label)

	var visual_scale_slider := HSlider.new()
	visual_scale_slider.name = "VisualScaleSlider"
	visual_scale_slider.min_value = PetVisualScaleScript.MIN_VALUE
	visual_scale_slider.max_value = PetVisualScaleScript.MAX_VALUE
	visual_scale_slider.step = PetVisualScaleScript.STEP
	visual_scale_slider.value = visual_scale
	visual_scale_slider.scrollable = false
	visual_scale_slider.custom_minimum_size = Vector2(0, 32)
	visual_scale_slider.tooltip_text = "調整桌寵顯示大小"
	var visual_scale_track := StyleBoxFlat.new()
	visual_scale_track.bg_color = _details_color("#dce5e7", "#3a4145")
	visual_scale_track.set_corner_radius_all(5)
	visual_scale_track.content_margin_top = 5
	visual_scale_track.content_margin_bottom = 5
	var visual_scale_area := StyleBoxFlat.new()
	visual_scale_area.bg_color = _details_color("#08a6b5", "#35a9bd")
	visual_scale_area.set_corner_radius_all(5)
	visual_scale_area.content_margin_top = 5
	visual_scale_area.content_margin_bottom = 5
	var visual_scale_area_highlight := StyleBoxFlat.new()
	visual_scale_area_highlight.bg_color = _details_color("#087f8b", "#4fc1ff")
	visual_scale_area_highlight.set_corner_radius_all(5)
	visual_scale_area_highlight.content_margin_top = 5
	visual_scale_area_highlight.content_margin_bottom = 5
	var visual_scale_theme := Theme.new()
	visual_scale_theme.set_stylebox("slider", "HSlider", visual_scale_track)
	visual_scale_theme.set_stylebox("grabber_area", "HSlider", visual_scale_area)
	visual_scale_theme.set_stylebox(
		"grabber_area_highlight", "HSlider", visual_scale_area_highlight
	)
	visual_scale_theme.set_icon(
		"grabber", "HSlider", _create_slider_grabber_texture(false)
	)
	visual_scale_theme.set_icon(
		"grabber_highlight", "HSlider", _create_slider_grabber_texture(true)
	)
	visual_scale_theme.set_constant("center_grabber", "HSlider", 1)
	visual_scale_slider.theme = visual_scale_theme
	var visual_scale_commit_timer := Timer.new()
	visual_scale_commit_timer.one_shot = true
	visual_scale_commit_timer.wait_time = 0.2
	visual_scale_slider.add_child(visual_scale_commit_timer)
	visual_scale_commit_timer.timeout.connect(
		func() -> void: visual_scale_changed.emit(visual_scale_slider.value)
	)
	visual_scale_slider.value_changed.connect(
		func(value: float) -> void:
			visual_scale_value_label.text = "%d%%" % roundi(value * 100.0)
			visual_scale_previewed.emit(value)
			visual_scale_commit_timer.start()
	)
	visual_scale_slider.gui_input.connect(
		_handle_visual_scale_wheel.bind(visual_scale_slider)
	)
	visual_scale_content.add_child(visual_scale_row)
	visual_scale_content.add_child(visual_scale_slider)

	var visual_scale_hint: Label = _new_label(
		"可調整為原始顯示大小的 %d%%–%d%%；設定會保存。" % [
			roundi(PetVisualScaleScript.MIN_VALUE * 100.0),
			roundi(PetVisualScaleScript.MAX_VALUE * 100.0),
		],
		13,
		_details_color("#68747a", "#9da1a6")
	)
	visual_scale_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_scale_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	visual_scale_content.add_child(visual_scale_hint)
	settings_content.add_child(visual_scale_content)
	settings_content.add_child(HSeparator.new())

	var focus_mode_check_box := CheckBox.new()
	focus_mode_check_box.text = "專注模式（不自主移動或做動作）"
	focus_mode_check_box.add_theme_font_size_override("font_size", 16)
	_style_checkbox(focus_mode_check_box)
	focus_mode_check_box.custom_minimum_size = Vector2(0, 40)
	focus_mode_check_box.button_pressed = focus_mode
	focus_mode_check_box.toggled.connect(
		func(enabled: bool) -> void: focus_mode_toggled.emit(enabled)
	)
	settings_content.add_child(focus_mode_check_box)

	var focus_mode_hint: Label = _new_label(
		"開啟後會停止桌寵自主移動、吃飯、喝水、睡覺與其他自主動作；手動操作仍可使用。",
		13,
		_details_color("#68747a", "#9da1a6")
	)
	focus_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_content.add_child(focus_mode_hint)
	settings_content.add_child(HSeparator.new())

	var keep_screen_on_check_box := CheckBox.new()
	keep_screen_on_check_box.text = "保持螢幕喚醒（阻止系統休眠）"
	keep_screen_on_check_box.add_theme_font_size_override("font_size", 16)
	_style_checkbox(keep_screen_on_check_box)
	keep_screen_on_check_box.custom_minimum_size = Vector2(0, 40)
	keep_screen_on_check_box.button_pressed = keep_screen_on
	keep_screen_on_check_box.toggled.connect(
		func(enabled: bool) -> void: keep_screen_on_toggled.emit(enabled)
	)
	settings_content.add_child(keep_screen_on_check_box)

	var keep_screen_on_hint: Label = _new_label(
		"開啟後會要求 Windows 保持螢幕喚醒；關閉後恢復系統電源計畫。",
		13,
		_details_color("#68747a", "#9da1a6")
	)
	keep_screen_on_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_content.add_child(keep_screen_on_hint)
	settings_content.add_child(HSeparator.new())

	var autostart_check_box := CheckBox.new()
	autostart_check_box.text = "登入 Windows 時自動開啟桌寵"
	autostart_check_box.add_theme_font_size_override("font_size", 16)
	_style_checkbox(autostart_check_box)
	autostart_check_box.custom_minimum_size = Vector2(0, 40)
	autostart_check_box.button_pressed = false
	autostart_check_box.disabled = true
	autostart_check_box.toggled.connect(
		func(enabled: bool) -> void: autostart_toggled.emit(enabled)
	)
	settings_content.add_child(autostart_check_box)

	var settings_feedback: Label = _new_label(
		"請使用打包版設定開機啟動。"
		if not autostart_supported
		else "正在讀取 Windows 開機啟動設定…",
		13,
		_details_color("#68747a", "#9da1a6")
	)
	settings_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_content.add_child(settings_feedback)
	if not autostart_supported:
		settings_feedback.text = "目前平台不支援 Windows 開機啟動設定。"
	settings_content.add_child(HSeparator.new())

	var update_refs := _build_update_section(settings_content)

	return {
		"fps_option_button": fps_option_button,
		"details_theme_option_button": details_theme_option_button,
		"visual_scale_slider": visual_scale_slider,
		"visual_scale_value_label": visual_scale_value_label,
		"focus_mode_check_box": focus_mode_check_box,
		"keep_screen_on_check_box": keep_screen_on_check_box,
		"autostart_check_box": autostart_check_box,
		"settings_feedback": settings_feedback,
		"update_auto_check_box": update_refs["auto_check_box"],
		"update_status_label": update_refs["status_label"],
		"update_check_button": update_refs["check_button"],
		"update_release_page_button": update_refs["release_page_button"],
		"update_skip_button": update_refs["skip_button"],
	}


func _build_update_section(settings_content: VBoxContainer) -> Dictionary:
	var update_title_row := HBoxContainer.new()
	update_title_row.add_theme_constant_override("separation", 12)
	var update_title: Label = _new_label(
		"版本更新", 16, _details_color("#30383c", "#d4d4d4")
	)
	update_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	update_title_row.add_child(update_title)
	update_title_row.add_child(_new_label(
		"目前版本 v%s" % UpdateCheckServiceScript.current_version(),
		14,
		_details_color("#68747a", "#9da1a6")
	))
	settings_content.add_child(update_title_row)

	var auto_check_box := CheckBox.new()
	auto_check_box.text = "自動檢查新版本（每天最多一次）"
	auto_check_box.add_theme_font_size_override("font_size", 16)
	_style_checkbox(auto_check_box)
	auto_check_box.custom_minimum_size = Vector2(0, 40)
	auto_check_box.toggled.connect(
		func(enabled: bool) -> void: update_auto_check_toggled.emit(enabled)
	)
	settings_content.add_child(auto_check_box)

	var privacy_hint: Label = _new_label(
		"預設關閉。檢查時只會向 GitHub 查詢最新的版本號，不會傳送你的設定、存檔、"
			+ "角色、Agent 資料或任何識別資訊；GitHub 仍會看到你的 IP 位址。"
			+ "桌寵只會開啟本專案的 GitHub 下載頁，不會自行下載或安裝。",
		13,
		_details_color("#68747a", "#9da1a6")
	)
	privacy_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_content.add_child(privacy_hint)

	var status_label: Label = _new_label(
		"尚未檢查。", 14, _details_color("#238b9d", "#4fc1ff")
	)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_content.add_child(status_label)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	var check_button := Button.new()
	check_button.text = "立即檢查"
	check_button.custom_minimum_size = Vector2(110, 38)
	_apply_secondary_button_style(check_button)
	check_button.pressed.connect(func() -> void: update_check_requested.emit())
	button_row.add_child(check_button)
	var release_page_button := Button.new()
	release_page_button.text = "前往下載頁"
	release_page_button.custom_minimum_size = Vector2(110, 38)
	release_page_button.visible = false
	_apply_primary_button_style(release_page_button)
	release_page_button.pressed.connect(
		func() -> void: update_release_page_requested.emit()
	)
	button_row.add_child(release_page_button)
	var skip_button := Button.new()
	skip_button.text = "略過這個版本"
	skip_button.custom_minimum_size = Vector2(110, 38)
	skip_button.visible = false
	_apply_secondary_button_style(skip_button)
	skip_button.pressed.connect(func() -> void: update_skip_requested.emit())
	button_row.add_child(skip_button)
	settings_content.add_child(button_row)

	return {
		"auto_check_box": auto_check_box,
		"status_label": status_label,
		"check_button": check_button,
		"release_page_button": release_page_button,
		"skip_button": skip_button,
	}


func _handle_visual_scale_wheel(event: InputEvent, slider: HSlider) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed:
		return
	var direction := 0.0
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		direction = 1.0
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		direction = -1.0
	if is_zero_approx(direction):
		return
	slider.value = clampf(
		slider.value + slider.step * direction,
		slider.min_value,
		slider.max_value
	)
	slider.accept_event()


func _create_slider_grabber_texture(highlighted: bool) -> Texture2D:
	const texture_size := 28
	const shadow_radius := 11.5
	const outer_radius := 10.0
	const inner_radius := 5.0
	var image := Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	var center := Vector2(texture_size, texture_size) * 0.5
	var shadow_color := Color(0.0, 0.0, 0.0, 0.14 if highlighted else 0.10)
	var border_color := _details_color("#cfd7da", "#6b7377")
	var outer_color := _details_color("#ffffff", "#f4f6f7")
	var inner_color := _details_color(
		"#079dac" if not highlighted else "#087f8b",
		"#35a9bd" if not highlighted else "#4fc1ff"
	)
	var effective_inner_radius := inner_radius + (0.5 if highlighted else 0.0)
	for y in texture_size:
		for x in texture_size:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var pixel_color := Color.TRANSPARENT
			if distance <= effective_inner_radius - 0.5:
				pixel_color = inner_color
			elif distance <= effective_inner_radius + 0.5:
				pixel_color = inner_color.lerp(
					outer_color,
					distance - (effective_inner_radius - 0.5)
				)
			elif distance <= outer_radius - 1.0:
				pixel_color = outer_color
			elif distance <= outer_radius:
				pixel_color = border_color
			elif distance <= outer_radius + 0.5:
				pixel_color = border_color
				pixel_color.a = lerpf(
					1.0,
					shadow_color.a,
					distance - outer_radius
				)
			elif distance <= shadow_radius:
				pixel_color = shadow_color
				pixel_color.a *= clampf(
					(shadow_radius - distance) / (shadow_radius - outer_radius),
					0.0,
					1.0
				)
			image.set_pixel(x, y, pixel_color)
	return ImageTexture.create_from_image(image)
