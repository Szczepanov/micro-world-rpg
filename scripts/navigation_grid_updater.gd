extends NavigationRegion3D

## NavigationGridUpdater
## Attached to the NavigationRegion3D node in the level scene.
## Server-only: re-bakes the navmesh asynchronously whenever a structure is
## placed or removed via GridManager signals. A 0.5 s debounce timer ensures
## that rapid burst placements collapse into a single bake request instead of
## stacking multiple blocking operations.

# Debounce window — rapid structure changes reset this timer, collapsing all
# pending bake requests into one bake that fires after the last placement.
const DEBOUNCE_SECONDS: float = 0.5

var _debounce_timer: Timer

func _ready() -> void:
	# Only the server performs the baking logic.
	if not multiplayer.is_server():
		return

	# Build and register the owned debounce timer.
	_debounce_timer = Timer.new()
	_debounce_timer.name = "NavBakeDebounceTimer"
	_debounce_timer.wait_time = DEBOUNCE_SECONDS
	_debounce_timer.one_shot = true
	_debounce_timer.timeout.connect(_execute_bake)
	add_child(_debounce_timer)

	# Connect to GridManager placement signals.
	if GridManager.has_signal("structure_placed"):
		GridManager.structure_placed.connect(_on_structure_placed)
	if GridManager.has_signal("structure_removed"):
		GridManager.structure_removed.connect(_on_structure_removed)

	# Ensure a NavigationMesh resource exists.
	if not navigation_mesh:
		navigation_mesh = NavigationMesh.new()
		# Parse StaticBody3D collision shapes — faster and more accurate than
		# visual mesh parsing for our procedural-placement workflow.
		navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		# Values aligned to cell_size (0.25) to avoid precision warnings
		navigation_mesh.agent_height    = 1.75  # 7 * 0.25
		navigation_mesh.agent_radius    = 0.5   # 2 * 0.25
		navigation_mesh.agent_max_slope = 45.0
		navigation_mesh.agent_max_climb = 0.5   # 2 * 0.25

	# Initial bake at startup — bypass debounce, run immediately.
	_execute_bake()

# ---------- Signal Handlers ----------

func _on_structure_placed(_grid_coords: Vector3i, _structure_id: String) -> void:
	rebake_navigation_mesh()

func _on_structure_removed(_grid_coords: Vector3i) -> void:
	rebake_navigation_mesh()

# ---------- Public API ----------

## Schedules a navmesh rebake after the debounce window.
## Safe to call multiple times in quick succession — only one bake will fire.
func rebake_navigation_mesh() -> void:
	if not multiplayer.is_server():
		return
	# Restarting the timer resets the countdown, collapsing burst calls.
	_debounce_timer.start()

# ---------- Internal ----------

## Called by the debounce timer. Dispatches the actual bake to a
## NavigationServer worker thread so the main/physics thread is never blocked.
func _execute_bake() -> void:
	print("NavigationGridUpdater: Dispatching async navmesh bake on worker thread...")
	# true = run on background thread (non-blocking). This is the correct
	# argument for asynchronous baking in Godot 4.
	bake_navigation_mesh(true)
	print("NavigationGridUpdater: Async bake dispatched.")
