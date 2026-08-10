class_name CodexPetImporter
extends RefCounted

const CELL_WIDTH := 192
const CELL_HEIGHT := 208
const V1_ROWS := 9
const V2_ROWS := 11
const MAX_ID_LENGTH := 80
const CharacterPackOptionsScript = preload("res://scripts/character_pack_options.gd")


static func is_codex_manifest(manifest: Dictionary) -> bool:
	var spritesheet_path := String(manifest.get("spritesheetPath", "")).strip_edges()
	return not spritesheet_path.is_empty() and not manifest.has("actions")


static func normalize(root: String, manifest: Dictionary) -> Dictionary:
	if not is_codex_manifest(manifest):
		return {"ok": false, "message": "不是 Codex Pet pet.json。"}
	var character_id := String(manifest.get("id", "")).strip_edges()
	if not _is_safe_id(character_id):
		return {"ok": false, "message": "Codex Pet id 不符合桌寵包命名規則。"}
	var spritesheet_path := String(manifest.get("spritesheetPath", "")).strip_edges()
	if not _is_safe_relative_path(spritesheet_path):
		return {"ok": false, "message": "Codex Pet spritesheetPath 不是安全的相對路徑。"}
	var sheet_path := root.path_join(spritesheet_path)
	if not FileAccess.file_exists(sheet_path):
		return {"ok": false, "message": "找不到 Codex Pet spritesheet：%s" % spritesheet_path}
	var sprite_version := int(manifest.get("spriteVersionNumber", 1))
	if sprite_version not in [1, 2]:
		return {"ok": false, "message": "不支援的 Codex Pet spriteVersionNumber：%d" % sprite_version}
	var dimensions := _read_dimensions(sheet_path)
	if dimensions.x != CELL_WIDTH * 8 or dimensions.y != CELL_HEIGHT * _rows_for_version(sprite_version):
		return {
			"ok": false,
			"message": "Codex Pet spritesheet 尺寸錯誤，應為 1536x%d。"
				% (CELL_HEIGHT * _rows_for_version(sprite_version)),
		}
	var actions := _build_actions(spritesheet_path, sprite_version)
	var normalized_manifest := manifest.duplicate(true)
	normalized_manifest["name"] = String(manifest.get("displayName", character_id))
	normalized_manifest["version"] = String(manifest.get("version", "codex-v%d" % sprite_version))
	normalized_manifest["format"] = "codex-pet"
	normalized_manifest["source_format"] = "codex-pet"
	normalized_manifest["fallback_action"] = "idle"
	normalized_manifest["scale"] = 0.58
	var options := CharacterPackOptionsScript.load_for_pack(root, {
		"autonomous_chance": 0.35,
		"effect_scale_ratio": float(normalized_manifest.scale),
	})
	return {
		"ok": true,
		"manifest": normalized_manifest,
		"actions": actions,
		"aliases": {"codex_idle": "idle"},
		"scale": clampf(float(normalized_manifest.scale), 0.01, 4.0),
		"root": root,
		"source_format": "codex-pet",
		"sprite_version": sprite_version,
		"options": options,
	}


static func inspect_manifest(manifest: Dictionary, available_files: Array = []) -> Dictionary:
	if not is_codex_manifest(manifest):
		return {"ok": false, "message": "不是 Codex Pet pet.json。"}
	var character_id := String(manifest.get("id", "")).strip_edges()
	if not _is_safe_id(character_id):
		return {"ok": false, "message": "Codex Pet id 不符合桌寵包命名規則。"}
	var spritesheet_path := String(manifest.get("spritesheetPath", "")).strip_edges()
	if not _is_safe_relative_path(spritesheet_path):
		return {"ok": false, "message": "Codex Pet spritesheetPath 不是安全的相對路徑。"}
	if not available_files.is_empty() and spritesheet_path not in available_files:
		return {"ok": false, "message": "ZIP 缺少 Codex Pet spritesheet：%s" % spritesheet_path}
	var sprite_version := int(manifest.get("spriteVersionNumber", 1))
	if sprite_version not in [1, 2]:
		return {"ok": false, "message": "不支援的 Codex Pet spriteVersionNumber：%d" % sprite_version}
	return {
		"ok": true,
		"id": character_id,
		"name": String(manifest.get("displayName", character_id)),
		"version": String(manifest.get("version", "codex-v%d" % sprite_version)),
		"source_format": "codex-pet",
		"sprite_version": sprite_version,
	}


static func _build_actions(spritesheet_path: String, sprite_version: int) -> Dictionary:
	var rows_count := _rows_for_version(sprite_version)
	var idle := _row_definition(spritesheet_path, 0, "idle", 0.25, 6, rows_count)
	idle["idle_interval"] = 0.25
	var running_right := _row_definition(
		spritesheet_path, 1, "running-right", 0.25, 8, rows_count, "right"
	)
	var running := _row_definition(
		spritesheet_path, 7, "running", 0.25, 6, rows_count
	)
	var jumping := _row_definition(spritesheet_path, 4, "jumping", 0.25, 5, rows_count)
	var rows := {
		"idle": idle,
		"running": running,
		"jumping": jumping,
		"pet": jumping.duplicate(true),
		"eat": idle.duplicate(true),
		"drink": idle.duplicate(true),
		"sleep": idle.duplicate(true),
		"move": running_right.duplicate(true),
		"drag": running_right.duplicate(true),
		"work": running.duplicate(true),
	}
	rows["move"]["autonomous_weight"] = 1
	rows.pet.display_name = "摸摸"
	rows.eat.display_name = "吃飯"
	rows.drink.display_name = "喝水"
	rows.sleep.display_name = "睡覺"
	rows.move.display_name = "移動"
	rows.drag.display_name = "拖曳"
	rows.work.display_name = "工作"
	return rows


static func _row_definition(
	spritesheet_path: String,
	row: int,
	action_name: String,
	frame_time: float,
	frame_count: int,
	rows_count: int,
	source_facing := "left"
) -> Dictionary:
	var sequence: Array[int] = []
	for column in mini(frame_count, 8):
		sequence.append(row * 8 + column)
	return {
		"file": spritesheet_path,
		"columns": 8,
		"rows": rows_count,
		"sequence": sequence,
		"frame_time": frame_time,
		"scale": 0.58,
		"source_facing": source_facing,
		"display_name": action_name,
	}


static func _rows_for_version(sprite_version: int) -> int:
	return V2_ROWS if sprite_version == 2 else V1_ROWS


static func _read_dimensions(path: String) -> Vector2i:
	var image := Image.new()
	var error := image.load(ProjectSettings.globalize_path(path))
	if error != OK:
		return Vector2i.ZERO
	return Vector2i(image.get_width(), image.get_height())


static func _is_safe_id(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_ID_LENGTH:
		return false
	for index in value.length():
		var character := value.substr(index, 1)
		if not (
			(character >= "a" and character <= "z")
			or (character >= "0" and character <= "9")
			or character == "_"
			or character == "-"
		):
			return false
	return true


static func _is_safe_relative_path(path: String) -> bool:
	if path.is_empty() or path.is_absolute_path() or path.contains("\\") or path.contains(":"):
		return false
	for part: String in path.split("/"):
		if part.is_empty() or part == "." or part == "..":
			return false
	return path.get_extension().to_lower() in ["png", "webp", "jpg", "jpeg"]
