extends Node

const SERVER_ADDRESS: String = "127.0.0.1"
const SERVER_PORT: int = 8080
const MAX_PLAYERS : int = 10

var players = {}
var player_info = {
	"nick" : "host",
	"skin" : Character.SkinColor.BLUE
}
var is_network_active: bool = true
var pending_error_message: String = ""

signal player_connected(peer_id, player_info)
signal server_disconnected

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

func join_game(nickname: String, skin_color_str: String, address: String = SERVER_ADDRESS):
	is_network_active = true
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, SERVER_PORT)
	if error:
		return error

	multiplayer.multiplayer_peer = peer

	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

	if !nickname or nickname.strip_edges() == "":
		nickname = "Player_" + str(multiplayer.get_unique_id())

	var skin_enum = skin_str_to_e(skin_color_str)

	player_info["nick"] = nickname
	player_info["skin"] = skin_enum

func _on_connected_ok():
	var peer_id = multiplayer.get_unique_id()
	players[peer_id] = player_info
	player_connected.emit(peer_id, player_info)

func _on_player_connected(id):
	if DisplayServer.get_name() == "headless":
		return
	_register_player.rpc_id(id, player_info)

@rpc("any_peer", "reliable")
func _register_player(new_player_info):
	var new_player_id = multiplayer.get_remote_sender_id()
	players[new_player_id] = new_player_info
	player_connected.emit(new_player_id, new_player_info)

func _on_player_disconnected(id):
	players.erase(id)

func _on_connection_failed():
	multiplayer.multiplayer_peer = null

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
		"blue": return Character.SkinColor.BLUE
		"yellow": return Character.SkinColor.YELLOW
		"green": return Character.SkinColor.GREEN
		"red": return Character.SkinColor.RED
		_: return Character.SkinColor.BLUE
