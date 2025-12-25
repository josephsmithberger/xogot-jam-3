extends Control
@onready var party_member = $VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/party_member
@onready var party_container = $VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer
@onready var start_game_button = $VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/start_game
@onready var warning_label = $VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/Label

var file_dialog: FileDialog

func _ready() -> void:
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
				member.texture = ImageTexture.create_from_image(img)

func _on_add_to_party_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/character_creator.tscn")


func _on_start_game_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/versus_screen.tscn")
