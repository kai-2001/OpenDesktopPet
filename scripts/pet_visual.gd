class_name PetVisual
extends Node2D

signal action_completed(request_id: int, requested_action: String, success: bool)
signal interaction_region_changed(polygon: PackedVector2Array)

const PetHitboxCalculatorScript = preload("res://scripts/pet_hitbox_calculator.gd")
const CharacterPackProfileScript = preload("res://scripts/character_pack_profile.gd")
const PetEffectControllerScript = preload("res://scripts/pet_effect_controller.gd")
const FRAME_VIEWPORT_PADDING := 2.0

var _profile = CharacterPackProfileScript.new()
var _hitbox_calculator = PetHitboxCalculatorScript.new()
var _sprite: Sprite2D
var _effect_controller: PetEffectController
var _texture_cache: Dictionary = {}
var _busy := false
var _dragging := false
var _drag_moving := false
var _drag_frame_clock := 0.0
var _drag_frame_step := 0
var _sleep_loop_active := false
var _facing_direction := -1
var _visual_size := 1.0
var _time := 0.0
var _idle_clock := 0.0
var _idle_step := 0
var _home_position := Vector2.ZERO
var _animation_serial := 0
var _current_action := ""
var _progressive_move_sequence_index := -1
var _active_request_id := 0
var _active_requested_action := ""
var _action_tween: Tween
var _hit_image_cache: Dictionary = {}
var _hit_polygon_cache: Dictionary = {}
var _opaque_bounds_cache: Dictionary = {}
var _base_window_size := Vector2i.ZERO
var _base_root_position := Vector2.ZERO


func _ready() -> void:
	_home_position = position
	_capture_base_geometry()
	_sprite = Sprite2D.new()
	_sprite.z_index = 1
	add_child(_sprite)
	_effect_controller = PetEffectControllerScript.new()
	_effect_controller.name = "EffectLayer"
	add_child(_effect_controller)
	if _load_pack():
		_effect_controller.configure_for_pack(
			_profile.effect_scale_ratio(), _profile.effect_overrides()
		)
		_show_action_frame("idle", _first_frame("idle"))
		print("CHARACTER_PACK_LOADED id=%s root=%s" % [
			get_character_id(), get_pack_root()
		])
	else:
		push_error("No valid character pack was found.")
		queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _dragging:
		if _drag_moving:
			var definition := _action_definition("drag")
			var sequence := _sequence_for(definition)
			var frame_time := float(definition.get("frame_time", 0.12))
			_drag_frame_clock += delta
			if _drag_frame_clock >= frame_time:
				_drag_frame_clock = fmod(_drag_frame_clock, frame_time)
				_drag_frame_step = (_drag_frame_step + 1) % sequence.size()
				_show_action_frame("drag", int(sequence[_drag_frame_step]))
		var sway := sin(_time * 8.0) * (0.025 if _drag_moving else 0.008)
		rotation = sway
		return
	if _busy or not _profile.has_action("idle"):
		return
	_idle_clock += delta
	var breath := 1.0 + sin(_time * 2.0) * 0.009
	scale = Vector2(1.0 / breath, breath) * _visual_size
	var idle_definition := _action_definition("idle")
	var idle_interval := float(idle_definition.get("idle_interval", 2.6))
	if _idle_clock >= idle_interval:
		_idle_clock = 0.0
		var sequence := _sequence_for(idle_definition)
		_idle_step = (_idle_step + 1) % sequence.size()
		_show_action_frame("idle", int(sequence[_idle_step]))


func set_progression(snapshot: Dictionary) -> void:
	_profile.set_progression(snapshot)


func reload_character() -> bool:
	_animation_serial += 1
	_cancel_active_request()
	_effect_controller.reset()
	_dragging = false
	_busy = false
	_drag_moving = false
	_drag_frame_clock = 0.0
	_drag_frame_step = 0
	_sleep_loop_active = false
	_current_action = ""
	_active_request_id = 0
	_active_requested_action = ""
	position = _home_position
	rotation = 0.0
	scale = Vector2.ONE * _visual_size
	_restore_base_geometry()
	_sprite.texture = null
	_texture_cache.clear()
	_hit_image_cache.clear()
	_hit_polygon_cache.clear()
	_opaque_bounds_cache.clear()
	_profile.clear()
	if not _load_pack():
		queue_redraw()
		_emit_interaction_region()
		return false
	_effect_controller.configure_for_pack(
		_profile.effect_scale_ratio(), _profile.effect_overrides()
	)
	_idle_clock = 0.0
	_idle_step = 0
	_show_action_frame("idle", _first_frame("idle"))
	queue_redraw()
	return true


