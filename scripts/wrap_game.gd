extends Node3D

@export var rotation_speed_rad := 1.6
@export var touch_sensitivity := 0.2
@export var grip_follow_speed := 10.0
@export var grip_separation_weight := 2.0
@export var grip_hand_distance_weight := 1.0
@export var hand_rotation_offset := Vector3(90.0, 0.0, 0.0)
@export var head_rotation_offset := Vector3(0.0, -90.0, 90.0)

@export_group("Juice")
@export var body_sway_amount := 15.0
@export var body_sway_speed := 5.0
@export var box_move_amount := 0.2

@export_group("Tension")
@export var start_fov := 75.0
@export var end_fov := 50.0
@export var start_sway := 15.0
@export var end_sway := 30.0
@export var max_shake := 1.0

const LEFT_HAND_BONE := "Stickman_Joint_14"
const RIGHT_HAND_BONE := "Stickman_Joint_10"
const HEAD_BONE := "Stickman_Joint_4"
const LEFT_FOOT_BONE := "Stickman_Joint_17"
const RIGHT_FOOT_BONE := "Stickman_Joint_22"

@onready var gift_box: Node3D = $gift_box
@onready var left_target: Node3D = $gift_box/LeftTarget
@onready var right_target: Node3D = $gift_box/RightTarget
@onready var grip_points_root: Node3D = $gift_box/GripPoints
@onready var player: Node = $player
@onready var timer_ui: Control = $CanvasLayer/Control
@onready var camera: Camera3D = $Camera3D

var face_decal: DecalCompatibility
var _skeleton: Skeleton3D
var _left_ik: SkeletonIK3D
var _right_ik: SkeletonIK3D
var _left_foot_ik: SkeletonIK3D
var _right_foot_ik: SkeletonIK3D
var _grip_points: Array[Node3D] = []
var _left_hand_idx := -1
var _right_hand_idx := -1
var _head_idx := -1
var _initial_player_rotation: Vector3
var _initial_box_position: Vector3
var _initial_box_rotation: Vector3
var _current_shake_intensity: float = 0.0

var _touch_input_acc := Vector2.ZERO

var _player_keys: Array = []
var _current_player_index: int = 0

# Audio pool for overlapping unwrap sounds
var _unwrap_audio_pool: Array[AudioStreamPlayer] = []
const UNWRAP_AUDIO_POOL_SIZE := 5
var _unwrap_sound_cooldown := 0.0
const UNWRAP_SOUND_MIN_INTERVAL := 0.05
var _time_since_last_stroke := 999.0
const FADE_OUT_DELAY := 0.1  # Start fading after this many seconds of no strokes
const FADE_OUT_SPEED := 25.0  # dB per second to fade


func _ready() -> void:
	_skeleton = _find_first_skeleton(player)
	_left_hand_idx = _skeleton.find_bone(LEFT_HAND_BONE)
	_right_hand_idx = _skeleton.find_bone(RIGHT_HAND_BONE)
	_head_idx = _skeleton.find_bone(HEAD_BONE)

	if player is Node3D:
		_initial_player_rotation = player.rotation
	_initial_box_position = gift_box.position
	_initial_box_rotation = gift_box.rotation

	for child in grip_points_root.get_children():
		if child is Node3D:
			_grip_points.append(child)

	_setup_hand_ik()
	_setup_foot_ik()
	_setup_face_attachment()
	_setup_unwrap_audio_pool()
	
	gift_box.unwrapped_percent_changed.connect(_on_unwrapped_percent_changed)
	gift_box.unwrap_stroke.connect(_on_unwrap_stroke)
	timer_ui.game_finished.connect(_on_game_finished)
	
	_player_keys = Global.player_data.keys()
	if _player_keys.is_empty():
		_player_keys.append("default")
		Global.player_data["default"] = {"name": "Player 1"}
		
	_start_turn()


func _input(event: InputEvent) -> void:
	if not is_processing():
		return
		
	if event is InputEventScreenDrag:
		_touch_input_acc += event.relative
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_touch_input_acc += event.relative


