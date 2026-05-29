## test_network_authority_failsafes.gd
## Security unit tests verifying that unauthenticated RPC calls, out-of-range melee
## attacks, dead-target actions, and client-side database flushes are safely rejected.
extends GutTest

var _root: Node3D
var _player: Character
var _enemy: Enemy

const TEST_PLAYER_PEER_ID = 100

func before_each():
	# Create root node
	_root = Node3D.new()
	get_tree().root.add_child(_root)
	
	# Instantiate player scene
	var player_scene = load("res://scenes/level/player.tscn")
	_player = player_scene.instantiate()
	# Name the player node with an integer string so _enter_tree() sets authority correctly
	_player.name = str(TEST_PLAYER_PEER_ID)
	_root.add_child(_player)
	
	# Instantiate enemy scene
	var enemy_scene = load("res://scenes/level/enemy.tscn")
	_enemy = enemy_scene.instantiate()
	_root.add_child(_enemy)
	
	# Defer wait for _ready() and node tree setup
	await get_tree().process_frame

func after_each():
	# Free nodes
	if _root:
		_root.queue_free()
		await get_tree().process_frame

func test_melee_rpc_wrong_sender():
	# Setup position: player and enemy in melee range (0.5m apart)
	_player.global_position = Vector3.ZERO
	_enemy.global_position = Vector3(0.5, 0.0, 0.0)
	
	# Set player authority to 100.
	# Since local call has remote sender ID = 0, sender_id (0) != player authority (100).
	# This simulates a forged RPC call from peer 0 targeting a player owned by peer 100.
	_player.set_multiplayer_authority(TEST_PLAYER_PEER_ID)
	
	var health_comp = _enemy.get_node_or_null("HealthComponent") as HealthComponent
	assert_not_null(health_comp, "Enemy should have a HealthComponent")
	health_comp.current_health = health_comp.max_health # 50.0
	
	# Perform hit check
	_player.request_enemy_melee_hit(_enemy.get_path())
	await get_tree().process_frame
	
	# Assert enemy health remains maximum (50.0)
	assert_eq(health_comp.current_health, health_comp.max_health, "Melee should be rejected from wrong sender")

func test_melee_rpc_out_of_range():
	# Setup position: enemy out of range (10m apart, max reach is 2.5m)
	_player.global_position = Vector3.ZERO
	_enemy.global_position = Vector3(10.0, 0.0, 0.0)
	
	# Set player authority to 0.
	# Since local call has remote sender ID = 0, sender_id (0) == player authority (0).
	# This bypasses the sender ID check and tests the range guard.
	_player.set_multiplayer_authority(0)
	
	var health_comp = _enemy.get_node_or_null("HealthComponent") as HealthComponent
	health_comp.current_health = health_comp.max_health
	
	# Perform hit check
	_player.request_enemy_melee_hit(_enemy.get_path())
	await get_tree().process_frame
	
	# Assert enemy health remains maximum
	assert_eq(health_comp.current_health, health_comp.max_health, "Melee should be rejected if target is out of range")

func test_melee_rpc_dead_enemy():
	# Setup position: player and enemy in melee range (0.5m apart)
	_player.global_position = Vector3.ZERO
	_enemy.global_position = Vector3(0.5, 0.0, 0.0)
	
	# Set player authority to 0 (passes sender validation)
	_player.set_multiplayer_authority(0)
	
	var health_comp = _enemy.get_node_or_null("HealthComponent") as HealthComponent
	health_comp.current_health = health_comp.max_health
	
	# Simulate dead enemy by settings collision layer to 0 (enemy.gd:147)
	_enemy.collision_layer = 0
	
	# Perform hit check
	_player.request_enemy_melee_hit(_enemy.get_path())
	await get_tree().process_frame
	
	# Assert enemy health remains maximum
	assert_eq(health_comp.current_health, health_comp.max_health, "Melee should be rejected if enemy is already dead")

func test_melee_rpc_success_under_authority():
	# Setup position: player and enemy in melee range (0.5m apart)
	_player.global_position = Vector3.ZERO
	_enemy.global_position = Vector3(0.5, 0.0, 0.0)
	
	# Set player authority to 0 (passes sender validation)
	_player.set_multiplayer_authority(0)
	
	var health_comp = _enemy.get_node_or_null("HealthComponent") as HealthComponent
	health_comp.current_health = health_comp.max_health
	
	# Ensure living enemy has normal collision
	_enemy.collision_layer = 1
	
	# Perform hit check
	_player.request_enemy_melee_hit(_enemy.get_path())
	await get_tree().process_frame
	
	# Assert enemy health decreased (melee damage is 20.0, starting health 50.0 -> final 30.0)
	assert_eq(health_comp.current_health, 30.0, "Melee should succeed when authority and range checks pass")

func test_add_item_rpc_wrong_sender():
	# Set player authority to 100.
	# Since local call has remote sender ID = 0, sender_id (0) != player authority (100).
	_player.set_multiplayer_authority(TEST_PLAYER_PEER_ID)
	
	# Ensure starting inventory has no wood
	var inventory = _player.get_inventory()
	assert_not_null(inventory, "Player should have an inventory component")
	inventory.clear()
	assert_eq(inventory.get_item_count("wood"), 0, "Inventory should be empty initially")
	
	# Request add item
	_player.request_add_item("wood", 5)
	await get_tree().process_frame
	
	# Verify no item was added
	assert_eq(inventory.get_item_count("wood"), 0, "Items should not be added by wrong sender")

func test_db_flush_ignored_on_client():
	var db_manager = Node.new()
	db_manager.set_script(load("res://scripts/database_manager.gd"))
	db_manager.name = "DatabaseManager"
	
	# Configure client peer
	var peer = ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", 28355)
	
	# Isolate client multiplayer to _root subtree
	var client_multiplayer = SceneMultiplayer.new()
	client_multiplayer.multiplayer_peer = peer
	
	get_tree().set_multiplayer(client_multiplayer, _root.get_path())
	_root.add_child(db_manager)
	
	# Run ready
	db_manager.call("_ready")
	await get_tree().process_frame
	
	# Assert database was never marked ready
	assert_false(db_manager.get("_is_ready"), "DatabaseManager should remain disabled on clients")
	assert_null(db_manager.get("_db"), "Database should not be initialized on clients")
	
	# Clean up
	get_tree().set_multiplayer(null, _root.get_path())
	db_manager.queue_free()
