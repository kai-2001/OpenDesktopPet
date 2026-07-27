class_name PetVisual
extends Node2D

const IDLE_SHEET := "res://private_pets/active/idle-actions.png"
const CARE_SHEET := "res://private_pets/active/care-actions.png"
const MOVEMENT_SHEET := "res://private_pets/active/movement-actions.png"
const LEGACY_SHEET := "res://private_pets/active/reference-sheet.png"

var _sprite: Sprite2D
var _sheets: Dictionary = {}
var _using_private_sheet := false
var _time := 0.0
var _busy := false
var _dragging := false
var _drag_is_moving := false
var _visual_size := 1.0
var _home_position := Vector2.ZERO


func _ready() -> void:
	_home_position = position
	_sprite = Sprite2D.new()
	add_child(_sprite)
	_load_sheet("idle", IDLE_SHEET, 4)
	_load_sheet("care", CARE_SHEET, 4)
	_load_sheet("movement", MOVEMENT_SHEET, 4)
	_load_sheet("legacy", LEGACY_SHEET, 3)
	if _sheets.has("idle"):
		_using_private_sheet = true
		_show_frame("idle", 0)
	elif _sheets.has("legacy"):
		_using_private_sheet = true
		_show_frame("legacy", 0)
	else:
		queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _dragging:
		scale = Vector2(1.04, 0.94)
	elif not _busy:
		var breath := 1.0 + sin(_time * 2.2) * 0.018
		scale = Vector2(1.0 / breath, breath)


func set_dragging(value: bool) -> void:
	_dragging = value
	_drag_is_moving = false
	if value:
		_show_frame("movement", 2)
	else:
		_show_idle()
		if not _busy:
			scale = Vector2.ONE


func set_drag_motion(is_moving: bool) -> void:
	if not _dragging or _drag_is_moving == is_moving:
		return
	_drag_is_moving = is_moving
	_show_frame("movement", 3 if is_moving else 2)


func is_busy() -> bool:
	return _busy or _dragging


func change_visual_size(delta: float) -> void:
	_visual_size = clampf(_visual_size + delta, 0.7, 1.4)
	_apply_sprite_scale()


func play_action(action: String) -> void:
	if _busy or _dragging:
		return
	_busy = true
	match action:
		"clap", "happy":
			await _clap(false)
		"belly_clap":
			await _clap(true)
		"eat":
			await _care_pose(0, 1.7)
		"drink":
			await _care_pose(1, 1.7)
		"sleep":
			await _sleepy()
		"roll":
			await _roll_visual()
		"wiggle":
			_show_frame("idle", 0)
			await _wiggle()
		_:
			await get_tree().create_timer(0.4).timeout
	_show_idle()
	rotation = 0.0
	position = _home_position
	scale = Vector2.ONE
	_busy = false


func _load_sheet(key: String, path: String, columns: int) -> void:
	if not ResourceLoader.exists(path):
		return
	var texture := load(path) as Texture2D
	if texture:
		_sheets[key] = {"texture": texture, "columns": columns}


func _show_frame(sheet_key: String, index: int) -> void:
	if not _sheets.has(sheet_key):
		if sheet_key != "legacy" and _sheets.has("legacy"):
			_show_frame("legacy", clampi(index, 0, 2))
		return
	var sheet: Dictionary = _sheets[sheet_key]
	var texture: Texture2D = sheet.texture
	var columns: int = sheet.columns
	var cell_width := float(texture.get_width()) / columns
	_sprite.texture = texture
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(cell_width * clampi(index, 0, columns - 1), 0, cell_width, texture.get_height())
	_sprite.position = Vector2(0, 8)
	_apply_sprite_scale()


func _apply_sprite_scale() -> void:
	if not _sprite or not _sprite.texture:
		return
	var columns: int = 4
	for value: Dictionary in _sheets.values():
		if value.texture == _sprite.texture:
			columns = value.columns
			break
	var cell_width := float(_sprite.texture.get_width()) / columns
	var base_scale := 125.0 / cell_width
	_sprite.scale = Vector2.ONE * base_scale * _visual_size


func _show_idle() -> void:
	if _sheets.has("idle"):
		_show_frame("idle", 0)
	else:
		_show_frame("legacy", 0)


func _clap(belly_up: bool) -> void:
	if belly_up:
		_show_frame("idle", 3)
		await _soft_bounce(2)
		return
	for frame in [1, 2, 1, 2]:
		_show_frame("idle", frame)
		await get_tree().create_timer(0.16).timeout
	await _soft_bounce(1)


func _care_pose(frame: int, duration: float) -> void:
	_show_frame("care", frame)
	var tween := create_tween()
	tween.set_loops(3)
	tween.tween_property(self, "position:y", _home_position.y - 4.0, 0.18)
	tween.tween_property(self, "position:y", _home_position.y, 0.18)
	await get_tree().create_timer(duration).timeout
	tween.kill()


func _sleepy() -> void:
	_show_frame("care", 2)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.06, 0.94), 0.45)
	tween.tween_property(self, "scale", Vector2(0.98, 1.02), 0.65)
	tween.set_loops(2)
	await get_tree().create_timer(2.2).timeout
	tween.kill()
	_show_frame("care", 3)
	await get_tree().create_timer(0.55).timeout


func _roll_visual() -> void:
	for frame in [0, 1, 0, 1]:
		_show_frame("movement", frame)
		await get_tree().create_timer(0.16).timeout


func _soft_bounce(count: int) -> void:
	var tween := create_tween()
	tween.set_loops(count)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "position:y", _home_position.y - 12.0, 0.16)
	tween.tween_property(self, "position:y", _home_position.y, 0.18)
	await tween.finished


func _wiggle() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "rotation", -0.07, 0.12)
	tween.tween_property(self, "rotation", 0.07, 0.20)
	tween.tween_property(self, "rotation", -0.04, 0.16)
	tween.tween_property(self, "rotation", 0.0, 0.12)
	await tween.finished


func _draw() -> void:
	if _using_private_sheet:
		return
	draw_circle(Vector2.ZERO, 112.0, Color("#a9d9e8"))
	draw_circle(Vector2(0, 30), 78.0, Color("#f6ead2"))
	draw_circle(Vector2(-39, -31), 10.0, Color("#183247"))
	draw_circle(Vector2(39, -31), 10.0, Color("#183247"))
	draw_circle(Vector2.ZERO, 9.0, Color("#183247"))
	draw_arc(Vector2(0, 7), 24.0, 0.25, PI - 0.25, 24, Color("#183247"), 5.0)
	draw_circle(Vector2(-92, 60), 34.0, Color("#86c5d9"))
	draw_circle(Vector2(92, 60), 34.0, Color("#86c5d9"))