func set_dragging(value: bool) -> void:
	if _dragging == value:
		return
	if value:
		_cancel_active_request()
		_stop_current_animation(false)
	else:
		_animation_serial += 1
	_dragging = value
	_busy = false
	_drag_moving = false
	_drag_frame_clock = 0.0
	_drag_frame_step = 0
	_current_action = ""
	if value:
		_show_action_frame("drag", _first_frame("drag"))
		scale = Vector2.ONE * _visual_size
	else:
		_restore_idle()
	_emit_interaction_region()


func cancel_autonomous_action() -> bool:
	if _active_request_id > 0 or _dragging:
		return false
	if not _busy:
		return true
	_stop_current_animation(true)
	_emit_interaction_region()
	return true


func start_sleep_loop() -> void:
	if _sleep_loop_active or _dragging or not _profile.has_action("idle"):
		return
	_stop_current_animation(false)
	_sleep_loop_active = true
	_busy = true
	_current_action = "idle"
	_animation_serial += 1
	var serial := _animation_serial
	_run_sleep_loop(serial)


func stop_sleep_loop(reason := "user") -> void:
	if not _sleep_loop_active:
		return
	_sleep_loop_active = false
	_animation_serial += 1
	var definition := _action_definition("idle")
	var wake_sequence := _optional_sequence(definition, "wake_sequence")
	if reason == "drag" or wake_sequence.is_empty():
		_busy = false
		_current_action = ""
		_restore_idle()
		_emit_interaction_region()
		return
	_busy = true
	_current_action = "idle"
	var serial := _animation_serial
	await _play_frames("idle", wake_sequence, definition, serial)
	if serial == _animation_serial and not _dragging:
		_busy = false
		_current_action = ""
		_restore_idle()
		_emit_interaction_region()


func _run_sleep_loop(serial: int) -> void:
	var action := "idle"
	var definition := _action_definition(action)
	var sequence := _optional_sequence(definition, "loop_sequence")
	if sequence.is_empty():
		sequence = _sequence_for(definition)
	var frame_time := float(definition.get("frame_time", 0.3))
	while _sleep_loop_active and serial == _animation_serial:
		for frame: Variant in sequence:
			if not _sleep_loop_active or serial != _animation_serial:
				return
			_show_action_frame(action, int(frame))
			await get_tree().create_timer(frame_time).timeout


func _stop_current_animation(restore_idle: bool) -> void:
	_animation_serial += 1
	_sleep_loop_active = false
	_effect_controller.stop_transient_effects()
	if is_instance_valid(_action_tween):
		_action_tween.kill()
	_action_tween = null
	_busy = false
	_current_action = ""
	if restore_idle:
		_restore_idle()


func _capture_base_geometry() -> void:
	var window := get_window()
	if window:
		_base_window_size = window.size
	var root_canvas := get_parent() as Node2D
	if root_canvas:
		_base_root_position = root_canvas.position


func _restore_base_geometry(resize_window := true) -> void:
	var window := get_window()
	var root_canvas := get_parent() as Node2D
	if root_canvas:
		# A previous oversized frame may have shifted the root canvas. Move the
		# native window by the inverse correction so the pet keeps the same
		# desktop position while returning to the common baseline.
		var canvas_delta := root_canvas.position - _base_root_position
		root_canvas.position = _base_root_position
		if window and not canvas_delta.is_zero_approx():
			window.position += Vector2i(
				roundi(canvas_delta.x),
				roundi(canvas_delta.y)
			)
	if resize_window and window \
			and _base_window_size.x > 0 and _base_window_size.y > 0:
		window.size = _base_window_size


func set_drag_motion(is_moving: bool) -> void:
	if not _dragging:
		return
	if _drag_moving == is_moving:
		return
	_drag_moving = is_moving
	_drag_frame_clock = 0.0
	if not is_moving:
		_drag_frame_step = 0
		_show_action_frame("drag", _first_frame("drag"))


