class_name PetVisual
extends Node2D

const PRIVATE_SHEET := "res://private_pets/active/reference-sheet.png"

var _sprite: Sprite2D
var _using_private_sheet := false
var _pose := 0
var _time := 0.0
var _busy := false
var _dragging := false
var _visual_size := 1.0


func _ready() -> void:
	_sprite = Sprite2D.new()
	add_child(_sprite)
	if ResourceLoader.exists(PRIVATE_SHEET):
		var texture := load(PRIVATE_SHEET) as Texture2D
		if texture:
			_using_private_sheet = true
			_sprite.texture = texture
			_sprite.region_enabled = true
			_sprite.region_rect = Rect2(0, 0, texture.get_width() / 3.0, texture.get_height())
			_sprite.scale = Vector2.ONE * 0.20
			_sprite.position = Vector2(0, 10)
	if not _using_private_sheet:
		queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _dragging:
		scale = Vector2(1.08, 0.90)
	elif not _busy:
		var breath := 1.0 + sin(_time * 2.2) * 0.018
		scale = Vector2(1.0 / breath, breath)


func set_dragging(value: bool) -> void:
	_dragging = value
	if not value and not _busy:
		scale = Vector2.ONE


func change_visual_size(delta: float) -> void:
	_visual_size = clampf(_visual_size + delta, 0.7, 1.4)
	if _sprite and _using_private_sheet:
		_sprite.scale = Vector2.ONE * 0.20 * _visual_size


func play_action(action: String) -> void:
	if _busy:
		return
	_busy = true
	match action:
		"clap", "happy":
			_set_pose(2)
			await _bounce()
		"roll":
			_set_pose(1)
			await _roll()
		"sleep":
			_set_pose(0)
			await _sleepy()
		"wiggle":
			_set_pose(0)
			await _wiggle()
		_:
			await get_tree().create_timer(0.4).timeout
	_set_pose(0)
	rotation = 0.0
	scale = Vector2.ONE
	_busy = false


func _set_pose(index: int) -> void:
	_pose = index
	if _using_private_sheet:
		var cell_width := _sprite.texture.get_width() / 3.0
		_sprite.region_rect.position.x = cell_width * index
	else:
		queue_redraw()


func _bounce() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", position.y - 30.0, 0.18)
	tween.tween_property(self, "position:y", position.y, 0.22)
	tween.tween_property(self, "scale", Vector2(1.08, 0.92), 0.10)
	tween.tween_property(self, "scale", Vector2.ONE, 0.12)
	await tween.finished


func _roll() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "rotation", TAU, 1.0)
	tween.tween_property(self, "position:x", position.x - 75.0, 0.5)
	tween.chain().tween_property(self, "position:x", position.x, 0.5)
	await tween.finished


func _sleepy() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.12, 0.84), 0.35)
	tween.tween_interval(1.2)
	tween.tween_property(self, "scale", Vector2.ONE, 0.35)
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
	# Public fallback mascot: a deliberately generic round pet placeholder.
	draw_circle(Vector2.ZERO, 112.0, Color("#a9d9e8"))
	draw_circle(Vector2(0, 30), 78.0, Color("#f6ead2"))
	draw_circle(Vector2(-39, -31), 10.0, Color("#183247"))
	draw_circle(Vector2(39, -31), 10.0, Color("#183247"))
	draw_circle(Vector2.ZERO, 9.0, Color("#183247"))
	draw_arc(Vector2(0, 7), 24.0, 0.25, PI - 0.25, 24, Color("#183247"), 5.0)
	draw_circle(Vector2(-92, 60), 34.0, Color("#86c5d9"))
	draw_circle(Vector2(92, 60), 34.0, Color("#86c5d9"))
