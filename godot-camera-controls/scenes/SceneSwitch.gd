"""
num1 - 1st person scene
num2 - free camera scene
num3 - 3rd person scene
"""
extends Node3D
func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("num1"):
		get_tree().change_scene_to_file("res://scenes/fps_test.tscn")
	elif Input.is_action_just_pressed("num2"):
		get_tree().change_scene_to_file("res:///scenes/tfc_test.tscn")
	elif Input.is_action_just_pressed("num3"):
		get_tree().change_scene_to_file("res:///scenes/tps_test.tscn")
