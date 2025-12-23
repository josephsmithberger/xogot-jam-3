extends TextureRect

signal photo_taken(image: Image)

@export_enum("Auto", "Off", "SwapRedBlue") var mac_color_fix := "Auto"
@export var debug_log := false
@export var capture_dir := "user://captures"
@export var web_capture_max_size := Vector2i(960, 540)
@export_range(1, 60, 1) var web_preview_fps := 15

var _feed_id: int = -1
var _tex_y: CameraTexture
var _tex_cbcr: CameraTexture

var _web_button: Button
var _flash_overlay: ColorRect

var _web_rect_provider: Control

var last_photo_image: Image
var last_photo_texture: ImageTexture

var _web_preview_accum: float = 0.0
var _web_has_started: bool = false


func _find_web_rect_provider() -> Control:
	# In the character creator scene, this node is instanced under a SubViewport.
	# Controls inside a SubViewport can be visually present but unreliable to interact
	# with on HTML5 exports. We instead attach the web permission button to a Control
	# that lives in the main viewport (the SubViewportContainer), and we use that
	# Control's global rect to position the DOM <video> overlay.
	var p := get_parent()
	if p != null:
		var gp := p.get_parent()
		if gp is Control:
			return gp as Control
	return self


func _add_web_enable_button() -> void:
	var host := _web_rect_provider if _web_rect_provider != null else _find_web_rect_provider()
	_web_rect_provider = host

	_web_button = Button.new()
	_web_button.text = "Enable Camera"
	_web_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_web_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_web_button.anchor_left = 0.5
	_web_button.anchor_top = 0.5
	_web_button.anchor_right = 0.5
	_web_button.anchor_bottom = 0.5
	_web_button.offset_left = -90
	_web_button.offset_top = -22
	_web_button.offset_right = 90
	_web_button.offset_bottom = 22
	# Ensure it can receive mouse/touch input.
	_web_button.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child.call_deferred(_web_button)
	_web_button.pressed.connect(_on_web_enable_pressed)





func _add_flash_overlay() -> void:
	_flash_overlay = ColorRect.new()
	_flash_overlay.color = Color(1, 1, 1, 0)
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_overlay.anchor_left = 0.0
	_flash_overlay.anchor_top = 0.0
	_flash_overlay.anchor_right = 1.0
	_flash_overlay.anchor_bottom = 1.0
	_flash_overlay.offset_left = 0
	_flash_overlay.offset_top = 0
	_flash_overlay.offset_right = 0
	_flash_overlay.offset_bottom = 0
	add_child(_flash_overlay)


