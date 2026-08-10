class_name PetEffectController
extends Node2D

const EFFECT_LIBRARY_PATH := "res://assets/effects/effect_library.json"
const DEFAULT_DEFINITIONS := {
	"food": {
		"file": "res://assets/effects/food.png",
		"anchor": [-72.0, 22.0],
		"scale": 0.45,
		"duration": 1.6,
		"sway": 5.0,
	},
	"water": {
		"file": "res://assets/effects/water_cup.png",
		"anchor": [-58.0, 18.0],
		"scale": 0.38,
		"duration": 1.5,
		"sway": 4.0,
	},
	"mask": {
		"file": "res://assets/effects/eye_mask.png",
		"anchor": [-70.0, -12.0],
		"scale": 0.32,
	},
	"zzz": {
		"file": "res://assets/effects/zzz.png",
		"anchor": [-24.0, -52.0],
		"scale": 0.28,
		"duration": 1.35,
	},
}

var _definitions: Dictionary = {}
var _base_definitions: Dictionary = {}
var _sprites: Dictionary = {}
var _texture_cache: Dictionary = {}
var _active_tweens: Array[Tween] = []
var _sleep_effect_active := false
var _effect_serial := 0


func _ready() -> void:
	z_index = 2
	_load_library()
	_create_sprite("food")
	_create_sprite("water")
	_create_sprite("mask")
	_create_sprite("zzz")
	_hide_all()


func configure_for_pack(effect_scale_ratio: float, overrides: Dictionary = {}) -> void:
	if _base_definitions.is_empty():
		return
	var ratio := clampf(effect_scale_ratio, 0.45, 2.0)
	_definitions = _base_definitions.duplicate(true)
	for effect_name: String in overrides:
		if not _definitions.has(effect_name) or not overrides[effect_name] is Dictionary:
			continue
		var definition: Dictionary = _definitions[effect_name]
		definition.merge(overrides[effect_name], true)
		_definitions[effect_name] = definition
	for effect_name: String in _definitions:
		var definition: Dictionary = _definitions[effect_name]
		var raw_anchor: Variant = definition.get("anchor", [0.0, 0.0])
		if raw_anchor is Array and raw_anchor.size() >= 2:
			definition["anchor"] = [float(raw_anchor[0]) * ratio, float(raw_anchor[1]) * ratio]
		if definition.has("scale"):
			definition["scale"] = float(definition.scale) * ratio
		_definitions[effect_name] = definition
		var sprite: Sprite2D = _sprites.get(effect_name) as Sprite2D
		if sprite != null:
			sprite.texture = _texture_for_definition(definition)
		_reset_sprite(effect_name)


func play_for_action(action: String) -> void:
	match action:
		"eat":
			_play_transient("food")
		"drink":
			_play_transient("water")
		"sleep":
			# The persistent sleep visuals start when PetState enters sleep.
			pass
		_:
			_stop_transient_effects()


func start_sleep() -> void:
	_sleep_effect_active = true
	_effect_serial += 1
	_stop_transient_effects()
	_set_sprite_visible("mask", true)
	_reset_sprite("mask")
	_run_zzz_loop(_effect_serial)


func stop_sleep() -> void:
	_sleep_effect_active = false
	_effect_serial += 1
	_stop_all_tweens()
	_set_sprite_visible("mask", false)
	_set_sprite_visible("zzz", false)


func reset() -> void:
	_sleep_effect_active = false
	_effect_serial += 1
	_stop_all_tweens()
	_hide_all()


func stop_transient_effects() -> void:
	_stop_transient_effects()


