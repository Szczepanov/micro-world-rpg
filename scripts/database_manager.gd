## database_manager.gd
## Server-only singleton. Provides a typed abstraction over SQLite for
## player session load/save and match result persistence.
##
## NEVER call any method on this node from a client peer.
## Guard all call-sites with: if multiplayer.is_server()
##
## Dependencies:
##   - godot-sqlite GDExtension (addons/godot-sqlite/)
##   - PlayerInventory class (scripts/player_inventory.gd)
##   - ItemDatabase autoload (scripts/item_database.gd)
##
## Lifecycle hooks:
##   load_player_session()   ← called from network.gd:_on_player_connected
##   save_match_result()     ← called from base_heart.gd:_on_core_died
##   flush_all_inventories() ← called from level.gd:_notification(WM_CLOSE_REQUEST)

extends Node

# ---------- Constants --------------------------------------------------------

var DB_PATH: String = "user://pocket_realms.db"
const SCHEMA_VERSION: int = 1

# ---------- State ------------------------------------------------------------

var _db  # SQLite instance — typed as Variant to avoid hard compile dependency
var _is_ready: bool = false
var _match_start_time_unix: int = 0

## Emitted when a player's session data has been loaded from the DB.
## The caller (level.gd) should use this to populate the PlayerInventory
## node over the network.
signal session_loaded(peer_id: int, player_id: String, inventory_dict: Dictionary)

## Emitted when a match record has been committed successfully.
signal match_saved(match_id: int)

# ---------- Initialisation ---------------------------------------------------

func _ready() -> void:
	# This node must ONLY do work on the dedicated server.
	# On a regular client it registers in the tree but stays inert.
	if not multiplayer.is_server():
		return

	_open_database()
	_run_migrations()
	_is_ready = true
	print("DatabaseManager: Online. DB path: ", ProjectSettings.globalize_path(DB_PATH))


func _open_database() -> void:
	# Lazy-load the SQLite class so the project doesn't hard-error on clients
	# that don't have the GDExtension registered (e.g. mobile builds).
	if not ClassDB.class_exists("SQLite"):
		push_error("DatabaseManager: godot-sqlite GDExtension not found! " +
		           "Install it at addons/godot-sqlite/.")
		return

	_db = ClassDB.instantiate("SQLite")
	_db.path = DB_PATH
	_db.verbosity_level = 1  # VERBOSE — set to 0 in production
	_db.foreign_keys = true

	if not _db.open_db():
		push_error("DatabaseManager: Failed to open database at: " + DB_PATH)
		_db = null


func _run_migrations() -> void:
	if not _db:
		return

	# Enable WAL mode for concurrent reads during active match.
	_db.query("PRAGMA journal_mode=WAL;")
	_db.query("PRAGMA synchronous=NORMAL;")

	# Create tables if they don't exist (idempotent).
	var ddl: Array[String] = [
		"""CREATE TABLE IF NOT EXISTS players (
			player_id               TEXT    NOT NULL,
			username                TEXT    NOT NULL,
			total_resources_harvested INTEGER NOT NULL DEFAULT 0,
			last_login_timestamp    TEXT    NOT NULL DEFAULT (datetime('now')),
			CONSTRAINT pk_players   PRIMARY KEY (player_id),
			CONSTRAINT uq_username  UNIQUE (username)
		);""",

		"""CREATE TABLE IF NOT EXISTS inventories (
			player_id   TEXT    NOT NULL,
			item_id     TEXT    NOT NULL,
			quantity    INTEGER NOT NULL DEFAULT 0,
			CONSTRAINT pk_inventories PRIMARY KEY (player_id, item_id),
			CONSTRAINT fk_player FOREIGN KEY (player_id)
			    REFERENCES players(player_id) ON DELETE CASCADE
		);""",

		"""CREATE INDEX IF NOT EXISTS idx_inv_player ON inventories(player_id);""",

		"""CREATE TABLE IF NOT EXISTS match_history (
			match_id                INTEGER PRIMARY KEY AUTOINCREMENT,
			waves_completed         INTEGER NOT NULL DEFAULT 0,
			base_heart_final_hp     REAL    NOT NULL DEFAULT 0.0,
			match_duration_seconds  INTEGER NOT NULL DEFAULT 0,
			completion_timestamp    TEXT    NOT NULL DEFAULT (datetime('now'))
		);"""
	]

	for statement in ddl:
		if not _db.query(statement):
			push_error("DatabaseManager: Migration failed:\n" + statement)


# ---------- Hook 1: On Client Connected — Load Session ----------------------

