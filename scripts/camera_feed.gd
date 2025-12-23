extends TextureRect

signal photo_taken(image: Image)

@export_enum("Auto", "Off", "SwapRedBlue") var mac_color_fix := "Auto"
@export var debug_log := false

var _feed_id: int = -1
var _tex_y: CameraTexture
var _tex_cbcr: CameraTexture

var _web_button: Button


func _add_web_enable_button() -> void:
	_web_button = Button.new()
	_web_button.text = "Enable Camera"
	_web_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_web_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_web_button.anchor_left = 0.5
	_web_button.anchor_top = 0.5
	_web_button.anchor_right = 0.5
	_web_button.anchor_bottom = 0.5
	_web_button.offset_left = -90
	_web_button.offset_top = -22
	_web_button.offset_right = 90
	_web_button.offset_bottom = 22
	add_child(_web_button)
	_web_button.pressed.connect(_on_web_enable_pressed)


func _init_web_js() -> void:
	JavaScriptBridge.eval("""
	(() => {
		const ensureVideo = () => {
			let video = document.getElementById('godot-camera-video');
			if (!video) {
				video = document.createElement('video');
				video.id = 'godot-camera-video';
				video.playsInline = true;
				video.muted = true;
				video.autoplay = true;
				video.style.position = 'absolute';
				video.style.objectFit = 'cover';
				video.style.pointerEvents = 'none';
			}
			return video;
		};

		const findCanvas = () => document.querySelector('canvas');

		window.godotCameraReady = false;
		window.godotCameraError = '';

		window.godotStartCameraAtRect = async (rx, ry, rw, rh, vw, vh) => {
			if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
				console.error('getUserMedia not supported');
				window.godotCameraError = 'not-supported';
				return;
			}
			const canvas = findCanvas();
			if (!canvas) {
				console.error('Godot canvas not found');
				window.godotCameraError = 'no-canvas';
				return;
			}
			const parent = canvas.parentElement || document.body;
			if (parent !== document.body && getComputedStyle(parent).position === 'static') {
				parent.style.position = 'relative';
			}

			let stream;
			try {
				stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
			} catch (e) {
				console.error('getUserMedia failed', e);
				window.godotCameraError = (e && e.name) ? e.name : 'getUserMedia-failed';
				return;
			}
			const video = ensureVideo();
			if (!video.parentElement) {
				parent.appendChild(video); // DOM order puts it above the canvas without z-index.
			}

			const canvasRect = canvas.getBoundingClientRect();
			const scaleX = (vw && vw > 0) ? (canvasRect.width / vw) : 1.0;
			const scaleY = (vh && vh > 0) ? (canvasRect.height / vh) : 1.0;
			// Position the <video> to match the requested Godot Control rect.
			video.style.left = (canvasRect.left + (rx * scaleX)) + 'px';
			video.style.top = (canvasRect.top + (ry * scaleY)) + 'px';
			video.style.width = Math.max(1, rw * scaleX) + 'px';
			video.style.height = Math.max(1, rh * scaleY) + 'px';
			video.style.position = 'fixed';

			video.srcObject = stream;
			try {
				await video.play();
			} catch (e) {
				console.error('video.play failed', e);
				window.godotCameraError = (e && e.name) ? e.name : 'play-failed';
				return;
			}
			window.godotCameraStream = stream;
			window.godotCameraReady = true;
		};
	})();
	""", true)


func take_photo() -> void:
	var image := _capture_texture_rect_from_viewport()
	if image == null:
		push_warning("Failed to capture photo.")
		return
	photo_taken.emit(image)


func _on_shutter_pressed() -> void:
	take_photo()


func _capture_texture_rect_from_viewport() -> Image:
	# Capture the portion of the *viewport* covered by this TextureRect.
	# This works for both native CameraTexture rendering and the web <video> overlay
	# (as long as it visually appears on top of the canvas).
	var viewport_tex := get_viewport().get_texture()
	if viewport_tex == null:
		return null
	var viewport_img := viewport_tex.get_image()
	if viewport_img == null:
		return null
	# Viewport images come in Y-flipped.
	viewport_img.flip_y()

	var rect := get_global_rect()
	var x := int(floor(rect.position.x))
	var y := int(floor(rect.position.y))
	var w := int(ceil(rect.size.x))
	var h := int(ceil(rect.size.y))

	var img_w := viewport_img.get_width()
	var img_h := viewport_img.get_height()
	if img_w <= 0 or img_h <= 0:
		return null

	x = clamp(x, 0, img_w - 1)
	y = clamp(y, 0, img_h - 1)
	w = clamp(w, 1, img_w - x)
	h = clamp(h, 1, img_h - y)

	return viewport_img.get_region(Rect2i(x, y, w, h))


