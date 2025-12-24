extends Control
@onready var party_member = $VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/party_member
@onready var party_container = $VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer

func _ready() -> void:
	if Global.player_data.size() == 0:
		$VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/start_game.disabled = true
		$VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/Label.show()
	# Show and populate party members based on player data
	for i in Global.player_data.size():
		var member: TextureRect
		if i == 0:
			# Use the existing party_member node for the first member
			member = party_member
		else:
			# Duplicate for additional members
			member = party_member.duplicate()
			party_container.add_child(member)
		member.show()

func _on_add_to_party_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/character_creator.tscn")


func _on_start_game_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/versus_screen.tscn")
