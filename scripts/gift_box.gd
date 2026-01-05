extends MeshInstance3D

signal unwrapped_percent_changed(percent: float)
signal unwrap_stroke()

@onready var mask_viewport: SubViewport = $MaskViewport
@onready var mask_brush: Sprite2D = $MaskViewport/Brush
@onready var background: ColorRect = $MaskViewport/Background

var unwrap_enabled: bool = false
var _check_timer: float = 0.0
const CHECK_INTERVAL: float = 0.05
var _is_fully_unwrapped: bool = false
var _last_brush_pos: Vector2 = Vector2(-1, -1)
var _last_face_idx: int = -1  # Track which face we were on
var _stroke_distance_accumulator: float = 0.0
const STROKE_SOUND_THRESHOLD: float = 15.0  # Emit sound every N pixels of movement

func _ready() -> void:
	_setup_gift_mesh()
	
	# Wait for material to be ready or force update
	var mat = get_active_material(0) as ShaderMaterial
	if mat:
		mat.set_shader_parameter("mask_tex", mask_viewport.get_texture())
	
	# Wait for a few frames to ensure the background is drawn, then hide it
	# so it doesn't overwrite the brush strokes.
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(background):
		background.visible = false

func reset() -> void:
	_is_fully_unwrapped = false
	_check_timer = 0.0
	_last_brush_pos = Vector2(-1, -1)
	_last_face_idx = -1
	_stroke_distance_accumulator = 0.0
	unwrap_enabled = false
	
	# Clear any black overlay from force_unwrap, line segments, and stamps
	for child in mask_viewport.get_children():
		if child is ColorRect and child != background:
			child.queue_free()
		elif child is Line2D:
			child.queue_free()
		elif child is Sprite2D and child != mask_brush:
			child.queue_free()
	
	if is_instance_valid(background):
		background.visible = true
		# Wait for draw
		await get_tree().process_frame
		await get_tree().process_frame
		background.visible = false
	
	unwrapped_percent_changed.emit(0.0)


func _process(delta: float) -> void:
	if _is_fully_unwrapped:
		return
	
	if not unwrap_enabled:
		return
		
	_handle_unwrapping()
	
	_check_timer += delta
	if _check_timer >= CHECK_INTERVAL:
		_check_timer = 0.0
		_calculate_unwrapped_percent()

func _calculate_unwrapped_percent() -> void:
	var img = mask_viewport.get_texture().get_image()
	# Downscale to make it faster
	img.resize(64, 64, Image.INTERPOLATE_NEAREST)
	
	var total_pixels = 64 * 64
	var unwrapped_pixels = 0
	
	for y in range(64):
		for x in range(64):
			var color = img.get_pixel(x, y)
			# Mask is white (1) for wrapped, black (0) for unwrapped.
			if color.r < 0.5:
				unwrapped_pixels += 1
				
	var percent = float(unwrapped_pixels) / float(total_pixels)
	
	if percent >= 0.99:
		force_unwrap()
		percent = 1.0
		
	unwrapped_percent_changed.emit(percent)

func force_unwrap() -> void:
	if _is_fully_unwrapped:
		return
		
	_is_fully_unwrapped = true
	
	var rect = ColorRect.new()
	rect.color = Color.BLACK
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask_viewport.add_child(rect)


func _setup_gift_mesh() -> void:
	# Preserve the material from the original mesh
	var material = get_active_material(0)
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# UV2 Layout: 3x2 grid
	# Row 1: Front, Right, Back
	# Row 2: Left, Top, Bottom
	
	var w = 1.0 / 3.0
	var h = 0.5
	
	# Front (+Z)
	_add_quad(st, Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(0.5, -0.5, 0.5), Vector3(-0.5, -0.5, 0.5), Vector3(0, 0, 1), Rect2(0, 0, w, h))
	# Right (+X)
	_add_quad(st, Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5), Vector3(1, 0, 0), Rect2(w, 0, w, h))
	# Back (-Z)
	_add_quad(st, Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0, 0, -1), Rect2(w*2, 0, w, h))
	# Left (-X)
	_add_quad(st, Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, 0.5, 0.5), Vector3(-0.5, -0.5, 0.5), Vector3(-0.5, -0.5, -0.5), Vector3(-1, 0, 0), Rect2(0, h, w, h))
	# Top (+Y)
	_add_quad(st, Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3(0, 1, 0), Rect2(w, h, w, h))
	# Bottom (-Y)
	_add_quad(st, Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5), Vector3(0.5, -0.5, -0.5), Vector3(-0.5, -0.5, -0.5), Vector3(0, -1, 0), Rect2(w*2, h, w, h))

	st.generate_normals()
	st.generate_tangents()
	mesh = st.commit()
	
	# Re-apply the material
	if material:
		material_override = material

func _add_quad(st: SurfaceTool, p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3, normal: Vector3, uv2_rect: Rect2) -> void:
	st.set_normal(normal)
	
	# Tri 1
	st.set_uv(Vector2(0, 0))
	st.set_uv2(uv2_rect.position)
	st.add_vertex(p1)
	
	st.set_uv(Vector2(1, 0))
	st.set_uv2(uv2_rect.position + Vector2(uv2_rect.size.x, 0))
	st.add_vertex(p2)
	
	st.set_uv(Vector2(1, 1))
	st.set_uv2(uv2_rect.position + uv2_rect.size)
	st.add_vertex(p3)
	
	# Tri 2
	st.set_uv(Vector2(0, 0))
	st.set_uv2(uv2_rect.position)
	st.add_vertex(p1)
	
	st.set_uv(Vector2(1, 1))
	st.set_uv2(uv2_rect.position + uv2_rect.size)
	st.add_vertex(p3)
	
	st.set_uv(Vector2(0, 1))
	st.set_uv2(uv2_rect.position + Vector2(0, uv2_rect.size.y))
	st.add_vertex(p4)