func set_facing_direction(direction: int) -> void:
	if direction == 0:
		return
	var normalized := 1 if direction > 0 else -1
	if normalized == _facing_direction:
		return
	_facing_direction = normalized
	var scale_action := _current_action
	if scale_action.is_empty():
		scale_action = "drag" if _dragging else "idle"
	_apply_sprite_scale(_action_definition(scale_action))
	_emit_interaction_region()


func is_busy() -> bool:
	return _busy or _dragging


func cancel_roll() -> void:
	if not _busy or _current_action != "move":
		return
	_animation_serial += 1
	_busy = false
	_current_action = ""
	_restore_idle()


func begin_progressive_move() -> bool:
	if _busy or _dragging or not _profile.has_action("idle"):
		return false
	var action := _resolve_action("move")
	if not _profile.has_action(action) or not is_action_unlocked(action):
		return false
	_animation_serial += 1
	_busy = true
	_current_action = action
	_active_request_id = 0
	_active_requested_action = ""
	_progressive_move_sequence_index = -1
	_show_action_frame(action, _first_frame(action))
	return true


func update_progressive_move(progress: float) -> void:
	if not _busy or _current_action != _resolve_action("move"):
		return
	var definition := _action_definition(_current_action)
	var sequence := _sequence_for(definition)
	if sequence.is_empty():
		return
	var normalized := clampf(progress, 0.0, 1.0)
	var sequence_index := mini(
		floori(normalized * sequence.size()),
		sequence.size() - 1
	)
	if sequence_index == _progressive_move_sequence_index:
		return
	_progressive_move_sequence_index = sequence_index
	_show_action_frame(_current_action, int(sequence[sequence_index]))


func finish_progressive_move() -> void:
	if not _busy or _current_action != _resolve_action("move"):
		return
	_animation_serial += 1
	_busy = false
	_current_action = ""
	_progressive_move_sequence_index = -1
	_restore_idle()


func change_visual_size(delta: float) -> void:
	_visual_size = clampf(_visual_size + delta, 0.7, 1.15)
	scale = Vector2.ONE * _visual_size
	_emit_interaction_region()


func set_visual_size(value: float) -> void:
	_visual_size = clampf(value, 0.7, 1.15)
	scale = Vector2.ONE * _visual_size
	_emit_interaction_region()


func contains_point(point_in_canvas: Vector2) -> bool:
	if not is_instance_valid(_sprite) or _sprite.texture == null:
		return false
	var sprite_point := _sprite.to_local(point_in_canvas)
	var sprite_rect := _sprite.get_rect()
	if not sprite_rect.has_point(sprite_point):
		return false
	var image := _hit_image_for(_sprite.texture)
	if image == null or image.is_empty():
		return true
	var normalized := (sprite_point - sprite_rect.position) / sprite_rect.size
	if _sprite.flip_h:
		normalized.x = 1.0 - normalized.x
	var source_rect := _sprite.region_rect if _sprite.region_enabled \
		else Rect2(Vector2.ZERO, Vector2(_sprite.texture.get_size()))
	var pixel := Vector2i(
		clampi(
			floori(source_rect.position.x + normalized.x * source_rect.size.x),
			0,
			image.get_width() - 1
		),
		clampi(
			floori(source_rect.position.y + normalized.y * source_rect.size.y),
			0,
			image.get_height() - 1
		)
	)
	return image.get_pixelv(pixel).a >= 0.08


func get_visual_bounds_in_canvas() -> Rect2:
	if not is_instance_valid(_sprite) or _sprite.texture == null:
		return Rect2(position, Vector2.ONE)
	# Use the opaque sprite contour rather than the full texture rectangle.
	# The animation sheets contain transparent padding, which previously made
	# the pet stop noticeably above the taskbar even though the window itself
	# had already reached the usable-screen boundary.
	var visible_polygon := get_interaction_polygon()
	if not visible_polygon.is_empty():
		var visible_bounds := Rect2(visible_polygon[0], Vector2.ZERO)
		for point: Vector2 in visible_polygon:
			visible_bounds = visible_bounds.expand(point)
		return visible_bounds
	var sprite_rect := _sprite.get_rect()
	var transform := _sprite.get_global_transform()
	var corners := [
		transform * sprite_rect.position,
		transform * Vector2(sprite_rect.end.x, sprite_rect.position.y),
		transform * sprite_rect.end,
		transform * Vector2(sprite_rect.position.x, sprite_rect.end.y),
	]
	var bounds := Rect2(corners[0], Vector2.ZERO)
	for corner: Vector2 in corners:
		bounds = bounds.expand(corner)
	return bounds