func _play_flash() -> void:
	$"../../../../../AudioStreamPlayer".play()
	# Native flash overlay.
	if _flash_overlay:
		_flash_overlay.color.a = 0.0
		var tween := create_tween()
		tween.tween_property(_flash_overlay, "color:a", 0.9, 0.05)
		tween.tween_property(_flash_overlay, "color:a", 0.0, 0.18)

	# Web flash affects the DOM <video> (Godot overlay would be under the video).
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.godotFlashCamera && window.godotFlashCamera();", true)


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
				// We keep the <video> element hidden and stream frames into Godot as textures.
				// This keeps all UI (like the face guide) rendered correctly on top.
				video.style.display = 'none';
				video.style.pointerEvents = 'none';
			}
			return video;
		};

		const findCanvas = () => document.querySelector('canvas');

		window.godotCameraReady = false;
		window.godotCameraError = '';

		window.godotFlashCamera = () => {};

		window.godotUpdateCameraRect = (rx, ry, rw, rh, vw, vh) => {};

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
				parent.appendChild(video);
			}

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

		window.godotCaptureCameraPngDataUrl = (maxW, maxH) => {
			const video = document.getElementById('godot-camera-video');
			if (!video || !video.videoWidth || !video.videoHeight) return '';
			const vw = video.videoWidth;
			const vh = video.videoHeight;
			let tw = vw;
			let th = vh;
			if (maxW && maxH && maxW > 0 && maxH > 0) {
				const s = Math.min(maxW / vw, maxH / vh, 1.0);
				tw = Math.max(1, Math.floor(vw * s));
				th = Math.max(1, Math.floor(vh * s));
			}
			const c = document.createElement('canvas');
			c.width = tw;
			c.height = th;
			const ctx = c.getContext('2d');
			ctx.drawImage(video, 0, 0, tw, th);
			try {
				return c.toDataURL('image/png');
			} catch (e) {
				console.error('toDataURL failed', e);
				return '';
			}
		};
	})();
	""", true)


func take_photo() -> void:
	var image := _capture_photo_image()
	if image == null:
		push_warning("Failed to capture photo.")
		return
	last_photo_image = image
	last_photo_texture = ImageTexture.create_from_image(image)
	_save_image_safely(image)
	photo_taken.emit(image)


func _on_shutter_pressed() -> void:
	_play_flash()
	take_photo()
	$"../../../../../AnimationPlayer".play("confirm")


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


func _capture_photo_image() -> Image:
	if OS.has_feature("web"):
		# Web camera is a DOM <video>; capture directly in JS.
		var max_w := int(web_capture_max_size.x)
		var max_h := int(web_capture_max_size.y)
		var data_url := str(JavaScriptBridge.eval("window.godotCaptureCameraPngDataUrl && window.godotCaptureCameraPngDataUrl(%d,%d);" % [max_w, max_h], true))
		if data_url == "" or not data_url.begins_with("data:image"):
			return null
		var comma := data_url.find(",")
		if comma == -1:
			return null
		var b64 := data_url.substr(comma + 1)
		var bytes: PackedByteArray = Marshalls.base64_to_raw(b64)
		var img := Image.new()
		var err := img.load_png_from_buffer(bytes)
		if err != OK:
			return null
		return img

	return _capture_texture_rect_from_viewport()


func _save_image_safely(image: Image) -> void:
	# Use user:// so it persists on desktop and is safe/sandboxed on web exports.
	if image == null:
		return
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var dt := Time.get_datetime_dict_from_system()
	var stamp := "%04d%02d%02d-%02d%02d%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]
	var path := "%s/capture-%s.png" % [capture_dir, stamp]
	var err := image.save_png(path)
	if err != OK:
		push_warning("Failed to save capture: %s (err=%d)" % [path, err])


func _on_web_enable_pressed() -> void:
	if _web_button:
		_web_button.disabled = true
		_web_button.text = "Requesting…"

	var rect_provider := _web_rect_provider if _web_rect_provider != null else self
	var rect := rect_provider.get_global_rect()
	var view_size := rect_provider.get_viewport_rect().size
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
		var camera_ready := bool(JavaScriptBridge.eval("window.godotCameraReady === true", true))
		if camera_ready:
			if _web_button:
				_web_button.queue_free()
				_web_button = null
			_web_has_started = true
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


func _update_web_live_texture() -> void:
	# Pull a PNG snapshot from the hidden <video> and show it in this TextureRect.
	# This keeps the face guide/UI drawn normally in Godot (on top), and allows
	# the same crop/zoom behavior as the editor (via Control sizing/clipping).
	var max_w := int(web_capture_max_size.x)
	var max_h := int(web_capture_max_size.y)
	var data_url := str(JavaScriptBridge.eval("window.godotCaptureCameraPngDataUrl && window.godotCaptureCameraPngDataUrl(%d,%d);" % [max_w, max_h], true))
	if data_url == "" or not data_url.begins_with("data:image"):
		return
	var comma := data_url.find(",")
	if comma == -1:
		return
	var b64 := data_url.substr(comma + 1)
	var bytes: PackedByteArray = Marshalls.base64_to_raw(b64)
	var img := Image.new()
	var err := img.load_png_from_buffer(bytes)
	if err != OK:
		return

	# Reuse an ImageTexture when possible to reduce allocations.
	if texture is ImageTexture:
		(texture as ImageTexture).update(img)
	else:
		texture = ImageTexture.create_from_image(img)

func _ready() -> void:
	_ensure_scaled_to_viewport()
	_add_flash_overlay()

	if OS.has_feature("web"):
		# Godot Web exports don't currently pipe getUserMedia() into CameraTexture.
		# Minimal working approach: show an HTML <video> overlay, started only by user gesture.
		_init_web_js()
		_web_rect_provider = _find_web_rect_provider()
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


func _process(_delta: float) -> void:
	if not OS.has_feature("web"):
		return
	if not _web_has_started:
		# Keep polling the JS flag (in case the button got freed early).
		_web_has_started = bool(JavaScriptBridge.eval("window.godotCameraReady === true", true))
	if not _web_has_started:
		return

	# Limit the update rate for performance.
	var fps: int = clampi(int(web_preview_fps), 1, 60)
	_web_preview_accum += _delta
	var interval: float = 1.0 / float(fps)
	if _web_preview_accum < interval:
		return
	_web_preview_accum = fmod(_web_preview_accum, interval)
	_update_web_live_texture()


func _ensure_scaled_to_viewport() -> void:
	# Ensure the camera texture scales to this Control's rect (instead of keeping native texture size).
	if expand_mode != TextureRect.EXPAND_IGNORE_SIZE:
		expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
		stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED


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
