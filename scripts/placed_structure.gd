class_name PlacedStructure
extends StaticBody3D

@onready var health_component: HealthComponent = $HealthComponent

# Injectable position on grid
var grid_coords: Vector3i

var _tween: Tween

func _ready() -> void:
	if health_component:
		health_component.health_changed.connect(_on_health_changed)
		health_component.died.connect(_on_died)

func _on_health_changed(new_health: float, _max_health: float) -> void:
	_play_squash_stretch_tween()

func _on_died() -> void:
	if multiplayer.is_server():
		# Wait a brief moment to let death animation play on clients before deleting node
		get_tree().create_timer(0.4).timeout.connect(func() -> void:
			if GridManager.has_method("destroy_grid_structure"):
				GridManager.destroy_grid_structure.rpc(grid_coords)
			else:
				queue_free()
		)
	_play_destruction_tween()

func _get_anim_target() -> Node3D:
	# If there is a child node named "Visuals" or "BaseMesh", animate that. Otherwise, animate self.
	for child in get_children():
		if child is Node3D and (child.name.to_lower() == "visuals" or child.name.to_lower() == "basemesh"):
			return child
	return self

func _play_squash_stretch_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
		
	_tween = create_tween()
	var target := _get_anim_target()
	var original_scale := target.scale
	
	_tween.tween_property(target, "scale", original_scale * Vector3(1.1, 0.9, 1.1), 0.08)
	_tween.tween_property(target, "scale", original_scale * Vector3(0.95, 1.05, 0.95), 0.08)
	_tween.tween_property(target, "scale", original_scale, 0.08)

func _play_destruction_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
		
	_tween = create_tween()
	var target := _get_anim_target()
	_tween.tween_property(target, "scale", Vector3.ZERO, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
