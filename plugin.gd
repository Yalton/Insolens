@tool
extends EditorPlugin

var dock
var scan_button: Button
var progress_bar: ProgressBar
var result_tree: Tree
var project_root: String
var scan_thread: Thread
var mutex = Mutex.new()
var progress_value: float = 0
var progress_description: String = ""
var scanning: bool = false
var scan_results: Dictionary = {}

func _enter_tree():
	dock = preload("res://addons/insolens/dock.tscn").instantiate()
	scan_button = dock.get_node("VBoxContainer/ScanButton")
	progress_bar = dock.get_node("VBoxContainer/ProgressBar")
	result_tree = dock.get_node("VBoxContainer/ResultTree")
	
	scan_button.pressed.connect(_on_scan_pressed)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	project_root = ProjectSettings.get_setting("application/config/project_root_dir")
	
	# Initialize progress bar
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.value = 0
	progress_bar.visible = false

func _exit_tree():
	# Ensure thread is properly closed
	if scan_thread and scan_thread.is_started():
		scan_thread.wait_to_finish()
	remove_control_from_docks(dock)
	dock.free()

func _process(_delta):
	if scanning and mutex:
		mutex.lock()
		progress_bar.value = progress_value
		progress_bar.tooltip_text = progress_description
		mutex.unlock()

func _on_scan_pressed():
	if scanning:
		return
		
	scan_button.disabled = true
	progress_bar.visible = true
	progress_bar.value = 0
	result_tree.clear()
	
	var root = result_tree.create_item()
	root.set_text(0, "Unused Assets")
	
	scanning = true
	scan_thread = Thread.new()
	scan_thread.start(_scan_thread_function)

func _scan_thread_function():
	_update_progress(0, "Starting scan...")
	
	# Scan for unused scenes
	var unused_scenes = find_unused_scenes()
	_update_progress(50, "Scanning scripts...")
	
	# Scan for unused scripts
	var unused_scripts = find_unused_scripts()
	
	# Store results
	scan_results = {
		"scenes": unused_scenes,
		"scripts": unused_scripts
	}
	
	# Signal completion
	call_deferred("_on_scan_complete")
	return null

func _on_scan_complete():
	var root = result_tree.get_root()
	_populate_tree(root, "Scenes", scan_results.scenes)
	_populate_tree(root, "Scripts", scan_results.scripts)
	
	_update_progress(100, "Scan complete!")
	
	# Clean up thread
	scan_thread.wait_to_finish()
	scanning = false
	scan_button.disabled = false
	
	# Hide progress bar after a delay
	await get_tree().create_timer(1.0).timeout
	progress_bar.visible = false

func _update_progress(value: float, description: String = ""):
	if mutex:
		mutex.lock()
		progress_value = value
		progress_description = description
		mutex.unlock()
	else:
		progress_value = value
		progress_description = description

func find_unused_scenes() -> Array:
	var all_scenes = []
	var referenced_scenes = []
	
	# Get all scenes in project
	_scan_directory("res://", all_scenes, ".tscn")
	_update_progress(10, "Found " + str(all_scenes.size()) + " scenes...")
	
	# Scan all scenes and scripts for references
	var current_progress = 10
	var progress_per_scene = 20.0 / max(all_scenes.size(), 1)
	
	for i in range(all_scenes.size()):
		var scene_path = all_scenes[i]
		var scene = load(scene_path)
		if scene:
			_scan_scene_for_references(scene, referenced_scenes)
		current_progress += progress_per_scene
		_update_progress(current_progress, "Scanning scene " + str(i + 1) + "/" + str(all_scenes.size()))
	
	# Also scan all scripts
	var scripts = []
	_scan_directory("res://", scripts, ".gd")
	
	current_progress = 30
	var progress_per_script = 10.0 / max(scripts.size(), 1)
	
	for i in range(scripts.size()):
		_scan_script_for_references(scripts[i], referenced_scenes)
		current_progress += progress_per_script
		_update_progress(current_progress, "Scanning script " + str(i + 1) + "/" + str(scripts.size()))
	
	# Find scenes that aren't referenced
	var unused = []
	for scene in all_scenes:
		if not scene in referenced_scenes and not _is_autoload(scene):
			unused.append(scene)
	
	return unused

func find_unused_scripts() -> Array:
	var all_scripts = []
	var referenced_scripts = []
	
	# Get all scripts in project
	_scan_directory("res://", all_scripts, ".gd")
	_update_progress(60, "Found " + str(all_scripts.size()) + " scripts...")
	
	# Scan all scenes for script references
	var scenes = []
	_scan_directory("res://", scenes, ".tscn")
	
	var current_progress = 60
	var progress_per_file = 30.0 / max((scenes.size() + all_scripts.size()), 1)
	
	for i in range(scenes.size()):
		var scene_path = scenes[i]
		var scene = load(scene_path)
		if scene:
			_scan_scene_for_script_references(scene, referenced_scripts)
		current_progress += progress_per_file
		_update_progress(current_progress, "Scanning scene " + str(i + 1) + "/" + str(scenes.size()))
	
	# Scan all scripts for other script references
	for i in range(all_scripts.size()):
		_scan_script_for_script_references(all_scripts[i], referenced_scripts)
		current_progress += progress_per_file
		_update_progress(current_progress, "Scanning script " + str(i + 1) + "/" + str(all_scripts.size()))
	
	# Find scripts that aren't referenced
	var unused = []
	for script in all_scripts:
		if not script in referenced_scripts and not _is_autoload(script):
			unused.append(script)
	
	return unused

