extends Node3D

var _pet_root: Node3D
var _expression_nodes: Dictionary = {
	"neutral": [],
	"open_mouth": [],
	"happy": [],
}
var _time := 0.0


func _ready() -> void:
	_pet_root = find_child("PetRoot", true, false) as Node3D
	_collect_expression_nodes(self)
	set_expression("neutral")


func _process(delta: float) -> void:
	_time += delta
	if _pet_root:
		_pet_root.position.y = sin(_time * 2.0) * 0.035
		_pet_root.rotation.y = sin(_time * 0.55) * 0.16


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed:
		return
	match event.keycode:
		KEY_1:
			set_expression("neutral")
		KEY_2:
			set_expression("open_mouth")
		KEY_3:
			set_expression("happy")


func set_expression(expression: String) -> void:
	for group: String in _expression_nodes:
		for node: Node3D in _expression_nodes[group]:
			node.visible = group == expression


func _collect_expression_nodes(node: Node) -> void:
	if node is Node3D:
		var node_name := node.name.to_lower()
		if "_neutral" in node_name:
			_expression_nodes.neutral.append(node)
		elif "_open" in node_name or node_name == "tongue":
			_expression_nodes.open_mouth.append(node)
		elif "_happy" in node_name:
			_expression_nodes.happy.append(node)
	for child in node.get_children():
		_collect_expression_nodes(child)
