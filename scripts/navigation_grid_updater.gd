extends NavigationRegion3D

func _ready() -> void:
	# Only the server performs the baking logic
	if multiplayer.is_server():
		# Connect to GridManager placement signals
		if GridManager.has_signal("structure_placed"):
			GridManager.structure_placed.connect(_on_structure_placed)
		if GridManager.has_signal("structure_removed"):
			GridManager.structure_removed.connect(_on_structure_removed)
		
		# Ensure a NavigationMesh resource exists
		if not navigation_mesh:
			navigation_mesh = NavigationMesh.new()
			# Optimize: parse StaticBody3D collision shape colliders instead of heavy visual meshes
			navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
			# Standard Agent navigation sizing
			navigation_mesh.agent_height = 1.7
			navigation_mesh.agent_radius = 0.4
			navigation_mesh.agent_max_slope = 45.0
			navigation_mesh.agent_max_climb = 0.3
			
		# Do an initial bake to map out static scene terrain/boundaries
		rebake_navigation_mesh()

func _on_structure_placed(_grid_coords: Vector3i, _structure_id: String) -> void:
	rebake_navigation_mesh()

func _on_structure_removed(_grid_coords: Vector3i) -> void:
	rebake_navigation_mesh()

func rebake_navigation_mesh() -> void:
	if not multiplayer.is_server():
		return
		
	print("NavigationGridUpdater: Starting server-side navigation mesh rebake...")
	# Trigger asynchronous background bake of the navigation region as requested
	bake_navigation_mesh(false)
	print("NavigationGridUpdater: Navigation mesh bake triggered.")
