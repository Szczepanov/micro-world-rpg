extends Node

const CELL_SIZE: float = 2.0

# Master server-side dictionary: Vector3i -> Dictionary {"structure_id": String, "peer_id": int}
var world_grid: Dictionary = {}

signal structure_placed(grid_coords: Vector3i, structure_id: String)
signal structure_removed(grid_coords: Vector3i)

func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	if multiplayer.multiplayer_peer and not multiplayer.is_server() and multiplayer.get_unique_id() != 0:
		request_grid_sync.rpc_id(1)

func _on_connected_to_server() -> void:
	request_grid_sync.rpc_id(1)

func world_to_grid(world_pos: Vector3) -> Vector3i:
	return Vector3i((world_pos / CELL_SIZE).round())

func grid_to_world(grid_pos: Vector3i) -> Vector3:
	return Vector3(grid_pos) * CELL_SIZE

func get_player_node(peer_id: int) -> Node:
	var level_scene = get_tree().current_scene
	if level_scene and level_scene.has_node("PlayersContainer"):
		var players_container = level_scene.get_node("PlayersContainer")
		if players_container.has_node(str(peer_id)):
			return players_container.get_node(str(peer_id))
	return null

## Sent by the server to a specific peer when their placement request is
## rejected. The client should wire this signal to the HUD notification system.
@rpc("authority", "call_local", "reliable")
func notify_placement_failed(reason: String) -> void:
	push_warning("GridManager [client]: Placement rejected — " + reason)
	# TODO: connect this to your HUD toast system, e.g.:
	# emit_signal("placement_rejected", reason)

@rpc("any_peer", "reliable")
func request_place_structure(grid_coords: Vector3i, structure_id: String) -> void:
	if not multiplayer.is_server():
		return
	
	var peer_id := multiplayer.get_remote_sender_id()
	var player := get_player_node(peer_id)
	if not player:
		push_warning("GridManager: Player node not found for peer %d" % peer_id)
		return
		
	# a) Distance-spoofing check.
	var target_world_pos := grid_to_world(grid_coords)
	var distance: float = player.global_position.distance_to(target_world_pos)
	if distance > 10.0:
		push_warning("GridManager: Distance check failed for peer %d (%.1fm)" % [peer_id, distance])
		notify_placement_failed.rpc_id(peer_id, "Too far from target tile.")
		return
		
	# b) Atomically RESERVE the cell before any inventory transaction.
	#    Writing a sentinel first ensures a second concurrent RPC in the same
	#    server tick sees the cell as occupied and is rejected immediately.
	if world_grid.has(grid_coords):
		push_warning("GridManager: Tile %s already occupied." % str(grid_coords))
		notify_placement_failed.rpc_id(peer_id, "Tile already occupied.")
		return

	# Write the reservation sentinel so any subsequent in-tick RPC is rejected.
	world_grid[grid_coords] = {"structure_id": structure_id, "peer_id": peer_id, "_pending": true}
	
	# c) Verify required item in inventory.
	var item_id := structure_id + "_item"
	if not player.player_inventory or not player.player_inventory.has_item(item_id, 1):
		push_warning("GridManager: Peer %d lacks item '%s'." % [peer_id, item_id])
		world_grid.erase(grid_coords)   # Roll back reservation — no item consumed.
		notify_placement_failed.rpc_id(peer_id, "Insufficient resources.")
		return
		
	# Deduct item from inventory.
	player.player_inventory.remove_item(item_id, 1)
	
	# Sync inventory back to client.
	if peer_id != 1:
		player.sync_inventory_to_owner.rpc_id(peer_id, player.player_inventory.to_dict())
	else:
		var level_scene := get_tree().current_scene
		if level_scene and level_scene.has_method("update_local_inventory_display"):
			level_scene.update_local_inventory_display()
			
	# Spawn structure globally — overwrites the pending sentinel with the real record.
	spawn_grid_structure.rpc(grid_coords, structure_id, peer_id)

@rpc("call_local", "reliable")
func spawn_grid_structure(grid_coords: Vector3i, structure_id: String, peer_id: int) -> void:
	world_grid[grid_coords] = {
		"structure_id": structure_id,
		"peer_id": peer_id
	}
	_spawn_visual_node(grid_coords, structure_id)
	if multiplayer.is_server():
		structure_placed.emit(grid_coords, structure_id)

func _spawn_visual_node(grid_coords: Vector3i, structure_id: String) -> void:
	var scene_path = "res://scenes/environment/props/" + structure_id + ".tscn"
	var scene = load(scene_path) as PackedScene
	if not scene:
		push_error("GridManager: Failed to load structure scene: " + scene_path)
		return
		
	var instance = scene.instantiate()
	var target_world_pos = grid_to_world(grid_coords)
	
	# Set unique name so we don't have collisions and can find it easily
	instance.name = "structure_" + str(grid_coords.x) + "_" + str(grid_coords.y) + "_" + str(grid_coords.z)
	
	var level_scene = get_tree().current_scene
	var parent_node = level_scene
	if level_scene and level_scene.has_node("Environment"):
		parent_node = level_scene.get_node("Environment")
		
	parent_node.add_child(instance)
	instance.global_position = target_world_pos
	if "grid_coords" in instance:
		instance.grid_coords = grid_coords
	print("GridManager: Spawned structure %s at %s" % [structure_id, target_world_pos])

@rpc("any_peer", "reliable")
func request_grid_sync() -> void:
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	
	# Serialize Vector3i keys as Vector3 for safe Godot RPC transmission
	var serialized_grid: Dictionary = {}
	for key in world_grid:
		var vec3_key = Vector3(key)
		serialized_grid[vec3_key] = world_grid[key]
		
	sync_entire_grid.rpc_id(sender_id, serialized_grid)

@rpc("reliable")
func sync_entire_grid(server_grid: Dictionary) -> void:
	world_grid.clear()
	for key in server_grid:
		var grid_coords = Vector3i(key)
		world_grid[grid_coords] = server_grid[key]
		
		# Spawn visuals locally if not already spawned
		var node_name = "structure_" + str(grid_coords.x) + "_" + str(grid_coords.y) + "_" + str(grid_coords.z)
		var level_scene = get_tree().current_scene
		var parent_node = level_scene
		if level_scene and level_scene.has_node("Environment"):
			parent_node = level_scene.get_node("Environment")
			
		if parent_node and not parent_node.has_node(node_name):
			_spawn_visual_node(grid_coords, server_grid[key]["structure_id"])

@rpc("call_local", "reliable")
func destroy_grid_structure(grid_coords: Vector3i) -> void:
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
		
	if world_grid.has(grid_coords):
		world_grid.erase(grid_coords)
		
	var node_name = "structure_" + str(grid_coords.x) + "_" + str(grid_coords.y) + "_" + str(grid_coords.z)
	var level_scene = get_tree().current_scene
	var parent_node = level_scene
	if level_scene and level_scene.has_node("Environment"):
		parent_node = level_scene.get_node("Environment")
		
	if parent_node and parent_node.has_node(node_name):
		parent_node.get_node(node_name).queue_free()
		print("GridManager: Removed structure at ", grid_coords)
		
	if multiplayer.is_server():
		structure_removed.emit(grid_coords)