func get_interaction_polygon() -> PackedVector2Array:
	if not is_instance_valid(_sprite) or _sprite.texture == null:
		return PackedVector2Array()
	var source_polygon := _source_hit_polygon()
	var transformed := PackedVector2Array()
	var transform := _sprite.get_global_transform()
	for point: Vector2 in source_polygon:
		transformed.append(transform * point)
	return transformed


func play_action(requested_action: String, request_id := 0) -> void:
	if _busy or _dragging or not _profile.has_action("idle"):
		if request_id > 0:
			action_completed.emit(request_id, requested_action, false)
		return
	var action := _resolve_action(requested_action)
	# Care visuals are intentionally composed from the idle loop plus a shared
	# overlay. Keep Codex and native character packs visually consistent.
	if requested_action in ["eat", "drink", "sleep"]:
		action = "idle"
	elif requested_action == "work":
		if _profile.has_action("work"):
			action = "work"
		elif _profile.has_action("running"):
			action = "running"
	elif requested_action == "pet" and _profile.has_action("jumping"):
		action = "jumping"
	if not _profile.has_action(action):
		if request_id > 0:
			action_completed.emit(request_id, requested_action, false)
			return
		action = _profile.fallback_action()
	if not is_action_unlocked(action):
		if request_id > 0:
			action_completed.emit(request_id, requested_action, false)
			return
		action = _profile.fallback_action()
	if not _profile.has_action(action):
		if request_id > 0:
			action_completed.emit(request_id, requested_action, false)
		return
	var definition := _action_definition(action)
	_busy = true
	_current_action = action
	_active_request_id = request_id
	_active_requested_action = requested_action
	_animation_serial += 1
	var serial := _animation_serial
	var enter_sequence := _optional_sequence(definition, "enter_sequence") \
			if action == "sleep" and request_id > 0 else []
	var behavior := String(definition.get("behavior", "sequence"))
	if not enter_sequence.is_empty():
		await _play_frames(action, enter_sequence, definition, serial)
	elif behavior == "pulse":
		await _pulse_action(action, definition, serial)
	else:
		await _play_sequence(action, definition, serial)
	if serial == _animation_serial and not _dragging:
		_restore_idle()
		_busy = false
		_current_action = ""
		_finish_active_request(true)


func play_effect_for_action(action: String) -> void:
	if _effect_controller != null:
		_effect_controller.play_for_action(action)


func start_sleep_effect() -> void:
	if _effect_controller != null:
		_effect_controller.start_sleep()


func stop_sleep_effect(_reason := "user") -> void:
	if _effect_controller != null:
		_effect_controller.stop_sleep()


func pick_autonomous_action(allow_move: bool) -> String:
	return _profile.pick_autonomous_action(allow_move)


func get_unlocked_action_ids() -> Array[String]:
	return _profile.unlocked_action_ids()


func get_next_unlock() -> Dictionary:
	return _profile.next_unlock()


func get_dialogue(key: String, fallback: String) -> String:
	return _profile.get_dialogue(key, fallback)


func get_character_id() -> String:
	return _profile.character_id()


func get_character_name() -> String:
	return _profile.character_name()


func get_character_version() -> String:
	return _profile.character_version()


func get_drag_anchor() -> Variant:
	return _profile.drag_anchor()


func get_pack_root() -> String:
	return _profile.pack_root()


func set_action_definition(action: String, definition: Dictionary) -> void:
	_profile.set_action_definition(action, definition)


func remove_action_definition(action: String) -> void:
	_profile.remove_action_definition(action)


func get_interaction_label(action: String, fallback: String) -> String:
	return _profile.get_interaction_label(action, fallback)


func get_interaction_icon(action: String, fallback: String) -> String:
	return _profile.get_interaction_icon(action, fallback)


func get_interaction_wish(
	action: String,
	fallback: String,
	minutes: int
) -> String:
	return _profile.get_interaction_wish(action, fallback, minutes)


func is_action_unlocked(action: String) -> bool:
	return _profile.is_action_unlocked(action)


func get_action_duration(requested_action: String) -> float:
	return _profile.action_duration(requested_action)


