class_name PetVisual
extends Node2D

const RIG_DIR := "res://private_pets/active/rig2d/"
const BODY_PATH := RIG_DIR + "body-neutral.png"
const PARTS_PATH := RIG_DIR + "rig-parts.png"
const FACE_PATH := RIG_DIR + "face-expressions.png"
const ALT_BODY_PATH := RIG_DIR + "alternate-bodies.png"
const PROPS_PATH := RIG_DIR + "action-props.png"

var _body: Sprite2D
var _tail: Sprite2D
var _left_flipper: Sprite2D
var _right_flipper: Sprite2D
var _face: Sprite2D
var _prop: Sprite2D
var _body_texture: Texture2D
var _parts_texture: Texture2D
var _face_texture: Texture2D
var _alt_body_texture: Texture2D
var _props_texture: Texture2D
var _rig_ready := false
var _time := 0.0
var _busy := false
var _dragging := false
var _visual_size := 1.0
var _home_position := Vector2.ZERO


func _ready() -> void:
	_home_position = position
	_body_texture = _load_texture(BODY_PATH)
	_parts_texture = _load_texture(PARTS_PATH)
	_face_texture = _load_texture(FACE_PATH)
	_alt_body_texture = _load_texture(ALT_BODY_PATH)
	_props_texture = _load_texture(PROPS_PATH)
	if _body_texture and _parts_texture and _face_texture:
		_build_rig()
	else:
		push_error("The private layered pet rig is incomplete.")
		queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _dragging:
		scale = Vector2(1.03, 0.96) * _visual_size
	elif not _busy:
		var breath := 1.0 + sin(_time * 2.0) * 0.012
		scale = Vector2(1.0 / breath, breath) * _visual_size


func set_dragging(value: bool) -> void:
	_dragging = value
	if value:
		_set_expression(1)
		_left_flipper.rotation = -0.24
		_right_flipper.rotation = 0.24
	else:
		_restore_neutral()


func set_drag_motion(_is_moving: bool) -> void:
	pass


func is_busy() -> bool:
	return _busy or _dragging


func change_visual_size(delta: float) -> void:
	_visual_size = clampf(_visual_size + delta, 0.7, 1.4)


func play_action(action: String) -> void:
	if _busy or _dragging or not _rig_ready:
		return
	_busy = true
	match action:
		"clap", "happy":
			await _clap(false)
		"belly_clap":
			await _clap(true)
		"eat":
			await _eat()
		"drink":
			await _drink()
		"sleep":
			await _sleep()
		"roll":
			await _roll()
		"wiggle":
			await _wiggle()
		_:
			await get_tree().create_timer(0.35).timeout
	_restore_neutral()
	_busy = false


func _build_rig() -> void:
	_tail = _new_region_sprite(_parts_texture, 3, 2)
	_tail.position = Vector2(0, 43)
	_tail.scale = Vector2.ONE * 0.105
	_tail.z_index = 0
	add_child(_tail)

	_body = Sprite2D.new()
	_body.texture = _body_texture
	_body.scale = Vector2.ONE * 0.142
	_body.z_index = 1
	add_child(_body)

	_face = _new_region_sprite(_face_texture, 4, 0)
	_face.position = Vector2(0, -19)
	_face.scale = Vector2.ONE * 0.23
	_face.z_index = 2
	add_child(_face)

	_left_flipper = _new_region_sprite(_parts_texture, 3, 0)
	_left_flipper.position = Vector2(-51, 43)
	_left_flipper.scale = Vector2.ONE * 0.078
	_left_flipper.z_index = 3
	add_child(_left_flipper)

	_right_flipper = _new_region_sprite(_parts_texture, 3, 1)
	_right_flipper.position = Vector2(51, 43)
	_right_flipper.scale = Vector2.ONE * 0.078
	_right_flipper.z_index = 3
	add_child(_right_flipper)

	if _props_texture:
		_prop = _new_region_sprite(_props_texture, 3, 0)
		_prop.visible = false
		_prop.z_index = 4
		add_child(_prop)
	_rig_ready = true


