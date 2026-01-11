extends Control

@onready var camera_feed: Node = $HBoxContainer/VBoxContainer/SubViewportContainer/SubViewport/CameraFeed
@onready var character_preview: Node = $HBoxContainer/SubViewportContainer/SubViewport/character_preview
@onready var player_input: LineEdit = $PanelContainer/MarginContainer/VBoxContainer/player_name
@onready var confirm_button: Button = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/confirm_name

var current_image: Image
var _last_player_text: String = ""

func _ready():
	camera_feed.photo_taken.connect(_on_photo_taken)
	_last_player_text = player_input.text
	_update_confirm_button_state()

	# Mobile web + virtual keyboard can be flaky with LineEdit's text_changed.
	# These extra signals + a _process fallback make the UI reliable.
	player_input.text_submitted.connect(_on_player_name_text_committed)
	player_input.focus_exited.connect(_on_player_name_focus_exited)


func _process(_delta: float) -> void:
	var current_text: String = player_input.text
	if current_text == _last_player_text:
		return
	_last_player_text = current_text
	_update_confirm_button_state()

func _on_photo_taken(image: Image):
	current_image = image
	character_preview.confirm(image)


func _on_confirm_name_pressed() -> void:
	if player_input.text.strip_edges().is_empty():
		_update_confirm_button_state()
		return
	Global.player_data[player_input.text] = current_image
	SceneLoader.goto_scene("res://scenes/title_screen.tscn")

func _on_player_name_text_changed(_new_text: String) -> void:
	_last_player_text = player_input.text
	_update_confirm_button_state()


func _on_player_name_text_committed(_text: String) -> void:
	_last_player_text = player_input.text
	_update_confirm_button_state()


func _on_player_name_focus_exited() -> void:
	_last_player_text = player_input.text
	_update_confirm_button_state()


func _update_confirm_button_state() -> void:
	confirm_button.disabled = player_input.text.strip_edges().is_empty()

func _on_retake_photo_pressed() -> void:
	$HBoxContainer/SubViewportContainer/SubViewport/character_preview._play_idle()
	$AnimationPlayer.play("retake")