func _on_web_enable_pressed() -> void:
	if _web_button:
		_web_button.disabled = true
		_web_button.text = "Requesting…"

	var rect := get_global_rect()
	var view_size := get_viewport_rect().size
	var js := "window.godotStartCameraAtRect(%f,%f,%f,%f,%f,%f);" % [
		rect.position.x,
		rect.position.y,
		rect.size.x,
		rect.size.y,
		view_size.x,
		view_size.y,
	]
	JavaScriptBridge.eval(js, true)
	_poll_web_camera_state()


func _poll_web_camera_state() -> void:
	# Don't block forever; re-enable the button on error/timeout.
	for _i in range(240):
		var camera_ready: bool = (JavaScriptBridge.eval("window.godotCameraReady === true", true) == true)
		if camera_ready:
			if _web_button:
				_web_button.queue_free()
				_web_button = null
			return
		var camera_error: String = str(JavaScriptBridge.eval("window.godotCameraError || ''", true))
		if camera_error != "":
			if _web_button:
				_web_button.disabled = false
				_web_button.text = "Enable Camera"
			push_warning("Web camera error: %s" % camera_error)
			return
		await get_tree().process_frame
	if _web_button:
		_web_button.disabled = false
		_web_button.text = "Enable Camera"
	push_warning("Web camera timed out waiting for video.")

func _ready() -> void:
	if OS.has_feature("web"):
		# Godot Web exports don't currently pipe getUserMedia() into CameraTexture.
		# Minimal working approach: show an HTML <video> overlay, started only by user gesture.
		_init_web_js()
		_add_web_enable_button()
		return

	# Native (macOS/iOS/desktop): use CameraServer feeds.
	OS.request_permissions()
	CameraServer.set_monitoring_feeds(true)
	material = null

	# Give the OS a moment to enumerate cameras.
	for _i in range(30):
		var feeds := CameraServer.feeds()
		if feeds.size() > 0:
			var feed: CameraFeed = feeds[0]
			_feed_id = feed.get_id()
			feed.set_active(true)

			# Prefer a format that exposes Y + CbCr so we can do correct color conversion.
			# IMPORTANT: set_format expects a full parameters dictionary for a *supported* format index.
			# Passing only {"output": ...} often fails and leaves us with a single-channel/tinted texture.
			var requested_sep := _try_set_output(feed, "separate")
			var dtype := feed.get_datatype()
			var tex_rgba_id := feed.get_texture_tex_id(CameraServer.FEED_RGBA_IMAGE)
			var tex_y_id := feed.get_texture_tex_id(CameraServer.FEED_Y_IMAGE)
			var tex_cbcr_id := feed.get_texture_tex_id(CameraServer.FEED_CBCR_IMAGE)
			if debug_log:
				print("[camera_feed] feed=", feed.get_name(), " id=", _feed_id, " requested_separate=", requested_sep, " datatype=", dtype, " tex_rgba_id=", tex_rgba_id, " tex_y_id=", tex_y_id, " tex_cbcr_id=", tex_cbcr_id)
			if dtype != CameraFeed.FEED_YCBCR_SEP and dtype != CameraFeed.FEED_YCBCR:
				# Second attempt: some backends may prefer 'copy' (combined YCbCr) over 'separate'.
				var requested_copy := _try_set_output(feed, "copy")
				dtype = feed.get_datatype()
				tex_rgba_id = feed.get_texture_tex_id(CameraServer.FEED_RGBA_IMAGE)
				tex_y_id = feed.get_texture_tex_id(CameraServer.FEED_Y_IMAGE)
				tex_cbcr_id = feed.get_texture_tex_id(CameraServer.FEED_CBCR_IMAGE)
				if debug_log:
					print("[camera_feed] requested_copy=", requested_copy, " datatype=", dtype, " tex_rgba_id=", tex_rgba_id, " tex_y_id=", tex_y_id, " tex_cbcr_id=", tex_cbcr_id)

			# Some platforms/backends report FEED_RGB but still expose Y+CbCr planes.
			# If we can see both planes, prefer them (this is the only way to get correct color).
			var has_ycbcr_planes := (tex_y_id != 0 and tex_cbcr_id != 0)
			# Back-compat: older versions of this script had extra enum values that forced grayscale.
			# If a scene still has those serialized values, treat them as Auto.
			var fix_mode := mac_color_fix
			if fix_mode == "SingleChannelRedToGray" or fix_mode == "SingleChannelBlueToGray":
				fix_mode = "Auto"

			if fix_mode == "Auto":
				if has_ycbcr_planes or dtype == CameraFeed.FEED_YCBCR_SEP or dtype == CameraFeed.FEED_YCBCR:
					_apply_ycbcr_material(false)
				else:
					# Already RGB, no material needed.
					material = null
			elif fix_mode == "Off":
				material = null
			elif fix_mode == "SwapRedBlue":
				if has_ycbcr_planes or dtype == CameraFeed.FEED_YCBCR_SEP or dtype == CameraFeed.FEED_YCBCR:
					_apply_ycbcr_material(true)
				else:
					_apply_swap_rb_material()
			else:
				material = null

			# Pick the correct texture source depending on feed type.
			# When the feed is split (YCbCr separate), we show the Y plane and use a shader
			# with the CbCr plane as a uniform texture.
			if has_ycbcr_planes or dtype == CameraFeed.FEED_YCBCR_SEP:
				_tex_y = CameraTexture.new()
				_tex_y.camera_feed_id = _feed_id
				_tex_y.which_feed = CameraServer.FEED_Y_IMAGE
				_tex_y.camera_is_active = true

				_tex_cbcr = CameraTexture.new()
				_tex_cbcr.camera_feed_id = _feed_id
				_tex_cbcr.which_feed = CameraServer.FEED_CBCR_IMAGE
				_tex_cbcr.camera_is_active = true
				if material is ShaderMaterial:
					(material as ShaderMaterial).set_shader_parameter("cbcr_tex", _tex_cbcr)
				texture = _tex_y
			else:
				var camera_texture := CameraTexture.new()
				camera_texture.camera_feed_id = _feed_id
				# Default to the main image.
				camera_texture.which_feed = CameraServer.FEED_RGBA_IMAGE
				camera_texture.camera_is_active = true
				texture = camera_texture
			return
		await get_tree().process_frame

	push_warning("No camera feeds found (permission denied or no camera available).")


