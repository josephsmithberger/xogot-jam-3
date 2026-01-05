extends MeshInstance3D

signal unwrapped_percent_changed(percent: float)

@onready var mask_viewport: SubViewport = $MaskViewport
@onready var mask_brush: Sprite2D = $MaskViewport/Brush
@onready var background: ColorRect = $MaskViewport/Background

var _check_timer: float = 0.0
const CHECK_INTERVAL: float = 0.2
var _is_fully_unwrapped: bool = false

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
	
	# Clear any black overlay from force_unwrap
	for child in mask_viewport.get_children():
		if child is ColorRect and child != background:
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
	
	# Front (+Z)
	_add_quad(st, Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(0.5, -0.5, 0.5), Vector3(-0.5, -0.5, 0.5), Vector3(0, 0, 1), Rect2(0, 0, 0.333, 0.5))
	# Right (+X)
	_add_quad(st, Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5), Vector3(1, 0, 0), Rect2(0.333, 0, 0.333, 0.5))
	# Back (-Z)
	_add_quad(st, Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0, 0, -1), Rect2(0.666, 0, 0.333, 0.5))
	# Left (-X)
	_add_quad(st, Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, 0.5, 0.5), Vector3(-0.5, -0.5, 0.5), Vector3(-0.5, -0.5, -0.5), Vector3(-1, 0, 0), Rect2(0, 0.5, 0.333, 0.5))
	# Top (+Y)
	_add_quad(st, Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3(0, 1, 0), Rect2(0.333, 0.5, 0.333, 0.5))
	# Bottom (-Y)
	_add_quad(st, Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5), Vector3(0.5, -0.5, -0.5), Vector3(-0.5, -0.5, -0.5), Vector3(0, -1, 0), Rect2(0.666, 0.5, 0.333, 0.5))

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
	var to = from - camera.global_transform.basis.z * 100.0
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	if result:
		if result.collider.get_parent() == self:
			var local_point = to_local(result.position)
			var local_normal = (global_transform.basis.inverse() * result.normal).normalized()
			var uv2 = _get_uv2_from_local(local_point, local_normal)
			mask_brush.position = uv2 * Vector2(1024, 1024)

func _get_uv2_from_local(pos: Vector3, normal: Vector3) -> Vector2:
	var uv_local = Vector2.ZERO
	var uv2_rect = Rect2()
	
	# Determine face based on normal
	var abs_norm = normal.abs()
	var max_axis = abs_norm.max_axis_index()
	var sign_axis = sign(normal[max_axis])
	
	if max_axis == 2: # Z
		if sign_axis > 0: # Front (+Z)
			uv_local = Vector2(pos.x + 0.5, -pos.y + 0.5)
			uv2_rect = Rect2(0, 0, 0.333, 0.5)
		else: # Back (-Z)
			uv_local = Vector2(0.5 - pos.x, 0.5 - pos.y)
			uv2_rect = Rect2(0.666, 0, 0.333, 0.5)
	elif max_axis == 0: # X
		if sign_axis > 0: # Right (+X)
			uv_local = Vector2(0.5 - pos.z, 0.5 - pos.y)
			uv2_rect = Rect2(0.333, 0, 0.333, 0.5)
		else: # Left (-X)
			uv_local = Vector2(pos.z + 0.5, 0.5 - pos.y)
			uv2_rect = Rect2(0, 0.5, 0.333, 0.5)
	elif max_axis == 1: # Y
		if sign_axis > 0: # Top (+Y)
			uv_local = Vector2(pos.x + 0.5, pos.z + 0.5)
			uv2_rect = Rect2(0.333, 0.5, 0.333, 0.5)
		else: # Bottom (-Y)
			uv_local = Vector2(pos.x + 0.5, 0.5 - pos.z)
			uv2_rect = Rect2(0.666, 0.5, 0.333, 0.5)
			
	return uv2_rect.position + (uv_local * uv2_rect.size)
