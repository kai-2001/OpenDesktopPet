class_name PetVisual
extends Node2D

signal action_completed(request_id: int, requested_action: String, success: bool)
signal interaction_region_changed(polygon: PackedVector2Array)

const BUNDLED_CUSTOM_PACK_ROOT := "res://characters/custom/"
const PUBLIC_PACK_ROOT := "res://characters/public/"
const INSTALLED_PACKS_ROOT := "user://character_packs/"
const CHARACTER_SETTINGS_PATH := "user://ui_settings.cfg"
const PUBLIC_CHARACTER_ID := "open_desktop_pet_default"
const REQUIRED_ACTIONS := ["idle", "pet", "eat", "drink", "sleep", "move", "drag", "work"]
const FRAME_VIEWPORT_PADDING := 2.0

var _sprite: Sprite2D
var _manifest: Dictionary = {}
var _actions: Dictionary = {}
var _aliases: Dictionary = {}
var _texture_cache: Dictionary = {}
var _progression: Dictionary = {"level": 1, "affection": 0}
var _busy := false
var _dragging := false
var _drag_moving := false
var _drag_frame_clock := 0.0
var _drag_frame_step := 0
var _facing_direction := -1
var _visual_size := 1.0
var _pack_scale := 0.31
var _time := 0.0
var _idle_clock := 0.0
var _idle_step := 0
var _home_position := Vector2.ZERO
var _animation_serial := 0
var _current_action := ""
var _pack_root := ""
var _active_request_id := 0
var _active_requested_action := ""
var _hit_image_cache: Dictionary = {}
var _hit_polygon_cache: Dictionary = {}
var _opaque_bounds_cache: Dictionary = {}


