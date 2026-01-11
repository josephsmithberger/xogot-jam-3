extends Control
@onready var party_member = $VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/party_member
@onready var party_container = $VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer
@onready var start_game_button = $VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/start_game
@onready var warning_label = $VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/Label
@onready var tutorial_window = $TutorialWindow
@onready var video_player = $TutorialWindow/VBoxContainer/VideoStreamPlayer

var file_dialog: FileDialog

func _ready() -> void:
	if has_node("TutorialWindow/VBoxContainer/VideoStreamPlayer"):
		video_player.stream = load("res://addons/intro.ogv")
	if OS.is_debug_build():
		_setup_debug_upload()
	update_party_display()

func _setup_debug_upload():
	# Create Debug Button
	var debug_btn = Button.new()
	debug_btn.text = "Debug: Upload Faces"
	debug_btn.position = Vector2(10, 10)
	debug_btn.pressed.connect(_on_debug_upload_pressed)
	add_child(debug_btn)
	
	# Create FileDialog
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.png, *.jpg, *.jpeg, *.webp ; Images"]
	file_dialog.files_selected.connect(_on_files_selected)
	file_dialog.use_native_dialog = true
	add_child(file_dialog)

func _on_debug_upload_pressed():
	file_dialog.popup_centered(Vector2(800, 600))

func _on_files_selected(paths: PackedStringArray):
	for path in paths:
		var image = Image.load_from_file(path)
		if image:
			var file_name = path.get_file().get_basename()
			Global.player_data[file_name] = image
	
	update_party_display()

func update_party_display():
	# Clear existing duplicates
	for child in party_container.get_children():
		if child != party_member and child is TextureRect:
			child.queue_free()
	
	party_member.hide()
	
	if Global.player_data.size() == 0:
		start_game_button.disabled = true
		warning_label.show()
	else:
		$VBoxContainer/title.hide()
		start_game_button.disabled = false
		warning_label.hide()
		
		var keys = Global.player_data.keys()
		for i in range(keys.size()):
			var member
			if i == 0:
				member = party_member
			else:
				member = party_member.duplicate()
				party_container.add_child(member)
			
			member.show()
			var key = keys[i]
			var img = Global.player_data[key]
			if img:
				var scaled_img = img.duplicate()
				var new_width = int(scaled_img.get_width() * 0.5)
				var new_height = int(scaled_img.get_height() * 0.5)
				scaled_img.resize(new_width, new_height)
				member.texture = ImageTexture.create_from_image(scaled_img)
				member.flip_v = true

func _on_add_to_party_pressed() -> void:
	SceneLoader.goto_scene("res://scenes/character_creator.tscn")


func _on_start_game_pressed() -> void:
	SceneLoader.goto_scene("res://scenes/versus_screen.tscn")


func _on_tutorial_pressed() -> void:
	tutorial_window.show()
	tutorial_window.scale = Vector2.ZERO
	var tween = create_tween()
	tween.tween_property(tutorial_window, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	video_player.play()


func _on_close_tutorial_pressed() -> void:
	var tween = create_tween()
	tween.tween_property(tutorial_window, "scale", Vector2.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(tutorial_window.hide)
	tween.tween_callback(video_player.stop)
