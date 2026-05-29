## test_db_crud_roundtrip.gd
## Integration tests verifying database CRUD, SIGTERM notification persistence,
## and transactional atomicity/rollback behavior.
extends GutTest

var test_db_manager: Node
var test_db_path: String = "user://test_crud_roundtrip.db"

# Mock classes to support notification testing
class CloseSimulatedLevel extends Node:
	var players_container: Node
	var db_manager: Node
	var is_server_override: bool = true
	
	func _notification(what):
		if what == NOTIFICATION_WM_CLOSE_REQUEST and is_server_override:
			if db_manager:
				var inv_map: Dictionary = {}
				for child in players_container.get_children():
					var peer_id: int = int(child.name)
					if child.has_method("get_inventory"):
						inv_map[peer_id] = child.get_inventory()
				db_manager.flush_all_inventories(inv_map)

class MockPlayerNode extends Node:
	var _inventory: PlayerInventory
	
	func _init():
		_inventory = PlayerInventory.new()
		
	func get_inventory() -> PlayerInventory:
		return _inventory

func before_each():
	# Create a temporary DatabaseManager instance for testing
	test_db_manager = Node.new()
	test_db_manager.set_script(load("res://scripts/database_manager.gd"))
	test_db_manager.name = "TestDatabaseManager"
	
	# Override the DB path to use a test database
	test_db_manager.set("DB_PATH", test_db_path)
	
	# Add to scene tree so _ready() can run
	get_tree().root.add_child(test_db_manager)
	
	# Wait for _ready() to complete
	await get_tree().process_frame
	
	# Manually initialize the database (bypass multiplayer.is_server() guard)
	test_db_manager.call("_open_database")
	test_db_manager.call("_run_migrations")
	test_db_manager.set("_is_ready", true)

func after_each():
	# Clean up the test database file
	if test_db_manager:
		test_db_manager.call("_notification", NOTIFICATION_PREDELETE)
		test_db_manager.queue_free()
		await get_tree().process_frame
	
	# Clean up players from Network singleton
	Network.players.clear()
	
	# Delete the test database file
	var test_db_global_path = ProjectSettings.globalize_path(test_db_path)
	if FileAccess.file_exists(test_db_global_path):
		DirAccess.remove_absolute(test_db_global_path)

func test_db_crud_roundtrip():
	var test_username = "CrudRoundTripPlayer"
	var test_peer_id = 123
	
	# Register mock player in Network singleton
	Network.players[test_peer_id] = {"nick": test_username}
	
	# 1. Create player row in the database
	test_db_manager.call("load_player_session", test_peer_id, test_username)
	await get_tree().process_frame
	
	# Get the player_id from the database to confirm it exists
	var db = test_db_manager.get("_db")
	db.query("SELECT player_id FROM players WHERE username = '%s';" % test_username)
	assert_eq(db.query_result.size(), 1, "Player should be created in the database")
	var player_id = db.query_result[0]["player_id"]
	
	# 2. Setup inventory and drop items into it
	var inventory = PlayerInventory.new()
	var wood_item = ItemDatabase.get_item("wood")
	var iron_item = ItemDatabase.get_item("iron_ore")
	
	assert_not_null(wood_item, "Wood item should exist in ItemDatabase")
	assert_not_null(iron_item, "Iron ore item should exist in ItemDatabase")
	
	inventory.add_item(wood_item, 5)
	inventory.add_item(iron_item, 3)
	
	var mock_inventory_map = {
		test_peer_id: inventory
	}
	
	# 3. Flush inventories to database
	test_db_manager.call("flush_all_inventories", mock_inventory_map)
	await get_tree().process_frame
	
	# Verify rows are saved
	db.query("SELECT item_id, quantity FROM inventories WHERE player_id = '%s' ORDER BY item_id ASC;" % player_id)
	var inv_rows = db.query_result
	assert_eq(inv_rows.size(), 2, "There should be exactly 2 items saved in the DB")
	
	# Note: iron_ore comes alphabetically before wood
	assert_eq(inv_rows[0]["item_id"], "iron_ore", "First item should be iron_ore")
	assert_eq(inv_rows[0]["quantity"], 3, "Iron ore quantity should be 3")
	assert_eq(inv_rows[1]["item_id"], "wood", "Second item should be wood")
	assert_eq(inv_rows[1]["quantity"], 5, "Wood quantity should be 5")
	
	# 4. Clear local inventory and reload it from DB
	inventory.clear()
	assert_eq(inventory.get_item_count("wood"), 0, "Inventory should be empty after clear")
	
	var results = {
		"peer_id": -1,
		"player_id": "",
		"inv_dict": {}
	}
	var session_loaded_callback = func(peer_id, p_id, inv_dict):
		results["peer_id"] = peer_id
		results["player_id"] = p_id
		results["inv_dict"] = inv_dict
		
	test_db_manager.session_loaded.connect(session_loaded_callback)
	
	test_db_manager.call("load_player_session", test_peer_id, test_username)
	await get_tree().process_frame
	
	assert_eq(results["peer_id"], test_peer_id, "Signal should emit correct peer ID")
	assert_eq(results["player_id"], player_id, "Signal should emit correct player ID")
	
	# Apply loaded data back to inventory component
	inventory.from_dict(results["inv_dict"])
	
	assert_eq(inventory.get_item_count("wood"), 5, "Wood should be restored to 5")
	assert_eq(inventory.get_item_count("iron_ore"), 3, "Iron ore should be restored to 3")

