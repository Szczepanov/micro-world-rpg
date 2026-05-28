extends StaticBody3D
class_name HarvestableNode

enum NodeType { TREE, IRON_ORE }

@export var node_type: NodeType = NodeType.TREE
@export var max_health: int = 5
@export var current_health: int = 5
@export var respawn_time: float = 8.0
@export var item_id: String = "wood"
@export var node_name: String = "Tree"

@export var is_depleted: bool = false:
	set(value):
		is_depleted = value
		_update_visuals()

var _visual_node: Node3D
var _collision_shape: CollisionShape3D

func _ready():
	# Set up collision layer (layer 2: world, layer 3: interactable)
	# Binary 110 = 6. So collision_layer = 6.
	collision_layer = 6
	collision_mask = 0 # Static node, doesn't need to detect anything
	
	# Group for easy detection
	add_to_group("harvestable")
	
	# Build visual representation programmatically
	_build_visuals()
	
	# Set up collision shape programmatically
	_setup_collision()
	
	# Set up MultiplayerSynchronizer if server
	if multiplayer.is_server():
		_setup_synchronizer()
		
	_update_visuals()

func _build_visuals():
	_visual_node = Node3D.new()
	_visual_node.name = "Visuals"
	add_child(_visual_node)
	
	if node_type == NodeType.TREE:
		# Brown trunk
		var trunk = MeshInstance3D.new()
		var trunk_mesh = CylinderMesh.new()
		trunk_mesh.top_radius = 0.25
		trunk_mesh.bottom_radius = 0.35
		trunk_mesh.height = 2.5
		trunk.mesh = trunk_mesh
		
		var trunk_mat = StandardMaterial3D.new()
		trunk_mat.albedo_color = Color(0.45, 0.29, 0.08) # brown
		trunk_mat.roughness = 0.9
		trunk.set_surface_override_material(0, trunk_mat)
		trunk.position.y = 1.25 # center of cylinder is at y=0, so shift up
		_visual_node.add_child(trunk)
		
		# Green leaves
		var leaves = MeshInstance3D.new()
		var leaves_mesh = SphereMesh.new()
		leaves_mesh.radius = 1.2
		leaves_mesh.height = 2.0
		leaves.mesh = leaves_mesh
		
		var leaves_mat = StandardMaterial3D.new()
		leaves_mat.albedo_color = Color(0.13, 0.55, 0.13) # forest green
		leaves_mat.roughness = 0.8
		leaves.set_surface_override_material(0, leaves_mat)
		leaves.position.y = 2.7
		_visual_node.add_child(leaves)
		
	elif node_type == NodeType.IRON_ORE:
		# Grey rock base
		var rock = MeshInstance3D.new()
		var rock_mesh = BoxMesh.new()
		rock_mesh.size = Vector3(1.2, 0.8, 1.2)
		rock.mesh = rock_mesh
		
		var rock_mat = StandardMaterial3D.new()
		rock_mat.albedo_color = Color(0.4, 0.4, 0.4) # grey
		rock_mat.roughness = 0.8
		rock.set_surface_override_material(0, rock_mat)
		rock.position.y = 0.4
		_visual_node.add_child(rock)
		
		# Metallic veins (iron)
		var vein_positions = [
			Vector3(0.4, 0.6, 0.4),
			Vector3(-0.4, 0.5, 0.2),
			Vector3(0.1, 0.7, -0.4),
			Vector3(-0.2, 0.6, -0.3)
		]
		for i in range(vein_positions.size()):
			var vein = MeshInstance3D.new()
			var vein_mesh = SphereMesh.new()
			vein_mesh.radius = 0.2
			vein.mesh = vein_mesh
			
			var vein_mat = StandardMaterial3D.new()
			# Make it look like a nice glowing / shiny copper-orange ore vein
			vein_mat.albedo_color = Color(0.95, 0.45, 0.1) # copper/orange iron
			vein_mat.metallic = 1.0
			vein_mat.roughness = 0.2
			vein.set_surface_override_material(0, vein_mat)
			vein.position = vein_positions[i]
			_visual_node.add_child(vein)

func _setup_collision():
	_collision_shape = CollisionShape3D.new()
	_collision_shape.name = "CollisionShape"
	var shape = CylinderShape3D.new()
	if node_type == NodeType.TREE:
		shape.radius = 0.4
		shape.height = 2.5
		_collision_shape.position.y = 1.25
	else:
		shape.radius = 0.7
		shape.height = 0.8
		_collision_shape.position.y = 0.4
	_collision_shape.shape = shape
	add_child(_collision_shape)

func _setup_synchronizer():
	var synchronizer = MultiplayerSynchronizer.new()
	synchronizer.name = "MultiplayerSynchronizer"
	
	var config = SceneReplicationConfig.new()
	
	# Sync current_health
	var hp_path = NodePath(".:current_health")
	config.add_property(hp_path)
	config.property_set_replication_mode(hp_path, 1) # 1: REPLICATION_MODE_ALWAYS / CONTINUOUS
	
	# Sync is_depleted
	var depleted_path = NodePath(".:is_depleted")
	config.add_property(depleted_path)
	config.property_set_replication_mode(depleted_path, 1) # 1: REPLICATION_MODE_ALWAYS / CONTINUOUS
	
	synchronizer.replication_config = config
	add_child(synchronizer)

func _update_visuals():
	if not _visual_node or not _collision_shape:
		return
		
	if is_depleted:
		_visual_node.hide()
		_collision_shape.disabled = true
	else:
		_visual_node.show()
		_collision_shape.disabled = false

func harvest_hit(player: Node):
	if not multiplayer.is_server():
		return
	if is_depleted:
		return
		
	current_health -= 1
	play_hit_effect_rpc.rpc()
	
	# Add item to player inventory
	var db_item = ItemDatabase.get_item(item_id)
	if db_item:
		var amount = randi_range(1, 2)
		var remaining = player.player_inventory.add_item(db_item, amount)
		var added = amount - remaining
		
		# Sync back to player owner
		var owner_id = player.get_multiplayer_authority()
		if owner_id != 1:
			player.sync_inventory_to_owner.rpc_id(owner_id, player.player_inventory.to_dict())
		else:
			var level = get_tree().current_scene
			if level and level.has_method("update_local_inventory_display"):
				level.update_local_inventory_display()
				
	if current_health <= 0:
		is_depleted = true
		# Start respawn timer
		get_tree().create_timer(respawn_time).timeout.connect(func():
			is_depleted = false
			current_health = max_health
		)

@rpc("call_local", "reliable")
func play_hit_effect_rpc():
	_play_hit_effect()

func _play_hit_effect():
	if not _visual_node:
		return
	var tween = create_tween()
	tween.tween_property(_visual_node, "scale", Vector3(1.2, 1.2, 1.2), 0.08)
	tween.tween_property(_visual_node, "scale", Vector3(1.0, 1.0, 1.0), 0.08)