func _play_sequence(action: String, definition: Dictionary, serial: int) -> void:
	await _play_frames(action, _sequence_for(definition), definition, serial)


func _play_frames(
	action: String,
	sequence: Array,
	definition: Dictionary,
	serial: int
) -> void:
	var frame_time := float(definition.get("frame_time", 0.16))
	for frame: Variant in sequence:
		if serial != _animation_serial:
			return
		_show_action_frame(action, int(frame))
		await get_tree().create_timer(frame_time).timeout


func _pulse_action(action: String, definition: Dictionary, serial: int) -> void:
	var sequence := _sequence_for(definition)
	var pulses := maxi(int(definition.get("pulses", 4)), 1)
	var frame_time := float(definition.get("frame_time", 0.25))
	for pulse in pulses:
		if serial != _animation_serial:
			return
		_show_action_frame(action, int(sequence[pulse % sequence.size()]))
		var target := Vector2(0.985, 1.018) if pulse % 2 == 0 else Vector2(1.01, 0.99)
		var tween := create_tween()
		_action_tween = tween
		tween.tween_property(self, "scale", target * _visual_size, frame_time)
		await tween.finished
		if _action_tween == tween:
			_action_tween = null


func _show_action_frame(action: String, frame: int) -> void:
	var definition := _action_definition(action)
	if definition.is_empty():
		return
	var texture := _texture_for(definition)
	if texture == null:
		return
	var columns := maxi(int(definition.get("columns", 1)), 1)
	var rows := maxi(int(definition.get("rows", 1)), 1)
	var safe_frame := clampi(frame, 0, columns * rows - 1)
	var cell_size := Vector2(float(texture.get_width()) / columns, float(texture.get_height()) / rows)
	_sprite.texture = texture
	_sprite.region_enabled = true
	_sprite.region_filter_clip_enabled = true
	_sprite.region_rect = Rect2(
		cell_size.x * (safe_frame % columns),
		cell_size.y * (safe_frame / columns),
		cell_size.x,
		cell_size.y
	)
	_sprite.position = _frame_offset(definition, safe_frame)
	_apply_sprite_scale(definition)
	# Reset the canvas coordinate system without first shrinking the native
	# transparent window. Shrinking and immediately growing an oversized frame
	# makes the Windows compositor briefly expose opaque black strips.
	_restore_base_geometry(false)
	_grow_window_to_fit_frame()
	_keep_frame_inside_viewport()
	_emit_interaction_region()


func _apply_sprite_scale(definition: Dictionary) -> void:
	if not is_instance_valid(_sprite):
		return
	var action_scale := float(definition.get("scale", _profile.pack_scale())) \
		if not definition.is_empty() \
		else _profile.pack_scale()
	_sprite.flip_h = _is_action_flipped(definition)
	_sprite.scale = Vector2.ONE * action_scale


func _frame_offset(definition: Dictionary, frame: int) -> Vector2:
	var offsets: Array = definition.get("offsets", [])
	if frame >= offsets.size() or offsets[frame] is not Array:
		return Vector2.ZERO
	var pair: Array = offsets[frame]
	if pair.size() < 2:
		return Vector2.ZERO
	var horizontal := -1.0 if _is_action_flipped(definition) else 1.0
	return Vector2(float(pair[0]) * horizontal, float(pair[1]))


func _is_action_flipped(definition: Dictionary) -> bool:
	var source_facing := String(definition.get(
		"source_facing", _profile.source_facing()
	)).to_lower()
	if source_facing not in ["left", "right"]:
		source_facing = "left"
	var desired_facing := "right" if _facing_direction > 0 else "left"
	return source_facing != desired_facing


func _sequence_for(definition: Dictionary) -> Array:
	return _profile.sequence_for(definition)


func _optional_sequence(definition: Dictionary, key: String) -> Array:
	return _profile.optional_sequence(definition, key)


func _first_frame(action: String) -> int:
	return _profile.first_frame(action)


func _action_definition(action: String) -> Dictionary:
	return _profile.action_definition(action)


func _resolve_action(action: String) -> String:
	return _profile.resolve_action(action)


func _texture_for(definition: Dictionary) -> Texture2D:
	var relative_path := String(definition.get("file", ""))
	if relative_path.is_empty():
		return null
	var path := _profile.pack_root().path_join(relative_path)
	if _texture_cache.has(path):
		return _texture_cache[path] as Texture2D
	var texture := _load_texture(path)
	if texture:
		_texture_cache[path] = texture
	return texture


