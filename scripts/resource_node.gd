extends StaticBody3D
class_name ResourceNode

# Synchronized export variables
@export var resource_health: int = 3:
	set(val):
		var old_val = resource_health
		resource_health = val
		if val != old_val and is_inside_tree():
			if val <= 0:
				_play_destruction_tween()
			else:
				_play_squash_stretch_tween()

@export var resource_id: String = "wood"

var _tween: Tween

func _ready() -> void:
	# Configure collision: Layer 2 (world) + Layer 3 (interactable) -> Binary 110 = 6
	collision_layer = 6
	collision_mask = 0
	
	# Add to groups for detection/querying
	add_to_group("interactable")
	add_to_group("resource_nodes")
	
	# Set up multiplayer synchronizer on the server
	if multiplayer.is_server():
		_setup_synchronizer()

func _setup_synchronizer() -> void:
	var synchronizer = MultiplayerSynchronizer.new()
	synchronizer.name = "MultiplayerSynchronizer"
	
	var config = SceneReplicationConfig.new()
	
	# Sync resource_health
	var hp_path = NodePath(".:resource_health")
	config.add_property(hp_path)
	config.property_set_replication_mode(hp_path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	
	# Sync resource_id
	var id_path = NodePath(".:resource_id")
	config.add_property(id_path)
	config.property_set_replication_mode(id_path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	
	synchronizer.replication_config = config
	add_child(synchronizer)

func interact(player_id: int) -> void:
	# Forward interaction request to the server
	server_interact.rpc_id(1, player_id)

@rpc("any_peer", "call_local", "reliable")
func server_interact(player_id: int) -> void:
	if not multiplayer.is_server():
		return
		
	# Check if node is already depleted
	if resource_health <= 0:
		return
		
	# Decrement health
	resource_health -= 1
	
	# Grant rewards to the player (Milestone 1.3 Integration)
	_grant_rewards(player_id)
	
	# If health reaches 0, play smooth scale-down Tween and safely queue_free on the server
	if resource_health <= 0:
		get_tree().create_timer(0.5).timeout.connect(func():
			queue_free()
		)

func _grant_rewards(player_id: int) -> void:
	var level = get_tree().current_scene
	if not level:
		return
		
	var players_container = level.get_node_or_null("PlayersContainer")
	if not players_container:
		return
		
	var player = players_container.get_node_or_null(str(player_id))
	if player and "player_inventory" in player and player.player_inventory:
		var db_item = ItemDatabase.get_item(resource_id)
		if db_item:
			var amount = randi_range(1, 2)
			var remaining = player.player_inventory.add_item(db_item, amount)
			var added = amount - remaining
			print("Server: Added ", added, " ", resource_id, " to player ", player_id)
			
			# Synchronize updated inventory to owner
			var owner_id = player.get_multiplayer_authority()
			if owner_id != 1:
				player.sync_inventory_to_owner.rpc_id(owner_id, player.player_inventory.to_dict())
			else:
				if level.has_method("update_local_inventory_display"):
					level.update_local_inventory_display()

func _get_anim_target() -> Node3D:
	# Try to animate visual child nodes if present, otherwise fallback to self
	for child in get_children():
		if child is Node3D and (child.name.to_lower() == "visuals" or child is MeshInstance3D):
			return child
	return self

func _play_squash_stretch_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
		
	_tween = create_tween()
	var target = _get_anim_target()
	
	# Visual squash and stretch effect
	_tween.tween_property(target, "scale", Vector3(1.15, 0.85, 1.15), 0.08)
	_tween.tween_property(target, "scale", Vector3(0.9, 1.1, 0.9), 0.08)
	_tween.tween_property(target, "scale", Vector3(1.0, 1.0, 1.0), 0.08)

func _play_destruction_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
		
	_tween = create_tween()
	var target = _get_anim_target()
	
	# Smooth scale down to Vector3.ZERO
	_tween.tween_property(target, "scale", Vector3.ZERO, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
