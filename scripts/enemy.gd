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
	_is_dead = true
	set_physics_process(false)
	if attack_timer:
		attack_timer.stop()

	# Brief visual delay then remove from tree
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		queue_free()
	)
