class_name PetVisual
extends Node2D

const PACK_ROOT := "res://private_pets/active/"
const MANIFEST_PATH := PACK_ROOT + "pet.json"
const REQUIRED_ACTIONS := ["idle", "pet", "eat", "drink", "sleep", "move", "drag", "work"]

var _sprite: Sprite2D
var _manifest: Dictionary = {}
var _actions: Dictionary = {}
var _aliases: Dictionary = {}
var _texture_cache: Dictionary = {}
var _progression: Dictionary = {"level": 1, "affection": 0}
var _busy := false
var _dragging := false
var _drag_moving := false
var _visual_size := 1.0
var _pack_scale := 0.31
var _time := 0.0
var _idle_clock := 0.0
var _idle_step := 0
var _home_position := Vector2.ZERO
var _animation_serial := 0
var _current_action := ""


func _ready() -> void:
	_home_position = position
	_sprite = Sprite2D.new()
	_sprite.z_index = 1
	add_child(_sprite)
	if _load_pack():
		_show_action_frame("idle", _first_frame("idle"))
	else:
		push_error("No valid character pack was found at %s." % MANIFEST_PATH)
		queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _dragging:
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
	_animation_serial += 1
	_dragging = value
	_busy = false
	_drag_moving = false
	_current_action = ""
	if value:
		_show_action_frame("drag", _first_frame("drag"))
		scale = Vector2.ONE * _visual_size
	else:
		_restore_idle()


func set_drag_motion(is_moving: bool) -> void:
	if not _dragging:
		return
	_drag_moving = is_moving
	var definition := _action_definition("drag")
	var sequence := _sequence_for(definition)
	var index := mini(1 if is_moving else 0, sequence.size() - 1)
	_show_action_frame("drag", int(sequence[index]))


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
	_visual_size = clampf(_visual_size + delta, 0.7, 1.4)
	scale = Vector2.ONE * _visual_size


func play_action(requested_action: String) -> void:
	if _busy or _dragging or not _actions.has("idle"):
		return
	var action := _resolve_action(requested_action)
	if not _actions.has(action):
		action = String(_manifest.get("fallback_action", "idle"))
	if not is_action_unlocked(action):
		action = String(_manifest.get("fallback_action", "idle"))
	var definition := _action_definition(action)
	_busy = true
	_current_action = action
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


func is_action_unlocked(action: String) -> bool:
	if not _actions.has(action):
		return false
	var unlock: Dictionary = _action_definition(action).get("unlock", {})
	return int(_progression.level) >= int(unlock.get("level", 1)) \
		and int(_progression.affection) >= int(unlock.get("affection", 0))


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
	_sprite.scale = Vector2.ONE * float(definition.get("scale", _pack_scale))


func _frame_offset(definition: Dictionary, frame: int) -> Vector2:
	var offsets: Array = definition.get("offsets", [])
	if frame >= offsets.size() or offsets[frame] is not Array:
		return Vector2.ZERO
	var pair: Array = offsets[frame]
	if pair.size() < 2:
		return Vector2.ZERO
	return Vector2(float(pair[0]), float(pair[1]))


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
	var path := PACK_ROOT + relative_path
	if _texture_cache.has(path):
		return _texture_cache[path] as Texture2D
	var texture := _load_texture(path)
	if texture:
		_texture_cache[path] = texture
	return texture


func _load_pack() -> bool:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return false
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("pet.json is not valid JSON.")
		return false
	_manifest = parsed
	if int(_manifest.get("format_version", 0)) != 1:
		push_error("Unsupported character-pack format version.")
		return false
	_actions = _manifest.get("actions", {})
	_aliases = _manifest.get("aliases", {})
	_pack_scale = float(_manifest.get("scale", 0.31))
	for required_action: String in REQUIRED_ACTIONS:
		if not _actions.has(required_action):
			push_error("Character pack is missing required action: %s" % required_action)
			return false
		var definition := _action_definition(required_action)
		if String(definition.get("file", "")).is_empty():
			push_error("Action '%s' has no file." % required_action)
			return false
	return true


func _restore_idle() -> void:
	position = _home_position
	rotation = 0.0
	scale = Vector2.ONE * _visual_size
	_idle_clock = 0.0
	_idle_step = 0
	_show_action_frame("idle", _first_frame("idle"))


func _load_texture(path: String) -> Texture2D:
	if FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image and not image.is_empty():
			return ImageTexture.create_from_image(image)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _draw() -> void:
	if _actions.has("idle"):
		return
	draw_circle(Vector2.ZERO, 72.0, Color("#a9d9e8"))
	draw_circle(Vector2(0, 18), 49.0, Color("#f6ead2"))
