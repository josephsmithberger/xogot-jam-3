extends Control

@onready var camera_feed = $HBoxContainer/VBoxContainer/SubViewportContainer/SubViewport/CameraFeed
@onready var character_preview = $HBoxContainer/SubViewportContainer/SubViewport/character_preview
@onready var player_input = $PanelContainer/MarginContainer/VBoxContainer/player_name

var current_image: Image

func _ready():
	camera_feed.photo_taken.connect(_on_photo_taken)

func _on_photo_taken(image: Image):
	current_image = image
	character_preview.confirm(image)


func _on_confirm_name_pressed() -> void:
	Global.player_data[player_input.text] = current_image
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")

func _on_player_name_text_changed(new_text: String) -> void:
	if $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/confirm_name.disabled:
		$PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/confirm_name.disabled = false

func _on_retake_photo_pressed() -> void:
	$HBoxContainer/SubViewportContainer/SubViewport/character_preview._play_idle()
	$AnimationPlayer.play("retake")