func _apply_swap_rb_material() -> void:
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nvoid fragment(){ vec4 c = texture(TEXTURE, UV); COLOR = vec4(c.b, c.g, c.r, c.a); }"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	material = mat


func _apply_ycbcr_material(swap_rb: bool) -> void:
	# Use the Y plane as TEXTURE and the CbCr plane as a uniform.
	# CbCr is typically stored with Cb in .r and Cr in .g, biased by 0.5.
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nuniform sampler2D cbcr_tex;\nuniform bool swap_rb = false;\nvoid fragment(){\n\tfloat y = texture(TEXTURE, UV).r;\n\tvec2 cbcr = texture(cbcr_tex, UV).rg;\n\tfloat cb = cbcr.r - 0.5;\n\tfloat cr = cbcr.g - 0.5;\n\tfloat r = y + 1.402 * cr;\n\tfloat g = y - 0.344136 * cb - 0.714136 * cr;\n\tfloat b = y + 1.772 * cb;\n\tvec3 rgb = clamp(vec3(r, g, b), 0.0, 1.0);\n\tif (swap_rb) { rgb = rgb.bgr; }\n\tCOLOR = vec4(rgb, 1.0);\n}"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("swap_rb", swap_rb)
	# cbcr_tex gets assigned once we build the textures (after feed ID exists).
	if _tex_cbcr:
		mat.set_shader_parameter("cbcr_tex", _tex_cbcr)
	material = mat


func _try_set_output(feed: CameraFeed, output: String) -> bool:
	var formats := feed.get_formats()
	if formats.size() == 0:
		return false
	for i in range(formats.size()):
		var params: Dictionary = formats[i]
		if params.is_empty():
			continue
		var merged := params.duplicate(true)
		merged["output"] = output
		var ok := feed.set_format(i, merged)
		if ok:
			return true
	return false
