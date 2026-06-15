## time_manager.gd
## Server-authoritative Day/Night Survival Cycle manager.
## Governs wave loops, toggles enemy spawner states, and synchronizes
## game states across clients without touching player or combat scripts.
class_name TimeManager
extends Node

# -----------------------------------------------------------------------------
# EXPORT VARIABLES — Replicated via MultiplayerSynchronizer
# -----------------------------------------------------------------------------
@export var is_night: bool = false
@export var current_phase_time: float = 0.0
@export var current_wave: int = 0

# -----------------------------------------------------------------------------
# CONFIGURATION CONSTANTS
# -----------------------------------------------------------------------------
const DAY_DURATION: float = 180.0  ## Seconds of daytime (gather/build phase)
const NIGHT_DURATION: float = 120.0  ## Seconds of nighttime (defend phase)

# -----------------------------------------------------------------------------
# INTERNAL STATE
# -----------------------------------------------------------------------------
var _syncronizer: MultiplayerSynchronizer
var _previous_is_night: bool = false
var _previous_phase_time: float = 0.0

# -----------------------------------------------------------------------------
# SIGNALS — For HUD integration and world state reactions
# -----------------------------------------------------------------------------
signal phase_changed(is_night_phase: bool, wave_number: int)
signal phase_time_updated(phase_time: float, max_phase_time: float, is_night_phase: bool)
signal wave_started(wave_number: int)

# -----------------------------------------------------------------------------
# GODOT LIFECYCLE
# -----------------------------------------------------------------------------
func _ready() -> void:
	_setup_synchronizer()
	_previous_is_night = is_night
	_previous_phase_time = current_phase_time


func _process(delta: float) -> void:
	# Only the server accumulates time and drives state transitions
	if not multiplayer.is_server():
		_client_process()
		return

	_server_process(delta)

# -----------------------------------------------------------------------------
# SERVER-SIDE STATE MACHINE
# -----------------------------------------------------------------------------
func _server_process(delta: float) -> void:
	current_phase_time += delta

	if not is_night:
		_server_process_day_phase()
	else:
		_server_process_night_phase()


func _server_process_day_phase() -> void:
	## Day phase: gather & build. Transition to night when day duration expires.
	if current_phase_time >= DAY_DURATION:
		_transition_to_night()


func _server_process_night_phase() -> void:
	## Night phase: defend the core. Transition to day when night duration expires.
	if current_phase_time >= NIGHT_DURATION:
		_transition_to_day()


func _transition_to_night() -> void:
	## Server-only: shift to night cycle, increment wave, trigger spawners.
	is_night = true
	current_phase_time = 0.0
	current_wave += 1

	print("TimeManager: Transitioning to NIGHT — Wave %d" % current_wave)

	# Trigger enemy spawner hub hooks
	_trigger_wave_start()

	# Emit signal for world systems (lighting, atmosphere, etc.)
	phase_changed.emit(true, current_wave)


func _transition_to_day() -> void:
	## Server-only: shift back to day cycle, stop spawners.
	is_night = false
	current_phase_time = 0.0

	print("TimeManager: Transitioning to DAY — Wave %d complete" % current_wave)

	# Stop enemy spawners
	_stop_all_spawners()

	# Emit signal for world systems
	phase_changed.emit(false, current_wave)


func _trigger_wave_start() -> void:
	## Calls SpawnerHub.start_wave(current_wave) equivalent via group iteration.
	var spawners: Array[Node] = get_tree().get_nodes_in_group("Spawners")
	if spawners.is_empty():
		push_warning("TimeManager: No WaveSpawner nodes found in 'Spawners' group.")
		return

	for spawner: Node in spawners:
		if spawner.has_method("start_next_wave"):
			spawner.start_next_wave()
			print("TimeManager: Started wave %d on spawner: %s" % [current_wave, spawner.name])

	wave_started.emit(current_wave)


func _stop_all_spawners() -> void:
	## Stops all active spawners when returning to day phase.
	var spawners: Array[Node] = get_tree().get_nodes_in_group("Spawners")
	for spawner: Node in spawners:
		if spawner.has_method("stop_spawning"):
			spawner.stop_spawning()
			print("TimeManager: Stopped spawner: %s" % spawner.name)

# -----------------------------------------------------------------------------
# CLIENT-SIDE PROCESSING
# -----------------------------------------------------------------------------
func _client_process() -> void:
	## Detect replicated state changes and emit appropriate signals.
	if is_night != _previous_is_night:
		_previous_is_night = is_night
		phase_changed.emit(is_night, current_wave)

	# Emit time update for HUD countdown display
	var max_time: float = NIGHT_DURATION if is_night else DAY_DURATION
	if abs(current_phase_time - _previous_phase_time) >= 0.1:  # Throttle updates
		_previous_phase_time = current_phase_time
		phase_time_updated.emit(current_phase_time, max_time, is_night)

# -----------------------------------------------------------------------------
# NETWORK SYNCHRONIZATION SETUP
# -----------------------------------------------------------------------------
func _setup_synchronizer() -> void:
	## Procedurally instantiate and configure MultiplayerSynchronizer.
	_syncronizer = MultiplayerSynchronizer.new()
	_syncronizer.name = "TimeSynchronizer"

	# Configure replication for exported properties
	var day_state_config: SceneReplicationConfig = SceneReplicationConfig.new()

	# Sync is_night
	var is_night_path := NodePath(".:is_night")
	day_state_config.add_property(is_night_path)
	day_state_config.property_set_replication_mode(is_night_path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)

	# Sync current_phase_time
	var phase_time_path := NodePath(".:current_phase_time")
	day_state_config.add_property(phase_time_path)
	day_state_config.property_set_replication_mode(phase_time_path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)

	# Sync current_wave
	var wave_path := NodePath(".:current_wave")
	day_state_config.add_property(wave_path)
	day_state_config.property_set_replication_mode(wave_path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)

	_syncronizer.replication_config = day_state_config
	add_child(_syncronizer)

	print("TimeManager: MultiplayerSynchronizer configured for day/night state")

# -----------------------------------------------------------------------------
# PUBLIC API — Manual control for debugging/admin
# -----------------------------------------------------------------------------
func force_start_night() -> void:
	## Server-only: immediately transition to night (debug/admin command).
	if not multiplayer.is_server():
		return
	_transition_to_night()


func force_start_day() -> void:
	## Server-only: immediately transition to day (debug/admin command).
	if not multiplayer.is_server():
		return
	_transition_to_day()


func reset_cycle() -> void:
	## Server-only: reset to day 0 (debug/admin command).
	if not multiplayer.is_server():
		return
	is_night = false
	current_phase_time = 0.0
	current_wave = 0
	_stop_all_spawners()
	phase_changed.emit(false, 0)


func get_time_remaining() -> float:
	## Returns seconds remaining in current phase.
	var max_time: float = NIGHT_DURATION if is_night else DAY_DURATION
	return max(0.0, max_time - current_phase_time)


func get_phase_display_text() -> String:
	## Returns localized phase description for HUD.
	if is_night:
		return "Night Phase: Defend the Core!"
	else:
		return "Day Phase: Gather & Build"
