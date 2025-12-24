extends Node3D

var anim_player: AnimationPlayer
var face_decal: Decal

func _ready() -> void:
	var stickman = $"Lowpoly Stickman Rigged and Animated for Games"
	if stickman:
		anim_player = stickman.get_node_or_null("AnimationPlayer")
		if not anim_player:
			anim_player = stickman.find_child("AnimationPlayer", true, false)
	
	if anim_player:
		anim_player.animation_finished.connect(_on_animation_finished)
		_play_idle()

	_setup_face_attachment()

func _setup_face_attachment():
	var skeleton = find_child("Skeleton3D", true, false)
	if skeleton:
		# Stickman_Joint_5 is the Head bone in this rig
		var bone_name = "Stickman_Joint_5"
		var bone_index = skeleton.find_bone(bone_name)
		
		if bone_index != -1:
			var attachment = BoneAttachment3D.new()
			attachment.bone_name = bone_name
			skeleton.add_child(attachment)
			
			face_decal = Decal.new()
			# Set decal size (width, height, depth)
			# Adjust these values to fit the face dimensions
			# x=width, z=height (due to rotation), y=projection depth
			face_decal.size = Vector3(2.8, 10.91, 2.17)
			
			# Position relative to the Head bone. 
			# Positioned slightly in front of the face
			face_decal.position = Vector3(0, 0.64, 0) 
			
			# Rotate to project backwards onto the face (Local -Y is projection axis)
			# Rotating 90 degrees around X makes local -Y point towards global -Z (backwards)
			face_decal.rotation_degrees = Vector3(90, 0, 0)
			
			attachment.add_child(face_decal)
			print("Face decal created on bone: ", bone_name)
		else:
			print("Head bone 'Stickman_Joint_5' not found.")
	else:
		print("Skeleton3D not found")


func _play_idle():
	if anim_player:
		anim_player.speed_scale = 0.7
		anim_player.play("Standing_Idle")

func _on_animation_finished(anim_name: String):
	if anim_name != "Standing_Idle":
		_play_idle()

func confirm(image: Image):
	var ui_anim = get_node_or_null("../../../../AnimationPlayer")
	if ui_anim:
		ui_anim.play("confirm")
	
	var anims = [
		"Swing_Dancing",
		"Thriller_Part_3"
	]
	if anim_player:
		anim_player.speed_scale = 1.0
		anim_player.play(anims.pick_random())
	
	if face_decal and image:
		var img_copy = image.duplicate()
		img_copy.flip_y()
		var tex = ImageTexture.create_from_image(img_copy)
		face_decal.texture_albedo = tex
