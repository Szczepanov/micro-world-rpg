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

# Used to generate unique node names across multiple spawners.
static var _global_enemy_counter: int = 0

func _ready() -> void:
	add_to_group("Spawners")

	if not multiplayer.is_server():
		return  # Spawner logic is exclusively server-side.

	_spawn_timer = Timer.new()
	_spawn_timer.one_shot = false
	_spawn_timer.wait_time = spawn_cooldown
	_spawn_timer.timeout.connect(_on_spawn_tick)
	add_child(_spawn_timer)

# ---------- Public API ----------

func start_next_wave() -> void:
	if not multiplayer.is_server():
		return
	if _wave_active:
		push_warning("WaveSpawner: Wave already in progress on '%s'." % name)
		return

	var packed := load(enemy_scene_path) as PackedScene
	if not packed:
		push_error("WaveSpawner: Could not load enemy scene at '%s'." % enemy_scene_path)
		return

	_wave_number += 1
	_spawned_count = 0
	_wave_active = true

	print("WaveSpawner [%s]: Starting wave %d (size: %d)" % [name, _wave_number, wave_size])
	_spawn_timer.start()

func stop_spawning() -> void:
	_wave_active = false
	if _spawn_timer:
		_spawn_timer.stop()

# ---------- Spawn Tick ----------

func _on_spawn_tick() -> void:
	if not _wave_active:
		_spawn_timer.stop()
		return

	if _spawned_count >= wave_size:
		_wave_active = false
		_spawn_timer.stop()
		print("WaveSpawner [%s]: Wave %d complete." % [name, _wave_number])
		return

	_spawn_enemy()

func _spawn_enemy() -> void:
	var packed := load(enemy_scene_path) as PackedScene
	if not packed:
		push_error("WaveSpawner: Enemy scene not found — '%s'." % enemy_scene_path)
		return

	# Instantiate on the server
	var enemy: Node = packed.instantiate()

	# Assign a globally unique name so MultiplayerSpawner can track it properly
	_global_enemy_counter += 1
	enemy.name = "Enemy_%d" % _global_enemy_counter

	# Place the enemy at the spawner's world position
	if enemy is Node3D:
		(enemy as Node3D).global_position = global_position

	# Ensure the enemy is tagged in the "Enemies" physics group
	enemy.add_to_group("Enemies")

	# Set collision layer to 8 (Layer 4 in Godot's 1-indexed UI = bit 3 = value 8)
	# so the AutomatedTurret's DetectionArea (collision_mask = 8) can detect it.
	if enemy is CollisionObject3D:
		(enemy as CollisionObject3D).collision_layer = 8
		(enemy as CollisionObject3D).collision_mask  = 3  # Floor(1) + Players(2)

	# Append to the active scene so it's visible to all peers via replication
	get_tree().current_scene.add_child(enemy, true)

	_spawned_count += 1
	print("WaveSpawner [%s]: Spawned %s (%d/%d)" % [name, enemy.name, _spawned_count, wave_size])
