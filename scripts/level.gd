extends Node3D

@onready var players_container: Node3D = $PlayersContainer
@onready var main_menu: MainMenuUI = $MainMenuUI
@export var player_scene: PackedScene

@onready var multiplayer_chat: MultiplayerChatUI = $MultiplayerChatUI
@onready var inventory_ui: InventoryUI = $InventoryUI
@onready var crafting_ui: CraftingUI = $CraftingUI

var chat_visible = false
var inventory_visible = false
var crafting_visible = false

var interaction_prompt: Label
var connection_status_label: Label

var _phase_banner_panel: Panel
var _phase_banner_label: Label
var _phase_timer_label: Label
var _time_manager: Node

func _ready():
	get_tree().paused = false

	if DisplayServer.get_name() == "headless":
		print("Dedicated server starting...")
		get_tree().auto_accept_quit = false # CRITICAL: Prevents immediate termination on SIGTERM
		Network.start_host("", "")
		# Record match start epoch for duration calculation on match end.
		if has_node("/root/DatabaseManager"):
			get_node("/root/DatabaseManager").set("_match_start_time_unix",
				int(Time.get_unix_time_from_system()))

	# Instantiate TimeManager for server-authoritative day/night cycle
	var time_manager_script: GDScript = load("res://scripts/time_manager.gd") as GDScript
	if time_manager_script:
		var time_manager: Node = time_manager_script.new()
		time_manager.name = "TimeManager"
		add_child(time_manager)
		print("LevelManager: TimeManager successfully attached to active scene graph.")

	multiplayer_chat.hide()
	main_menu.show_menu()
	# While the main menu is visible the cursor must be free
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if Network.pending_error_message != "":
		main_menu.show_error(Network.pending_error_message)
		Network.pending_error_message = ""

	multiplayer_chat.set_process_input(true)

	main_menu.host_pressed.connect(_on_host_pressed)
	main_menu.join_pressed.connect(_on_join_pressed)
	main_menu.quit_pressed.connect(_on_quit_pressed)

	if inventory_ui:
		inventory_ui.inventory_closed.connect(_on_inventory_closed)

	if crafting_ui:
		crafting_ui.crafting_closed.connect(_on_crafting_closed)

	if multiplayer_chat:
		multiplayer_chat.message_sent.connect(_on_chat_message_sent)

	# Always connect player_connected and peer_disconnected so clients spawn/cleanup peers correctly
	Network.connect("player_connected", Callable(self, "_on_player_connected"))
	Network.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_remove_player)

	# Connect DatabaseManager session_loaded signal for server-side inventory restoration
	if has_node("/root/DatabaseManager"):
		get_node("/root/DatabaseManager").session_loaded.connect(_on_player_session_loaded)

	# Setup the screen interaction UI prompt
	_setup_interaction_ui()
	_setup_connection_status_ui()
	_setup_phase_banner_ui()
	Network.connection_status_changed.connect(_on_connection_status_changed)

	# Connect to TimeManager for day/night cycle HUD updates
	_time_manager = get_node_or_null("TimeManager")
	if _time_manager:
		_time_manager.phase_changed.connect(_on_phase_changed)
		_time_manager.phase_time_updated.connect(_on_phase_time_updated)

	# Spawn resource nodes in the world
	spawn_resources()

	# Setup enemy spawner for multiplayer replication
	_setup_enemy_spawner()

func _on_player_connected(peer_id, player_info):
	_add_player(peer_id, player_info)
	if peer_id == multiplayer.get_unique_id():
		if multiplayer_chat:
			multiplayer_chat.show()

