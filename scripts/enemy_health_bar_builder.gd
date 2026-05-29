## enemy_health_bar_builder.gd
## Procedural generator helper to dynamically spawn the 3D billboard health bar
## above enemy character meshes if the node is missing from enemy.tscn.
class_name EnemyHealthBarBuilder
extends RefCounted

static func build_for(enemy: Node) -> void:
	if enemy.has_node("HealthBar3D"):
		return
		
	var bar_root := Node3D.new()
	bar_root.name = "HealthBar3D"
	# Position the health bar above the enemy's head
	bar_root.position = Vector3(0.0, 2.2, 0.0)
	
	# Create Background Mesh
	var background := MeshInstance3D.new()
	background.name = "Background"
	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(0.6, 0.08)
	background.mesh = bg_mesh
	
	# Create Background Material
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.15, 0.15, 0.15, 1.0) # Dark gray background
	bg_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	background.set_surface_override_material(0, bg_mat)
	bar_root.add_child(background)
	
	# Create Foreground Mesh
	var foreground := MeshInstance3D.new()
	foreground.name = "Foreground"
	var fg_mesh := QuadMesh.new()
	fg_mesh.size = Vector2(0.6, 0.08)
	foreground.mesh = fg_mesh
	
	# Create Foreground Material
	var fg_mat := StandardMaterial3D.new()
	fg_mat.albedo_color = Color(0.0, 0.85, 0.05, 1.0) # Initial Green
	fg_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	foreground.set_surface_override_material(0, fg_mat)
	bar_root.add_child(foreground)
	
	# Attach the controller script
	var controller_script = load("res://scripts/enemy_health_bar_3d.gd")
	if controller_script:
		bar_root.set_script(controller_script)
		
	# Add to enemy node tree
	enemy.add_child(bar_root)
	print("EnemyHealthBarBuilder: Dynamically created 3D health bar for ", enemy.name)