func _load_pack() -> bool:
	return _profile.load_selected_pack()


func _restore_idle() -> void:
	position = _home_position
	rotation = 0.0
	scale = Vector2.ONE * _visual_size
	_idle_clock = 0.0
	_idle_step = 0
	_show_action_frame("idle", _first_frame("idle"))


func _cancel_active_request() -> void:
	if _active_request_id <= 0:
		return
	var request_id := _active_request_id
	var requested_action := _active_requested_action
	_active_request_id = 0
	_active_requested_action = ""
	action_completed.emit(request_id, requested_action, false)


func _finish_active_request(success: bool) -> void:
	if _active_request_id <= 0:
		return
	var request_id := _active_request_id
	var requested_action := _active_requested_action
	_active_request_id = 0
	_active_requested_action = ""
	action_completed.emit(request_id, requested_action, success)


func _load_texture(path: String) -> Texture2D:
	if path.begins_with("res://") and ResourceLoader.exists(path):
		return load(path) as Texture2D
	if FileAccess.file_exists(path):
		if path.get_extension().to_lower() == "svg":
			var svg_image := Image.new()
			var svg_error := svg_image.load_svg_from_buffer(
				FileAccess.get_file_as_bytes(path)
			)
			if svg_error == OK and not svg_image.is_empty():
				return ImageTexture.create_from_image(svg_image)
		var image := Image.load_from_file(path)
		if image and not image.is_empty():
			return ImageTexture.create_from_image(image)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _hit_image_for(texture: Texture2D) -> Image:
	var key := texture.get_rid().get_id()
	if _hit_image_cache.has(key):
		return _hit_image_cache[key] as Image
	var image := texture.get_image()
	_hit_image_cache[key] = image
	return image


func _source_hit_polygon() -> PackedVector2Array:
	var texture := _sprite.texture
	var image := _hit_image_for(texture)
	if image == null or image.is_empty():
		return PackedVector2Array()
	var source_rect := _sprite.region_rect if _sprite.region_enabled \
		else Rect2(Vector2.ZERO, Vector2(texture.get_size()))
	var pixel_rect := Rect2i(
		Vector2i(floori(source_rect.position.x), floori(source_rect.position.y)),
		Vector2i(ceili(source_rect.size.x), ceili(source_rect.size.y))
	)
	var cache_key := "%s:%s" % [texture.get_rid().get_id(), pixel_rect]
	var pixel_polygon: PackedVector2Array
	if _hit_polygon_cache.has(cache_key):
		pixel_polygon = _hit_polygon_cache[cache_key]
	else:
		var frame_image := image.get_region(pixel_rect)
		pixel_polygon = _hitbox_calculator.content_polygon(
			frame_image,
			Rect2i(Vector2i.ZERO, frame_image.get_size())
		)
		_hit_polygon_cache[cache_key] = pixel_polygon
	var sprite_rect := _sprite.get_rect()
	var result := PackedVector2Array()
	for point: Vector2 in pixel_polygon:
		var normalized_point := Vector2(
			point.x / source_rect.size.x,
			point.y / source_rect.size.y
		)
		if _sprite.flip_h:
			normalized_point.x = 1.0 - normalized_point.x
		result.append(sprite_rect.position + normalized_point * sprite_rect.size)
	return result


func _keep_frame_inside_viewport() -> void:
	var visible_bounds := _opaque_frame_bounds_in_canvas()
	if visible_bounds.size == Vector2.ZERO:
		return
	var viewport_rect := get_viewport().get_visible_rect().grow(-FRAME_VIEWPORT_PADDING)
	if viewport_rect.size.x <= 0.0 or viewport_rect.size.y <= 0.0:
		return
	var canvas_shift := Vector2(
		_axis_containment_shift(
			visible_bounds.position.x,
			visible_bounds.end.x,
			viewport_rect.position.x,
			viewport_rect.end.x
		),
		_axis_containment_shift(
			visible_bounds.position.y,
			visible_bounds.end.y,
			viewport_rect.position.y,
			viewport_rect.end.y
		)
	)
	if not canvas_shift.is_zero_approx():
		_sprite.position += global_transform.basis_xform_inv(canvas_shift)