func _on_player_session_loaded(peer_id: int, player_id: String, inv_dict: Dictionary) -> void:
	# Called when DatabaseManager finishes loading a player's session from the DB.
	# Locate the player node in PlayersContainer and restore their inventory.
	var player_node = players_container.get_node_or_null(str(peer_id))
	
	# If player node doesn't exist yet, wait for it to be added to the container
	if not player_node:
		print("Level: Player node %d not yet in PlayersContainer, waiting for child_entered_tree signal..." % peer_id)
		await players_container.child_entered_tree
		player_node = players_container.get_node_or_null(str(peer_id))
		
		# Double-check after the await in case a different child was added
		if not player_node:
			push_error("Level: Player node %d still not found after child_entered_tree signal." % peer_id)
			return
	
	if not player_node.has_method("get_inventory"):
		push_warning("Level: Player node %d has no get_inventory() method." % peer_id)
		return

	# Wait for the player node to be ready if it's still initializing
	if not player_node.is_node_ready():
		await player_node.ready

	var inventory = player_node.get_inventory()
	if not inventory:
		push_warning("Level: Player %d has no inventory instance." % peer_id)
		return

	# Restore inventory from the loaded dictionary
	inventory.from_dict(inv_dict)
	print("Level: Restored inventory for player %d (%s) from database." % [peer_id, player_id])

	# Broadcast the restored inventory to the owning client via RPC
	if peer_id != 1:
		player_node.sync_inventory_to_owner.rpc_id(peer_id, inventory.to_dict())
	else:
		# Server player (peer_id 1) - update local UI directly
		if has_method("update_local_inventory_display"):
			update_local_inventory_display()

func _on_server_disconnected() -> void:
	teardown_multiplayer()
	main_menu.show_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func teardown_multiplayer() -> void:
	# Reset TimeManager cycle state if present
	var time_mgr: Node = get_node_or_null("TimeManager")
	if time_mgr and time_mgr.has_method("reset_cycle"):
		time_mgr.reset_cycle()

	# 1. Close current connection
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	# 2. Reset Network players dictionary
	Network.players.clear()
	
	# 3. Remove all players from the scene
	for child in players_container.get_children():
		child.queue_free()
		
	# 4. Clear grid structures
	if "world_grid" in GridManager:
		GridManager.world_grid.clear()
	var parent_node = self
	if has_node("Environment"):
		parent_node = get_node("Environment")
	for child in parent_node.get_children():
		if child.name.begins_with("structure_"):
			child.queue_free()
			
	# 5. Hide all active game UIs
	if inventory_ui:
		inventory_ui.close_inventory()
	if crafting_ui:
		crafting_ui.close_crafting()
	inventory_visible = false
	crafting_visible = false
	chat_visible = false
	if multiplayer_chat:
		multiplayer_chat.hide()

func _on_host_pressed(nickname: String, skin: String):
	teardown_multiplayer()
	main_menu.hide_menu()
	# Cursor will be captured by the spawned player's _ready()
	var error = Network.start_host(nickname, skin)
	if error:
		main_menu.show_error("Failed to start host (port " + str(Network.SERVER_PORT) + " may be in use).")
		main_menu.show_menu()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_join_pressed(nickname: String, skin: String, address: String):
	teardown_multiplayer()
	main_menu.hide_menu()
	Network.join_game(nickname, skin, address)

func _add_player(id: int, player_info : Dictionary):
	if DisplayServer.get_name() == "headless" and id == 1:
		return

	if players_container.has_node(str(id)):
		return

	var player = player_scene.instantiate()
	player.name = str(id)
	player.position = get_spawn_point()
	players_container.add_child(player, true)

	var nick = Network.players[id]["nick"]
	if player.has_method("set_nickname"):
		player.set_nickname(nick)
	else:
		player.nickname.text = nick

	var skin_enum = player_info["skin"]
	player.set_player_skin(skin_enum)