func _start_turn() -> void:
	if _current_player_index >= _player_keys.size():
		await timer_ui.show_finished()
		await get_tree().create_timer(1.0).timeout
		SceneLoader.goto_scene("res://scenes/winners.tscn")
		return

	var player_key = _player_keys[_current_player_index]
	var data = Global.player_data[player_key]
	
	var p_name = str(player_key)
	var p_face = null
	
	if data is Dictionary:
		if data.has("name"):
			p_name = data["name"]
		if data.has("face_texture"):
			p_face = data["face_texture"]
	elif data is Image:
		p_face = data
		
	timer_ui.name_label.text = p_name
	
	if p_face:
		set_face_texture(p_face)
		
	# Reset game state
	camera.fov = start_fov
	body_sway_amount = start_sway
	_current_shake_intensity = 0.0
	gift_box.rotation = _initial_box_rotation
	gift_box.position = _initial_box_position
	if player is Node3D:
		player.rotation = _initial_player_rotation
		
	await gift_box.reset()
	
	$AnimationPlayer.play("in")
	
	# Start UI animation halfway through camera animation for smoother transition
	await get_tree().create_timer(0.4).timeout
	
	await timer_ui.play_start_animation()
	
	if $AnimationPlayer.is_playing():
		await $AnimationPlayer.animation_finished
	
	set_process(true)
	timer_ui.start_game()
	gift_box.unwrap_enabled = true



func _process(delta: float) -> void:
	_update_head_look_at(delta)
	
	# Update audio cooldown
	if _unwrap_sound_cooldown > 0:
		_unwrap_sound_cooldown -= delta
	
	# Track time since last unwrap stroke and fade out audio
	_time_since_last_stroke += delta
	if _time_since_last_stroke > FADE_OUT_DELAY:
		_fade_out_unwrap_audio(delta)
	
	var input_vec := Vector2.ZERO
	if timer_ui.is_game_active:
		input_vec = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		
	if not input_vec.is_zero_approx():
		# Rotate around global axes so controls stay consistent
		gift_box.rotate(Vector3.UP, input_vec.x * rotation_speed_rad * delta)
		gift_box.rotate(Vector3.RIGHT, input_vec.y * rotation_speed_rad * delta)

	if not _touch_input_acc.is_zero_approx():
		# Scale based on sensitivity (approx radians per 100px)
		var rot_scale = touch_sensitivity * 0.05
		gift_box.rotate(Vector3.UP, _touch_input_acc.x * rot_scale)
		gift_box.rotate(Vector3.RIGHT, _touch_input_acc.y * rot_scale)

	var combined_input = input_vec
	if not _touch_input_acc.is_zero_approx():
		# Estimate equivalent stick input for juice (20px approx full stick)
		combined_input += (_touch_input_acc / 20.0).clamp(Vector2(-1,-1), Vector2(1,1))
		combined_input = combined_input.clamp(Vector2(-1,-1), Vector2(1,1))

	_apply_juice(combined_input, delta)
	_touch_input_acc = Vector2.ZERO
	_apply_shake(delta)
	_update_grips(delta)
	_update_ik_magnets()


func _apply_juice(input: Vector2, delta: float) -> void:
	if player is Node3D:
		var target_z := _initial_player_rotation.z - (input.x * deg_to_rad(body_sway_amount))
		var target_x := _initial_player_rotation.x + (input.y * deg_to_rad(body_sway_amount))
		player.rotation.z = lerp_angle(player.rotation.z, target_z, delta * body_sway_speed)
		player.rotation.x = lerp_angle(player.rotation.x, target_x, delta * body_sway_speed)

	var target_pos := _initial_box_position + Vector3(input.x, -input.y, 0.0) * box_move_amount
	gift_box.position = gift_box.position.lerp(target_pos, delta * body_sway_speed)


func _apply_shake(delta: float) -> void:
	if _current_shake_intensity > 0:
		var offset = Vector2(
			randf_range(-1, 1),
			randf_range(-1, 1)
		) * _current_shake_intensity * 0.05
		camera.h_offset = offset.x
		camera.v_offset = offset.y
	else:
		camera.h_offset = 0
		camera.v_offset = 0


