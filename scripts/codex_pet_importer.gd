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
	var character_id := _normalized_id(manifest)
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
	normalized_manifest["id"] = character_id
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
	var character_id := _normalized_id(manifest)
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
	# Standard Codex rows the base mapping did not use. Every Codex atlas,
	# v1 and v2, contains them with these frame counts.
	var waving := _row_definition(spritesheet_path, 3, "waving", 0.25, 4, rows_count)
	var failed := _row_definition(spritesheet_path, 5, "failed", 0.25, 8, rows_count)
	var waiting := _row_definition(spritesheet_path, 6, "waiting", 0.25, 6, rows_count)
	var review := _row_definition(spritesheet_path, 8, "review", 0.25, 6, rows_count)
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
		# Autonomous actions unlocked through long-term care.
		"waving": waving.duplicate(true),
		"review": review.duplicate(true),
		"waiting": waiting.duplicate(true),
		# Event reactions: never picked autonomously and never locked, because
		# they report Agent or care state rather than reward progression.
		"agent_done": waving.duplicate(true),
		"agent_waiting": waiting.duplicate(true),
		"failed": failed.duplicate(true),
	}
	rows["move"]["autonomous_weight"] = 4
	rows.waving.autonomous_weight = 2
	rows.waving.unlock = {"level": 3}
	rows.waving.display_name = "揮手"
	rows.review.autonomous_weight = 2
	rows.review.unlock = {"level": 6, "affection": 15}
	rows.review.display_name = "專注"
	rows.waiting.autonomous_weight = 2
	rows.waiting.unlock = {"level": 10, "affection": 40}
	rows.waiting.display_name = "期待"
	rows.agent_done.display_name = "完成報告"
	rows.agent_waiting.display_name = "等待回應"
	rows.failed.display_name = "沮喪"
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
	var header_size := _read_header_dimensions(path)
	if header_size != Vector2i.ZERO:
		return header_size
	var image := Image.new()
	var error := image.load(ProjectSettings.globalize_path(path))
	if error != OK:
		return Vector2i.ZERO
	return Vector2i(image.get_width(), image.get_height())


## Listing packs checks every spritesheet's size. PNG and WebP store it in
## their first bytes, so read those instead of decoding the whole sheet; other
## formats fall back to decoding.
static func _read_header_dimensions(path: String) -> Vector2i:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Vector2i.ZERO
	var header := file.get_buffer(30)
	file.close()
	if header.size() >= 24 			and header.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) 			and header.slice(12, 16).get_string_from_ascii() == "IHDR":
		return Vector2i(_big_endian_u32(header, 16), _big_endian_u32(header, 20))
	if header.size() < 30 			or header.slice(0, 4).get_string_from_ascii() != "RIFF" 			or header.slice(8, 12).get_string_from_ascii() != "WEBP":
		return Vector2i.ZERO
	match header.slice(12, 16).get_string_from_ascii():
		"VP8 ":
			# Lossy: 14-bit sizes follow the 9D 01 2A frame start code.
			if header[23] == 0x9D and header[24] == 0x01 and header[25] == 0x2A:
				return Vector2i(
					header.decode_u16(26) & 0x3FFF, header.decode_u16(28) & 0x3FFF
				)
		"VP8L":
			# Lossless: after the 0x2F signature, 14 bits each of width - 1 and height - 1.
			if header[20] == 0x2F:
				var bits := header.decode_u32(21)
				return Vector2i((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1)
		"VP8X":
			# Extended: 24-bit canvas width - 1 and height - 1.
			return Vector2i(
				(header[24] | header[25] << 8 | header[26] << 16) + 1,
				(header[27] | header[28] << 8 | header[29] << 16) + 1
			)
	return Vector2i.ZERO


static func _big_endian_u32(bytes: PackedByteArray, offset: int) -> int:
	return bytes[offset] << 24 | bytes[offset + 1] << 16 | bytes[offset + 2] << 8 | bytes[offset + 3]


## Codex pet files may use mixed-case ids such as "Giratina". Pack folders and
## saves are keyed by id, and Windows paths ignore case, so fold to lowercase
## once here instead of rejecting the pet.
static func _normalized_id(manifest: Dictionary) -> String:
	return String(manifest.get("id", "")).strip_edges().to_lower()


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
