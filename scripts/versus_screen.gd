extends Control

@onready var container = $HBoxContainer
@onready var audio_player = $AudioStreamPlayer
@onready var start_game_container = $VBoxContainer

const PLAYER_PORTRAIT_SCENE = preload("res://scenes/player_portrait.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	start_game_container.visible = false
	
	# Clear placeholder content if any
	for child in container.get_children():
		child.queue_free()
	
	var players = Global.player_data.keys()
	var delay = 0.0
	
	for player_name in players:
		var photo = Global.player_data[player_name]
		_create_player_portrait(player_name, photo, delay)
		delay += 1 # Stagger animations

	# Handle layout and scrolling
	await get_tree().process_frame
	
	var viewport_width = get_viewport_rect().size.x
	var container_width = container.size.x
	
	if container_width > viewport_width:
		# Scroll logic
		var move_tween = create_tween()
		move_tween.set_parallel(true)
		
		for i in range(container.get_child_count()):
			var child = container.get_child(i)
			var child_center = child.position.x + child.size.x / 2.0
			var target_x = (viewport_width / 2.0) - child_center
			
			# Clamp to keep within bounds if possible, but prioritize centering the active player
			# If we clamp strictly, we might not center the player. 
			# Let's clamp only if we are at the very ends.
			var max_x = 50.0 # Left padding
			var min_x = viewport_width - container_width - 50.0 # Right padding
			
			target_x = clamp(target_x, min_x, max_x)
			
			# Animate to this position when the player appears
			var appear_time = i * 1.0
			move_tween.tween_property(container, "position:x", target_x, 0.8).set_delay(appear_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		# Center content
		container.position.x = (viewport_width - container_width) / 2.0

	# Schedule start button appearance
	var total_time = max(0, (players.size() - 1) * 1.0) + 1.0
	get_tree().create_timer(total_time).timeout.connect(_show_start_button)

func _show_start_button() -> void:
	start_game_container.visible = true
	# Center the container
	start_game_container.reset_size() # Ensure size is calculated based on content
	start_game_container.position = (get_viewport_rect().size - start_game_container.size) / 2.0
	
	# Animate in
	start_game_container.modulate.a = 0.0
	start_game_container.scale = Vector2(1.5, 1.5)
	start_game_container.pivot_offset = start_game_container.size / 2.0
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(start_game_container, "modulate:a", 1.0, 0.5)
	tween.tween_property(start_game_container, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _create_player_portrait(p_name: String, p_photo: Image, delay: float) -> void:
	var portrait = PLAYER_PORTRAIT_SCENE.instantiate()
	container.add_child(portrait)
	
	# Setup content
	portrait.setup(p_name, p_photo)
	
	# Layout settings
	# Use min size from the scene, don't force expand if we want to scroll
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Initial state for animation
	portrait.modulate.a = 0.0
	
	# Create Tween
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(portrait, "modulate:a", 1.0, 0.5).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# Play sound with delay
	tween.tween_callback(audio_player.play).set_delay(delay)
	
	# Let's try to animate the "SubViewportContainer" inside the portrait if we can access it.
	var internal_container = portrait.get_node("SubViewportContainer")
	if internal_container:
		internal_container.pivot_offset = Vector2(100, 250) # Approximate center of 200x500
		internal_container.scale = Vector2(2.0, 2.0)
		tween.parallel().tween_property(internal_container, "scale", Vector2.ONE, 0.4).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_button_pressed() -> void:
	SceneLoader.goto_scene("res://scenes/wrap_game.tscn")
