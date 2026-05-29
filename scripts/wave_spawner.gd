## wave_spawner.gd
## Place this node at map entry points. The server controls all wave logic.
## Call start_next_wave() (or press F3 in debug) to begin spawning enemies.
## Registers itself in the "Spawners" group so BaseHeart can stop it on defeat.
class_name WaveSpawner
extends Node3D

@export var enemy_scene_path: String = "res://scenes/level/enemy.tscn"
@export var wave_size: int = 5
@export var spawn_cooldown: float = 1.5

var _spawn_timer: Timer
var _spawned_count: int = 0
var _wave_active: bool = false
var _wave_number: int = 0

# Cached packed scene — loaded once per wave start, reused every spawn tick.
# Avoids repeated disk I/O and resource deserialization during active gameplay.
var _cached_enemy_scene: PackedScene = null

# Used to generate unique node names across multiple spawners.
static var _global_enemy_counter: int = 0

func _ready() -> void:
	print("WaveSpawner: _ready() called")
	add_to_group("Spawners")

	# Always create the timer so it exists when start_next_wave() is called.
	# Multiplayer may not be ready yet when _ready() runs.
	print("WaveSpawner: Setting up timer")
	_spawn_timer = Timer.new()
	_spawn_timer.one_shot = false
	_spawn_timer.wait_time = spawn_cooldown
	_spawn_timer.timeout.connect(_on_spawn_tick)
	add_child(_spawn_timer)
	print("WaveSpawner: Timer setup complete, wait_time=", _spawn_timer.wait_time)

# ---------- Public API ----------

func start_next_wave() -> void:
	print("WaveSpawner: start_next_wave() called")
	if not multiplayer.is_server():
		print("WaveSpawner: Not server, aborting")
		return
	if _wave_active:
		push_warning("WaveSpawner: Wave already in progress on '%s'." % name)
		return

	# Ensure timer exists (handles case where _ready() ran before multiplayer was ready).
	if not _spawn_timer:
		print("WaveSpawner: Timer missing, creating on-demand")
		_spawn_timer = Timer.new()
		_spawn_timer.one_shot = false
		_spawn_timer.wait_time = spawn_cooldown
		_spawn_timer.timeout.connect(_on_spawn_tick)
		add_child(_spawn_timer)

	# Load the scene ONCE here instead of on every spawn tick.
	_cached_enemy_scene = load(enemy_scene_path) as PackedScene
	if not _cached_enemy_scene:
		push_error("WaveSpawner: Could not load enemy scene at '%s'." % enemy_scene_path)
		return

	_wave_number    += 1
	_spawned_count   = 0
	_wave_active     = true

	print("WaveSpawner [%s]: Starting wave %d (size: %d)" % [name, _wave_number, wave_size])
	print("WaveSpawner: Starting timer with wait_time=", _spawn_timer.wait_time)
	_spawn_timer.start()

func stop_spawning() -> void:
	_wave_active = false
	_cached_enemy_scene = null   # Release reference; let GC reclaim memory.
	if _spawn_timer:
		_spawn_timer.stop()

func get_wave_number() -> int:
	return _wave_number

# ---------- Spawn Tick ----------

func _on_spawn_tick() -> void:
	if not multiplayer.is_server():
		_spawn_timer.stop()
		return
	print("WaveSpawner: _on_spawn_tick() fired, _wave_active=", _wave_active, " _spawned_count=", _spawned_count)
	if not _wave_active:
		print("WaveSpawner: Wave not active, stopping timer")
		_spawn_timer.stop()
		return

	if _spawned_count >= wave_size:
		_wave_active = false
		_spawn_timer.stop()
		print("WaveSpawner [%s]: Wave %d complete." % [name, _wave_number])
		return

	_spawn_enemy()

func _spawn_enemy() -> void:
	if not multiplayer.is_server():
		return

	# Locate the container node that the MultiplayerSpawner is watching.
	# spawn_path on EnemySpawner is set to get_path() of the Level root in
	# level.gd::_setup_enemy_spawner(), so enemies become direct children of Level.
	var level: Node3D = get_tree().current_scene

	# Increment the global counter BEFORE instantiation so the name is
	# embedded at construction time, before any network traffic is sent.
	_global_enemy_counter += 1
	var enemy_name: String = "Enemy_%d" % _global_enemy_counter

	# --- Step 1: Instantiate (server only, not yet in the tree) ---
	var enemy: CharacterBody3D = _cached_enemy_scene.instantiate() as CharacterBody3D
	if not enemy:
		push_error("WaveSpawner: _cached_enemy_scene.instantiate() returned null.")
		return

	# Set the unique name before entering the tree.
	enemy.name = enemy_name

	# --- Step 2: Enter the tree (triggers MultiplayerSpawner replication) ---
	level.add_child(enemy, true)

	# --- Step 3: Set spatial state AFTER add_child() ---
	# global_position requires is_inside_tree(); safe to access now.
	enemy.global_position = global_position  # Use the WaveSpawner's world position.

	# collision_layer/mask are baked into enemy.tscn (layer=8, mask=3),
	# so no manual override is needed here; left as an explicit assertion
	# for clarity during debugging.
	assert(enemy.collision_layer == 8, "enemy.tscn collision_layer must be 8 (layer 4)")

	# --- Step 4: Post-tree server-side setup ---
	# add_to_group must be called after add_child so it is properly propagated.
	enemy.add_to_group("Enemies")

	_spawned_count += 1
	print("WaveSpawner [%s]: Spawned %s at %s (%d/%d)" % [
		name, enemy.name, enemy.global_position, _spawned_count, wave_size
	])