func _scan_directory(path: String, results: Array, extension: String):
	# Skip addons folder
	if path.begins_with("res://addons"):
		return
		
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if dir.current_is_dir() and not file_name.begins_with("."):
				_scan_directory(path + file_name + "/", results, extension)
			elif file_name.ends_with(extension):
				results.append(path + file_name)
			file_name = dir.get_next()

func _scan_scene_for_references(scene: PackedScene, referenced_scenes: Array):
	# Get the scene state which contains all the scene data
	var state = scene.get_state()
	
	# Check node-level references
	for i in range(state.get_node_count()):
		# Check node properties for direct scene references
		for j in range(state.get_node_property_count(i)):
			var prop_value = state.get_node_property_value(i, j)
			if prop_value is PackedScene:
				referenced_scenes.append(prop_value.resource_path)
			# Check if the property is an array or dictionary that might contain scenes
			elif prop_value is Array or prop_value is Dictionary:
				_check_container_for_scenes(prop_value, referenced_scenes)
		
		# Check for inherited scenes
		var instance = state.get_node_instance(i)
		if instance:
			var instance_path = instance.get_path()
			if instance_path and str(instance_path).ends_with(".tscn"):
				referenced_scenes.append(str(instance_path))
			
		# Check for groups that might be scene files
		var groups = state.get_node_groups(i)
		for group in groups:
			if group.ends_with(".tscn"):
				referenced_scenes.append("res://" + group)
	
	# Check scene dependencies through ResourceLoader
	var deps = ResourceLoader.get_dependencies(scene.resource_path)
	for dep in deps:
		if dep.ends_with(".tscn"):
			referenced_scenes.append(dep)

func _check_container_for_scenes(container, referenced_scenes: Array):
	if container is Array:
		for item in container:
			if item is PackedScene:
				referenced_scenes.append(item.resource_path)
			elif item is Array or item is Dictionary:
				_check_container_for_scenes(item, referenced_scenes)
	elif container is Dictionary:
		for item in container.values():
			if item is PackedScene:
				referenced_scenes.append(item.resource_path)
			elif item is Array or item is Dictionary:
				_check_container_for_scenes(item, referenced_scenes)

func _scan_script_for_references(script_path: String, referenced_scenes: Array):
	var file = FileAccess.open(script_path, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		
		# Check for preload and load calls
		var regex = RegEx.new()
		regex.compile("(preload|load)\\([\"'](.+\\.tscn)[\"']\\)")
		for result in regex.search_all(content):
			referenced_scenes.append("res://" + result.get_string(2))
		
		# Check for scene paths in strings
		regex.compile("[\"']res://.*\\.tscn[\"']")
		for result in regex.search_all(content):
			var path = result.get_string()
			path = path.trim_prefix("\"").trim_prefix("'")
			path = path.trim_suffix("\"").trim_suffix("'")
			referenced_scenes.append(path)
		
		# Check for instantiate calls
		regex.compile("instantiate\\s*\\(\\s*[\"'](.+\\.tscn)[\"']\\s*\\)")
		for result in regex.search_all(content):
			referenced_scenes.append("res://" + result.get_string(1))
			
		# Check for scene variables and constants
		regex.compile("\\s*(?:var|const)\\s+\\w+\\s*=\\s*[\"'](.+\\.tscn)[\"']")
		for result in regex.search_all(content):
			referenced_scenes.append("res://" + result.get_string(1))

func _scan_scene_for_script_references(scene: PackedScene, referenced_scripts: Array):
	var state = scene.get_state()
	for i in range(state.get_node_count()):
		# Check attached scripts
		for j in range(state.get_node_property_count(i)):
			var prop_name = state.get_node_property_name(i, j)
			var prop_value = state.get_node_property_value(i, j)
			
			# Check if this property is a script
			if prop_name == "script" and prop_value is GDScript:
				if prop_value.resource_path.ends_with(".gd"):
					referenced_scripts.append(prop_value.resource_path)
			
			# Check if the property value contains scripts (like exported vars)
			elif prop_value is Array or prop_value is Dictionary:
				_check_container_for_scripts(prop_value, referenced_scripts)

func _check_container_for_scripts(container, referenced_scripts: Array):
	if container is Array:
		for item in container:
			if item is GDScript and item.resource_path.ends_with(".gd"):
				referenced_scripts.append(item.resource_path)
			elif item is Array or item is Dictionary:
				_check_container_for_scripts(item, referenced_scripts)
	elif container is Dictionary:
		for item in container.values():
			if item is GDScript and item.resource_path.ends_with(".gd"):
				referenced_scripts.append(item.resource_path)
			elif item is Array or item is Dictionary:
				_check_container_for_scripts(item, referenced_scripts)

func _scan_script_for_script_references(script_path: String, referenced_scripts: Array):
	var file = FileAccess.open(script_path, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		var regex = RegEx.new()
		regex.compile("(preload|load)\\([\"'](.+\\.gd)[\"']\\)")
		
		for result in regex.search_all(content):
			referenced_scripts.append("res://" + result.get_string(2))

func _is_autoload(path: String) -> bool:
	var autoloads = ProjectSettings.get_property_list()
	for autoload in autoloads:
		if autoload.name.begins_with("autoload/"):
			var autoload_path = ProjectSettings.get_setting(autoload.name)
			if autoload_path == path:
				return true
	return false

func _populate_tree(parent: TreeItem, category: String, items: Array):
	if items.size() > 0:
		var category_item = result_tree.create_item(parent)
		category_item.set_text(0, category + " (" + str(items.size()) + ")")
		
		for item in items:
			var tree_item = result_tree.create_item(category_item)
			tree_item.set_text(0, item.replace("res://", ""))