func _ready() -> void:
	_home_position = position
	_sprite = Sprite2D.new()
	_sprite.z_index = 1
	add_child(_sprite)
	if _load_pack():
		_show_action_frame("idle", _first_frame("idle"))
		print("CHARACTER_PACK_LOADED id=%s root=%s" % [
			get_character_id(), _pack_root
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
	if _busy or not _actions.has("idle"):
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
	_progression.level = int(snapshot.get("level", 1))
	_progression.affection = int(snapshot.get("affection", 0))


func set_dragging(value: bool) -> void:
	if _dragging == value:
		return
	if value:
		_cancel_active_request()
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
	if _busy or _dragging or not _actions.has("idle"):
		if request_id > 0:
			action_completed.emit(request_id, requested_action, false)
		return
	var action := _resolve_action(requested_action)
	if not _actions.has(action):
		if request_id > 0:
			action_completed.emit(request_id, requested_action, false)
			return
		action = String(_manifest.get("fallback_action", "idle"))
	if not is_action_unlocked(action):
		if request_id > 0:
			action_completed.emit(request_id, requested_action, false)
			return
		action = String(_manifest.get("fallback_action", "idle"))
	if not _actions.has(action):
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
	var behavior := String(definition.get("behavior", "sequence"))
	if behavior == "pulse":
		await _pulse_action(action, definition, serial)
	else:
		await _play_sequence(action, definition, serial)
	if serial == _animation_serial and not _dragging:
		_restore_idle()
		_busy = false
		_current_action = ""
		_finish_active_request(true)


func pick_autonomous_action(allow_move: bool) -> String:
	var candidates: Array[Dictionary] = []
	var total_weight := 0
	for action: String in _actions:
		var definition := _action_definition(action)
		var weight := int(definition.get("autonomous_weight", 0))
		if weight <= 0 or not is_action_unlocked(action):
			continue
		if action == "move" and not allow_move:
			continue
		total_weight += weight
		candidates.append({"id": action, "ceiling": total_weight})
	if total_weight <= 0:
		return ""
	var roll := randi_range(1, total_weight)
	for candidate: Dictionary in candidates:
		if roll <= int(candidate.ceiling):
			return String(candidate.id)
	return ""


func get_unlocked_action_ids() -> Array[String]:
	var result: Array[String] = []
	for action: String in _actions:
		if is_action_unlocked(action):
			result.append(action)
	return result


func get_next_unlock() -> Dictionary:
	var best: Dictionary = {}
	var best_distance := 1000000
	for action: String in _actions:
		var definition := _action_definition(action)
		var unlock: Dictionary = definition.get("unlock", {})
		if unlock.is_empty() or is_action_unlocked(action):
			continue
		var level_need := int(unlock.get("level", 1))
		var affection_need := int(unlock.get("affection", 0))
		var distance := maxi(level_need - int(_progression.level), 0) * 100 \
			+ maxi(affection_need - int(_progression.affection), 0)
		if distance < best_distance:
			best_distance = distance
			best = {
				"id": action,
				"name": String(definition.get("display_name", action)),
				"level": level_need,
				"affection": affection_need,
			}
	return best


func get_dialogue(key: String, fallback: String) -> String:
	var dialogue: Variant = _manifest.get("dialogue", {})
	if dialogue is not Dictionary or not dialogue.has(key):
		return fallback
	var entry: Variant = dialogue[key]
	if entry is String:
		return String(entry)
	if entry is Array and not entry.is_empty():
		return String(entry.pick_random())
	return fallback


func get_character_id() -> String:
	var character_id := String(_manifest.get("id", "")).strip_edges()
	return character_id if not character_id.is_empty() else "default"


func get_character_name() -> String:
	return String(_manifest.get("name", get_character_id()))


func get_character_version() -> String:
	return String(_manifest.get("version", "1.0.0"))


func get_pack_root() -> String:
	return _pack_root


func get_interaction_label(action: String, fallback: String) -> String:
	return String(_interaction_value(action, "label", fallback))


func get_interaction_icon(action: String, fallback: String) -> String:
	return String(_interaction_value(action, "icon", fallback))


func get_interaction_wish(
	action: String,
	fallback: String,
	minutes: int
) -> String:
	var template := String(_interaction_value(action, "wish", fallback))
	return template.replace("{minutes}", str(minutes))


func _interaction_value(action: String, key: String, fallback: Variant) -> Variant:
	var interactions: Variant = _manifest.get("interactions", {})
	if interactions is not Dictionary:
		return fallback
	var definition: Variant = interactions.get(action, {})
	if definition is not Dictionary:
		return fallback
	return definition.get(key, fallback)


func is_action_unlocked(action: String) -> bool:
	if not _actions.has(action):
		return false
	var unlock: Dictionary = _action_definition(action).get("unlock", {})
	return int(_progression.level) >= int(unlock.get("level", 1)) \
		and int(_progression.affection) >= int(unlock.get("affection", 0))


func get_action_duration(requested_action: String) -> float:
	var action := _resolve_action(requested_action)
	if not _actions.has(action):
		return 0.0
	var definition := _action_definition(action)
	var frame_time := float(definition.get("frame_time", 0.16))
	if String(definition.get("behavior", "sequence")) == "pulse":
		return maxi(int(definition.get("pulses", 4)), 1) * frame_time
	return _sequence_for(definition).size() * frame_time


func _play_sequence(action: String, definition: Dictionary, serial: int) -> void:
	var frame_time := float(definition.get("frame_time", 0.16))
	for frame: Variant in _sequence_for(definition):
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
		tween.tween_property(self, "scale", target * _visual_size, frame_time)
		await tween.finished


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
	_grow_window_to_fit_frame()
	_keep_frame_inside_viewport()
	_emit_interaction_region()


func _apply_sprite_scale(definition: Dictionary) -> void:
	if not is_instance_valid(_sprite):
		return
	var action_scale := float(definition.get("scale", _pack_scale)) \
		if not definition.is_empty() \
		else _pack_scale
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
		"source_facing", _manifest.get("source_facing", "left")
	)).to_lower()
	if source_facing not in ["left", "right"]:
		source_facing = "left"
	var desired_facing := "right" if _facing_direction > 0 else "left"
	return source_facing != desired_facing


func _sequence_for(definition: Dictionary) -> Array:
	var sequence: Array = definition.get("sequence", [0])
	return sequence if not sequence.is_empty() else [0]


