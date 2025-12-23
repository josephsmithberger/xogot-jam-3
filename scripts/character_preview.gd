extends Node3D

var anim_player: AnimationPlayer
var face_sprite: Sprite3D

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
			
			face_sprite = Sprite3D.new()
			# Adjust pixel size based on your texture resolution and desired world size
			face_sprite.pixel_size = 0.01
			face_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			face_sprite.no_depth_test = true # Ensure it renders on top
			
			# Position relative to the Head bone. 
			# Adjust these values based on the character's scale.
			# Assuming Z is forward, Y is up.
			face_sprite.position = Vector3(0, 0.25, 0.15) 
			face_sprite.scale = Vector3(1.5, 1.5, 1.5)
			
			attachment.add_child(face_sprite)
			print("Face attachment created on bone: ", bone_name)
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
	$"../../../../AnimationPlayer".play("confirm")
	var anims = [
		"Swing_Dancing",
		"Thriller_Part_3"
	]
	if anim_player:
		anim_player.speed_scale = 1.0
		anim_player.play(anims.pick_random())
	
	if face_sprite and image:
		image.flip_y()
		var tex = ImageTexture.create_from_image(image)
		face_sprite.texture = tex
