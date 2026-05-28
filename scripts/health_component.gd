class_name HealthComponent
extends Node

signal health_changed(new_health: float, max_health: float)
signal died

@export var max_health: float = 100.0
@export var current_health: float:
	set(val):
		var old_health := current_health
		current_health = clamp(val, 0.0, max_health)
		if current_health != old_health:
			health_changed.emit(current_health, max_health)
			if current_health == 0.0 and multiplayer.is_server():
				died.emit()

func _ready() -> void:
	current_health = max_health
	if multiplayer.is_server():
		_setup_synchronizer()

func _setup_synchronizer() -> void:
	var synchronizer := MultiplayerSynchronizer.new()
	synchronizer.name = "MultiplayerSynchronizer"
	
	var config := SceneReplicationConfig.new()
	
	# Sync current_health
	var hp_path := NodePath(".:current_health")
	config.add_property(hp_path)
	config.property_set_replication_mode(hp_path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	
	# Sync max_health
	var max_hp_path := NodePath(".:max_health")
	config.add_property(max_hp_path)
	config.property_set_replication_mode(max_hp_path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	
	synchronizer.replication_config = config
	add_child(synchronizer)

@rpc("any_peer", "call_local", "reliable")
func request_damage(amount: float) -> void:
	if not multiplayer.is_server():
		return
	current_health = clamp(current_health - amount, 0.0, max_health)

@rpc("any_peer", "call_local", "reliable")
func request_healing(amount: float) -> void:
	if not multiplayer.is_server():
		return
	current_health = clamp(current_health + amount, 0.0, max_health)