## Called by network.gd immediately after _on_player_connected fires.
## Queries the players and inventories tables, then emits session_loaded.
##
## @param peer_id  The ENet multiplayer peer ID (int).
## @param username The player's display name from Network.players[peer_id]["nick"].
func load_player_session(peer_id: int, username: String) -> void:
	if not _is_ready or not _db:
		push_warning("DatabaseManager: load_player_session called before DB is ready.")
		return

	if not multiplayer.is_server():
		push_error("DatabaseManager: load_player_session must only run on the server.")
		return

	# Derive a stable player_id from the username.
	# NOTE: In production, replace with a proper UUID from your auth layer.
	var player_id: String = _stable_id_from_username(username)

	# --- Upsert player row (update last_login on every connection) ---
	var upsert_query: String = """
		INSERT INTO players (player_id, username, last_login_timestamp)
		VALUES ('{pid}', '{uname}', datetime('now'))
		ON CONFLICT(player_id) DO UPDATE SET
		    username = excluded.username,
		    last_login_timestamp = excluded.last_login_timestamp;
	""".format({"pid": player_id, "uname": _escape(username)})

	if not _db.query(upsert_query):
		push_error("DatabaseManager: Failed to upsert player '%s'." % username)
		return

	# --- Load inventory rows ---
	var inv_query: String = """
		SELECT item_id, quantity FROM inventories
		WHERE player_id = '%s';
	""" % player_id

	_db.query(inv_query)
	var rows: Array = _db.query_result

	# Build a dictionary matching PlayerInventory.from_dict() input format.
	# The 'slots' array is sparse — from_dict() handles empty slots natively.
	var inventory_dict: Dictionary = {"slots": []}
	for row in rows:
		inventory_dict["slots"].append({
			"item_id": row["item_id"],
			"quantity": row["quantity"]
		})

	print("DatabaseManager: Loaded %d inventory rows for '%s' (peer %d)." \
	      % [rows.size(), username, peer_id])

	# Emit so level.gd (or network.gd) can populate the PlayerInventory node.
	session_loaded.emit(peer_id, player_id, inventory_dict)


# ---------- Hook 2: On Match Over — Save Match Result -----------------------

## Called by base_heart.gd immediately inside _on_core_died(), BEFORE
## trigger_defeat.rpc() broadcasts to clients. This ensures the record is
## committed even if the server process is killed shortly after.
##
## @param waves_completed         How many full waves WaveSpawner completed.
## @param base_heart_final_hp     The HealthComponent.current_health at death.
## @param match_duration_seconds  Time since level._ready() was called.
func save_match_result(
	waves_completed: int,
	base_heart_final_hp: float,
	match_duration_seconds: int
) -> void:
	if not _is_ready or not _db:
		push_warning("DatabaseManager: save_match_result called before DB is ready.")
		return

	if not multiplayer.is_server():
		push_error("DatabaseManager: save_match_result must only run on the server.")
		return

	# Atomic INSERT wrapped in explicit transaction to prevent partial writes
	# if the process is interrupted mid-flight.
	_db.query("BEGIN TRANSACTION;")

	var insert_query: String = """
		INSERT INTO match_history
		    (waves_completed, base_heart_final_hp, match_duration_seconds)
		VALUES (%d, %f, %d);
	""" % [waves_completed, base_heart_final_hp, match_duration_seconds]

	if not _db.query(insert_query):
		_db.query("ROLLBACK;")
		push_error("DatabaseManager: Failed to insert match_history row.")
		return

	_db.query("COMMIT;")

	# Retrieve the auto-assigned match_id for the signal payload.
	_db.query("SELECT last_insert_rowid() AS match_id;")
	var match_id: int = _db.query_result[0]["match_id"] if _db.query_result.size() > 0 else -1

	print("DatabaseManager: Match record committed. match_id=%d, waves=%d, duration=%ds" \
	      % [match_id, waves_completed, match_duration_seconds])

	match_saved.emit(match_id)


# ---------- Hook 3: Graceful Shutdown — Flush All Inventories ---------------

## Called from level.gd's _notification(NOTIFICATION_WM_CLOSE_REQUEST)
## or from a SIGTERM handler to persist all in-memory inventories before
## the process exits.
##
## @param player_inventory_map  Dictionary[int, PlayerInventory] mapping
##                              peer_id → PlayerInventory instance.
func flush_all_inventories(player_inventory_map: Dictionary) -> void:
	if not _is_ready or not _db:
		return

	print("DatabaseManager: Flushing %d player inventories..." \
	      % player_inventory_map.size())

	_db.query("BEGIN TRANSACTION;")

	for peer_id in player_inventory_map:
		var username: String = Network.players.get(peer_id, {}).get("nick", "")
		if username.is_empty():
			continue

		var player_id: String = _stable_id_from_username(username)
		var inventory: PlayerInventory = player_inventory_map[peer_id]

		# Delete existing rows for this player, then re-insert current state.
		# DELETE + INSERT is simpler than UPSERT per-slot and SQLite handles
		# the transaction atomically.
		_db.query("DELETE FROM inventories WHERE player_id = '%s';" % player_id)

		for slot in inventory.slots:
			if slot.is_empty():
				continue
			var insert: String = """
				INSERT INTO inventories (player_id, item_id, quantity)
				VALUES ('%s', '%s', %d);
			""" % [player_id, _escape(slot.item_id), slot.quantity]
			_db.query(insert)

	_db.query("COMMIT;")
	print("DatabaseManager: Inventory flush complete.")


# ---------- Utility ---------------------------------------------------------

## Generates a stable, deterministic player_id from a username string.
## This is a placeholder — replace with a proper auth UUID in production.
func _stable_id_from_username(username: String) -> String:
	# Use Godot's built-in hash and format as a pseudo-UUID.
	var h: int = username.hash()
	return "usr-%08x-0000-4000-8000-000000000000" % abs(h)


## Escapes single quotes in SQL string literals to prevent injection.
## For production, use prepared statements / the SQLite bind API instead.
func _escape(s: String) -> String:
	return s.replace("'", "''")


## Closes the database cleanly. Call from _notification(NOTIFICATION_PREDELETE).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _db:
		_db.close_db()
		print("DatabaseManager: Database connection closed.")
