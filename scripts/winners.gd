extends Node3D

@onready var first_place_node = $first_place
@onready var second_place_node = $second_place
@onready var third_place_node = $third_place

@onready var time_first_label = $CanvasLayer/Control/time_first
@onready var time_second_label = $CanvasLayer/Control/time_second
@onready var time_third_label = $CanvasLayer/Control/time_third

func _ready() -> void:
	_display_winners()

func _display_winners() -> void:
	var scores = []
	for player_key in Global.score_data:
		if player_key == "scores": continue
		
		var time = Global.score_data[player_key]
		scores.append({"key": player_key, "time": time})
	
	# Sort by time (ascending)
	scores.sort_custom(func(a, b): return a.time < b.time)
	
	var podium_nodes = [first_place_node, second_place_node, third_place_node]
	var time_labels = [time_first_label, time_second_label, time_third_label]
	
	for i in range(3):
		if i < scores.size():
			var player_info = scores[i]
			var player_key = player_info.key
			var time = player_info.time
			
			# Set time text
			var minutes = int(time / 60)
			var seconds = int(time) % 60
			var milliseconds = int((time - int(time)) * 100)
			time_labels[i].text = "%d:%02d.%02d" % [minutes, seconds, milliseconds]
			# Visibility is handled by the animation player in the scene, but we ensure text is correct
			
			# Setup character
			var character = podium_nodes[i]
			
			# Face
			if Global.player_data.has(player_key):
				var data = Global.player_data[player_key]
				var face_image = null
				
				if data is Image:
					face_image = data
				elif data is Dictionary and data.has("face_texture"):
					face_image = data["face_texture"]
				
				if face_image:
					_attach_face(character, face_image)
			
			# Animation
			var anim_player = _get_anim_player(character)
			if anim_player:
				if i == 0: # First place
					var anims = ["Swing_Dancing", "Thriller_Part_3"]
					anim_player.play(anims.pick_random())
				else:
					anim_player.speed_scale = 0.7
					anim_player.play("Standing_Idle")
					
		else:
			# No player for this spot
			podium_nodes[i].queue_free()
			time_labels[i].visible = false
			# Also hide the label if the animation tries to show it? 
			# The animation "in" toggles visibility. 
			# If we queue_free the label, the animation might complain if it tries to animate it.
			# But the labels are not children of the character nodes.
			# The labels are time_first, time_second, time_third.
			# If I queue_free them, the AnimationPlayer in the scene might throw errors if it has tracks for them.
			# Better to just hide them and maybe remove them from animation?
			# Or just let them be hidden. The animation sets visible=true at the end.
			# So I should probably remove the label node if I want it to stay gone, 
			# OR update the animation to not show it.
			# But I can't easily edit the animation resource.
			# If I queue_free the label, the AnimationPlayer will just fail to find the node and print an error, but game continues.
			time_labels[i].queue_free()

func _get_anim_player(character: Node) -> AnimationPlayer:
	var anim_player = character.get_node_or_null("AnimationPlayer")
	if not anim_player:
		anim_player = character.find_child("AnimationPlayer", true, false)
	return anim_player

func _attach_face(character_node: Node3D, face_image: Image) -> void:
	var skeleton = character_node.find_child("Skeleton3D", true, false)
	if skeleton:
		var bone_name = "Stickman_Joint_5"
		var bone_index = skeleton.find_bone(bone_name)
		
		if bone_index != -1:
			var attachment = BoneAttachment3D.new()
			attachment.bone_name = bone_name
			skeleton.add_child(attachment)
			
			var face_decal = DecalCompatibility.new()
			face_decal.size = Vector3(2.46, 14.58, 2.17)
			face_decal.position = Vector3(-0.06, 0.77, -1.38)
			face_decal.rotation_degrees = Vector3(-84.28, 0, 0)
			
			var img_copy = face_image.duplicate()
			# img_copy.flip_y() # Removed flip_y
			var texture = ImageTexture.create_from_image(img_copy)
			face_decal.texture = texture
			
			attachment.add_child(face_decal)