func _setup_foot_ik() -> void:
	# Create targets at current foot positions to keep them planted
	var left_target_node := _create_foot_target(LEFT_FOOT_BONE, "LeftFootTarget")
	var right_target_node := _create_foot_target(RIGHT_FOOT_BONE, "RightFootTarget")

	_left_foot_ik = _create_ik("LeftFootIK", left_target_node, LEFT_FOOT_BONE)
	_right_foot_ik = _create_ik("RightFootIK", right_target_node, RIGHT_FOOT_BONE)
	
	_left_foot_ik.start()
	_right_foot_ik.start()


func _create_foot_target(bone_name: String, target_name: String) -> Node3D:
	var bone_idx := _skeleton.find_bone(bone_name)
	var bone_pos := _get_bone_global_position(bone_idx)
	var target := Marker3D.new()
	target.name = target_name
	add_child(target)
	target.global_position = bone_pos
	
	# Match rotation
	var bone_trans := _skeleton.global_transform * _skeleton.get_bone_global_pose(bone_idx)
	target.global_transform = bone_trans
	return target


func _update_head_look_at(delta: float) -> void:
	if _head_idx == -1: return
	
	var head_pos := _get_bone_global_position(_head_idx)
	var target_pos := gift_box.global_position
	
	var look_dir := head_pos.direction_to(target_pos)
	if look_dir.is_zero_approx(): return
	
	var up := Vector3.UP
	if abs(look_dir.dot(up)) > 0.99:
		up = Vector3.BACK
		
	var target_trans := Transform3D.IDENTITY.looking_at(look_dir, up)
	target_trans.origin = head_pos
	
	# Apply rotation offset
	var offset_rad := head_rotation_offset * (PI / 180.0)
	target_trans.basis = target_trans.basis * Basis.from_euler(offset_rad)
	
	# Convert to skeleton local space
	var skel_trans := _skeleton.global_transform
	var local_target := skel_trans.affine_inverse() * target_trans
	
	# Preserve original bone scale
	var original_pose := _skeleton.get_bone_global_pose(_head_idx)
	var original_scale := original_pose.basis.get_scale()
	local_target.basis = local_target.basis.orthonormalized().scaled(original_scale)
	
	_skeleton.set_bone_global_pose_override(_head_idx, local_target, 1.0, true)




func _setup_hand_ik() -> void:
	_left_ik = _create_ik("LeftHandIK", left_target, LEFT_HAND_BONE)
	_right_ik = _create_ik("RightHandIK", right_target, RIGHT_HAND_BONE)
	_left_ik.start()
	_right_ik.start()
	_snap_grips()


func _create_ik(ik_name: String, target: Node3D, tip_bone: String) -> SkeletonIK3D:
	var tip_idx := _skeleton.find_bone(tip_bone)
	var root_bone := _root_bone_from_tip(tip_idx)

	var ik := SkeletonIK3D.new()
	ik.name = ik_name
	ik.root_bone = root_bone
	ik.tip_bone = tip_bone
	ik.interpolation = 1.0
	_skeleton.add_child(ik)
	# target_node is relative to the IK node.
	ik.target_node = ik.get_path_to(target)
	return ik



func _root_bone_from_tip(tip_idx: int) -> String:
	var root_idx := tip_idx
	for _i in range(3):
		var parent := _skeleton.get_bone_parent(root_idx)
		if parent < 0:
			break
		root_idx = parent
	return _skeleton.get_bone_name(root_idx)



func _snap_grips() -> void:
	var left_hand_pos := _get_bone_global_position(_left_hand_idx)
	var right_hand_pos := _get_bone_global_position(_right_hand_idx)

	var pair := _choose_grip_pair(left_hand_pos, right_hand_pos)
	var left_best: Node3D = pair[0]
	var right_best: Node3D = pair[1]

	# Place targets immediately (no smoothing on init).
	left_target.global_transform = _get_box_aligned_transform(left_best)
	right_target.global_transform = _get_box_aligned_transform(right_best)