func _load_library() -> void:
	_definitions = DEFAULT_DEFINITIONS.duplicate(true)
	if not FileAccess.file_exists(EFFECT_LIBRARY_PATH):
		return
	var file := FileAccess.open(EFFECT_LIBRARY_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary or not parsed.has("effects"):
		return
	var effects: Variant = parsed.effects
	if effects is not Dictionary:
		return
	for effect_name: String in effects:
		if effects[effect_name] is Dictionary:
			var definition: Dictionary = _definitions.get(effect_name, {}).duplicate(true)
			definition.merge(effects[effect_name], true)
			_definitions[effect_name] = definition
	_base_definitions = _definitions.duplicate(true)


func _create_sprite(effect_name: String) -> void:
	var definition: Dictionary = _definition(effect_name)
	var sprite := Sprite2D.new()
	sprite.name = effect_name.capitalize()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = 1
	var path := String(definition.get("file", ""))
	if not path.is_empty():
		sprite.texture = _texture_for_definition(definition)
	add_child(sprite)
	_sprites[effect_name] = sprite


func _play_transient(effect_name: String) -> void:
	if not _sprites.has(effect_name):
		return
	_effect_serial += 1
	var serial := _effect_serial
	_stop_transient_effects()
	var sprite: Sprite2D = _sprites[effect_name]
	var definition := _definition(effect_name)
	var anchor := _anchor(definition)
	var base_scale := float(definition.get("scale", 1.0))
	var duration := maxf(float(definition.get("duration", 1.4)), 0.2)
	var sway := float(definition.get("sway", 4.0))
	sprite.visible = true
	sprite.position = anchor
	sprite.rotation = 0.0
	sprite.scale = Vector2.ONE * base_scale
	sprite.modulate = Color.WHITE

	var tween := create_tween()
	_active_tweens.append(tween)
	tween.tween_property(sprite, "position", anchor + Vector2(sway, 0.0), duration * 0.16)
	tween.tween_property(sprite, "rotation", deg_to_rad(7.0), duration * 0.16)
	tween.tween_property(sprite, "position", anchor - Vector2(sway, 0.0), duration * 0.16)
	tween.tween_property(sprite, "rotation", deg_to_rad(-7.0), duration * 0.16)
	tween.tween_property(sprite, "position", anchor, duration * 0.16)
	tween.tween_property(sprite, "rotation", 0.0, duration * 0.16)
	tween.tween_interval(duration * 0.12)
	tween.tween_property(sprite, "modulate:a", 0.0, duration * 0.2)
	_hide_transient_after(sprite, serial, duration, tween)


func _hide_transient_after(sprite: Sprite2D, serial: int, duration: float, tween: Tween) -> void:
	await get_tree().create_timer(duration).timeout
	_remove_tween(tween)
	if serial == _effect_serial:
		sprite.visible = false


func _run_zzz_loop(serial: int) -> void:
	while _sleep_effect_active and serial == _effect_serial:
		var sprite: Sprite2D = _sprites.get("zzz") as Sprite2D
		if sprite == null:
			return
		var definition := _definition("zzz")
		var anchor := _anchor(definition)
		var base_scale := float(definition.get("scale", 0.28))
		var duration := maxf(float(definition.get("duration", 1.35)), 0.4)
		sprite.visible = true
		sprite.position = anchor + Vector2(0.0, 8.0)
		sprite.scale = Vector2.ONE * base_scale
		sprite.modulate = Color(1.0, 1.0, 1.0, 0.0)
		var tween := create_tween()
		_active_tweens.append(tween)
		tween.set_parallel(true)
		tween.tween_property(
			sprite, "position", anchor + Vector2(8.0, -22.0), duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(sprite, "modulate:a", 1.0, duration * 0.22)
		tween.tween_property(
			sprite, "scale", Vector2.ONE * base_scale * 1.12, duration
		).set_trans(Tween.TRANS_SINE)
		tween.chain().tween_property(sprite, "modulate:a", 0.0, duration * 0.28)
		await tween.finished
		_remove_tween(tween)
		if serial != _effect_serial:
			return
		sprite.visible = false
		await get_tree().create_timer(0.18).timeout


func _stop_transient_effects() -> void:
	_stop_all_tweens()
	for effect_name: String in ["food", "water"]:
		_set_sprite_visible(effect_name, false)


func _stop_all_tweens() -> void:
	for tween: Tween in _active_tweens.duplicate():
		if is_instance_valid(tween):
			tween.kill()
	_active_tweens.clear()


func _remove_tween(tween: Tween) -> void:
	_active_tweens.erase(tween)


func _hide_all() -> void:
	for effect_name: String in _sprites:
		_set_sprite_visible(effect_name, false)


func _reset_sprite(effect_name: String) -> void:
	var sprite: Sprite2D = _sprites.get(effect_name) as Sprite2D
	if sprite == null:
		return
	var definition := _definition(effect_name)
	sprite.position = _anchor(definition)
	sprite.rotation = 0.0
	sprite.scale = Vector2.ONE * float(definition.get("scale", 1.0))
	sprite.modulate = Color.WHITE


func _set_sprite_visible(effect_name: String, visible: bool) -> void:
	var sprite: Sprite2D = _sprites.get(effect_name) as Sprite2D
	if sprite:
		sprite.visible = visible


func _definition(effect_name: String) -> Dictionary:
	return _definitions.get(effect_name, {}) as Dictionary


func _anchor(definition: Dictionary) -> Vector2:
	var raw_anchor: Variant = definition.get("anchor", [0.0, 0.0])
	if raw_anchor is Array and raw_anchor.size() >= 2:
		return Vector2(float(raw_anchor[0]), float(raw_anchor[1]))
	return Vector2.ZERO


func _texture_for_definition(definition: Dictionary) -> Texture2D:
	var path := String(definition.get("file", ""))
	if path.is_empty():
		return null
	if _texture_cache.has(path):
		return _texture_cache[path] as Texture2D
	var texture: Texture2D
	if path.begins_with("res://") and ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var image := Image.new()
		if image.load(ProjectSettings.globalize_path(path)) == OK:
			texture = ImageTexture.create_from_image(image)
	if texture != null:
		_texture_cache[path] = texture
	return texture
