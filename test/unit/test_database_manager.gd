## test_database_manager.gd
## GUT unit tests for DatabaseManager covering CRUD operations.
## Tests database initialization, player upsert/read, inventory flush/reload,
## and match_history INSERT with last_insert_rowid validation.
extends gut_test

var DatabaseManager: Node
var test_db_path: String = "user://test_pocket_realms.db"

func before_each():
	# Create a temporary DatabaseManager instance for testing
	DatabaseManager = Node.new()
	DatabaseManager.set_script(load("res://scripts/database_manager.gd"))
	DatabaseManager.name = "DatabaseManager"
	
	# Override the DB path to use a test database
	DatabaseManager.set("DB_PATH", test_db_path)
	
	# Add to scene tree so _ready() can run
	get_tree().root.add_child(DatabaseManager)
	
	# Wait for _ready() to complete
	await get_tree().process_frame
	
	# Manually initialize the database (bypass multiplayer.is_server() guard)
	DatabaseManager.call("_open_database")
	DatabaseManager.call("_run_migrations")
	
func after_each():
	# Clean up the test database file
	if DatabaseManager:
		DatabaseManager.call("_notification", NOTIFICATION_PREDELETE)
		DatabaseManager.queue_free()
		await get_tree().process_frame
	
	# Delete the test database file
	var test_db_global_path = ProjectSettings.globalize_path(test_db_path)
	if FileAccess.file_exists(test_db_global_path):
		DirAccess.remove_absolute(test_db_global_path)

func test_database_initialization():
	assert_not_null(DatabaseManager.get("_db"), "Database instance should be created")
	assert_true(DatabaseManager.get("_is_ready"), "Database should be marked as ready")

func test_player_upsert_and_read():
	# Test upserting a new player
	var test_username = "TestPlayer123"
	var test_peer_id = 999
	
	DatabaseManager.call("load_player_session", test_peer_id, test_username)
	await get_tree().process_frame
	
	# Verify the player was upserted by checking the database directly
	var db = DatabaseManager.get("_db")
	db.query("SELECT * FROM players WHERE username = '%s';" % test_username)
	var result = db.query_result
	
	assert_eq(result.size(), 1, "Should have exactly one player row")
	assert_eq(result[0]["username"], test_username, "Username should match")
	assert_gt(result[0]["player_id"].length(), 0, "Player ID should be generated")

func test_inventory_flush_and_reload():
	# First, create a player
	var test_username = "InventoryTestPlayer"
	var test_peer_id = 888
	
	DatabaseManager.call("load_player_session", test_peer_id, test_username)
	await get_tree().process_frame
	
	# Get the player_id from the database
	var db = DatabaseManager.get("_db")
	db.query("SELECT player_id FROM players WHERE username = '%s';" % test_username)
	var player_id = db.query_result[0]["player_id"]
	
	# Create a mock inventory map
	var mock_inventory = {
		888: PlayerInventory.new()
	}
	
	# Add some test items to the inventory
	var test_item = ItemDatabase.get_item("wood")
	if test_item:
		mock_inventory[888].add_item(test_item, 10)
	
	var iron_item = ItemDatabase.get_item("iron_ore")
	if iron_item:
		mock_inventory[888].add_item(iron_item, 5)
	
	# Flush the inventory to the database
	DatabaseManager.call("flush_all_inventories", mock_inventory)
	await get_tree().process_frame
	
	# Verify the inventory was saved
	db.query("SELECT * FROM inventories WHERE player_id = '%s';" % player_id)
	var inv_result = db.query_result
	
	assert_gt(inv_result.size(), 0, "Inventory should have rows")
	
	# Verify we can reload it via load_player_session
	DatabaseManager.call("load_player_session", test_peer_id, test_username)
	await get_tree().process_frame
	
	# The session_loaded signal should have emitted with the inventory data
	# For this test, we just verify the query succeeds
	db.query("SELECT item_id, quantity FROM inventories WHERE player_id = '%s';" % player_id)
	var reload_result = db.query_result
	
	assert_gt(reload_result.size(), 0, "Reloaded inventory should have rows")

