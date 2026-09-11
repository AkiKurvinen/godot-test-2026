extends CheckButton

const TPS_CONTROLLER_SCRIPT := preload("res://scripts/tps_controller.gd")

func _ready() -> void:
	toggled.connect(_on_toggled)
	_on_toggled(button_pressed)


func _on_toggled(enabled: bool) -> void:
	var controller := _find_tps_controller(get_tree().current_scene)
	if controller:
		controller.set("strafe", enabled)


func _find_tps_controller(node: Node) -> Node:
	if node.get_script() == TPS_CONTROLLER_SCRIPT:
		return node

	for child in node.get_children():
		var controller := _find_tps_controller(child)
		if controller:
			return controller

	return null