func _update_grips(delta: float) -> void:
	var left_hand_pos := _get_bone_global_position(_left_hand_idx)
	var right_hand_pos := _get_bone_global_position(_right_hand_idx)

	var pair := _choose_grip_pair(left_hand_pos, right_hand_pos)
	var left_best: Node3D = pair[0]
	var right_best: Node3D = pair[1]

	var t := 1.0 - exp(-grip_follow_speed * delta)
	left_target.global_transform = left_target.global_transform.interpolate_with(_get_box_aligned_transform(left_best), t)
	right_target.global_transform = right_target.global_transform.interpolate_with(_get_box_aligned_transform(right_best), t)


func _choose_grip_pair(left_hand_pos: Vector3, right_hand_pos: Vector3) -> Array[Node3D]:
	# "Firmest" simplified: pick two *different* grip points that are far apart (stable grip)
	# while keeping each hand reasonably close to its chosen point.
	var best_i := 0
	var best_j := 1
	var best_score := -INF

	for i in range(_grip_points.size()):
		var gi := _grip_points[i]
		var gi_pos := gi.global_position
		for j in range(_grip_points.size()):
			if i == j:
				continue
			var gj := _grip_points[j]
			var gj_pos := gj.global_position

			var separation := gi_pos.distance_to(gj_pos)
			var hand_cost := left_hand_pos.distance_to(gi_pos) + right_hand_pos.distance_to(gj_pos)
			var score := (grip_separation_weight * separation) - (grip_hand_distance_weight * hand_cost)
			if score > best_score:
				best_score = score
				best_i = i
				best_j = j

	return [_grip_points[best_i], _grip_points[best_j]]


func _get_bone_global_position(bone_idx: int) -> Vector3:
	var bone_global := _skeleton.global_transform * _skeleton.get_bone_global_pose(bone_idx)
	return bone_global.origin


func _find_first_skeleton(root: Node) -> Skeleton3D:
	if root == null:
		return null
	if root is Skeleton3D:
		return root
	for child in root.get_children():
		var found := _find_first_skeleton(child)
		if found != null:
			return found
	return null


func _get_box_aligned_transform(grip_point: Node3D) -> Transform3D:
	var local_pos := gift_box.to_local(grip_point.global_position)
	var abs_pos := local_pos.abs()
	var max_axis := abs_pos.max_axis_index()

	var normal := Vector3.ZERO
	normal[max_axis] = sign(local_pos[max_axis])

	# Construct a basis where Y is the normal (pointing out).
	# This assumes the hand's +Y axis is "out of palm" or "back of hand".
	var up_ref := Vector3.UP
	if abs(normal.dot(Vector3.UP)) > 0.9:
		up_ref = Vector3.BACK

	var tangent := normal.cross(up_ref).normalized()
	var bitangent := normal.cross(tangent).normalized()

	# Basis(x, y, z) -> Tangent, Normal, Bitangent
	var target_basis := Basis(tangent, normal, bitangent)
	
	# Apply local rotation offset to fix wrist orientation
	var offset_rad := hand_rotation_offset * (PI / 180.0)
	target_basis = target_basis * Basis.from_euler(offset_rad)
	
	var target_global_basis := gift_box.global_transform.basis * target_basis
	return Transform3D(target_global_basis, grip_point.global_position)


func _update_ik_magnets() -> void:
	if not _skeleton: return
	var skel_trans := _skeleton.global_transform
	# Place magnets to the side and slightly forward/up to guide elbows outward
	var left_pos := skel_trans.origin + (-skel_trans.basis.x * 0.5) + (skel_trans.basis.y * 0.5) + (skel_trans.basis.z * 0.5)
	var right_pos := skel_trans.origin + (skel_trans.basis.x * 0.5) + (skel_trans.basis.y * 0.5) + (skel_trans.basis.z * 0.5)

	_left_ik.magnet = left_pos
	_right_ik.magnet = right_pos


