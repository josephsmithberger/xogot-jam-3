extends Node3D

@onready var anim_player = $"Lowpoly Stickman Rigged and Animated for Games"/AnimationPlayer

func _ready() -> void:
	anim_player.animation_finished.connect(_on_animation_finished)
	_play_idle()

func _play_idle():
	anim_player.speed_scale = 0.7
	anim_player.play("Standing_Idle")

func _on_animation_finished(anim_name: String):
	if anim_name != "Standing_Idle":
		_play_idle()

func confirm(image):
	var anims = [
		"Swing_Dancing",
		"Thriller_Part_3"
	]
	anim_player.speed_scale = 1.0
	anim_player.play(anims.pick_random())
