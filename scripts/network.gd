extends Node

const SERVER_ADDRESS: String = "127.0.0.1"
const SERVER_PORT: int = 8080
const MAX_PLAYERS : int = 10

var players = {}
var player_info = {
	"nick" : "host",
	"skin" : 0
}
var is_network_active: bool = true
var pending_error_message: String = ""

var _connection_attempts: int = 0
var _join_nickname: String = ""
var _join_skin: String = ""
var _join_address: String = ""

signal player_connected(peer_id, player_info)
signal server_disconnected
signal connection_status_changed(message: String)

func _ready() -> void:
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.connected_to_server.connect(_on_connected_ok)

func start_host(nickname: String, skin_color_str: String):
	is_network_active = true
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(SERVER_PORT, MAX_PLAYERS)
	if error:
		return error

	multiplayer.multiplayer_peer = peer

	if !nickname or nickname.strip_edges() == "":
		nickname = "Host_" + str(multiplayer.get_unique_id())

	player_info["nick"] = nickname
	player_info["skin"] = skin_str_to_e(skin_color_str)
	
	if DisplayServer.get_name() == "headless":
		return

	players[1] = player_info
	player_connected.emit(1, player_info)

func join_game(nickname: String, skin_color_str: String, address: String = SERVER_ADDRESS) -> Error:
	is_network_active = true
	_join_nickname = nickname
	_join_skin = skin_color_str
	_join_address = address
	_connection_attempts = 1

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, SERVER_PORT)
	if error != OK:
		return error

	multiplayer.multiplayer_peer = peer

	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

	if !nickname or nickname.strip_edges() == "":
		nickname = "Player_" + str(multiplayer.get_unique_id())

	var skin_enum = skin_str_to_e(skin_color_str)

	player_info["nick"] = nickname
	player_info["skin"] = skin_enum

	connection_status_changed.emit("Connecting to %s..." % address)
	_start_connection_timeout(_connection_attempts)
	return OK

func _start_connection_timeout(attempt_num: int) -> void:
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		_check_connection_timeout(attempt_num)
	)

func _check_connection_timeout(attempt_num: int) -> void:
	if not multiplayer.multiplayer_peer:
		return
	if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		push_warning("Network: Connection attempt %d timed out." % attempt_num)
		if attempt_num < 2:
			# Retry once after 1s delay
			if multiplayer.multiplayer_peer:
				multiplayer.multiplayer_peer.close()
			multiplayer.multiplayer_peer = null
			
			connection_status_changed.emit("Connection timed out. Retrying (Attempt 2/2)...")
			get_tree().create_timer(1.0).timeout.connect(func() -> void:
				push_warning("Network: Retrying connection to %s..." % _join_address)
				_connection_attempts += 1
				var peer := ENetMultiplayerPeer.new()
				var error := peer.create_client(_join_address, SERVER_PORT)
				if error != OK:
					_handle_connection_failure("Server unavailable.")
					return
				multiplayer.multiplayer_peer = peer
				_start_connection_timeout(_connection_attempts)
			)
		else:
			_handle_connection_failure("Server unavailable. Connection timed out.")

func _handle_connection_failure(reason: String) -> void:
	is_network_active = false
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	pending_error_message = reason
	connection_status_changed.emit("")
	
	# Go back to level.tscn (login screen)
	get_tree().change_scene_to_file("res://scenes/level/level.tscn")

func _on_connected_ok():
	var peer_id = multiplayer.get_unique_id()
	players[peer_id] = player_info
	player_connected.emit(peer_id, player_info)
	connection_status_changed.emit("")

func _on_player_connected(id):
	if DisplayServer.get_name() == "headless":
		return
	_register_player.rpc_id(id, player_info)

@rpc("any_peer", "reliable")
func _register_player(new_player_info):
	var new_player_id = multiplayer.get_remote_sender_id()
	players[new_player_id] = new_player_info
	player_connected.emit(new_player_id, new_player_info)

	if DisplayServer.get_name() == "headless":
		var username: String = new_player_info.get("nick", "Player_%d" % new_player_id)
		if has_node("/root/DatabaseManager"):
			get_node("/root/DatabaseManager").load_player_session(new_player_id, username)

func _on_player_disconnected(id):
	players.erase(id)

func _on_connection_failed() -> void:
	_handle_connection_failure("Server unavailable. Connection failed.")

func _on_server_disconnected():
	is_network_active = false
	
	# Execute cleanup steps
	var local_player = _get_local_player()
	if local_player:
		var placement_controller = local_player.get_node_or_null("PlayerPlacementController")
		if placement_controller and placement_controller.has_method("_destroy_ghost_preview"):
			placement_controller._destroy_ghost_preview()
		
		if "player_inventory" in local_player and local_player.player_inventory:
			local_player.player_inventory.clear()

	pending_error_message = "Error: Connection to host lost."
	
	multiplayer.multiplayer_peer = null
	players.clear()
	server_disconnected.emit()
	
	get_tree().change_scene_to_file("res://scenes/level/level.tscn")

func _get_local_player() -> Node:
	var tree = get_tree()
	if not tree or not tree.current_scene:
		return null
	var players_container = tree.current_scene.get_node_or_null("PlayersContainer")
	if players_container:
		var peer_id = multiplayer.get_unique_id()
		return players_container.get_node_or_null(str(peer_id))
	return null

func skin_str_to_e(s):
	match s.to_lower():
		"blue": return 0
		"yellow": return 1
		"green": return 2
		"red": return 3
		_: return 0
