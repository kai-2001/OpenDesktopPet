class_name PetVisual
extends Node2D

const FRAME_DIR := "res://private_pets/active/rig2d/fullframes/"
const SHEETS := {
	"idle": ["idle.png", 4],
	"roll": ["roll.png", 4],
	"belly_clap": ["belly-clap.png", 4],
	"sleep": ["sleep.png", 4],
	"actions": ["actions.png", 4],
	"drag": ["drag.png", 3],
}

var _sprite: Sprite2D
var _textures: Dictionary = {}
var _columns: Dictionary = {}
var _busy := false
var _dragging := false
var _drag_moving := false
var _visual_size := 1.0
var _time := 0.0
var _idle_clock := 0.0
var _idle_step := 0
var _home_position := Vector2.ZERO
var _animation_serial := 0


func _ready() -> void:
	_home_position = position
	for key: String in SHEETS:
		var spec: Array = SHEETS[key]
		var texture := _load_texture(FRAME_DIR + String(spec[0]))
		if texture:
			_textures[key] = texture
			_columns[key] = int(spec[1])
	_sprite = Sprite2D.new()
	_sprite.z_index = 1
	add_child(_sprite)
	if _textures.has("idle"):
		_show_frame("idle", 0)
	else:
		push_error("The private full-frame pet animation set is incomplete.")
		queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _dragging:
		var sway := sin(_time * 8.0) * (0.025 if _drag_moving else 0.008)
		rotation = sway
		return
	if _busy:
		return
	_idle_clock += delta
	var breath := 1.0 + sin(_time * 2.0) * 0.009
	scale = Vector2(1.0 / breath, breath) * _visual_size
	if _idle_clock >= 2.6:
		_idle_clock = 0.0
		_idle_step = (_idle_step + 1) % 4
		var idle_frames := [0, 1, 2, 0]
		_show_frame("idle", idle_frames[_idle_step])


func set_dragging(value: bool) -> void:
	_animation_serial += 1
	_dragging = value
	_busy = false
	_drag_moving = false
	if value:
		_show_frame("drag", 0)
		scale = Vector2.ONE * _visual_size
	else:
		_restore_idle()


func set_drag_motion(is_moving: bool) -> void:
	if not _dragging:
		return
	_drag_moving = is_moving
	_show_frame("drag", 1 if is_moving else 0)


func is_busy() -> bool:
	return _busy or _dragging


func change_visual_size(delta: float) -> void:
	_visual_size = clampf(_visual_size + delta, 0.7, 1.4)
	scale = Vector2.ONE * _visual_size


func play_action(action: String) -> void:
	if _busy or _dragging or not _textures.has("idle"):
		return
	_busy = true
	_animation_serial += 1
	var serial := _animation_serial
	match action:
		"clap", "happy":
			await _pose_action("actions", 0, 3, 0.16, serial)
		"eat":
			await _pose_action("actions", 1, 4, 0.28, serial)
		"drink":
			await _pose_action("actions", 2, 4, 0.28, serial)
		"belly_clap":
			await _sequence("belly_clap", [0, 1, 2, 3, 2, 3, 1, 0], 0.17, serial)
		"sleep":
			await _sequence("sleep", [0, 1, 2, 3, 2, 3, 2, 3], 0.34, serial)
		"roll":
			await _sequence("roll", [0, 1, 2, 3], 0.18, serial)
		"wiggle":
			await _sequence("idle", [0, 3, 0, 3, 0], 0.12, serial)
		_:
			await get_tree().create_timer(0.35).timeout
	if serial == _animation_serial and not _dragging:
		_restore_idle()
		_busy = false


func _pose_action(sheet: String, frame: int, pulses: int, delay: float, serial: int) -> void:
	_show_frame(sheet, frame)
	for pulse in pulses:
		if serial != _animation_serial:
			return
		var target := Vector2(0.985, 1.018) if pulse % 2 == 0 else Vector2(1.01, 0.99)
		var tween := create_tween()
		tween.tween_property(self, "scale", target * _visual_size, delay)
		await tween.finished


func _sequence(sheet: String, frames: Array, delay: float, serial: int) -> void:
	for frame: int in frames:
		if serial != _animation_serial:
			return
		_show_frame(sheet, frame)
		await get_tree().create_timer(delay).timeout


func _show_frame(sheet: String, frame: int) -> void:
	if not _textures.has(sheet):
		return
	var texture: Texture2D = _textures[sheet]
	var columns: int = _columns[sheet]
	var cell_width := float(texture.get_width()) / columns
	_sprite.texture = texture
	_sprite.region_enabled = true
	_sprite.region_filter_clip_enabled = true
	_sprite.region_rect = Rect2(cell_width * clampi(frame, 0, columns - 1), 0, cell_width, texture.get_height())
	# Generated sheets share a 2048x768 canvas. This keeps the visible pet near
	# the original desktop footprint while every pose remains a complete drawing.
	_sprite.scale = Vector2.ONE * 0.31


func _restore_idle() -> void:
	position = _home_position
	rotation = 0.0
	scale = Vector2.ONE * _visual_size
	_idle_clock = 0.0
	_idle_step = 0
	_show_frame("idle", 0)


func _load_texture(path: String) -> Texture2D:
	if FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image and not image.is_empty():
			return ImageTexture.create_from_image(image)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _draw() -> void:
	if _textures.has("idle"):
		return
	draw_circle(Vector2.ZERO, 72.0, Color("#a9d9e8"))
	draw_circle(Vector2(0, 18), 49.0, Color("#f6ead2"))
