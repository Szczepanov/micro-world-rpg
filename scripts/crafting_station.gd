extends Area3D
class_name CraftingStation

@export_enum("Workbench", "Anvil") var station_type: String = "Workbench"

var _prop_instance: Node3D = null

func _ready() -> void:
	# Configure Area3D collision
	# Layer: 3 (Interactable, value 4)
	# Mask: 1 (Player, value 1)
	collision_layer = 4
	collision_mask = 1
	
	# Instantiate visuals based on type
	_setup_visuals()
	
	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _setup_visuals() -> void:
	if _prop_instance:
		_prop_instance.queue_free()
		
	var scene_path = ""
	if station_type == "Workbench":
		scene_path = "res://scenes/environment/props/fantasy_props/Workbench.tscn"
	else:
		scene_path = "res://scenes/environment/props/fantasy_props/Anvil_Log.tscn"
		
	var scene = load(scene_path)
	if scene:
		_prop_instance = scene.instantiate()
		add_child(_prop_instance)
		_prop_instance.position = Vector3.ZERO
		
		# Make sure the physical model blocks movement (collision_layer = 2 (world))
		# but does not block interaction queries by itself since the Area3D handles interaction.
		if _prop_instance is StaticBody3D:
			_prop_instance.collision_layer = 2
			_prop_instance.collision_mask = 0
		else:
			# If it's a generic node, check if it has a StaticBody3D child
			for child in _prop_instance.get_children():
				if child is StaticBody3D:
					child.collision_layer = 2
					child.collision_mask = 0

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("is_multiplayer_authority") and body.is_multiplayer_authority() and "active_crafting_station" in body:
		print("Player entered crafting zone of type: ", station_type)
		body.active_crafting_station = self

func _on_body_exited(body: Node3D) -> void:
	if body.has_method("is_multiplayer_authority") and body.is_multiplayer_authority() and "active_crafting_station" in body:
		print("Player exited crafting zone")
		if body.active_crafting_station == self:
			body.active_crafting_station = null
		if body.has_method("clear_interaction_prompt"):
			body.clear_interaction_prompt()
		
		# Close crafting UI if it was open for this player
		var level = get_tree().current_scene
		if level and level.has_method("close_crafting_ui_if_open"):
			level.close_crafting_ui_if_open()

func open_crafting_ui(player: Node) -> void:
	var level = get_tree().current_scene
	if level and level.has_method("toggle_crafting"):
		level.toggle_crafting(self)