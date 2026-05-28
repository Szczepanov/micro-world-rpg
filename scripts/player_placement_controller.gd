extends Node
class_name PlayerPlacementController

var player: Character
var camera: Camera3D
var raycast: RayCast3D
var ghost_instance: Node3D = null

var selected_structure_id: String = "spiked_wall"
var is_active: bool = false

# Semi-transparent materials for preview
var valid_material: StandardMaterial3D
var invalid_material: StandardMaterial3D

func _ready() -> void:
	player = get_parent() as Character
	if not player:
		push_error("PlayerPlacementController: Parent is not a Character")
		set_physics_process(false)
		return
		
	# Find the camera
	camera = player.get_node_or_null("SpringArmOffset/SpringArm3D/Camera3D") as Camera3D
	if not camera:
		push_error("PlayerPlacementController: Camera3D not found")
		set_physics_process(false)
		return
		
	# Create RayCast3D dynamically for floor detection
	raycast = RayCast3D.new()
	raycast.name = "PlacementRayCast"
	raycast.target_position = Vector3(0, 0, -20.0) # 20 meters forward range
	# Detect world/floor layer (2)
	raycast.collision_mask = 2
	raycast.enabled = false # only enable when build mode is active
	camera.add_child(raycast)
	
	# Initialize materials
	_init_materials()
	
	# Listen for input actions or map them programmatically
	_setup_input_actions()

func _init_materials() -> void:
	valid_material = StandardMaterial3D.new()
	valid_material.albedo_color = Color(0.0, 1.0, 0.0, 0.4) # Green semi-transparent
	valid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	valid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	invalid_material = StandardMaterial3D.new()
	invalid_material.albedo_color = Color(1.0, 0.0, 0.0, 0.4) # Red semi-transparent
	invalid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	invalid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

func _setup_input_actions() -> void:
	if not InputMap.has_action("toggle_build_mode"):
		InputMap.add_action("toggle_build_mode")
		var key_event = InputEventKey.new()
		key_event.physical_keycode = KEY_B
		InputMap.action_add_event("toggle_build_mode", key_event)

func _unhandled_input(event: InputEvent) -> void:
	if not player.is_multiplayer_authority():
		return
		
	if event.is_action_pressed("toggle_build_mode"):
		toggle_build_mode()
		get_viewport().set_input_as_handled()
		
	if is_active and event.is_action_pressed("attack"):
		# Try to place structure when clicking in Build Mode
		_try_place_structure()
		get_viewport().set_input_as_handled()

func toggle_build_mode() -> void:
	if player.is_dead:
		return
		
	is_active = !is_active
	player.is_building = is_active
	
	raycast.enabled = is_active
	
	if is_active:
		print("PlayerPlacementController: Build Mode Activated")
		_create_ghost_preview()
	else:
		print("PlayerPlacementController: Build Mode Deactivated")
		_destroy_ghost_preview()
		
	# Clear prompt if exiting, or set initial prompt if entering
	var level = get_tree().current_scene
	if level and level.has_method("set_interaction_prompt"):
		if is_active:
			level.set_interaction_prompt("Build Mode: [LMB] Place Spiked Wall | [B] Exit")
		else:
			level.set_interaction_prompt("")

func _physics_process(_delta: float) -> void:
	if not is_active or not player.is_multiplayer_authority() or player.is_dead:
		return
		
	if raycast and raycast.is_colliding():
		var hit_point = raycast.get_collision_point()
		var grid_coords = GridManager.world_to_grid(hit_point)
		var snapped_world_pos = GridManager.grid_to_world(grid_coords)
		
		if ghost_instance:
			ghost_instance.global_position = snapped_world_pos
			ghost_instance.visible = true
			
			# Check validity
			var is_valid = _check_placement_validity(grid_coords)
			_apply_ghost_materials(ghost_instance, is_valid)
	else:
		if ghost_instance:
			ghost_instance.visible = false

func _check_placement_validity(grid_coords: Vector3i) -> bool:
	# Check distance locally
	var target_pos = GridManager.grid_to_world(grid_coords)
	var distance = player.global_position.distance_to(target_pos)
	if distance > 10.0:
		return false
		
	# Check occupation locally
	if GridManager.world_grid.has(grid_coords):
		return false
		
	# Check inventory locally
	var item_id = selected_structure_id + "_item"
	if not player.player_inventory or not player.player_inventory.has_item(item_id, 1):
		return false
		
	return true

func _try_place_structure() -> void:
	if not raycast or not raycast.is_colliding():
		return
		
	var hit_point = raycast.get_collision_point()
	var grid_coords = GridManager.world_to_grid(hit_point)
	
	if _check_placement_validity(grid_coords):
		print("PlayerPlacementController: Requesting placement at ", grid_coords)
		GridManager.request_place_structure.rpc_id(1, grid_coords, selected_structure_id)
	else:
		print("PlayerPlacementController: Placement position invalid")

func _create_ghost_preview() -> void:
	_destroy_ghost_preview()
	
	var scene_path = "res://scenes/environment/props/" + selected_structure_id + ".tscn"
	var scene = load(scene_path) as PackedScene
	if scene:
		ghost_instance = scene.instantiate()
		_disable_collisions(ghost_instance)
		get_tree().current_scene.add_child(ghost_instance)
		ghost_instance.visible = false
	else:
		push_error("PlayerPlacementController: Failed to load preview scene: " + scene_path)

func _destroy_ghost_preview() -> void:
	if ghost_instance:
		ghost_instance.queue_free()
		ghost_instance = null

func _disable_collisions(node: Node) -> void:
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	elif node is CollisionShape3D:
		node.disabled = true
		
	for child in node.get_children():
		_disable_collisions(child)

func _apply_ghost_materials(node: Node, is_valid: bool) -> void:
	var material = valid_material if is_valid else invalid_material
	_set_material_override(node, material)

func _set_material_override(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = material
	for child in node.get_children():
		_set_material_override(child, material)
