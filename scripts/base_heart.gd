## base_heart.gd
## Attach to the central structure of the base layout (StaticBody3D).
## This node IS the global loss objective. When its HealthComponent reaches 0,
## the server fires trigger_defeat() via call_local RPC to all connected peers.
class_name BaseHeart
extends StaticBody3D

@onready var health_component: HealthComponent = $HealthComponent

func _ready() -> void:
	# Register as the game objective so WaveSpawner and enemies can locate us.
	add_to_group("Objective")

	if not health_component:
		push_error("BaseHeart: HealthComponent child node is missing!")
		return

	# Only the server processes authoritative death logic.
	if multiplayer.is_server():
		health_component.died.connect(_on_core_died)

# ---------- Server-Only Logic ----------

func _on_core_died() -> void:
	# Server detected health == 0. Broadcast the defeat state to every peer.
	trigger_defeat.rpc()

# ---------- RPC: Broadcast Defeat ----------

@rpc("call_local", "reliable")
func trigger_defeat() -> void:
	# 1. Freeze every spawned enemy so the world "stops" on all clients.
	var enemies := get_tree().get_nodes_in_group("Enemies")
	for enemy in enemies:
		if enemy is Node:
			enemy.set_physics_process(false)
			enemy.set_process(false)

	# 2. Stop all wave spawners from issuing new waves.
	var spawners := get_tree().get_nodes_in_group("Spawners")
	for spawner in spawners:
		if spawner.has_method("stop_spawning"):
			spawner.stop_spawning()

	# 3. Show the defeat overlay UI on this client's viewport.
	_show_defeat_overlay()

# ---------- Defeat Overlay UI ----------

func _show_defeat_overlay() -> void:
	# Build a full-screen CanvasLayer overlay programmatically so we have no
	# scene dependency and can display it from any scene context.
	var canvas := CanvasLayer.new()
	canvas.name = "DefeatOverlay"
	canvas.layer = 128  # Render above all other game UI layers.
	get_tree().current_scene.add_child(canvas)

	# Dimmed dark backdrop
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.05, 0.75)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(backdrop)

	# Central card (glassmorphic panel)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560.0, 240.0)
	panel.offset_left   = -280.0
	panel.offset_right  =  280.0
	panel.offset_top    = -120.0
	panel.offset_bottom =  120.0

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color              = Color(0.04, 0.04, 0.10, 0.82)
	panel_style.border_color          = Color(0.55, 0.20, 0.80, 0.90)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(18)
	panel_style.shadow_color          = Color(0.55, 0.20, 0.80, 0.45)
	panel_style.shadow_size           = 24
	panel.add_theme_stylebox_override("panel", panel_style)
	canvas.add_child(panel)

	# VBox for text layout inside the card
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	# Title label — "DEFEAT"
	var title := Label.new()
	title.text = "DEFEAT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.85, 0.20, 0.20))
	title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	title.add_theme_constant_override("outline_size", 6)
	vbox.add_child(title)

	# Subtitle label
	var subtitle := Label.new()
	subtitle.text = "The Base Heart Has Been Destroyed."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.75, 0.95))
	subtitle.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.6))
	subtitle.add_theme_constant_override("outline_size", 4)
	vbox.add_child(subtitle)

	# Entrance animation: slide-in + fade-in from alpha 0
	panel.modulate.a = 0.0
	backdrop.modulate.a = 0.0

	var tween := canvas.create_tween()
	tween.set_parallel(true)
	tween.tween_property(backdrop, "modulate:a", 1.0, 0.45)
	tween.tween_property(panel, "modulate:a", 1.0, 0.55).set_delay(0.15)
	tween.tween_property(panel, "position:y", panel.position.y - 18.0, 0.55) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.15)