func _grow_window_to_fit_frame() -> void:
	var visible_bounds := _opaque_frame_bounds_in_canvas()
	if visible_bounds.size == Vector2.ZERO:
		return
	var window := get_window()
	if window == null:
		return
	var base_size := Vector2(_base_window_size) \
			if _base_window_size.x > 0 and _base_window_size.y > 0 \
			else Vector2(window.size)
	var required_start := Vector2(
		minf(visible_bounds.position.x - FRAME_VIEWPORT_PADDING, 0.0),
		minf(visible_bounds.position.y - FRAME_VIEWPORT_PADDING, 0.0)
	)
	var required_end := Vector2(
		maxf(visible_bounds.end.x + FRAME_VIEWPORT_PADDING, base_size.x),
		maxf(visible_bounds.end.y + FRAME_VIEWPORT_PADDING, base_size.y)
	)
	var required_size := Vector2i(
		ceili(required_end.x - required_start.x),
		ceili(required_end.y - required_start.y)
	)
	if required_size == window.size:
		return
	# When content extends past the left or top edge, move the native window
	# outward and shift the whole scene by the opposite amount. This grows the
	# transparent canvas without making the pet jump on the desktop.
	if required_start != Vector2.ZERO:
		var root_canvas := get_parent() as Node2D
		if root_canvas:
			root_canvas.position -= required_start
		window.position += Vector2i(floori(required_start.x), floori(required_start.y))
	window.size = required_size


func _axis_containment_shift(
	content_start: float,
	content_end: float,
	limit_start: float,
	limit_end: float
) -> float:
	var content_size := content_end - content_start
	var limit_size := limit_end - limit_start
	if content_size > limit_size:
		return (limit_start + limit_end - content_start - content_end) * 0.5
	if content_start < limit_start:
		return limit_start - content_start
	if content_end > limit_end:
		return limit_end - content_end
	return 0.0


func _opaque_frame_bounds_in_canvas() -> Rect2:
	if not is_instance_valid(_sprite) or _sprite.texture == null:
		return Rect2()
	var source_rect := _sprite.region_rect if _sprite.region_enabled \
		else Rect2(Vector2.ZERO, Vector2(_sprite.texture.get_size()))
	var pixel_rect := Rect2i(
		Vector2i(floori(source_rect.position.x), floori(source_rect.position.y)),
		Vector2i(ceili(source_rect.size.x), ceili(source_rect.size.y))
	)
	var cache_key := "%s:%s" % [_sprite.texture.get_rid().get_id(), pixel_rect]
	var opaque_bounds: Rect2
	if _opaque_bounds_cache.has(cache_key):
		opaque_bounds = _opaque_bounds_cache[cache_key] as Rect2
	else:
		var image := _hit_image_for(_sprite.texture)
		if image == null or image.is_empty():
			return Rect2()
		opaque_bounds = _hitbox_calculator.content_bounds(image, pixel_rect)
		_opaque_bounds_cache[cache_key] = opaque_bounds
	if opaque_bounds.size == Vector2.ZERO:
		return Rect2()
	var sprite_rect := _sprite.get_rect()
	var normalized_start := opaque_bounds.position / source_rect.size
	var normalized_end := opaque_bounds.end / source_rect.size
	if _sprite.flip_h:
		var flipped_start := 1.0 - normalized_end.x
		normalized_end.x = 1.0 - normalized_start.x
		normalized_start.x = flipped_start
	var local_rect := Rect2(
		sprite_rect.position + normalized_start * sprite_rect.size,
		(normalized_end - normalized_start) * sprite_rect.size
	)
	var transform := _sprite.get_global_transform()
	var corners := [
		transform * local_rect.position,
		transform * Vector2(local_rect.end.x, local_rect.position.y),
		transform * local_rect.end,
		transform * Vector2(local_rect.position.x, local_rect.end.y),
	]
	var canvas_bounds := Rect2(corners[0], Vector2.ZERO)
	for corner: Vector2 in corners:
		canvas_bounds = canvas_bounds.expand(corner)
	return canvas_bounds


func _emit_interaction_region() -> void:
	interaction_region_changed.emit(get_interaction_polygon())


func _draw() -> void:
	if _profile.has_action("idle"):
		return
	draw_circle(Vector2.ZERO, 72.0, Color("#a9d9e8"))
	draw_circle(Vector2(0, 18), 49.0, Color("#f6ead2"))