func _setup_face_attachment() -> void:
	if not _skeleton: return
	
	# Use bone index 5 as requested
	var bone_idx := 5
	if bone_idx >= _skeleton.get_bone_count():
		print("Bone 5 not found in skeleton")
		return
		
	var bone_name := _skeleton.get_bone_name(bone_idx)
	
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone_name
	_skeleton.add_child(attachment)
	
	face_decal = DecalCompatibility.new()
	face_decal.size = Vector3(235, 190, 270)
	face_decal.position = Vector3(0, 90, -20)
	face_decal.rotation_degrees = Vector3(-90, 180, 0)
	# face_decal.cull_mask = 1048575 # Not supported in DecalCompatibility directly or handled differently
	
	attachment.add_child(face_decal)
	
	# Debug: Print to confirm creation
	print("Face decal created. Parent: ", attachment.name, " Bone: ", bone_name)
	
	# Default texture
	var default_tex = load("res://assets/test.png")
	if default_tex:
		face_decal.texture = default_tex
		print("Default texture loaded")
	else:
		print("Failed to load default texture")


func _on_unwrapped_percent_changed(percent: float) -> void:
	timer_ui.update_progress(percent)
	
	# Juice: Increase FOV zoom (lower FOV), increase sway
	var target_fov = lerp(start_fov, end_fov, percent)
	camera.fov = lerp(camera.fov, target_fov, 0.1)
	
	# Increase sway amount based on progress
	body_sway_amount = lerp(start_sway, end_sway, percent)
	
	# Increase shake
	_current_shake_intensity = percent * max_shake


func _on_game_finished() -> void:
	$finish.play()
	set_process(false)
	print("Game Finished!")
	
	var player_key = _player_keys[_current_player_index]
	Global.score_data[player_key] = timer_ui.time_elapsed
	
	timer_ui.animate_out()
	
	$AnimationPlayer.play("out")
	await $AnimationPlayer.animation_finished
	
	_current_player_index += 1
	_start_turn()


func set_face_texture(image: Image) -> void:
	if face_decal and image:
		var img_copy = image.duplicate()
		# img_copy.flip_y() # Removed flip_y as per previous fix
		var tex = ImageTexture.create_from_image(img_copy)
		face_decal.texture = tex


func _setup_unwrap_audio_pool() -> void:
	# Create a pool of AudioStreamPlayers for overlapping sounds
	var unwrap_stream = $unwrap_audio.stream
	for i in range(UNWRAP_AUDIO_POOL_SIZE):
		var audio_player = AudioStreamPlayer.new()
		audio_player.stream = unwrap_stream
		audio_player.volume_db = -6.0  # Lower volume since multiple will play
		add_child(audio_player)
		_unwrap_audio_pool.append(audio_player)


func _on_unwrap_stroke() -> void:
	# Reset the time since last stroke
	_time_since_last_stroke = 0.0
	
	# Find an available audio player from the pool, or reuse one that's been playing longest
	var best_player: AudioStreamPlayer = null
	var longest_play_position: float = -1.0
	
	for audio_player in _unwrap_audio_pool:
		if not audio_player.playing:
			best_player = audio_player
			break
		elif audio_player.get_playback_position() > longest_play_position:
			longest_play_position = audio_player.get_playback_position()
			best_player = audio_player
	
	if best_player:
		# Add randomness to pitch and volume for variety
		best_player.pitch_scale = randf_range(0.85, 1.2)
		best_player.volume_db = randf_range(-10.0, -4.0)
		
		# Start at a random position in the sound for variety
		var stream_length = best_player.stream.get_length()
		best_player.play(randf_range(0.0, stream_length * 0.25))


func _fade_out_unwrap_audio(delta: float) -> void:
	# Quickly fade out all playing unwrap sounds
	for audio_player in _unwrap_audio_pool:
		if audio_player.playing:
			audio_player.volume_db -= FADE_OUT_SPEED * delta
			# Stop if faded enough
			if audio_player.volume_db < -40.0:
				audio_player.stop()
