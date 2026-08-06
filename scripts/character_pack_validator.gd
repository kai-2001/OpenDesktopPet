class_name CharacterPackValidator
extends RefCounted

const ALLOWED_IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "svg"]
const MAX_FRAME_CELLS := 4096
const MAX_SEQUENCE_LENGTH := 120


func validate_action(
	action_id: String,
	raw_definition: Variant,
	root: String,
	allow_resource_loader := false,
	enforce_image_extension := false
) -> bool:
	if raw_definition is not Dictionary:
		return _fail("Action '%s' must be an object." % action_id)
	var definition: Dictionary = raw_definition
	var relative_path := String(definition.get("file", ""))
	if relative_path.is_empty() \
			or relative_path.is_absolute_path() \
			or relative_path.contains("..") \
			or relative_path.contains("\\"):
		return _fail("Action '%s' has an unsafe or empty file path." % action_id)
	if enforce_image_extension \
			and relative_path.get_extension().to_lower() not in ALLOWED_IMAGE_EXTENSIONS:
		return _fail("Action '%s' uses an unsupported image format." % action_id)
	var full_path := root.path_join(relative_path)
	if not FileAccess.file_exists(full_path) \
			and not (allow_resource_loader and ResourceLoader.exists(full_path)):
		return _fail("Action '%s' image does not exist: %s" % [action_id, full_path])

	var columns := int(definition.get("columns", 1))
	var rows := int(definition.get("rows", 1))
	if columns <= 0 or rows <= 0 or columns * rows > MAX_FRAME_CELLS:
		return _fail("Action '%s' has invalid frame dimensions." % action_id)

	var sequence: Variant = definition.get("sequence", [0])
	if sequence is not Array \
			or sequence.is_empty() \
			or sequence.size() > MAX_SEQUENCE_LENGTH:
		return _fail("Action '%s' sequence is invalid." % action_id)
	if not _validate_frames(action_id, sequence, columns * rows):
		return false

	if action_id == "sleep":
		for phase_key: String in ["enter_sequence", "loop_sequence", "wake_sequence"]:
			if not definition.has(phase_key):
				continue
			var phase: Variant = definition[phase_key]
			if phase is not Array \
					or phase.is_empty() \
					or phase.size() > MAX_SEQUENCE_LENGTH:
				return _fail("Sleep action '%s' is invalid." % phase_key)
			if not _validate_frames("Sleep action '%s'" % phase_key, phase, columns * rows):
				return false

	var frame_time := float(definition.get("frame_time", 0.16))
	if frame_time <= 0.0 or frame_time > 5.0:
		return _fail("Action '%s' frame_time is invalid." % action_id)
	var pulses := int(definition.get("pulses", 4))
	if pulses < 1 or pulses > MAX_SEQUENCE_LENGTH:
		return _fail("Action '%s' pulses are invalid." % action_id)
	var offsets: Variant = definition.get("offsets", [])
	if offsets is not Array:
		return _fail("Action '%s' offsets are invalid." % action_id)
	for offset: Variant in offsets:
		if offset is not Array or offset.size() < 2:
			return _fail("Action '%s' has an invalid offset." % action_id)
	return true


func _validate_frames(label: String, frames: Array, frame_count: int) -> bool:
	for frame: Variant in frames:
		var frame_index := int(frame)
		if frame_index < 0 or frame_index >= frame_count:
			return _fail("%s contains an out-of-range frame." % label)
	return true


func _fail(message: String) -> bool:
	push_warning(message)
	return false
