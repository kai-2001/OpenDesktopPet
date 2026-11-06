class_name CharacterGeometryCache
extends RefCounted

# Remembers the fixed-window envelope measured for each character pack.
# Measuring decodes every frame of every action, which took over a second for
# large packs on each switch, so the envelope is reused while none of the
# pack's files, the measuring code or the app version changed.

const CACHE_PATH := "user://character_geometry_cache.json"
const FORMAT := 1


## `inputs` lists the measuring code's own parameters, so changing them
## invalidates every cached envelope.
static func signature(pack_root: String, inputs: Array) -> String:
	var parts: Array[String] = [
		String(ProjectSettings.get_setting("application/config/version", "")),
	]
	for value: Variant in inputs:
		parts.append(str(value))
	for path: String in _pack_files(pack_root):
		parts.append("%s|%d|%d" % [
			path.trim_prefix(pack_root), _file_size(path), FileAccess.get_modified_time(path),
		])
	return "\n".join(parts).sha256_text()


## Returns the cached envelope as a Rect2, or null when it must be measured.
static func lookup(character_id: String, pack_signature: String) -> Variant:
	var entry: Variant = _read_packs().get(character_id)
	if entry is not Dictionary or String(entry.get("signature", "")) != pack_signature:
		return null
	var raw: Variant = entry.get("envelope")
	if raw is not Array or raw.size() != 4:
		return null
	return Rect2(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))


static func store(character_id: String, pack_signature: String, envelope: Rect2) -> void:
	var packs := _read_packs()
	packs[character_id] = {
		"signature": pack_signature,
		"envelope": [envelope.position.x, envelope.position.y, envelope.size.x, envelope.size.y],
	}
	_write_packs(packs)


static func forget(character_id: String) -> void:
	var packs := _read_packs()
	if packs.erase(character_id):
		_write_packs(packs)


static func _read_packs() -> Dictionary:
	if not FileAccess.file_exists(CACHE_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CACHE_PATH))
	if parsed is not Dictionary or int(parsed.get("format", 0)) != FORMAT:
		return {}
	var packs: Variant = parsed.get("packs", {})
	return packs if packs is Dictionary else {}


static func _write_packs(packs: Dictionary) -> void:
	var file := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"format": FORMAT, "packs": packs}))
	file.close()


static func _pack_files(root: String) -> Array[String]:
	var files: Array[String] = []
	var directory := DirAccess.open(root)
	if directory == null:
		return files
	for file_name: String in directory.get_files():
		files.append(root.path_join(file_name))
	for folder: String in directory.get_directories():
		files.append_array(_pack_files(root.path_join(folder)))
	files.sort()
	return files


static func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var size := file.get_length()
	file.close()
	return size
