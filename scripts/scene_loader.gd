extends Node

var scene_path: String
var progress = []

func goto_scene(path: String):
	scene_path = path
	# Request the thread to start loading
	if OS.has_feature("web"):
		# On Web, use blocking load to avoid "Out of bounds memory access" with threaded loading
		var scene = load(path)
		_change_scene(scene)
	else:
		ResourceLoader.load_threaded_request(scene_path)
		set_process(true)

func _ready():
	# Don't process until requested
	set_process(false)

func _process(_delta):
	# Check loading status
	var status = ResourceLoader.load_threaded_get_status(scene_path, progress)
	
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			# Update progress bar if needed: progress[0] * 100
			pass
		ResourceLoader.THREAD_LOAD_LOADED:
			# Loading complete, switch scene
			_change_scene(ResourceLoader.load_threaded_get(scene_path))
		ResourceLoader.THREAD_LOAD_FAILED:
			# Handle error
			print("Error loading scene: " + scene_path)
			set_process(false)

func _change_scene(scene_resource: PackedScene):
	set_process(false)
	get_tree().change_scene_to_packed(scene_resource)
