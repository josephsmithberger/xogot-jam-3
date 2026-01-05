extends Node3D

@export var rotation_speed_rad := 1.6
@export var grip_follow_speed := 10.0
@export var grip_separation_weight := 2.0
@export var grip_hand_distance_weight := 1.0
@export var hand_rotation_offset := Vector3(90.0, 0.0, 0.0)

const LEFT_HAND_BONE := "Stickman_Joint_14"
const RIGHT_HAND_BONE := "Stickman_Joint_10"

@onready var gift_box: Node3D = $gift_box
@onready var left_target: Node3D = $gift_box/LeftTarget
@onready var right_target: Node3D = $gift_box/RightTarget
@onready var grip_points_root: Node3D = $gift_box/GripPoints
@onready var player: Node = $player

var _skeleton: Skeleton3D
var _left_ik: SkeletonIK3D
var _right_ik: SkeletonIK3D
var _grip_points: Array[Node3D] = []
var _left_hand_idx := -1
var _right_hand_idx := -1


func _ready() -> void:
	_skeleton = _find_first_skeleton(player)
	_left_hand_idx = _skeleton.find_bone(LEFT_HAND_BONE)
	_right_hand_idx = _skeleton.find_bone(RIGHT_HAND_BONE)

	for child in grip_points_root.get_children():
		if child is Node3D:
			_grip_points.append(child)

	_setup_hand_ik()


func _process(delta: float) -> void:
	var input_vec := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if not input_vec.is_zero_approx():
		# Left/right yaw, up/down pitch.
		gift_box.rotate_object_local(Vector3.UP, -input_vec.x * rotation_speed_rad * delta)
		gift_box.rotate_object_local(Vector3.RIGHT, -input_vec.y * rotation_speed_rad * delta)

	_update_grips(delta)
	_update_ik_magnets()


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
	var left_hand_pos := _hand_global_position(_left_hand_idx)
	var right_hand_pos := _hand_global_position(_right_hand_idx)

	var pair := _choose_grip_pair(left_hand_pos, right_hand_pos)
	var left_best: Node3D = pair[0]
	var right_best: Node3D = pair[1]

	# Place targets immediately (no smoothing on init).
	left_target.global_transform = _get_box_aligned_transform(left_best)
	right_target.global_transform = _get_box_aligned_transform(right_best)


func _update_grips(delta: float) -> void:
	var left_hand_pos := _hand_global_position(_left_hand_idx)
	var right_hand_pos := _hand_global_position(_right_hand_idx)

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


func _hand_global_position(bone_idx: int) -> Vector3:
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