func get_spawn_point() -> Vector3:
	randomize() # Randomize seed so multiple client instances don't generate identical coordinates

	var space_state = get_world_3d().direct_space_state
	if not space_state:
		# Fallback if physics state is not ready yet
		var spawn_point = Vector2.from_angle(randf() * 2 * PI) * 10
		return Vector3(spawn_point.x, 0.5, spawn_point.y)

	var shape = CapsuleShape3D.new()
	shape.radius = 0.36
	shape.height = 1.73

	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	# Check layer 1 (players) and layer 3 (interactables like trees/ores). 
	# Exclude layer 2 (floor) to prevent the query from always colliding with the ground.
	query.collision_mask = 5

	var attempts = 0
	var max_attempts = 100
	var current_radius = 5.0

	while attempts < max_attempts:
		var angle = randf() * 2 * PI
		var distance = randf_range(0.0, current_radius)
		# Calculate spawn coordinates. Capsule center is at Y = 0.90 (capsule bottom Y = 0.035, above floor Y = 0.025)
		var target_pos = Vector3(
			cos(angle) * distance,
			0.90,
			sin(angle) * distance
		)
		
		query.transform = Transform3D(Basis.IDENTITY, target_pos)
		
		# Check for intersections
		var result = space_state.intersect_shape(query, 1)
		if result.is_empty():
			return target_pos
			
		attempts += 1
		# Expand the search circle dynamically as we fail to find a spot
		if attempts % 10 == 0:
			current_radius += 5.0

	# Fallback if no safe point found. Set Y = 0.90 to match target height.
	var spawn_point_fallback = Vector2.from_angle(randf() * 2 * PI) * 15.0
	return Vector3(spawn_point_fallback.x, 0.90, spawn_point_fallback.y)

func _remove_player(id):
	if not players_container.has_node(str(id)):
		return
	var player_node = players_container.get_node(str(id))
	if player_node:
		player_node.queue_free()

func _setup_interaction_ui():
	var canvas = CanvasLayer.new()
	interaction_prompt = Label.new()
	interaction_prompt.text = ""
	interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	interaction_prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	interaction_prompt.position.y -= 100
	
	interaction_prompt.add_theme_font_size_override("font_size", 24)
	interaction_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	interaction_prompt.add_theme_constant_override("outline_size", 8)
	
	canvas.add_child(interaction_prompt)
	add_child(canvas)

func _setup_connection_status_ui() -> void:
	var canvas := CanvasLayer.new()
	connection_status_label = Label.new()
	connection_status_label.text = ""
	connection_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	connection_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	connection_status_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	
	connection_status_label.add_theme_font_size_override("font_size", 24)
	connection_status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	connection_status_label.add_theme_constant_override("outline_size", 8)
	
	var custom_font := load("res://assets/fonts/Kurland.ttf")
	if custom_font:
		connection_status_label.add_theme_font_override("font", custom_font)
		
	canvas.add_child(connection_status_label)
	add_child(canvas)

func _setup_phase_banner_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "PhaseBannerCanvas"

	_phase_banner_panel = Panel.new()
	_phase_banner_panel.name = "PhaseBannerPanel"
	_phase_banner_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_phase_banner_panel.offset_top = 10
	_phase_banner_panel.offset_bottom = 80  # Extended to fit timer
	_phase_banner_panel.offset_left = 100
	_phase_banner_panel.offset_right = -100

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.0, 0.4, 0.0, 0.7)  # Dark green, alpha-transparent
	_phase_banner_panel.add_theme_stylebox_override("panel", panel_style)

	_phase_banner_label = Label.new()
	_phase_banner_label.name = "PhaseBannerLabel"
	_phase_banner_label.text = "DAYTIME: PREPARE & BUILD"
	_phase_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_phase_banner_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_phase_banner_label.offset_top = 5
	_phase_banner_label.offset_bottom = 30
	_phase_banner_label.add_theme_font_size_override("font_size", 20)
	_phase_banner_label.add_theme_color_override("font_color", Color.WHITE)
	_phase_banner_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_phase_banner_label.add_theme_constant_override("outline_size", 4)

	_phase_timer_label = Label.new()
	_phase_timer_label.name = "PhaseTimerLabel"
	_phase_timer_label.text = "03:00"
	_phase_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_phase_timer_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_phase_timer_label.offset_top = 35
	_phase_timer_label.offset_bottom = 65
	_phase_timer_label.add_theme_font_size_override("font_size", 24)
	_phase_timer_label.add_theme_color_override("font_color", Color.YELLOW)
	_phase_timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_phase_timer_label.add_theme_constant_override("outline_size", 6)

	_phase_banner_panel.add_child(_phase_banner_label)
	_phase_banner_panel.add_child(_phase_timer_label)
	canvas.add_child(_phase_banner_panel)
	add_child(canvas)