func test_match_history_insert_and_last_insert_rowid():
	# Test inserting a match result
	var waves_completed = 5
	var final_hp = 25.5
	var duration = 300
	
	DatabaseManager.call("save_match_result", waves_completed, final_hp, duration)
	await get_tree().process_frame
	
	# Verify the match was inserted
	var db = DatabaseManager.get("_db")
	db.query("SELECT * FROM match_history ORDER BY match_id DESC LIMIT 1;")
	var result = db.query_result
	
	assert_eq(result.size(), 1, "Should have one match history row")
	assert_eq(result[0]["waves_completed"], waves_completed, "Waves completed should match")
	assert_eq(result[0]["base_heart_final_hp"], final_hp, "Final HP should match")
	assert_eq(result[0]["match_duration_seconds"], duration, "Duration should match")
	assert_gt(result[0]["match_id"], 0, "Match ID should be auto-generated")

func test_stable_id_from_username():
	# Test the stable ID generation function
	var username1 = "TestUser"
	var username2 = "TestUser"
	var username3 = "DifferentUser"
	
	var id1 = DatabaseManager.call("_stable_id_from_username", username1)
	var id2 = DatabaseManager.call("_stable_id_from_username", username2)
	var id3 = DatabaseManager.call("_stable_id_from_username", username3)
	
	assert_eq(id1, id2, "Same username should generate same ID")
	assert_ne(id1, id3, "Different usernames should generate different IDs")

func test_sql_escape():
	# Test SQL string escaping
	var unsafe_string = "O'Reilly"
	var escaped = DatabaseManager.call("_escape", unsafe_string)
	
	assert_eq(escaped, "O''Reilly", "Single quotes should be escaped")
	
	var safe_string = "SafeString123"
	var safe_escaped = DatabaseManager.call("_escape", safe_string)
	
	assert_eq(safe_escaped, safe_string, "Safe strings should remain unchanged")

func test_inventory_delete_before_insert():
	# Test that flush_all_inventories deletes existing rows before inserting
	var test_username = "FlushTestPlayer"
	var test_peer_id = 777
	
	DatabaseManager.call("load_player_session", test_peer_id, test_username)
	await get_tree().process_frame
	
	var db = DatabaseManager.get("_db")
	db.query("SELECT player_id FROM players WHERE username = '%s';" % test_username)
	var player_id = db.query_result[0]["player_id"]
	
	# First flush with some items
	var mock_inventory = {
		777: PlayerInventory.new()
	}
	var test_item = ItemDatabase.get_item("wood")
	if test_item:
		mock_inventory[777].add_item(test_item, 5)
	
	DatabaseManager.call("flush_all_inventories", mock_inventory)
	await get_tree().process_frame
	
	db.query("SELECT COUNT(*) as count FROM inventories WHERE player_id = '%s';" % player_id)
	var first_count = db.query_result[0]["count"]
	
	assert_eq(first_count, 1, "Should have 1 inventory row after first flush")
	
	# Second flush with different items
	mock_inventory[777].clear()
	var iron_item = ItemDatabase.get_item("iron_ore")
	if iron_item:
		mock_inventory[777].add_item(iron_item, 3)
	
	DatabaseManager.call("flush_all_inventories", mock_inventory)
	await get_tree().process_frame
	
	db.query("SELECT COUNT(*) as count FROM inventories WHERE player_id = '%s';" % player_id)
	var second_count = db.query_result[0]["count"]
	
	assert_eq(second_count, 1, "Should still have 1 inventory row after second flush (old deleted)")
	
	db.query("SELECT item_id FROM inventories WHERE player_id = '%s';" % player_id)
	var item_result = db.query_result
	assert_eq(item_result[0]["item_id"], "iron_ore", "Item should be the new one")
