extends Node3D

@export_group("Decal Settings")
@export var decal_position: Vector3 = Vector3(0, 0.25, 0.15)
@export var decal_rotation: Vector3 = Vector3(90, 0, 0)
@export var decal_size: Vector3 = Vector3(0.3, 0.5, 0.3)
@export var debug_texture: Texture2D

var face_decal: Decal
var attachment: BoneAttachment3D

func _ready() -> void:
	# Load a default texture if none provided
	if not debug_texture:
		debug_texture = load("res://assets/face_guide.png")

	_setup_face_attachment()

func _process(delta: float) -> void:
	if face_decal:
		face_decal.position = decal_position
		face_decal.rotation_degrees = decal_rotation
		face_decal.size = decal_size
		if face_decal.texture_albedo != debug_texture:
			face_decal.texture_albedo = debug_texture

func _setup_face_attachment():
	var skeleton = find_child("Skeleton3D", true, false)
	if skeleton:
		var bone_name = "Stickman_Joint_5"
		var bone_index = skeleton.find_bone(bone_name)
		
		if bone_index != -1:
			attachment = BoneAttachment3D.new()
			attachment.bone_name = bone_name
			skeleton.add_child(attachment)
			
			face_decal = Decal.new()
			attachment.add_child(face_decal)
			
			# Set initial values
			face_decal.position = decal_position
			face_decal.rotation_degrees = decal_rotation
			face_decal.size = decal_size
			face_decal.texture_albedo = debug_texture
			
			# Ensure visibility
			face_decal.cull_mask = 1048575 
			
			print("Debug Decal created on bone: ", bone_name)
		else:
			print("Head bone 'Stickman_Joint_5' not found.")
	else:
		print("Skeleton3D not found")
