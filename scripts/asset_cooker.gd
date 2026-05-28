@tool
extends EditorScript

# Directory and Script Configurations
const SOURCE_ROOT = "res://assets/models/environment/"
const PROPS_ROOT = "res://scenes/environment/props/"
const RESOURCES_ROOT = "res://scenes/environment/resources/"
const EQUIPMENT_ROOT = "res://scenes/equipment/"
const RESOURCE_SCRIPT = "res://scripts/resource_node.gd"

func _run() -> void:
	print("\n[Asset Cooker] Starting multi-pack auto-cooking process (Props, Resources, and Equipment)...")
	
	# Find all glTF/glb files recursively under the environment root
	var files: Array[String] = []
	_find_files_recursive(SOURCE_ROOT, ["gltf", "glb"], files)
	
	if files.is_empty():
		print("[Asset Cooker] No .gltf or .glb files found under ", SOURCE_ROOT)
		return
		
	print("[Asset Cooker] Found ", files.size(), " total model files to cook.\n")
	
	# Stats tracker per pack: { pack_name: { "props": int, "resources": int, "equipment": int } }
	var stats: Dictionary = {}
	
	for file_path in files:
		# Determine pack name (top-level directory under SOURCE_ROOT)
		var rel_path = file_path.trim_prefix(SOURCE_ROOT)
		var parts = rel_path.split("/")
		var pack_name = "common"
		if parts.size() > 1:
			pack_name = parts[0]
			
		# Initialize stats for this pack if not exists
		if not stats.has(pack_name):
			stats[pack_name] = {"props": 0, "resources": 0, "equipment": 0}
			
		var base_name = file_path.get_file().get_basename()
		var is_equipment = _is_equipment(base_name)
		var is_resource = _is_resource_node(base_name)
		
		var success = _cook_asset(file_path, pack_name, is_equipment, is_resource)
		if success:
			if is_equipment:
				stats[pack_name]["equipment"] += 1
			elif is_resource:
				stats[pack_name]["resources"] += 1
			else:
				stats[pack_name]["props"] += 1
				
	# Final summary log per pack
	print("\n==========================================")
	print("[Asset Cooker] Run Complete Summary:")
	var total_props = 0
	var total_resources = 0
	var total_equipment = 0
	for p_name in stats.keys():
		var p_count = stats[p_name]["props"]
		var r_count = stats[p_name]["resources"]
		var e_count = stats[p_name]["equipment"]
		total_props += p_count
		total_resources += r_count
		total_equipment += e_count
		print("  [%s]:" % p_name)
		print("    - Props Cooked:     ", p_count)
		print("    - Resources Cooked: ", r_count)
		print("    - Equipment Cooked: ", e_count)
	print("------------------------------------------")
	print("  TOTALS:")
	print("    - Total Props Cooked:     ", total_props)
	print("    - Total Resources Cooked: ", total_resources)
	print("    - Total Equipment Cooked: ", total_equipment)
	print("    - Total Scenes Generated: ", total_props + total_resources + total_equipment)
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

# Classifies whether the asset is a weapon or equipment attachment
func _is_equipment(base_name: String) -> bool:
	var base_lower = base_name.to_lower()
	# Exclude storage, stands, and racks
	for ex in ["stand", "rack", "holder"]:
		if ex in base_lower:
			return false
	# Match equipment items
	for eq in ["sword", "axe", "pickaxe", "shield"]:
		if eq in base_lower:
			return true
	return false

# Classifies whether the asset should be a ResourceNode
func _is_resource_node(base_name: String) -> bool:
	var base_lower = base_name.to_lower()
	# Equipment has its own classification and routing
	if _is_equipment(base_name):
		return false
	# Check for resource/loot keywords
	for kw in ["tree", "ore", "rock", "vein", "potion", "coin", "chest", "bag", "pouch", "carrot", "pot", "key"]:
		if kw in base_lower:
			return true
	return false

# Dynamically maps file name keywords to Item database IDs
func _get_resource_id(base_name: String) -> String:
	var base_lower = base_name.to_lower()
	if "potion" in base_lower:
		return "health_potion"
	elif "iron" in base_lower:
		return "iron_ore"
	elif "sword" in base_lower:
		return "iron_sword"
	elif "pickaxe" in base_lower:
		return "iron_pickaxe"
	elif "chest" in base_lower or "gem" in base_lower or "coin" in base_lower:
		return "magic_gem"
	elif "leather" in base_lower or "armor" in base_lower:
		return "leather_armor"
	return "wood"

# Cooks a single 3D asset file into a ready-to-use scene
func _cook_asset(file_path: String, pack_name: String, is_equipment: bool, is_resource: bool) -> bool:
	var base_name = file_path.get_file().get_basename()
	
	# Load the 3D model scene
	var model_scene = load(file_path)
	if not model_scene:
		print("[Asset Cooker ERROR] Failed to load model scene: ", file_path)
		return false
		
	var root: Node3D
	var target_dir: String
	
	if is_equipment:
		root = Node3D.new()
		root.name = base_name
		target_dir = EQUIPMENT_ROOT.path_join(pack_name)
	elif is_resource:
		var static_root = StaticBody3D.new()
		static_root.name = base_name
		
		# Attach the resource script
		var res_script = load(RESOURCE_SCRIPT)
		if res_script:
			static_root.set_script(res_script)
			# Pre-configure script's exported variables
			static_root.set("resource_health", 3)
			static_root.set("resource_id", _get_resource_id(base_name))
		else:
			print("[Asset Cooker ERROR] Failed to load resource script: ", RESOURCE_SCRIPT)
			static_root.free()
			return false
			
		root = static_root
		target_dir = RESOURCES_ROOT.path_join(pack_name)
	else:
		var static_root = StaticBody3D.new()
		static_root.name = base_name
		static_root.collision_layer = 2  # Layer 2: world (environment static props)
		static_root.collision_mask = 0
		
		root = static_root
		target_dir = PROPS_ROOT.path_join(pack_name)
		
	# Ensure the subfolder exists
	if not DirAccess.dir_exists_absolute(target_dir):
		var err = DirAccess.make_dir_recursive_absolute(target_dir)
		if err != OK:
			print("[Asset Cooker ERROR] Failed to create directory: ", target_dir)
			root.free()
			return false
			
	# Instantiate the 3D model as "Visuals" child
	var model_instance = model_scene.instantiate()
	model_instance.name = "Visuals"
	root.add_child(model_instance)
	
	# Find all MeshInstance3D nodes in the model hierarchy
	var mesh_instances: Array[MeshInstance3D] = []
	_collect_mesh_instances(model_instance, mesh_instances)
	
	# Generate convex collision shapes for each MeshInstance3D (only if root is a physics body)
	if root is StaticBody3D:
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
			print("[Asset Cooker] Cooked: %s/%s -> %s" % [pack_name, base_name, save_path])
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