func _handle_unwrapping() -> void:
	var camera = get_viewport().get_camera_3d()
	if not camera: return
	
	var space_state = get_world_3d().direct_space_state
	var from = camera.global_position
	# Aim the ray toward the box center, not just straight forward
	var ray_dir = (global_position - from).normalized()
	var to = from + ray_dir * 100.0
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	if not result:
		return
		
	if result.collider.get_parent() != self:
		return
		
	var local_point = to_local(result.position)
	var local_normal = (global_transform.basis.inverse() * result.normal).normalized()
	var uv2_result = _get_uv2_from_local_with_face(local_point, local_normal)
	var uv2: Vector2 = uv2_result[0]
	var face_idx: int = uv2_result[1]
	var new_pos = uv2 * Vector2(1024, 1024)
	
	# Draw connecting lines even across face changes for smoother coverage
	if _last_brush_pos.x >= 0:
		var dist = _last_brush_pos.distance_to(new_pos)
		# For same face, draw line; for different faces, still stamp but no line
		if _last_face_idx == face_idx and dist > 2 and dist < 600:
			_draw_line_segment(_last_brush_pos, new_pos)
	
	# Track movement distance for sound
	if _last_brush_pos.x >= 0:
		var move_dist = _last_brush_pos.distance_to(new_pos)
		if move_dist < 500:  # Ignore large jumps (face changes)
			_stroke_distance_accumulator += move_dist
	
	# Emit sound signal when we've moved enough
	if _stroke_distance_accumulator >= STROKE_SOUND_THRESHOLD:
		unwrap_stroke.emit()
		_stroke_distance_accumulator = 0.0
	
	# Always stamp the brush at the current position
	_stamp_brush(new_pos)
	
	mask_brush.position = new_pos
	_last_brush_pos = new_pos
	_last_face_idx = face_idx

func _stamp_brush(pos: Vector2) -> void:
	# Create a solid black circle at the position for reliable coverage
	var stamp = ColorRect.new()
	var size = mask_brush.scale.x * 64
	stamp.size = Vector2(size, size)
	stamp.position = pos - Vector2(size/2, size/2)
	stamp.color = Color.BLACK
	mask_viewport.add_child(stamp)

func _draw_line_segment(from_pos: Vector2, to_pos: Vector2) -> void:
	var line = Line2D.new()
	line.width = mask_brush.scale.x * 64  # Match brush size
	line.default_color = Color.BLACK
	line.add_point(from_pos)
	line.add_point(to_pos)
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	mask_viewport.add_child(line)

func _get_uv2_from_local_with_face(pos: Vector3, normal: Vector3) -> Array:
	var uv_local = Vector2.ZERO
	# Use precise float constants to match Setup
	var w = 1.0 / 3.0
	var h = 0.5
	var uv2_rect = Rect2()
	var face_idx = 0
	
	# Clamp local position to valid range
	pos = pos.clamp(Vector3(-0.5, -0.5, -0.5), Vector3(0.5, 0.5, 0.5))
	
	# Determine face based on normal
	var abs_norm = normal.abs()
	var max_axis = abs_norm.max_axis_index()
	var sign_axis = sign(normal[max_axis])
	
	if max_axis == 2: # Z
		if sign_axis > 0: # Front (+Z)
			uv_local = Vector2(pos.x + 0.5, 0.5 - pos.y)
			uv2_rect = Rect2(0, 0, w, h)
			face_idx = 0
		else: # Back (-Z)
			uv_local = Vector2(0.5 - pos.x, 0.5 - pos.y)
			uv2_rect = Rect2(w*2, 0, w, h)
			face_idx = 2
	elif max_axis == 0: # X
		if sign_axis > 0: # Right (+X)
			uv_local = Vector2(0.5 - pos.z, 0.5 - pos.y)
			uv2_rect = Rect2(w, 0, w, h)
			face_idx = 1
		else: # Left (-X)
			uv_local = Vector2(pos.z + 0.5, 0.5 - pos.y)
			uv2_rect = Rect2(0, h, w, h)
			face_idx = 3
	elif max_axis == 1: # Y
		if sign_axis > 0: # Top (+Y)
			uv_local = Vector2(pos.x + 0.5, pos.z + 0.5)
			uv2_rect = Rect2(w, h, w, h)
			face_idx = 4
		else: # Bottom (-Y)
			uv_local = Vector2(pos.x + 0.5, 0.5 - pos.z)
			uv2_rect = Rect2(w*2, h, w, h)
			face_idx = 5
	
	# Clamp uv_local to [0, 1] range
	uv_local = uv_local.clamp(Vector2.ZERO, Vector2.ONE)
	
	var uv2 = uv2_rect.position + (uv_local * uv2_rect.size)
	return [uv2, face_idx]

# Keep legacy function for compatibility
func _get_uv2_from_local(pos: Vector3, normal: Vector3) -> Vector2:
	return _get_uv2_from_local_with_face(pos, normal)[0]