func _first_frame(action: String) -> int:
	return int(_sequence_for(_action_definition(action))[0])


func _action_definition(action: String) -> Dictionary:
	return _actions.get(action, {})


func _resolve_action(action: String) -> String:
	return String(_aliases.get(action, action))


func _texture_for(definition: Dictionary) -> Texture2D:
	var relative_path := String(definition.get("file", ""))
	if relative_path.is_empty():
		return null
	var path := _pack_root.path_join(relative_path)
	if _texture_cache.has(path):
		return _texture_cache[path] as Texture2D
	var texture := _load_texture(path)
	if texture:
		_texture_cache[path] = texture
	return texture


func _load_pack() -> bool:
	var candidates: Array[String] = []
	var selected_id := _selected_character_id()
	if selected_id == PUBLIC_CHARACTER_ID:
		candidates.append(PUBLIC_PACK_ROOT)
	elif not selected_id.is_empty():
		candidates.append(INSTALLED_PACKS_ROOT.path_join(selected_id))
	if selected_id != PUBLIC_CHARACTER_ID:
		candidates.append(BUNDLED_CUSTOM_PACK_ROOT)
		candidates.append(PUBLIC_PACK_ROOT)
	for candidate_root: String in candidates:
		if _load_pack_from(candidate_root):
			return true
	return false


func _selected_character_id() -> String:
	var config := ConfigFile.new()
	if config.load(CHARACTER_SETTINGS_PATH) != OK:
		return ""
	var selected := String(config.get_value("character", "selected_id", ""))
	if selected.is_empty():
		return ""
	var sanitized := selected.to_lower()
	var safe := ""
	for index in sanitized.length():
		var character := sanitized.substr(index, 1)
		if character >= "a" and character <= "z" \
				or character >= "0" and character <= "9" \
				or character == "_" or character == "-":
			safe += character
	return safe if safe == selected else ""


func _load_pack_from(candidate_root: String) -> bool:
	var manifest_path := candidate_root.path_join("pet.json")
	if not FileAccess.file_exists(manifest_path):
		return false
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("pet.json is not valid JSON.")
		return false
	var candidate_manifest: Dictionary = parsed
	if int(candidate_manifest.get("format_version", 0)) != 1:
		push_warning("Unsupported character-pack format version: %s" % manifest_path)
		return false
	var candidate_actions: Variant = candidate_manifest.get("actions", {})
	if candidate_actions is not Dictionary:
		push_warning("Character pack actions must be an object: %s" % manifest_path)
		return false
	for required_action: String in REQUIRED_ACTIONS:
		if not candidate_actions.has(required_action):
			push_warning("Character pack is missing required action '%s': %s" % [
				required_action, manifest_path
			])
			return false
	for action_id: String in candidate_actions:
		if not _validate_action(action_id, candidate_actions[action_id], candidate_root):
			return false
	var fallback := String(candidate_manifest.get("fallback_action", "idle"))
	if not candidate_actions.has(fallback):
		push_warning("Character-pack fallback action does not exist: %s" % fallback)
		return false
	_manifest = candidate_manifest
	_actions = candidate_actions
	_aliases = candidate_manifest.get("aliases", {}) \
		if candidate_manifest.get("aliases", {}) is Dictionary else {}
	_pack_scale = clampf(float(candidate_manifest.get("scale", 0.31)), 0.01, 4.0)
	_pack_root = candidate_root
	return true


