extends Control

signal game_finished

@onready var name_label: Label = $MarginContainer/VBoxContainer/name
@onready var progress_bar: ProgressBar = $MarginContainer/VBoxContainer/ProgressBar
@onready var timer_label: Label = $MarginContainer/VBoxContainer/timer

var time_elapsed: float = 0.0
var is_game_active: bool = false
var player_name: String = "Player"

func _ready() -> void:
	if Global.player_data.has("name"):
		player_name = Global.player_data["name"]
	name_label.text = player_name
	reset()

func animate_out() -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(name_label, "modulate:a", 0.0, 0.2)
	tween.tween_property(timer_label, "modulate:a", 0.0, 0.2)
	tween.tween_property(progress_bar, "modulate:a", 0.0, 0.2)
	await tween.finished

func play_start_animation() -> void:
	# Wait a frame to ensure the label has the correct size after text update
	await get_tree().process_frame
	
	name_label.pivot_offset = name_label.size / 2
	timer_label.pivot_offset = timer_label.size / 2
	
	# Initial "Sakurai" style setup: Huge, rotated, transparent
	name_label.scale = Vector2(5.0, 5.0)
	name_label.modulate.a = 0.0
	name_label.rotation_degrees = -15.0
	
	# Ensure other elements are hidden initially
	timer_label.scale = Vector2.ZERO
	timer_label.modulate.a = 1.0
	progress_bar.modulate.a = 0.0
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Slam down Name with impact
	tween.tween_property(name_label, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(name_label, "modulate:a", 1.0, 0.1)
	tween.tween_property(name_label, "rotation_degrees", 0.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	await tween.finished
	
	# A moment to read it
	await get_tree().create_timer(0.3).timeout
	
	# Pop in Timer and Progress Bar
	var ui_tween = create_tween()
	ui_tween.set_parallel(true)
	ui_tween.tween_property(timer_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ui_tween.tween_property(progress_bar, "modulate:a", 1.0, 0.3)
	await ui_tween.finished

func show_finished() -> void:
	name_label.text = "Finished!"
	name_label.pivot_offset = name_label.size / 2
	
	# Reset for animation
	name_label.scale = Vector2(5.0, 5.0)
	name_label.rotation_degrees = -15.0
	name_label.modulate.a = 0.0
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Slam down "Finished!"
	tween.tween_property(name_label, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(name_label, "modulate:a", 1.0, 0.1)
	tween.tween_property(name_label, "rotation_degrees", 0.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	await tween.finished

func start_game() -> void:
	reset()
	is_game_active = true
	time_elapsed = 0.0

func reset():
	time_elapsed = 0.0
	progress_bar.value = 0
	_update_timer_label()

func _process(delta: float) -> void:
	if not is_game_active:
		return
		
	time_elapsed += delta
	_update_timer_label()

func _update_timer_label() -> void:
	var minutes = int(time_elapsed / 60)
	var seconds = int(time_elapsed) % 60
	var milliseconds = int((time_elapsed - int(time_elapsed)) * 100)
	timer_label.text = "%d:%02d.%02d" % [minutes, seconds, milliseconds]

func update_progress(percent: float) -> void:
	progress_bar.value = percent * 100
	
	if percent >= 0.99 and is_game_active:
		_game_over()

func _game_over() -> void:
	is_game_active = false
	
	if not Global.score_data.has("scores"):
		Global.score_data["scores"] = []
		
	var score_entry = {
		"name": player_name,
		"time": time_elapsed
	}
	Global.score_data["scores"].append(score_entry)
	
	game_finished.emit()
 