func _on_connection_status_changed(message: String) -> void:
	if connection_status_label:
		connection_status_label.text = message

func _on_phase_changed(is_night_phase: bool, _wave_number: int) -> void:
	if not _phase_banner_label or not _phase_banner_panel:
		return

	var panel_style: StyleBoxFlat = _phase_banner_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if not panel_style:
		panel_style = StyleBoxFlat.new()

	if is_night_phase:
		_phase_banner_label.text = "NIGHTFALL: DEFEND THE CORE!"
		panel_style.bg_color = Color(0.8, 0.1, 0.1, 0.85)  # Warning crimson

		# Lock building capability during night
		var local_player: Node = _get_local_player()
		if local_player:
			var placement_controller: Node = local_player.get_node_or_null("PlayerPlacementController")
			if placement_controller and "is_active" in placement_controller:
				placement_controller.is_active = false
			if "is_building" in local_player:
				local_player.is_building = false
	else:
		_phase_banner_label.text = "DAYTIME: PREPARE & BUILD"
		panel_style.bg_color = Color(0.0, 0.4, 0.0, 0.7)  # Alpha-transparent dark green

	_phase_banner_panel.add_theme_stylebox_override("panel", panel_style)

func _on_phase_time_updated(phase_time: float, max_time: float, _is_night_phase: bool) -> void:
	if not _phase_timer_label:
		return
	var time_remaining: float = max(0.0, max_time - phase_time)
	var minutes: int = int(time_remaining / 60.0)
	var seconds: int = int(time_remaining) % 60
	_phase_timer_label.text = "%02d:%02d" % [minutes, seconds]

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_skip_phase"):
		_debug_skip_phase()
	elif event.is_action_pressed("toggle_chat"):
		toggle_chat()
	elif event.is_action_pressed("inventory"):
		if crafting_visible:
			toggle_crafting()
		# Prevent opening inventory while in build mode to avoid state confusion
		var local_player: Node = _get_local_player()
		if local_player and local_player.is_building:
			return
		toggle_inventory()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_debug_add_item()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		_debug_print_inventory()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		print("Debug: F3 key pressed in level.gd _input")
		_debug_start_wave()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F4:
		_debug_damage_base_heart()

func set_interaction_prompt(prompt_text: String):
	if interaction_prompt:
		if main_menu and main_menu.is_menu_visible():
			interaction_prompt.text = ""
		else:
			interaction_prompt.text = prompt_text

func spawn_resources():
	# Seed the RNG so all clients spawn them in the exact same positions
	seed(54321)
	
	# Spawn 15 trees
	for i in range(15):
		var tree = preload("res://scripts/harvestable_node.gd").new()
		tree.node_type = HarvestableNode.NodeType.TREE
		tree.item_id = "wood"
		tree.node_name = "Tree"
		tree.name = "Tree_" + str(i)
		
		var x = randf_range(-40.0, 40.0)
		var z = randf_range(-40.0, 40.0)
		if Vector2(x, z).length() < 12.0:
			var shifted = Vector2(x, z).normalized() * 15.0
			x = shifted.x
			z = shifted.y
			
		tree.position = Vector3(x, 0.0, z)
		$Environment.add_child(tree)
		
	# Spawn 10 iron ores
	for i in range(10):
		var ore = preload("res://scripts/harvestable_node.gd").new()
		ore.node_type = HarvestableNode.NodeType.IRON_ORE
		ore.item_id = "iron_ore"
		ore.node_name = "Iron Ore"
		ore.name = "IronOre_" + str(i)
		
		var x = randf_range(-40.0, 40.0)
		var z = randf_range(-40.0, 40.0)
		if Vector2(x, z).length() < 12.0:
			var shifted = Vector2(x, z).normalized() * 15.0
			x = shifted.x
			z = shifted.y
			
		ore.position = Vector3(x, 0.0, z)
		$Environment.add_child(ore)

	# Spawn a Workbench crafting station
	var station_scene = load("res://scenes/environment/crafting_station.tscn")
	if station_scene:
		var workbench = station_scene.instantiate()
		workbench.station_type = "Workbench"
		workbench.name = "Crafting_Workbench"
		workbench.position = Vector3(-3.0, 0.0, -3.0)
		$Environment.add_child(workbench)

		# Spawn an Anvil crafting station
		var anvil = station_scene.instantiate()
		anvil.station_type = "Anvil"
		anvil.name = "Crafting_Anvil"
		anvil.position = Vector3(3.0, 0.0, -3.0)
		$Environment.add_child(anvil)