func _validate_action(action_id: String, raw_definition: Variant, root: String) -> bool:
	if raw_definition is not Dictionary:
		push_warning("Action '%s' must be an object." % action_id)
		return false
	var definition: Dictionary = raw_definition
	var relative_path := String(definition.get("file", ""))
	if relative_path.is_empty() or relative_path.is_absolute_path() or relative_path.contains(".."):
		push_warning("Action '%s' has an unsafe or empty file path." % action_id)
		return false
	var full_path := root.path_join(relative_path)
	if not FileAccess.file_exists(full_path) and not ResourceLoader.exists(full_path):
		push_warning("Action '%s' image does not exist: %s" % [action_id, full_path])
		return false
	var columns := int(definition.get("columns", 1))
	var rows := int(definition.get("rows", 1))
	if columns <= 0 or rows <= 0:
		push_warning("Action '%s' columns and rows must be positive." % action_id)
		return false
	var sequence: Variant = definition.get("sequence", [0])
	if sequence is not Array or sequence.is_empty():
		push_warning("Action '%s' sequence must be a non-empty array." % action_id)
		return false
	for frame: Variant in sequence:
		var frame_index := int(frame)
		if frame_index < 0 or frame_index >= columns * rows:
			push_warning("Action '%s' contains an out-of-range frame." % action_id)
			return false
	if float(definition.get("frame_time", 0.16)) <= 0.0:
		push_warning("Action '%s' frame_time must be positive." % action_id)
		return false
	if float(definition.get("frame_time", 0.16)) > 5.0 or sequence.size() > 120:
		push_warning("Action '%s' animation duration settings are excessive." % action_id)
		return false
	if int(definition.get("pulses", 4)) < 1 or int(definition.get("pulses", 4)) > 120:
		push_warning("Action '%s' pulses must be between 1 and 120." % action_id)
		return false
	var offsets: Variant = definition.get("offsets", [])
	if offsets is not Array:
		push_warning("Action '%s' offsets must be an array." % action_id)
		return false
	for offset: Variant in offsets:
		if offset is not Array or offset.size() < 2:
			push_warning("Action '%s' has an invalid offset." % action_id)
			return false
	return true


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
		var bitmap := BitMap.new()
		bitmap.create_from_image_alpha(frame_image, 0.08)
		var polygons := bitmap.opaque_to_polygons(
			Rect2i(Vector2i.ZERO, frame_image.get_size()),
			2.0
		)
		var all_points := PackedVector2Array()
		for candidate: PackedVector2Array in polygons:
			all_points.append_array(candidate)
		if not all_points.is_empty():
			var content_bounds := Rect2(all_points[0], Vector2.ZERO)
			for point: Vector2 in all_points:
				content_bounds = content_bounds.expand(point)
			pixel_polygon = PackedVector2Array([
				content_bounds.position,
				Vector2(content_bounds.end.x, content_bounds.position.y),
				content_bounds.end,
				Vector2(content_bounds.position.x, content_bounds.end.y),
			])
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
	var current_size := Vector2(window.size)
	var required_start := Vector2(
		minf(visible_bounds.position.x - FRAME_VIEWPORT_PADDING, 0.0),
		minf(visible_bounds.position.y - FRAME_VIEWPORT_PADDING, 0.0)
	)
	var required_end := Vector2(
		maxf(visible_bounds.end.x + FRAME_VIEWPORT_PADDING, current_size.x),
		maxf(visible_bounds.end.y + FRAME_VIEWPORT_PADDING, current_size.y)
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
		var frame_image := image.get_region(pixel_rect)
		var bitmap := BitMap.new()
		bitmap.create_from_image_alpha(frame_image, 0.08)
		var polygons := bitmap.opaque_to_polygons(
			Rect2i(Vector2i.ZERO, frame_image.get_size()),
			2.0
		)
		var has_point := false
		for polygon: PackedVector2Array in polygons:
			for point: Vector2 in polygon:
				if has_point:
					opaque_bounds = opaque_bounds.expand(point)
				else:
					opaque_bounds = Rect2(point, Vector2.ZERO)
					has_point = true
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


func _polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for index in polygon.size():
		var next := (index + 1) % polygon.size()
		area += polygon[index].x * polygon[next].y
		area -= polygon[next].x * polygon[index].y
	return area * 0.5


func _emit_interaction_region() -> void:
	interaction_region_changed.emit(get_interaction_polygon())


func _draw() -> void:
	if _actions.has("idle"):
		return
	draw_circle(Vector2.ZERO, 72.0, Color("#a9d9e8"))
	draw_circle(Vector2(0, 18), 49.0, Color("#f6ead2"))
