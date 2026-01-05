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

func start_game() -> void:
	is_game_active = true
	time_elapsed = 0.0
	reset()

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
 
