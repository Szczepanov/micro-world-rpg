## enemy_health_bar_3d.gd
## Attach to the HealthBar3D node inside enemy.tscn.
## Reads HealthComponent.current_health and max_health (already replicated)
## and updates the foreground bar scale every frame.
## Runs on ALL peers — it is pure cosmetic, never server-authoritative.
extends Node3D

@onready var foreground: MeshInstance3D = $Foreground
@onready var background: MeshInstance3D = $Background

var _health_component: HealthComponent = null
var _camera: Camera3D = null

func _ready() -> void:
	_health_component = get_parent().get_node_or_null("HealthComponent") as HealthComponent
	if not _health_component:
		push_error("EnemyHealthBar3D: HealthComponent not found on parent.")
		queue_free()
		return
	_health_component.health_changed.connect(_on_health_changed)

func _process(_delta: float) -> void:
	# Billboard: always face the active camera.
	_camera = get_viewport().get_camera_3d()
	if _camera:
		look_at(_camera.global_position, Vector3.UP)

func _on_health_changed(new_health: float, max_health: float) -> void:
	if max_health <= 0.0:
		return
	var ratio: float = clamp(new_health / max_health, 0.0, 1.0)
	# Scale the foreground mesh on the X axis only.
	foreground.scale.x = ratio
	# Shift foreground left so it shrinks from the right edge.
	foreground.position.x = (ratio - 1.0) * 0.3  # half the full width * (ratio-1)
	# Color shift: green → yellow → red as health decreases.
	var bar_mat: StandardMaterial3D = foreground.get_surface_override_material(0)
	if bar_mat:
		bar_mat.albedo_color = Color(1.0 - ratio, ratio * 0.85, 0.05)
