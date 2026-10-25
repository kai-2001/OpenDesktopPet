class_name CjkLineBreaks
extends RefCounted

## Lets Chinese text wrap in exported builds. Exports ship without ICU break
## data, and Godot then only breaks lines at whitespace, so a sentence with
## no spaces runs past its label. Zero-width spaces count as whitespace in
## that fallback and are explicit break opportunities when the data exists,
## so inserting them between CJK characters wraps the same way in both.

const BREAK := "​"
# Closing punctuation must not start a line; opening punctuation must not
# end one. No break is inserted on those sides.
const NO_LINE_START := "，。、．！？：；）」』】〕〉》”’…—～・,.!?:;)]}%"
const NO_LINE_END := "（「『【〔〈《“‘([{"


static func insert_break_opportunities(text: String) -> String:
	var result := ""
	for index in text.length():
		var current := text[index]
		if index > 0 and _can_break_between(text[index - 1], current):
			result += BREAK
		result += current
	return result


static func strip(text: String) -> String:
	return text.replace(BREAK, "")


static func _can_break_between(before: String, after: String) -> bool:
	if before == BREAK or after == BREAK:
		return false
	if before.strip_edges().is_empty() or after.strip_edges().is_empty():
		return false
	if NO_LINE_START.contains(after) or NO_LINE_END.contains(before):
		return false
	# Latin words keep breaking only at spaces; a break is allowed next to any
	# wide character, as between ideographs or between "Lv.3" and "解鎖".
	return _is_wide(before) or _is_wide(after)


static func _is_wide(character: String) -> bool:
	var code := character.unicode_at(0)
	return (code >= 0x1100 and code <= 0x115F) \
		or (code >= 0x2E80 and code <= 0x303F) \
		or (code >= 0x3040 and code <= 0x33FF) \
		or (code >= 0x3400 and code <= 0x4DBF) \
		or (code >= 0x4E00 and code <= 0x9FFF) \
		or (code >= 0xAC00 and code <= 0xD7AF) \
		or (code >= 0xF900 and code <= 0xFAFF) \
		or (code >= 0xFE30 and code <= 0xFE4F) \
		or (code >= 0xFF00 and code <= 0xFF60) \
		or (code >= 0xFFE0 and code <= 0xFFE6) \
		or (code >= 0x20000 and code <= 0x3FFFD)
