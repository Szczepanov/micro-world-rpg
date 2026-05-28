class_name AutomatedTurret
extends PlacedStructure

# Configurable turret properties
@export var target_range: float = 10.0
@export var turret_damage: float = 25.0
@export var rotation_speed: float = 8.0

# Node references
@onready var detection_area: Area3D = $DetectionArea
@onready var attack_timer: Timer = $AttackTimer
@onready var turret_head: Node3D = get_node_or_null("%TurretHead")

# Network-replicated target path (used by clients for visual rotation)
var target_node_path: NodePath = NodePath()
var current_target: Node3D = null

func _ready() -> void:
	super._ready()
	
	if not turret_head:
		# Fallback to direct path search if unique name flag was stripped
		turret_head = get_node_or_null("TurretHead") or get_node_or_null("MeshInstance3D")
		if not turret_head:
			push_error("AutomatedTurret: Rotating head assembly node could not be resolved!")
	
	if multiplayer.is_server():
		# Setup detection radius shape on the server
		var col_shape = detection_area.get_node("CollisionShape3D") as CollisionShape3D
		if col_shape and col_shape.shape is SphereShape3D:
			col_shape.shape.radius = target_range
			
		# Connect the heartbeat timer and start it
		attack_timer.timeout.connect(_on_attack_timer_timeout)
		attack_timer.start()
		
		# Set up the multiplayer synchronizer for the target node path
		_setup_turret_synchronizer()

func _setup_turret_synchronizer() -> void:
	var synchronizer := MultiplayerSynchronizer.new()
	synchronizer.name = "TurretSynchronizer"
	
	var config := SceneReplicationConfig.new()
	var target_prop_path := NodePath(".:target_node_path")
	config.add_property(target_prop_path)
	config.property_set_replication_mode(target_prop_path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	
	synchronizer.replication_config = config
	add_child(synchronizer)

func _process(delta: float) -> void:
	# Update visual head rotation towards target smoothly
	_update_visual_rotation(delta)

func _update_visual_rotation(delta: float) -> void:
	if not turret_head:
		return
		
	var target: Node3D = null
	if not target_node_path.is_empty():
		target = get_node_or_null(target_node_path) as Node3D
		
	if is_instance_valid(target):
		var target_pos = target.global_position
		# Offset slightly upwards to aim at chest level rather than feet
		target_pos.y += 0.8
		
		var dist = turret_head.global_position.distance_to(target_pos)
		if dist > 0.1:
			# Calculate global target transform and slerp the basis
			var target_transform = turret_head.global_transform.looking_at(target_pos, Vector3.UP)
			var current_q = turret_head.global_transform.basis.get_rotation_quaternion()
			var target_q = target_transform.basis.get_rotation_quaternion()
			var next_q = current_q.slerp(target_q, rotation_speed * delta)
			
			var scale_backup = turret_head.scale
			turret_head.global_transform.basis = Basis(next_q)
			turret_head.scale = scale_backup
	else:
		# Return head to local neutral (forward-facing) rotation
		var current_q = turret_head.transform.basis.get_rotation_quaternion()
		var target_q = Quaternion.IDENTITY
		var next_q = current_q.slerp(target_q, rotation_speed * delta)
		
		var scale_backup = turret_head.scale
		turret_head.transform.basis = Basis(next_q)
		turret_head.scale = scale_backup

func _on_attack_timer_timeout() -> void:
	if not multiplayer.is_server():
		return
		
	# Find and lock closest valid target
	_scan_for_target()
	
	if is_instance_valid(current_target):
		# Target is valid, verify health on the server
		var target_health = current_target.get_node_or_null("HealthComponent") as HealthComponent
		if target_health and target_health.current_health > 0:
			# Deal server-authoritative damage
			target_health.request_damage(turret_damage)
			
			# Broadcast projectile/visual shoot feedback to all clients
			var aim_pos = current_target.global_position
			aim_pos.y += 0.8 # Center mass of enemy
			broadcast_shoot.rpc(aim_pos)

func _scan_for_target() -> void:
	var overlapping = detection_area.get_overlapping_bodies()
	var closest_enemy: Node3D = null
	var closest_dist: float = INF
	
	for body in overlapping:
		if not body is Node3D or body == self:
			continue
			
		# Check if body is in "Enemies" group
		if body.is_in_group("Enemies"):
			var target_health = body.get_node_or_null("HealthComponent") as HealthComponent
			if target_health and target_health.current_health > 0:
				var dist = global_position.distance_to(body.global_position)
				if dist < closest_dist:
					closest_dist = dist
					closest_enemy = body
					
	current_target = closest_enemy
	
	# Update path for client replication
	if current_target:
		target_node_path = current_target.get_path()
	else:
		target_node_path = NodePath()

@rpc("call_local", "unreliable")
func broadcast_shoot(target_position: Vector3) -> void:
	# Spawns visual laser tracer on all clients
	_spawn_shoot_effects(target_position)

func _spawn_shoot_effects(target_position: Vector3) -> void:
	# Define start position (muzzle node or top of head)
	var muzzle = turret_head.get_node_or_null("Muzzle") as Node3D
	var start_pos = muzzle.global_position if muzzle else turret_head.global_position
	
	# Create a visual tracer line
	var tracer := MeshInstance3D.new()
	var mesh_data := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	
	# Glowing red tracer material
	mat.albedo_color = Color(1.0, 0.2, 0.2, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.2)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	tracer.mesh = mesh_data
	tracer.material_override = mat
	
	get_tree().current_scene.add_child(tracer)
	
	mesh_data.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh_data.surface_add_vertex(start_pos)
	mesh_data.surface_add_vertex(target_position)
	mesh_data.surface_end()
	
	# Fade laser tracer quickly
	var tween = create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.1)
	tween.tween_callback(tracer.queue_free)
