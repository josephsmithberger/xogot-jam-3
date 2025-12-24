extends VBoxContainer

@onready var player_name_label = $player_name
@onready var sub_viewport = $SubViewportContainer/SubViewport

const CHARACTER_PREVIEW_SCENE = preload("res://scenes/character_preview.tscn")

func setup(p_name: String, p_photo: Image) -> void:
	player_name_label.text = p_name
	
	# Clear existing children in viewport if any
	for child in sub_viewport.get_children():
		child.queue_free()
	
	var character_instance = CHARACTER_PREVIEW_SCENE.instantiate()
	sub_viewport.add_child(character_instance)
	
	# Apply photo and animation
	if character_instance.has_method("confirm"):
		character_instance.confirm(p_photo)
		# Add a slight random rotation for style
		character_instance.rotation_degrees.y = randf_range(-20, 20)
	
	# Adjust camera for portrait view
	var cam = character_instance.find_child("Camera3D", true, false)
	if cam:
		# Reposition existing camera for a better portrait shot
		# Head is roughly at Y=1.7. We want a close up.
		cam.position = Vector3(0, 4, 6)
		cam.rotation_degrees = Vector3(-5, 0, 0) # Look slightly up/straight
	else:
		cam = Camera3D.new()
		cam.position = Vector3(0, 0, 6)
		cam.rotation_degrees = Vector3(-5, 0, 0)
		character_instance.add_child(cam)
	
	cam.current = true
