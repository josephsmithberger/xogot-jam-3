extends TextureRect

signal photo_taken(image: Image)

@export var capture_dir := "user://captures"
@export var web_capture_max_size := Vector2i(960, 540)
@export_range(1, 60, 1) var web_preview_fps := 15
@export var photo_mask: Texture2D

var _feed_id: int = -1
var _tex_y: CameraTexture
var _tex_cbcr: CameraTexture

@onready var _flash_overlay: ColorRect = $FlashOverlay
var _web_button: Button

var last_photo_image: Image
var last_photo_texture: ImageTexture

var _web_preview_accum: float = 0.0
var _web_has_started: bool = false



func _find_web_rect_provider() -> Control:
	var p := get_parent()
	var gp := p.get_parent() if p != null else null
	return gp as Control if gp is Control else self


func _play_flash() -> void:
	$"../../../../../AudioStreamPlayer".play()
	_flash_overlay.color.a = 0.0
	var tween := create_tween()
	tween.tween_property(_flash_overlay, "color:a", 0.9, 0.05)
	tween.tween_property(_flash_overlay, "color:a", 0.0, 0.18)
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
				video.style.display = 'none';
				video.style.pointerEvents = 'none';
			}
			return video;
		};

		const findCanvas = () => document.querySelector('canvas');

		window.godotCameraReady = false;
		window.godotCameraError = '';

		window.godotFlashCamera = () => {};

		window.godotStartCameraAtRect = async (rx, ry, rw, rh, vw, vh) => {
			const canvas = findCanvas();
			const parent = (canvas && canvas.parentElement) ? canvas.parentElement : document.body;
			let stream;
			try {
				stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
			} catch (e) {
				window.godotCameraError = (e && e.name) ? e.name : 'getUserMedia-failed';
				return;
			}
			const video = ensureVideo();
			if (!video.parentElement) parent.appendChild(video);
			video.srcObject = stream;
			await video.play();
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
			return c.toDataURL('image/png');
		};
	})();
	""", true)


func take_photo() -> void:
	var image := _capture_photo_image()
	if image == null:
		return

	if photo_mask:
		image = _apply_photo_mask(image, photo_mask)

	last_photo_image = image
	last_photo_texture = ImageTexture.create_from_image(image)
	_save_image_safely(image)
	photo_taken.emit(image)


func _apply_photo_mask(image: Image, mask_tex: Texture2D) -> Image:
	if image == null or mask_tex == null:
		return image
	var mask_img := mask_tex.get_image()
	if mask_img == null:
		return image

	mask_img = mask_img.duplicate()
	image = image.duplicate()

	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	var w := image.get_width()
	var h := image.get_height()
	if mask_img.get_size() != Vector2i(w, h):
		mask_img.resize(w, h)

	var use_alpha := mask_img.detect_alpha() != Image.ALPHA_NONE
	if use_alpha:
		if mask_img.get_format() != Image.FORMAT_RGBA8:
			mask_img.convert(Image.FORMAT_RGBA8)
	else:
		if mask_img.get_format() != Image.FORMAT_L8:
			mask_img.convert(Image.FORMAT_L8)

	var photo_data := image.get_data()
	var mask_data := mask_img.get_data()
	var pixel_count := w * h
	for i in range(pixel_count):
		var a: int
		if use_alpha:
			a = int(mask_data[i * 4 + 3])
		else:
			a = int(mask_data[i])
		photo_data[i * 4 + 3] = a

	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, photo_data)


func _on_shutter_pressed() -> void:
	_play_flash()
	take_photo()
	$"../../../../../AnimationPlayer".play("confirm")


func _capture_texture_rect_from_viewport() -> Image:
	var viewport_tex := get_viewport().get_texture()
	if viewport_tex == null:
		return null
	var viewport_img := viewport_tex.get_image()
	if viewport_img == null:
		return null
	viewport_img.flip_y()

	var rect := get_global_rect()
	var x := int(floor(rect.position.x))
	var y := int(floor(rect.position.y))
	var w := int(ceil(rect.size.x))
	var h := int(ceil(rect.size.y))

	var img_w := viewport_img.get_width()
	var img_h := viewport_img.get_height()
	x = clamp(x, 0, img_w - 1)
	y = clamp(y, 0, img_h - 1)
	w = clamp(w, 1, img_w - x)
	h = clamp(h, 1, img_h - y)

	return viewport_img.get_region(Rect2i(x, y, w, h))


func _capture_photo_image() -> Image:
	if OS.has_feature("web"):
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
		img.load_png_from_buffer(bytes)
		return img

	return _capture_texture_rect_from_viewport()


func _save_image_safely(image: Image) -> void:
	if image == null:
		return
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var dt := Time.get_datetime_dict_from_system()
	var stamp := "%04d%02d%02d-%02d%02d%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]
	var path := "%s/capture-%s.png" % [capture_dir, stamp]
	image.save_png(path)


func _on_web_enable_pressed() -> void:
	_web_button.disabled = true
	_web_button.text = "Requesting…"

	var rect_provider := _find_web_rect_provider()
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
	for _i in range(240):
		var camera_ready := bool(JavaScriptBridge.eval("window.godotCameraReady === true", true))
		if camera_ready:
			_web_button.visible = false
			_web_has_started = true
			return
		await get_tree().process_frame
	_web_button.disabled = false
	_web_button.text = "Enable Camera"


func _update_web_live_texture() -> void:
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
	img.load_png_from_buffer(bytes)

	if texture is ImageTexture:
		(texture as ImageTexture).update(img)
	else:
		texture = ImageTexture.create_from_image(img)

func _ready() -> void:
	_ensure_scaled_to_viewport()
	_web_button = _find_web_rect_provider().get_node("EnableCameraButton") as Button

	if OS.has_feature("web"):
		_init_web_js()
		_web_button.visible = true
		_web_button.pressed.connect(_on_web_enable_pressed)
		return

	_web_button.visible = false

	OS.request_permissions()
	CameraServer.set_monitoring_feeds(true)

	for _i in range(30):
		var feeds := CameraServer.feeds()
		if feeds.size() > 0:
			var feed: CameraFeed = feeds[0]
			_feed_id = feed.get_id()
			feed.set_active(true)
			_try_set_output(feed, "separate")
			_try_set_output(feed, "copy")
			_apply_ycbcr_material()

			_tex_y = CameraTexture.new()
			_tex_y.camera_feed_id = _feed_id
			_tex_y.which_feed = CameraServer.FEED_Y_IMAGE
			_tex_y.camera_is_active = true

			_tex_cbcr = CameraTexture.new()
			_tex_cbcr.camera_feed_id = _feed_id
			_tex_cbcr.which_feed = CameraServer.FEED_CBCR_IMAGE
			_tex_cbcr.camera_is_active = true
			(material as ShaderMaterial).set_shader_parameter("cbcr_tex", _tex_cbcr)
			texture = _tex_y
			return
		await get_tree().process_frame

	push_warning("No camera feeds found (permission denied or no camera available).")


func _process(_delta: float) -> void:
	if not OS.has_feature("web"):
		return
	if not _web_has_started:
		_web_has_started = bool(JavaScriptBridge.eval("window.godotCameraReady === true", true))
	if not _web_has_started:
		return
	var fps: int = clampi(int(web_preview_fps), 1, 60)
	_web_preview_accum += _delta
	var interval: float = 1.0 / float(fps)
	if _web_preview_accum < interval:
		return
	_web_preview_accum = fmod(_web_preview_accum, interval)
	_update_web_live_texture()


func _ensure_scaled_to_viewport() -> void:
	if expand_mode != TextureRect.EXPAND_IGNORE_SIZE:
		expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
		stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED


func _apply_ycbcr_material() -> void:
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nuniform sampler2D cbcr_tex;\nvoid fragment(){\n\tfloat y = texture(TEXTURE, UV).r;\n\tvec2 cbcr = texture(cbcr_tex, UV).rg;\n\tfloat cb = cbcr.r - 0.5;\n\tfloat cr = cbcr.g - 0.5;\n\tfloat r = y + 1.402 * cr;\n\tfloat g = y - 0.344136 * cb - 0.714136 * cr;\n\tfloat b = y + 1.772 * cb;\n\tCOLOR = vec4(clamp(vec3(r, g, b), 0.0, 1.0), 1.0);\n}"
	var mat := ShaderMaterial.new()
	mat.shader = shader
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
