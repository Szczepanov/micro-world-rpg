@tool
extends EditorScript

# Directory and Script Configurations
const SOURCE_DIR = "res://assets/models/environment/fantasy_props/"
const PROPS_DIR = "res://scenes/environment/props/"
const RESOURCES_DIR = "res://scenes/environment/resources/"
const RESOURCE_SCRIPT = "res://scripts/resource_node.gd"

func _run() -> void:
	print("\n[Asset Cooker] Starting auto-cooking process...")
	
	# 1. Ensure target directories exist
	if not DirAccess.dir_exists_absolute(PROPS_DIR):
		var err = DirAccess.make_dir_recursive_absolute(PROPS_DIR)
		if err != OK:
			print("[Asset Cooker ERROR] Failed to create props directory: ", PROPS_DIR)
			return
		print("[Asset Cooker] Created directory: ", PROPS_DIR)
		
	if not DirAccess.dir_exists_absolute(RESOURCES_DIR):
		var err = DirAccess.make_dir_recursive_absolute(RESOURCES_DIR)
		if err != OK:
			print("[Asset Cooker ERROR] Failed to create resources directory: ", RESOURCES_DIR)
			return
		print("[Asset Cooker] Created directory: ", RESOURCES_DIR)
		
	# 2. Find all glTF/glb files recursively
	var files: Array[String] = []
	_find_files_recursive(SOURCE_DIR, ["gltf", "glb"], files)
	
	if files.is_empty():
		print("[Asset Cooker] No .gltf or .glb files found in ", SOURCE_DIR)
		return
		
	print("[Asset Cooker] Found ", files.size(), " model files to cook.\n")
	
	var props_cooked = 0
	var resources_cooked = 0
	
	# 3. Process each model
	for file_path in files:
		var base_name = file_path.get_file().get_basename()
		var success = _cook_asset(file_path)
		if success:
			if _is_resource_node(base_name):
				resources_cooked += 1
			else:
				props_cooked += 1
				
	# 4. Final summary log
	print("\n==========================================")
	print("[Asset Cooker] Run Complete!")
	print("  - Standard Props Cooked:   ", props_cooked)
	print("  - Resource Nodes Cooked:   ", resources_cooked)
	print("  - Total Scenes Generated: ", props_cooked + resources_cooked)
	print("==========================================\n")

# Recursively scans a directory for files matching target extensions
func _find_files_recursive(path: String, extensions: Array, file_list: Array[String]) -> void:
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir():
				if file_name != "." and file_name != "..":
					_find_files_recursive(path.path_join(file_name), extensions, file_list)
			else:
				var ext = file_name.get_extension().to_lower()
				if ext in extensions:
					file_list.append(path.path_join(file_name))
			file_name = dir.get_next()
		dir.list_dir_end()
	else:
		print("[Asset Cooker ERROR] Failed to open source directory: ", path)

# Classifies whether the asset should be a ResourceNode
func _is_resource_node(base_name: String) -> bool:
	var base_name_lower = base_name.to_lower()
	for kw in ["tree", "ore", "rock", "vein"]:
		if kw in base_name_lower:
			return true
	return false

# Cooks a single 3D asset file into a ready-to-use scene
func _cook_asset(file_path: String) -> bool:
	var base_name = file_path.get_file().get_basename()
	var is_resource = _is_resource_node(base_name)
	
	# Load the 3D model scene
	var model_scene = load(file_path)
	if not model_scene:
		print("[Asset Cooker ERROR] Failed to load model scene: ", file_path)
		return false
		
	var root: StaticBody3D
	var target_dir: String
	
	if is_resource:
		root = StaticBody3D.new()
		root.name = base_name
		
		# Attach the resource script
		var res_script = load(RESOURCE_SCRIPT)
		if res_script:
			root.set_script(res_script)
			# Pre-configure script's exported variables
			root.set("resource_health", 3)
			var resource_id = "wood"
			if "iron" in base_name.to_lower():
				resource_id = "iron_ore"
			root.set("resource_id", resource_id)
		else:
			print("[Asset Cooker ERROR] Failed to load resource script: ", RESOURCE_SCRIPT)
			root.free()
			return false
			
		target_dir = RESOURCES_DIR
	else:
		root = StaticBody3D.new()
		root.name = base_name
		root.collision_layer = 2  # Layer 2: world (environment static props)
		root.collision_mask = 0
		
		target_dir = PROPS_DIR
		
	# Instantiate the 3D model as "Visuals" child
	var model_instance = model_scene.instantiate()
	model_instance.name = "Visuals"
	root.add_child(model_instance)
	
	# Find all MeshInstance3D nodes in the model hierarchy
	var mesh_instances: Array[MeshInstance3D] = []
	_collect_mesh_instances(model_instance, mesh_instances)
	
	# Generate convex collision shapes for each MeshInstance3D
	for mi in mesh_instances:
		var mesh = mi.mesh
		if mesh:
			var shape = mesh.create_convex_shape()
			if shape:
				var collision_shape = CollisionShape3D.new()
				collision_shape.name = mi.name + "Collision"
				collision_shape.shape = shape
				
				# Position and orient collision shape relative to root using accumulated transforms
				collision_shape.transform = _get_relative_transform(mi, root)
				root.add_child(collision_shape)
			else:
				print("[Asset Cooker WARNING] Failed to create convex shape for mesh: ", mi.name, " in ", base_name)
				
	# Update ownership of all children of root (model_instance and collision shapes)
	# This ensures Godot serializes them when the PackedScene is saved
	for child in root.get_children():
		child.owner = root
		
	# Pack and save the scene
	var packed_scene = PackedScene.new()
	var result = packed_scene.pack(root)
	var success = false
	if result == OK:
		var save_path = target_dir.path_join(base_name + ".tscn")
		var err = ResourceSaver.save(packed_scene, save_path)
		if err == OK:
			print("[Asset Cooker] Cooked: ", base_name, " -> ", save_path)
			success = true
		else:
			print("[Asset Cooker ERROR] Failed to save scene: ", save_path, " Error: ", err)
	else:
		print("[Asset Cooker ERROR] Failed to pack scene: ", base_name, " Error code: ", result)
		
	# Clean up from memory immediately to avoid leaks
	root.free()
	return success

# Recursively finds all MeshInstance3D nodes in a node structure
func _collect_mesh_instances(node: Node, list: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		list.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, list)

# Recursively calculates transform of a node relative to an ancestor node
func _get_relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var t = Transform3D.IDENTITY
	var curr = node
	while curr != ancestor and curr != null:
		t = curr.transform * t
		curr = curr.get_parent()
	return t
