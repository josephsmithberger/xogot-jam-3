extends Control

func _on_add_to_party_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/character_creator.tscn")