func test_simulated_sigterm_flush():
	var test_username = "SigtermPlayer"
	var test_peer_id = 456
	
	# Register mock player in Network singleton
	Network.players[test_peer_id] = {"nick": test_username}
	
	# Load session to create player row
	test_db_manager.call("load_player_session", test_peer_id, test_username)
	await get_tree().process_frame
	
	# Setup simulated level, container, and player
	var simulated_level = CloseSimulatedLevel.new()
	simulated_level.db_manager = test_db_manager
	
	var players_container = Node.new()
	players_container.name = "PlayersContainer"
	simulated_level.add_child(players_container)
	simulated_level.players_container = players_container
	
	var mock_player = MockPlayerNode.new()
	mock_player.name = str(test_peer_id)
	players_container.add_child(mock_player)
	
	# Add items to the player's inventory
	var wood_item = ItemDatabase.get_item("wood")
	mock_player.get_inventory().add_item(wood_item, 10)
	
	# Add level to the scene tree so it can receive notifications
	get_tree().root.add_child(simulated_level)
	
	# Send the simulated SIGTERM close notification
	simulated_level.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	await get_tree().process_frame
	
	# Verify rows were committed to SQLite
	var db = test_db_manager.get("_db")
	db.query("SELECT player_id FROM players WHERE username = '%s';" % test_username)
	var player_id = db.query_result[0]["player_id"]
	
	db.query("SELECT item_id, quantity FROM inventories WHERE player_id = '%s';" % player_id)
	var inv_rows = db.query_result
	
	assert_eq(inv_rows.size(), 1, "Inventory should have exactly one item row")
	assert_eq(inv_rows[0]["item_id"], "wood", "Item should be wood")
	assert_eq(inv_rows[0]["quantity"], 10, "Quantity should be 10")
	
	# Clean up nodes
	simulated_level.queue_free()
	await get_tree().process_frame

func test_transaction_atomicity_and_rollback():
	var db = test_db_manager.get("_db")
	
	# Count initial players
	db.query("SELECT COUNT(*) as count FROM players;")
	var initial_count = db.query_result[0]["count"]
	
	# Begin transaction
	db.query("BEGIN TRANSACTION;")
	
	# Insert a valid player row
	var insert_query = """
		INSERT INTO players (player_id, username, last_login_timestamp)
		VALUES ('usr-atomicity-test-01', 'AtomicityPlayer1', datetime('now'));
	"""
	db.query(insert_query)
	
	# Verify that the player row is temporarily visible within the transaction block
	db.query("SELECT * FROM players WHERE player_id = 'usr-atomicity-test-01';")
	assert_eq(db.query_result.size(), 1, "Row should exist temporarily within the transaction")
	
	# Roll back transaction manually
	db.query("ROLLBACK;")
		
	# Verify that initial player count is unchanged (rollback occurred and was fully atomic)
	db.query("SELECT COUNT(*) as count FROM players;")
	var final_count = db.query_result[0]["count"]
	
	assert_eq(final_count, initial_count, "No players should be added due to transaction rollback")
	
	# Verify player 'AtomicityPlayer1' was rolled back completely
	db.query("SELECT * FROM players WHERE player_id = 'usr-atomicity-test-01';")
	assert_eq(db.query_result.size(), 0, "Row should not exist in the database after rollback")