func _new_region_sprite(texture: Texture2D, columns: int, index: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.region_enabled = true
	var width := float(texture.get_width()) / columns
	sprite.region_rect = Rect2(width * index, 0, width, texture.get_height())
	return sprite


func _set_region(sprite: Sprite2D, columns: int, index: int) -> void:
	var width := float(sprite.texture.get_width()) / columns
	sprite.region_rect = Rect2(width * index, 0, width, sprite.texture.get_height())


func _set_expression(index: int) -> void:
	_set_region(_face, 4, index)


func _restore_neutral() -> void:
	if not _rig_ready:
		return
	_body.texture = _body_texture
	_body.region_enabled = false
	_body.scale = Vector2.ONE * 0.142
	_body.position = Vector2.ZERO
	_body.rotation = 0.0
	_tail.visible = true
	_tail.position = Vector2(0, 43)
	_tail.rotation = 0.0
	_face.visible = true
	_face.position = Vector2(0, -19)
	_face.rotation = 0.0
	_face.scale = Vector2.ONE * 0.23
	_set_expression(0)
	_left_flipper.visible = true
	_right_flipper.visible = true
	_left_flipper.position = Vector2(-51, 43)
	_right_flipper.position = Vector2(51, 43)
	_left_flipper.scale = Vector2.ONE * 0.078
	_right_flipper.scale = Vector2.ONE * 0.078
	_left_flipper.rotation = 0.0
	_right_flipper.rotation = 0.0
	if _prop:
		_prop.visible = false
		_prop.position = Vector2.ZERO
		_prop.rotation = 0.0
	position = _home_position
	rotation = 0.0
	scale = Vector2.ONE * _visual_size


func _clap(belly_up: bool) -> void:
	_set_expression(2)
	if belly_up:
		_use_alt_body(0)
		_face.position = Vector2(0, -8)
		_left_flipper.position = Vector2(-25, 4)
		_right_flipper.position = Vector2(25, 4)
	for cycle in 2:
		var close := create_tween().set_parallel(true)
		close.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		close.tween_property(_left_flipper, "position", Vector2(-12, 4), 0.16)
		close.tween_property(_right_flipper, "position", Vector2(12, 4), 0.16)
		close.tween_property(_left_flipper, "rotation", 0.72, 0.16)
		close.tween_property(_right_flipper, "rotation", -0.72, 0.16)
		await close.finished
		var open := create_tween().set_parallel(true)
		open.tween_property(_left_flipper, "position", Vector2(-34, 17), 0.17)
		open.tween_property(_right_flipper, "position", Vector2(34, 17), 0.17)
		open.tween_property(_left_flipper, "rotation", 0.18, 0.17)
		open.tween_property(_right_flipper, "rotation", -0.18, 0.17)
		await open.finished


func _eat() -> void:
	_set_expression(1)
	_show_prop(0, Vector2(0, 11), 0.075)
	await _bring_flippers_together(Vector2(-19, 15), Vector2(19, 15), 0.24)
	for bite in 3:
		_set_expression(2 if bite == 2 else 1)
		var chew := create_tween()
		chew.tween_property(_face, "scale:y", 0.21, 0.10)
		chew.tween_property(_face, "scale:y", 0.23, 0.11)
		await chew.finished
	await get_tree().create_timer(0.35).timeout


func _drink() -> void:
	_set_expression(1)
	_show_prop(1, Vector2(0, 29), 0.073)
	await _bring_flippers_together(Vector2(-23, 23), Vector2(23, 23), 0.24)
	for sip in 3:
		var bob := create_tween()
		bob.tween_property(_face, "position:y", -16.0, 0.14)
		bob.tween_property(_face, "position:y", -19.0, 0.14)
		await bob.finished
	_set_expression(2)
	await get_tree().create_timer(0.3).timeout


func _bring_flippers_together(left_target: Vector2, right_target: Vector2, duration: float) -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_left_flipper, "position", left_target, duration)
	tween.tween_property(_right_flipper, "position", right_target, duration)
	tween.tween_property(_left_flipper, "rotation", 0.62, duration)
	tween.tween_property(_right_flipper, "rotation", -0.62, duration)
	await tween.finished


func _sleep() -> void:
	_use_alt_body(1)
	_set_expression(3)
	_face.position = Vector2(-39, 12)
	_face.scale = Vector2.ONE * 0.17
	_left_flipper.position = Vector2(-43, 27)
	_right_flipper.visible = false
	_tail.position = Vector2(53, 29)
	_show_prop(2, Vector2(48, -25), 0.072)
	var tween := create_tween()
	tween.set_loops(2)
	tween.tween_property(self, "scale", Vector2(1.025, 0.985) * _visual_size, 0.5)
	tween.tween_property(self, "scale", Vector2(0.99, 1.01) * _visual_size, 0.65)
	await tween.finished


func _roll() -> void:
	_set_expression(2)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "rotation", TAU, 0.72)
	await tween.finished


func _wiggle() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "rotation", -0.055, 0.12)
	tween.tween_property(self, "rotation", 0.055, 0.18)
	tween.tween_property(self, "rotation", 0.0, 0.14)
	await tween.finished


func _use_alt_body(index: int) -> void:
	if not _alt_body_texture:
		return
	_body.texture = _alt_body_texture
	_body.region_enabled = true
	var width := float(_alt_body_texture.get_width()) / 2.0
	_body.region_rect = Rect2(width * index, 0, width, _alt_body_texture.get_height())
	_body.scale = Vector2.ONE * 0.18
	_tail.visible = index != 0


func _show_prop(index: int, at: Vector2, prop_scale: float) -> void:
	if not _prop:
		return
	_set_region(_prop, 3, index)
	_prop.position = at
	_prop.scale = Vector2.ONE * prop_scale
	_prop.visible = true


func _load_texture(path: String) -> Texture2D:
	if FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image and not image.is_empty():
			return ImageTexture.create_from_image(image)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _draw() -> void:
	if _rig_ready:
		return
	draw_circle(Vector2.ZERO, 105.0, Color("#a9d9e8"))
	draw_circle(Vector2(0, 25), 73.0, Color("#f6ead2"))
