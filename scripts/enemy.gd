## enemy.gd
## Server-authoritative enemy character that navigates toward the "Objective" group
## (the Base Heart). Spawned exclusively by WaveSpawner on the server.
## Position is replicated to all clients via MultiplayerSynchronizer.
class_name Enemy
extends CharacterBody3D

# --- Movement & Combat ---
@export var move_speed: float = 3.5
@export var attack_range: float = 1.8
@export var attack_damage: float = 10.0
@export var attack_interval: float = 1.0

# --- Node References ---
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var health_component: HealthComponent = $HealthComponent
@onready var attack_timer: Timer = $AttackTimer

var _target_node: Node3D = null
var _is_dead: bool = false
# Double-fire guard: HealthComponent's property setter can re-emit `died` if
# something reads current_health after it hits 0.  This flag makes _on_died
# strictly idempotent.
var _death_triggered: bool = false

const GRAVITY: float = 9.8

func _ready() -> void:
	# Ensure group membership is set (WaveSpawner also sets this before add_child,
	# but we add it here as a failsafe for manual scene placement).
	add_to_group("Enemies")

	if not multiplayer.is_server():
		# Clients only need position sync; disable all gameplay logic.
		set_physics_process(false)
		set_process(false)
		return

	# --- Server-only setup ---
	if health_component:
		health_component.died.connect(_on_died)

	if attack_timer:
		attack_timer.wait_time = attack_interval
		attack_timer.one_shot = false
		attack_timer.timeout.connect(_on_attack_timer_timeout)
		attack_timer.start()

	# Hook up the NavigationAgent path-changed callback (Godot 4.x).
	nav_agent.velocity_computed.connect(_on_velocity_computed)

	# Defer the target assignment so NavigationServer has had one frame to
	# register the agent before we request a path.
	call_deferred("_assign_pathfinding_target")

# ---------- Pathfinding Target Hook ----------

func _assign_pathfinding_target() -> void:
	var objectives := get_tree().get_nodes_in_group("Objective")
	if objectives.is_empty():
		push_warning("Enemy: No node found in group 'Objective'. Enemy will not navigate.")
		return

	_target_node = objectives[0] as Node3D
	if _target_node:
		nav_agent.target_position = _target_node.global_position

# ---------- Server Physics Loop ----------

func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	# Continuously refresh the target position so the enemy re-routes around
	# newly placed walls baked by NavigationGridUpdater.
	if _target_node and is_instance_valid(_target_node):
		nav_agent.target_position = _target_node.global_position

	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# Request the next navigation step
	if nav_agent.is_navigation_finished():
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var next_pos: Vector3 = nav_agent.get_next_path_position()
	var direction: Vector3 = (next_pos - global_position).normalized()
	var desired_velocity := Vector3(
		direction.x * move_speed,
		velocity.y,
		direction.z * move_speed
	)

	# Submit to NavigationAgent for avoidance calculations
	nav_agent.velocity = desired_velocity

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity = safe_velocity
	move_and_slide()

# ---------- Combat ----------

func _on_attack_timer_timeout() -> void:
	if _is_dead or not _target_node or not is_instance_valid(_target_node):
		return

	var dist: float = global_position.distance_to(_target_node.global_position)
	if dist <= attack_range:
		var target_health := _target_node.get_node_or_null("HealthComponent") as HealthComponent
		if target_health and target_health.current_health > 0.0:
			target_health.request_damage(attack_damage)

# ---------- Death ----------

func _on_died() -> void:
	if not multiplayer.is_server():
		return
	# Idempotency guard — prevents double-fire from the HealthComponent setter.
	if _death_triggered:
		return
	_death_triggered = true
	_is_dead = true

	# 1. Halt all server-side processing immediately.
	set_physics_process(false)
	set_process(false)

	if attack_timer:
		attack_timer.stop()

	# 2. Remove from physics layers so turrets cannot re-acquire this corpse
	#    as a target and HealthComponent won't re-trigger the died signal.
	collision_layer = 0
	collision_mask  = 0

	# 3. Cancel the active NavigationServer path query so the RVO agent
	#    is de-registered cleanly before the node leaves the tree.
	if nav_agent and is_instance_valid(nav_agent):
		nav_agent.target_position = global_position  # Cancel in-flight path request.

	# 4. Use a child Timer (owned by self) for the death delay.
	#    This is automatically freed if the node is externally freed first,
	#    preventing the dangling-lambda crash that SceneTreeTimer causes.
	var death_timer := Timer.new()
	death_timer.name      = "DeathCleanupTimer"
	death_timer.wait_time = 0.5
	death_timer.one_shot  = true
	add_child(death_timer)
	death_timer.timeout.connect(_deferred_free)
	death_timer.start()

func _deferred_free() -> void:
	# Final safety check in case something freed us before the timer fired.
	if not is_instance_valid(self):
		return
	queue_free()
