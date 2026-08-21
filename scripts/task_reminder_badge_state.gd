class_name TaskReminderBadgeState
extends RefCounted

var visible: bool
var label: String
var tooltip: String
var attention_label: String
var attention_tooltip: String


func _init(
	visible_value := false,
	label_value := "",
	tooltip_value := "",
	attention_label_value := "",
	attention_tooltip_value := ""
) -> void:
	visible = visible_value
	label = label_value
	tooltip = tooltip_value
	attention_label = attention_label_value
	attention_tooltip = attention_tooltip_value


func has_attention() -> bool:
	return not attention_label.is_empty()
