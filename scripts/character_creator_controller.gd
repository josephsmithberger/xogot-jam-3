extends Control

@onready var camera_feed = $HBoxContainer/VBoxContainer/SubViewportContainer/SubViewport/CameraFeed
@onready var character_preview = $HBoxContainer/SubViewportContainer/SubViewport/character_preview

func _ready():
	camera_feed.photo_taken.connect(_on_photo_taken)

func _on_photo_taken(image: Image):
	character_preview.confirm(image)