func _setup_enemy_spawner() -> void:
	if not multiplayer.is_server():
		return
	print("Debug: _setup_enemy_spawner() running on server")
	var spawner: MultiplayerSpawner = get_node_or_null("EnemySpawner") as MultiplayerSpawner
	if not spawner:
		push_error("Level: EnemySpawner (MultiplayerSpawner) node is missing from level.tscn!")
		return
	# Register the enemy scene so the spawner can track children that match it.
	# Automatic Scene Mode: the spawner watches spawn_path for new children whose
	# PackedScene matches an entry in spawnable_scenes. When WaveSpawner calls
	# level.add_child(enemy, true), the spawner detects the match and replicates
	# the node + its MultiplayerSynchronizer initial state to all clients.
	# No spawn_function / custom callable is needed or configured.
	spawner.add_spawnable_scene("res://scenes/level/enemy.tscn")
	spawner.spawn_path = get_path()
	print("Debug: EnemySpawner configured — Automatic Scene Mode, spawn_path=", spawner.spawn_path)

func _on_quit_pressed() -> void:
	get_tree().quit()

# ---------- MULTIPLAYER CHAT ----------
func toggle_chat():
	if main_menu.is_menu_visible():
		return

	multiplayer_chat.toggle_chat()

func is_chat_visible() -> bool:
	return multiplayer_chat.is_chat_visible() if multiplayer_chat else false



func _on_chat_message_sent(message_text: String) -> void:
	var trimmed_message = message_text.strip_edges()
	if trimmed_message == "":
		return # do not send empty messages

	var nick = Network.players[multiplayer.get_unique_id()]["nick"]
	rpc("msg_rpc", nick, trimmed_message)

@rpc("any_peer", "call_local")
func msg_rpc(nick, msg):
	multiplayer_chat.add_message(nick, msg)

# ---------- INVENTORY SYSTEM ----------
func toggle_inventory():
	if main_menu.is_menu_visible():
		return

	var local_player = _get_local_player()
	if not local_player:
		return

	if not inventory_visible:
		inventory_visible = true
		inventory_ui.open_inventory(local_player)
	else:
		inventory_visible = false
		inventory_ui.close_inventory()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func is_inventory_visible() -> bool:
	return inventory_visible

# ---------- CRAFTING SYSTEM ----------
func toggle_crafting(station = null):
	if main_menu.is_menu_visible():
		return

	var local_player = _get_local_player()
	if not local_player:
		return

	if not crafting_visible:
		if inventory_visible:
			toggle_inventory()
		crafting_visible = true
		crafting_ui.open_crafting(local_player)
	else:
		crafting_visible = false
		crafting_ui.close_crafting()

func is_crafting_visible() -> bool:
	return crafting_visible

func close_crafting_ui_if_open() -> void:
	if crafting_visible:
		toggle_crafting()

func _on_crafting_closed():
	crafting_visible = false

# Additional helper for testing
func _notification(what):
	if what == NOTIFICATION_READY:
		print("Inventory System Controls:")
		print("  B - Toggle inventory")
		print("  F1 - Add random test item (debug)")
		print("  F2 - Print inventory contents (debug)")
	# Intercept the OS close/SIGTERM signal on the server to flush inventories.
	if what == NOTIFICATION_WM_CLOSE_REQUEST and multiplayer.is_server():
		if has_node("/root/DatabaseManager"):
			# Build the peer→inventory map from all spawned player nodes.
			var inv_map: Dictionary = {}
			for child in players_container.get_children():
				var peer_id: int = int(child.name)
				if child.has_method("get_inventory"):
					inv_map[peer_id] = child.get_inventory()
			get_node("/root/DatabaseManager").flush_all_inventories(inv_map)
		get_tree().quit()

