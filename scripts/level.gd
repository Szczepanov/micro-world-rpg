extends Node3D

@onready var players_container: Node3D = $PlayersContainer
@onready var main_menu: MainMenuUI = $MainMenuUI
@export var player_scene: PackedScene

@onready var multiplayer_chat: MultiplayerChatUI = $MultiplayerChatUI
@onready var inventory_ui: InventoryUI = $InventoryUI

var chat_visible = false
var inventory_visible = false

var interaction_prompt: Label

func _ready():
	if DisplayServer.get_name() == "headless":
		print("Dedicated server starting...")
		Network.start_host("", "")

	multiplayer_chat.hide()
	main_menu.show_menu()
	multiplayer_chat.set_process_input(true)

	main_menu.host_pressed.connect(_on_host_pressed)
	main_menu.join_pressed.connect(_on_join_pressed)
	main_menu.quit_pressed.connect(_on_quit_pressed)

	if inventory_ui:
		inventory_ui.inventory_closed.connect(_on_inventory_closed)

	if multiplayer_chat:
		multiplayer_chat.message_sent.connect(_on_chat_message_sent)

	# Always connect player_connected and peer_disconnected so clients spawn/cleanup peers correctly
	Network.connect("player_connected", Callable(self, "_on_player_connected"))
	multiplayer.peer_disconnected.connect(_remove_player)

	# Setup the screen interaction UI prompt
	_setup_interaction_ui()
	
	# Spawn resource nodes in the world
	spawn_resources()

func _on_player_connected(peer_id, player_info):
	_add_player(peer_id, player_info)

func _on_host_pressed(nickname: String, skin: String):
	main_menu.hide_menu()
	Network.start_host(nickname, skin)

func _on_join_pressed(nickname: String, skin: String, address: String):
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
	var spawn_point = Vector2.from_angle(randf() * 2 * PI) * 10 # spawn radius
	return Vector3(spawn_point.x, 0.5, spawn_point.y) # Spawn slightly above floor

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

func set_interaction_prompt(prompt_text: String):
	if interaction_prompt:
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

func _on_quit_pressed() -> void:
	get_tree().quit()

# ---------- MULTIPLAYER CHAT ----------
func toggle_chat():
	if main_menu.is_menu_visible():
		return

	multiplayer_chat.toggle_chat()
	chat_visible = multiplayer_chat.is_chat_visible()

func is_chat_visible() -> bool:
	return multiplayer_chat.is_chat_visible()

func _input(event):
	if event.is_action_pressed("toggle_chat"):
		toggle_chat()
	elif chat_visible and multiplayer_chat.message.has_focus():
		if event is InputEventKey and event.keycode == KEY_ENTER and event.pressed:
			multiplayer_chat._on_send_pressed()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		toggle_inventory()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_debug_add_item()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		_debug_print_inventory()

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

	inventory_visible = !inventory_visible
	if inventory_visible:
		inventory_ui.open_inventory(local_player)
	else:
		inventory_ui.close_inventory()

func is_inventory_visible() -> bool:
	return inventory_visible

# Additional helper for testing
func _notification(what):
	if what == NOTIFICATION_READY:
		print("Inventory System Controls:")
		print("  B - Toggle inventory")
		print("  F1 - Add random test item (debug)")
		print("  F2 - Print inventory contents (debug)")

func _on_inventory_closed():
	inventory_visible = false

func update_local_inventory_display():
	if inventory_ui:
		# Always refresh if the UI exists, regardless of visibility
		inventory_ui.refresh_display()
		print("Debug: Inventory display updated from server sync")

func _get_local_player() -> Character:
	var local_player_id = multiplayer.get_unique_id()
	if players_container.has_node(str(local_player_id)):
		return players_container.get_node(str(local_player_id)) as Character
	return null

# Debug functions for testing inventory system
func _debug_add_item():
	var local_player = _get_local_player()
	if local_player:
		var test_items = ["iron_sword", "health_potion", "leather_armor", "magic_gem", "iron_pickaxe"]
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