func _on_inventory_closed():
	inventory_visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func update_local_inventory_display():
	if inventory_ui:
		# Always refresh if the UI exists, regardless of visibility
		inventory_ui.refresh_display()
		print("Debug: Inventory display updated from server sync")

func _get_local_player() -> Node:
	var local_player_id = multiplayer.get_unique_id()
	if players_container.has_node(str(local_player_id)):
		return players_container.get_node(str(local_player_id))
	return null

# Debug functions for testing inventory system
func _debug_add_item():
	var local_player = _get_local_player()
	if local_player:
		var test_items = ["iron_sword", "health_potion", "leather_armor", "magic_gem", "iron_pickaxe", "spiked_wall_item", "automated_turret_item", "wood", "iron_ore"]
		var random_item = test_items[randi() % test_items.size()]
		print("Debug: Requesting to add ", random_item, " to player ", local_player.name, " (authority: ", local_player.get_multiplayer_authority(), ")")
		local_player.request_add_item.rpc_id(1, random_item, 1)
	else:
		print("Debug: No local player found!")

func _debug_print_inventory():
	var local_player = _get_local_player()
	if local_player and local_player.get_inventory():
		var inventory = local_player.get_inventory()
		print("=== Inventory Debug ===")
		for i in range(inventory.slots.size()):
			var slot = inventory.get_slot(i)
			if slot and not slot.is_empty():
				print("Slot ", i, ": ", slot.item_id, " x", slot.quantity)
		print("=====================")
	else:
		print("No inventory found for local player")

# ---------- WAVE SPAWNER DEBUG ----------
func _debug_start_wave() -> void:
	print("Debug: _debug_start_wave() called")
	if multiplayer.is_server():
		# Host/server: call directly
		request_start_wave()
	else:
		# Client: send RPC to server
		request_start_wave.rpc_id(1)

@rpc("any_peer", "reliable")
func request_start_wave() -> void:
	print("Debug: request_start_wave() RPC received on server")
	if not multiplayer.is_server():
		print("Debug: Not server, returning")
		return
	var spawners := get_tree().get_nodes_in_group("Spawners")
	print("Debug: Found ", spawners.size(), " spawners in group")
	if spawners.is_empty():
		print("Debug: No WaveSpawner nodes found in the scene. Add one via 'wave_spawner.tscn'.")
		return
	print("Debug: Starting next wave on ", spawners.size(), " spawner(s)...")
	for spawner in spawners:
		print("Debug: Calling start_next_wave on spawner: ", spawner.name)
		if spawner.has_method("start_next_wave"):
			spawner.start_next_wave()

func _debug_damage_base_heart() -> void:
	if not multiplayer.is_server():
		print("Debug: Only the server can damage the Base Heart.")
		return
	var objectives := get_tree().get_nodes_in_group("Objective")
	if objectives.is_empty():
		print("Debug: No node found in group 'Objective'. Place a BaseHeart in the scene.")
		return
	var heart_health := objectives[0].get_node_or_null("HealthComponent") as HealthComponent
	if heart_health:
		heart_health.request_damage(100.0)
		print("Debug: Dealt 100 damage to Base Heart (current HP: ", heart_health.current_health, ")")

# ---------- DEBUG SKIP PHASE ----------
func _debug_skip_phase() -> void:
	print("Debug: _debug_skip_phase() called")
	if multiplayer.is_server():
		request_skip_phase()
	else:
		request_skip_phase.rpc_id(1)

@rpc("any_peer", "reliable")
func request_skip_phase() -> void:
	print("Debug: request_skip_phase() RPC received on server")
	if not multiplayer.is_server():
		print("Debug: Not server, returning")
		return
	if _time_manager:
		_time_manager.skip_to_next_phase()
