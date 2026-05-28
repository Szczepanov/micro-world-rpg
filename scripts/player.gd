extends CharacterBody3D
class_name Character

const NORMAL_SPEED = 6.0
const SPRINT_SPEED = 10.0
const JUMP_VELOCITY = 10

enum SkinColor { BLUE, YELLOW, GREEN, RED }

@onready var nickname: Label3D = $PlayerNick/Nickname

var player_inventory: PlayerInventory
var is_building: bool = false

# RPG Mechanics & Combat States
@onready var health_component: HealthComponent = $HealthComponent

var max_health: float:
	get:
		return health_component.max_health if health_component else 100.0
	set(val):
		if health_component:
			health_component.max_health = val

var current_health: float:
	get:
		return health_component.current_health if health_component else 100.0
	set(val):
		if health_component:
			health_component.current_health = val

var is_dead: bool = false
var _last_attacker: Character = null
var is_attacking: bool = false
var current_nick: String = "Player"
var interaction_area: Area3D = null
var active_crafting_station: Area3D = null
@onready var interaction_raycast: RayCast3D = %InteractionRayCast if has_node("%InteractionRayCast") else null

@export_category("Objects")
@export var _body: Node3D = null
@export var _spring_arm_offset: Node3D = null

@export_category("Modular Outfits")
@export var outfits_dir: String = "res://assets/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits/"
@export var textures_dir: String = "res://assets/Modular Character Outfits - Fantasy[Standard]/Textures/"
@export var main_skeleton: Skeleton3D = null

@export_category("Skin Colors")
@export var blue_texture : CompressedTexture2D
@export var yellow_texture : CompressedTexture2D
@export var green_texture : CompressedTexture2D
@export var red_texture : CompressedTexture2D

@onready var _bottom_mesh: MeshInstance3D = get_node_or_null("3DGodotRobot/RobotArmature/Skeleton3D/Bottom")
@onready var _chest_mesh: MeshInstance3D = get_node_or_null("3DGodotRobot/RobotArmature/Skeleton3D/Chest")
@onready var _face_mesh: MeshInstance3D = get_node_or_null("3DGodotRobot/RobotArmature/Skeleton3D/Face")
@onready var _limbs_head_mesh: MeshInstance3D = get_node_or_null("3DGodotRobot/RobotArmature/Skeleton3D/Llimbs and head")
@onready var animation_player: AnimationPlayer = _get_animation_player()

var _current_speed: float
var _respawn_point = Vector3(0, 5, 0)
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var can_double_jump = true
var has_double_jumped = false

func _enter_tree():
	set_multiplayer_authority(str(name).to_int())
	$SpringArmOffset/SpringArm3D/Camera3D.current = is_multiplayer_authority()

func _ready():
	var is_local_player = is_multiplayer_authority()
	var local_client_id = multiplayer.get_unique_id()

	print("Debug: Player ", name, " ready - authority: ", get_multiplayer_authority(), ", local client: ", local_client_id, ", is_local: ", is_local_player)

	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)

	_setup_input_actions()
	_setup_interaction_area()
	_setup_health_replication()
	
	if health_component:
		health_component.health_changed.connect(func(_new_health: float, _max_health: float) -> void:
			update_nickname_display()
		)
		health_component.died.connect(_on_died)

	if is_local_player:
		player_inventory = PlayerInventory.new()
		_add_starting_items()

		# Dynamically add the player placement controller for local authority player
		var controller_script = load("res://scripts/player_placement_controller.gd")
		if controller_script:
			var controller = Node.new()
			controller.set_script(controller_script)
			controller.name = "PlayerPlacementController"
			add_child(controller)
			print("Debug: PlayerPlacementController attached to local player")

		# Capture the cursor for camera rotation on the local player
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif multiplayer.is_server():
		player_inventory = PlayerInventory.new()
		_add_starting_items()
		# Server peer does not own a HUD — free it to save resources
		var hud_node := get_node_or_null("HUD")
		if hud_node:
			hud_node.queue_free()
	else:
		if get_multiplayer_authority() == local_client_id:
			request_inventory_sync.rpc_id(1)
		else:
			# Remote player — no HUD needed on this client
			var hud_node := get_node_or_null("HUD")
			if hud_node:
				hud_node.queue_free()

	# Dynamically load the character model (e.g. Male_ranger) for testing/customization
	set_character_model("res://assets/Modular character outfits - fantasy/Exports/glTF/Outfits/Male_ranger.gltf")
	_sanitize_player_mesh_materials()



func _physics_process(delta):
	if not is_multiplayer_authority(): return

	if not Network.is_network_active:
		freeze()
		return

	if is_dead:
		freeze()
		return

	var current_scene = get_tree().get_current_scene()
	# Check menu visibility regardless of floor state
	if current_scene:
		var should_freeze = false
		if current_scene.has_method("is_chat_visible") and current_scene.is_chat_visible():
			should_freeze = true
		elif current_scene.has_method("is_inventory_visible") and current_scene.is_inventory_visible():
			should_freeze = true
		elif current_scene.has_method("is_crafting_visible") and current_scene.is_crafting_visible():
			should_freeze = true

		if should_freeze:
			freeze()
			return
	
	# Attack and interact are now handled in _unhandled_input to prevent input leakage

	if is_on_floor():
		can_double_jump = true
		has_double_jumped = false

		if Input.is_action_just_pressed("jump") and not is_attacking:
			velocity.y = JUMP_VELOCITY
			can_double_jump = true
			if _body and _body.has_method("play_jump_animation"):
				_body.play_jump_animation("Jump")
			else:
				_play_anim("Jump")
	else:
		velocity.y -= gravity * delta

		if can_double_jump and not has_double_jumped and Input.is_action_just_pressed("jump") and not is_attacking:
			velocity.y = JUMP_VELOCITY
			has_double_jumped = true
			can_double_jump = false
			if _body and _body.has_method("play_jump_animation"):
				_body.play_jump_animation("Jump2")
			else:
				_play_anim("Jump2")

	velocity.y -= gravity * delta

	_move()
	move_and_slide()
	if not is_attacking:
		animate_locomotion(velocity)

func _process(_delta):
	if not is_multiplayer_authority(): return
	if not Network.is_network_active:
		return
	_check_fall_and_respawn()
	_update_interaction_ui()

## Central ESC / ui_cancel conditional state stack.
## Priority (high → low): Crafting → Inventory → Chat → Build Mode → Pause Overlay
## Also handles combat actions (attack/interact) to prevent input leakage to UI
func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	var level := get_tree().get_current_scene()
	if event.is_action_pressed("ui_cancel"):
		if level and level.has_method("is_crafting_visible") and level.is_crafting_visible():
			if level.has_method("toggle_crafting"):
				level.toggle_crafting()
			get_viewport().set_input_as_handled()
			return

		if level and level.has_method("is_inventory_visible") and level.is_inventory_visible():
			if level.has_method("toggle_inventory"):
				level.toggle_inventory()
			get_viewport().set_input_as_handled()
			return

		if level and level.has_method("is_chat_visible") and level.is_chat_visible():
			if level.has_method("toggle_chat"):
				level.toggle_chat()
			get_viewport().set_input_as_handled()
			return

		if is_building:
			var controller := get_node_or_null("PlayerPlacementController") as PlayerPlacementController
			if controller and controller.has_method("toggle_build_mode"):
				controller.toggle_build_mode()
			get_viewport().set_input_as_handled()
			return

		var in_game_menu := get_node_or_null("HUD/InGameMenu") as InGameMenu
		if in_game_menu:
			in_game_menu.toggle()
		get_viewport().set_input_as_handled()
		return
	
	# Block all combat actions if mouse is visible (UI is open)
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		return
	
	# Handle attack action
	if event.is_action_pressed("attack"):
		if not is_attacking and not is_building:
			_perform_melee_attack(false)
		get_viewport().set_input_as_handled()
		return
	
	# Handle interact action
	if event.is_action_pressed("interact"):
		if not is_attacking and not is_building:
			_perform_interaction()
		get_viewport().set_input_as_handled()
		return

func freeze():
	velocity.x = 0
	velocity.z = 0
	_current_speed = 0
	if not is_attacking:
		animate_locomotion(Vector3.ZERO)

func _move() -> void:
	if is_attacking:
		velocity.x = 0
		velocity.z = 0
		return

	var _input_direction: Vector2 = Vector2.ZERO
	if is_multiplayer_authority():
		_input_direction = Input.get_vector(
			"move_left", "move_right",
			"move_forward", "move_backward"
			)

	var _direction: Vector3 = transform.basis * Vector3(_input_direction.x, 0, _input_direction.y).normalized()

	is_running()
	_direction = _direction.rotated(Vector3.UP, _spring_arm_offset.rotation.y)

	if _direction:
		velocity.x = _direction.x * _current_speed
		velocity.z = _direction.z * _current_speed
		apply_locomotion_rotation(velocity)
		return

	velocity.x = move_toward(velocity.x, 0, _current_speed)
	velocity.z = move_toward(velocity.z, 0, _current_speed)

func is_running() -> bool:
	if Input.is_action_pressed("shift"):
		_current_speed = SPRINT_SPEED
		return true
	else:
		_current_speed = NORMAL_SPEED
		return false

func _check_fall_and_respawn():
	if global_transform.origin.y < -15.0:
		_respawn()

func _respawn():
	global_transform.origin = _respawn_point
	velocity = Vector3.ZERO

@rpc("any_peer", "reliable")
func change_nick(new_nick: String):
	current_nick = new_nick
	update_nickname_display()

func set_nickname(new_nick: String):
	current_nick = new_nick
	update_nickname_display()

func update_nickname_display():
	if nickname:
		nickname.text = current_nick + " (" + str(current_health) + "/" + str(max_health) + " HP)"

func get_texture_from_name(skin_color: SkinColor) -> CompressedTexture2D:
	match skin_color:
		SkinColor.BLUE: return blue_texture
		SkinColor.GREEN: return green_texture
		SkinColor.RED: return red_texture
		SkinColor.YELLOW: return yellow_texture
		_: return blue_texture

@rpc("any_peer", "reliable")
func set_player_skin(skin_name: SkinColor) -> void:
	var texture = get_texture_from_name(skin_name)

	set_mesh_texture(_bottom_mesh, texture)
	set_mesh_texture(_chest_mesh, texture)
	set_mesh_texture(_face_mesh, texture)
	set_mesh_texture(_limbs_head_mesh, texture)

func set_mesh_texture(mesh_instance: MeshInstance3D, texture: CompressedTexture2D) -> void:
	if mesh_instance:
		for s in range(mesh_instance.get_surface_count()):
			var material := mesh_instance.get_surface_override_material(s)
			if not material and mesh_instance.mesh:
				material = mesh_instance.mesh.surface_get_material(s)
			if material and material is StandardMaterial3D:
				var new_material := material.duplicate(true) as StandardMaterial3D
				new_material.resource_local_to_scene = true
				new_material.albedo_texture = texture
				_configure_player_standard_material(new_material, mesh_instance.name, s)
				mesh_instance.set_surface_override_material(s, new_material)

# Inventory Network Functions - Server authoritative, client-specific
@rpc("any_peer", "call_local", "reliable")
func request_inventory_sync():
	print("Debug: request_inventory_sync called on player ", name, " (authority: ", get_multiplayer_authority(), ") by client ", multiplayer.get_remote_sender_id())

	if not multiplayer.is_server():
		return

	var requesting_client = multiplayer.get_remote_sender_id()
	if requesting_client != get_multiplayer_authority():
		push_warning("Client " + str(requesting_client) + " tried to request inventory for player " + str(get_multiplayer_authority()))
		return

	if player_inventory:
		sync_inventory_to_owner.rpc_id(requesting_client, player_inventory.to_dict())

@rpc("any_peer", "call_local", "reliable")
func sync_inventory_to_owner(inventory_data: Dictionary):
	print("Debug: sync_inventory_to_owner called on player ", name, " (authority: ", get_multiplayer_authority(), ") - local unique id: ", multiplayer.get_unique_id(), " from: ", multiplayer.get_remote_sender_id())

	if multiplayer.get_remote_sender_id() != 1:
		return

	if not is_multiplayer_authority():
		return

	if not player_inventory:
		player_inventory = PlayerInventory.new()
	player_inventory.from_dict(inventory_data)

	var level_scene = get_tree().get_current_scene()
	if level_scene:
		if is_multiplayer_authority() or get_multiplayer_authority() == multiplayer.get_unique_id():
			print("Debug: This is the local player, updating UI")
			if level_scene.has_method("update_local_inventory_display"):
				level_scene.update_local_inventory_display()
			if level_scene.has_node("InventoryUI"):
				var inventory_ui = level_scene.get_node("InventoryUI")
				if inventory_ui.visible and inventory_ui.has_method("refresh_display"):
					print("Debug: Calling refresh_display directly on InventoryUI")
					inventory_ui.refresh_display()
			if level_scene.has_node("CraftingUI"):
				var crafting_ui = level_scene.get_node("CraftingUI")
				if crafting_ui.visible and crafting_ui.has_method("refresh_display"):
					print("Debug: Calling refresh_display directly on CraftingUI")
					crafting_ui.refresh_display()
		else:
			print("Debug: Not the local player, skipping UI update")

@rpc("any_peer", "call_local", "reliable")
func request_move_item(from_slot: int, to_slot: int, quantity: int = -1):
	print("Debug: request_move_item called - from:", from_slot, " to:", to_slot, " on player ", name, " (authority: ", get_multiplayer_authority(), ") by client ", multiplayer.get_remote_sender_id())

	if not multiplayer.is_server():
		return

	var requesting_client = multiplayer.get_remote_sender_id()
	if requesting_client != get_multiplayer_authority():
		push_warning("Client " + str(requesting_client) + " tried to modify inventory for player " + str(get_multiplayer_authority()))
		return

	if not player_inventory:
		return

	if from_slot < 0 or from_slot >= PlayerInventory.INVENTORY_SIZE or to_slot < 0 or to_slot >= PlayerInventory.INVENTORY_SIZE:
		push_warning("Invalid slot indices: from=" + str(from_slot) + " to=" + str(to_slot))
		return

	var success = false
	if quantity == -1:
		success = player_inventory.move_item(from_slot, to_slot)
		if not success:
			success = player_inventory.swap_items(from_slot, to_slot)
			print("Debug: Swapped items between slots ", from_slot, " and ", to_slot)
		else:
			print("Debug: Moved item from slot ", from_slot, " to ", to_slot)
	else:
		success = player_inventory.move_item(from_slot, to_slot, quantity)
		print("Debug: Moved ", quantity, " items from slot ", from_slot, " to ", to_slot)

	if success:
		print("Debug: Move successful, syncing inventory to owner ", get_multiplayer_authority())
		var owner_id = get_multiplayer_authority()
		if owner_id != 1:
			sync_inventory_to_owner.rpc_id(owner_id, player_inventory.to_dict())
		else:
			var level_scene = get_tree().get_current_scene()
			if level_scene and level_scene.has_method("update_local_inventory_display"):
				level_scene.update_local_inventory_display()
	else:
		print("Debug: Move/swap failed")

@rpc("any_peer", "call_local", "reliable")
func request_add_item(item_id: String, quantity: int = 1):
	print("Debug: request_add_item called on player ", name, " (authority: ", get_multiplayer_authority(), ") by client ", multiplayer.get_remote_sender_id())

	if not multiplayer.is_server():
		return

	var requesting_client = multiplayer.get_remote_sender_id()
	if requesting_client != get_multiplayer_authority() and requesting_client != 1:
		push_warning("Client " + str(requesting_client) + " tried to add items to player " + str(get_multiplayer_authority()))
		return

	if not player_inventory:
		return

	if quantity <= 0:
		push_warning("Invalid quantity: " + str(quantity))
		return

	var item = ItemDatabase.get_item(item_id)
	if not item:
		push_warning("Item not found: " + item_id)
		return

	var remaining = player_inventory.add_item(item, quantity)
	var added = quantity - remaining
	print("Debug: Added ", added, " ", item_id, " to inventory (", remaining, " remaining)")

	if added > 0:
		var owner_id = get_multiplayer_authority()
		print("Debug: Syncing inventory to owner ", owner_id)
		if owner_id != 1:
			sync_inventory_to_owner.rpc_id(owner_id, player_inventory.to_dict())
		else:
			var level_scene = get_tree().get_current_scene()
			if level_scene and level_scene.has_method("update_local_inventory_display"):
				level_scene.update_local_inventory_display()

@rpc("any_peer", "call_local", "reliable")
func request_remove_item(item_id: String, quantity: int = 1):
	print("Debug: request_remove_item called on player ", name, " (authority: ", get_multiplayer_authority(), ") by client ", multiplayer.get_remote_sender_id())

	if not multiplayer.is_server():
		return

	var requesting_client = multiplayer.get_remote_sender_id()
	if requesting_client != get_multiplayer_authority():
		push_warning("Client " + str(requesting_client) + " tried to remove items from player " + str(get_multiplayer_authority()))
		return

	if not player_inventory:
		return

	if quantity <= 0:
		push_warning("Invalid quantity: " + str(quantity))
		return

	var removed = player_inventory.remove_item(item_id, quantity)

	if removed > 0:
		var owner_id = get_multiplayer_authority()
		if owner_id != 1:
			sync_inventory_to_owner.rpc_id(owner_id, player_inventory.to_dict())

@rpc("any_peer", "call_local", "reliable")
func request_craft(item_to_craft: String):
	print("Debug: request_craft called for ", item_to_craft, " on player ", name, " by client ", multiplayer.get_remote_sender_id())
	
	if not multiplayer.is_server():
		return
		
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != get_multiplayer_authority():
		push_warning("Client " + str(sender_id) + " tried to craft for player " + str(get_multiplayer_authority()))
		return
		
	if not player_inventory:
		return
		
	if not ItemDatabase.recipes.has(item_to_craft):
		push_warning("Item is not craftable: " + item_to_craft)
		return
		
	var recipe = ItemDatabase.recipes[item_to_craft]
	
	var can_craft = true
	for ing_id in recipe:
		var req_qty = recipe[ing_id]
		if not player_inventory.has_item(ing_id, req_qty):
			can_craft = false
			break
			
	if not can_craft:
		print("Server: Player does not have enough materials to craft ", item_to_craft)
		return
		
	for ing_id in recipe:
		var req_qty = recipe[ing_id]
		player_inventory.remove_item(ing_id, req_qty)
		
	var crafted_item = ItemDatabase.get_item(item_to_craft)
	if crafted_item:
		player_inventory.add_item(crafted_item, 1)
		print("Server: Crafted ", item_to_craft, " successfully for player ", sender_id)
		
	var owner_id = get_multiplayer_authority()
	if owner_id != 1:
		sync_inventory_to_owner.rpc_id(owner_id, player_inventory.to_dict())
	else:
		var level_scene = get_tree().get_current_scene()
		if level_scene and level_scene.has_method("update_local_inventory_display"):
			level_scene.update_local_inventory_display()

func get_inventory() -> PlayerInventory:
	return player_inventory

func _add_starting_items():
	if not player_inventory:
		return

	var sword = ItemDatabase.get_item("iron_sword")
	var potion = ItemDatabase.get_item("health_potion")
	var wall = ItemDatabase.get_item("spiked_wall_item")

	if sword:
		player_inventory.add_item(sword, 1)
	if potion:
		player_inventory.add_item(potion, 3)
	if wall:
		player_inventory.add_item(wall, 5)

func _setup_input_actions():
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var click_event = InputEventMouseButton.new()
		click_event.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", click_event)
		var key_event = InputEventKey.new()
		key_event.physical_keycode = KEY_F
		InputMap.action_add_event("attack", key_event)
		
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var key_event = InputEventKey.new()
		key_event.physical_keycode = KEY_E
		InputMap.action_add_event("interact", key_event)

func _setup_interaction_area():
	interaction_area = Area3D.new()
	interaction_area.name = "InteractionDetector"
	# Layer 1 (player=1) + Layer 2 (world=2) + Layer 4 (enemy=8) = 11
	interaction_area.collision_mask = 11
	interaction_area.collision_layer = 0 # Doesn't need to be detected
	
	var col_shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 2.5
	col_shape.shape = sphere
	interaction_area.add_child(col_shape)
	
	add_child(interaction_area)

func _setup_health_replication() -> void:
	var synchronizer = get_node_or_null("MultiplayerSynchronizer")
	if synchronizer:
		var config = synchronizer.replication_config
		var dead_path = NodePath(".:is_dead")
		if not config.has_property(dead_path):
			config.add_property(dead_path)
			config.property_set_replication_mode(dead_path, 1) # 1: REPLICATION_MODE_ALWAYS / CONTINUOUS

func _on_animation_finished(anim_name: String):
	if anim_name == "Attack1" or anim_name == "Sword_Attack":
		is_attacking = false

func _perform_melee_attack(is_interact: bool) -> void:
	is_attacking = true
	_play_anim("Attack1")
	# Always broadcast the swing VFX so all peers see the animation.
	play_strike_vfx.rpc()

	# Fallback timer (1.3s) to prevent getting stuck if animation_finished fails to fire
	get_tree().create_timer(1.3).timeout.connect(func():
		is_attacking = false
	)

	var target = _find_closest_target()
	if target:
		if target is HarvestableNode:
			request_harvest_hit.rpc_id(1, target.get_path())
		elif target is Character and target != self:
			request_combat_hit.rpc_id(1, target.get_path())
		elif target is Enemy:
			# NEW: Lightweight notification — no damage calculated client-side.
			request_enemy_melee_hit.rpc_id(1, target.get_path())

func _perform_interaction() -> void:
	if active_crafting_station != null:
		active_crafting_station.open_crafting_ui(self)
		return
		
	var target = null
	
	# Detect via RayCast3D first
	if interaction_raycast and interaction_raycast.is_colliding():
		target = interaction_raycast.get_collider()
		
	# Fallback to Area3D closest target
	if not target:
		target = _find_closest_target()
		
	if target:
		if target.has_method("interact"):
			# Local visual feedback swing
			is_attacking = true
			_play_anim("Attack1")
			get_tree().create_timer(1.3).timeout.connect(func():
				is_attacking = false
			)
			
			# Call interact
			target.interact(multiplayer.get_unique_id())
		elif target is HarvestableNode:
			# Legacy fallback
			_perform_melee_attack(true)

func _find_closest_target() -> Node3D:
	if not interaction_area:
		return null
		
	var bodies = interaction_area.get_overlapping_bodies()
	var closest_body: Node3D = null
	var closest_dist: float = 999.0
	
	for body in bodies:
		if body == self:
			continue
		if body is HarvestableNode and body.is_depleted:
			continue
		if "is_depleted" in body and body.is_depleted:
			continue
		if body is Character and body.is_dead:
			continue
		# Skip dead enemies (Enemy._is_dead is not exported, check collision_layer instead)
		if body is Enemy and body.collision_layer == 0:
			continue
			
		var dist = global_position.distance_to(body.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest_body = body
			
	return closest_body

func _update_interaction_ui():
	var level = get_tree().current_scene
	if not level or not level.has_method("set_interaction_prompt"):
		return
		
	if is_dead:
		level.set_interaction_prompt("You are dead. Respawning...")
		return
		
	if is_attacking:
		level.set_interaction_prompt("")
		return
		
	if active_crafting_station != null:
		level.set_interaction_prompt("[E] Open Crafting Station (" + active_crafting_station.station_type + ")")
		return
		
	var target = null
	if interaction_raycast and interaction_raycast.is_colliding():
		target = interaction_raycast.get_collider()
	if not target:
		target = _find_closest_target()
		
	if target:
		if target.has_method("interact"):
			var node_name_to_use = target.name
			if "resource_id" in target:
				node_name_to_use = target.resource_id.capitalize()
			elif "node_name" in target:
				node_name_to_use = target.node_name
				
			var health_str = ""
			if "resource_health" in target:
				health_str = " (HP: " + str(target.resource_health) + ")"
			elif "current_health" in target:
				health_str = " (HP: " + str(target.current_health) + ")"
				
			level.set_interaction_prompt("[E] Interact with " + node_name_to_use + health_str)
		elif target is HarvestableNode:
			level.set_interaction_prompt("[E] Harvest " + target.node_name + " (HP: " + str(target.current_health) + ")")
		elif target is Character:
			level.set_interaction_prompt("[Left-Click] Attack " + target.current_nick)
	else:
		level.set_interaction_prompt("")

func clear_interaction_prompt() -> void:
	var level = get_tree().current_scene
	if level and level.has_method("set_interaction_prompt"):
		level.set_interaction_prompt("")

@rpc("any_peer", "call_local", "reliable")
func request_harvest_hit(node_path: NodePath):
	if not multiplayer.is_server():
		return
		
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != get_multiplayer_authority() and sender_id != 1:
		return
		
	var node = get_node_or_null(node_path)
	if not node or not (node is HarvestableNode) or node.is_depleted:
		return
		
	var dist = global_position.distance_to(node.global_position)
	if dist > 5.0:
		return
		
	node.harvest_hit(self)

@rpc("any_peer", "call_local", "reliable")
func request_combat_hit(target_path: NodePath):
	if not multiplayer.is_server():
		return
		
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != get_multiplayer_authority() and sender_id != 1:
		return
		
	var target = get_node_or_null(target_path)
	if not target or not (target is Character) or target.is_dead or target == self:
		return
		
	var dist = global_position.distance_to(target.global_position)
	if dist > 5.0:
		return
		
	target.take_damage(20, self)

## Player melee hit request against an Enemy.
## Client sends only the node path — zero gameplay data.
## Server does all spatial validation and damage application.
@rpc("any_peer", "call_local", "reliable")
func request_enemy_melee_hit(enemy_path: NodePath) -> void:
	# ── Server-only guard ──────────────────────────────────────────────
	if not multiplayer.is_server():
		return

	# ── Sender identity check: only this player's authority peer may call ──
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != get_multiplayer_authority() and sender_id != 1:
		push_warning("Security: Peer %d tried to trigger melee for player %d" \
				% [sender_id, get_multiplayer_authority()])
		return

	# ── Resolve the enemy node from the path ──────────────────────────
	var enemy: Enemy = get_node_or_null(enemy_path) as Enemy
	if not enemy or not is_instance_valid(enemy):
		return  # Enemy was freed between RPC send and receipt.

	# ── Dead-state guard: collision_layer == 0 means _on_died() was already called ──
	if enemy.collision_layer == 0:
		return

	# ── Spatial validation: ShapeCast3D (server-side, ephemeral) ──────
	# Cast a short sphere from the server-authoritative player position
	# toward the enemy. Accept hit only if within melee range (2.5 m).
	const MELEE_REACH: float = 2.5
	var dist: float = global_position.distance_to(enemy.global_position)
	if dist > MELEE_REACH:
		push_warning("Melee rejected: dist=%.2f > reach=%.2f (player=%s)" \
				% [dist, MELEE_REACH, name])
		return

	# ── Damage application ─────────────────────────────────────────────
	const MELEE_DAMAGE: float = 20.0
	var target_health: HealthComponent = \
			enemy.get_node_or_null("HealthComponent") as HealthComponent
	if target_health and target_health.current_health > 0.0:
		target_health.request_damage(MELEE_DAMAGE)

func take_damage(amount: float, attacker: Character) -> void:
	if not multiplayer.is_server():
		return
	if is_dead:
		return
		
	_last_attacker = attacker
	play_hurt_effect.rpc()
	health_component.request_damage(amount)

@rpc("call_local", "reliable")
func play_hurt_effect() -> void:
	_play_anim("Hurt")

## Broadcast the weapon swing animation to all connected peers.
## Called by the authority client; executes locally on every peer.
## Uses unreliable transport — a dropped packet means a missed swing
## frame, not a gameplay desynced state. This is intentional.
@rpc("any_peer", "call_local", "unreliable")
func play_strike_vfx() -> void:
	# Run on all peers including the caller (call_local).
	# Only play if not already in an attack animation (prevents spam).
	if not is_attacking:
		_play_anim("Attack1")

func _on_died() -> void:
	if multiplayer.is_server():
		die(_last_attacker)
		_last_attacker = null

func die(attacker: Character) -> void:
	if not multiplayer.is_server():
		return
	is_dead = true
	
	var level = get_tree().current_scene
	if level and level.has_method("msg_rpc"):
		var attacker_name = attacker.current_nick if attacker else "Unknown"
		level.msg_rpc.rpc("System", current_nick + " was slain by " + attacker_name + "!")
		
	get_tree().create_timer(3.0).timeout.connect(func():
		respawn()
	)

func respawn():
	if not multiplayer.is_server():
		return
	is_dead = false
	current_health = max_health
	
	var level = get_tree().current_scene
	if level and level.has_method("get_spawn_point"):
		global_position = level.get_spawn_point()
	else:
		global_position = Vector3(0, 5, 0)
		
	velocity = Vector3.ZERO
	respawn_client.rpc(global_position)

@rpc("call_local", "reliable")
func respawn_client(pos: Vector3):
	global_position = pos
	velocity = Vector3.ZERO
	if is_multiplayer_authority():
		is_attacking = false
		# Re-capture cursor in case it was released while the pause menu was open
		var in_game_menu := get_node_or_null("HUD/InGameMenu")
		if in_game_menu and not in_game_menu.is_open():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# --- Modular Character Customization ---

func _find_meshes_recursive(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		_find_meshes_recursive(child, meshes)

func find_gltf_file(part_name: String, outfit_style: String) -> String:
	var dir = DirAccess.open(outfits_dir)
	if not dir:
		push_error("Cannot open outfits directory: " + outfits_dir)
		return ""
		
	# Search patterns for flexibility
	var search_patterns = [
		part_name + "_" + outfit_style,
		outfit_style + "_" + part_name,
		"Male_" + outfit_style + "_" + part_name,
		"Female_" + outfit_style + "_" + part_name,
		"Male_" + part_name + "_" + outfit_style,
		"Female_" + part_name + "_" + outfit_style,
		part_name,
		outfit_style
	]
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".gltf"):
			var base_name = file_name.get_basename()
			for pattern in search_patterns:
				if base_name.to_lower() == pattern.to_lower():
					dir.list_dir_end()
					return outfits_dir.path_join(file_name)
				if part_name.to_lower() in base_name.to_lower() and outfit_style.to_lower() in base_name.to_lower():
					dir.list_dir_end()
					return outfits_dir.path_join(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	
	# Direct fallbacks
	var direct_name = part_name + "_" + outfit_style + ".gltf"
	var direct_path = outfits_dir.path_join(direct_name)
	if FileAccess.file_exists(direct_path):
		return direct_path
		
	var direct_alt_name = outfit_style + "_" + part_name + ".gltf"
	var direct_alt_path = outfits_dir.path_join(direct_alt_name)
	if FileAccess.file_exists(direct_alt_path):
		return direct_alt_path
		
	# Try sub-folder "Modular Parts" if present
	var parts_dir_path = outfits_dir.get_base_dir().path_join("Modular Parts")
	var parts_dir = DirAccess.open(parts_dir_path)
	if parts_dir:
		parts_dir.list_dir_begin()
		file_name = parts_dir.get_next()
		while file_name != "":
			if not parts_dir.current_is_dir() and file_name.ends_with(".gltf"):
				var base_name = file_name.get_basename()
				if part_name.to_lower() in base_name.to_lower() and outfit_style.to_lower() in base_name.to_lower():
					parts_dir.list_dir_end()
					return parts_dir_path.path_join(file_name)
			file_name = parts_dir.get_next()
		parts_dir.list_dir_end()
		
	push_error("Could not find gltf file for part: %s, style: %s" % [part_name, outfit_style])
	return ""

func find_texture_file(outfit_style: String) -> String:
	var base_dir = DirAccess.open(textures_dir)
	if not base_dir:
		push_error("Cannot open textures directory: " + textures_dir)
		return ""
		
	var target_subdir = ""
	base_dir.list_dir_begin()
	var sub_name = base_dir.get_next()
	while sub_name != "":
		if base_dir.current_is_dir() and sub_name.to_lower() == outfit_style.to_lower():
			target_subdir = sub_name
			break
		sub_name = base_dir.get_next()
	base_dir.list_dir_end()
	
	if target_subdir == "":
		target_subdir = outfit_style
		
	var outfit_textures_dir = textures_dir.path_join(target_subdir)
	var dir = DirAccess.open(outfit_textures_dir)
	if not dir:
		dir = DirAccess.open(textures_dir)
		outfit_textures_dir = textures_dir
		if not dir:
			return ""
			
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var best_match = ""
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".png"):
			var lower_name = file_name.to_lower()
			if "basecolor" in lower_name or "diffuse" in lower_name or "albedo" in lower_name:
				dir.list_dir_end()
				return outfit_textures_dir.path_join(file_name)
			elif best_match == "" and not "normal" in lower_name and not "orm" in lower_name and not "roughness" in lower_name:
				best_match = file_name
		file_name = dir.get_next()
	dir.list_dir_end()
	
	if best_match != "":
		return outfit_textures_dir.path_join(best_match)
		
	dir.list_dir_begin()
	file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".png"):
			dir.list_dir_end()
			return outfit_textures_dir.path_join(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	
	return ""

func load_local_mesh(part_name: String, outfit_style: String) -> void:
	main_skeleton = _get_main_skeleton()
	if not main_skeleton:
		push_error("main_skeleton not set and cannot be auto-detected! Please assign it in the Inspector.")
		return

	var gltf_path = find_gltf_file(part_name, outfit_style)
	if gltf_path == "":
		return
		
	var texture_path = find_texture_file(outfit_style)
	if texture_path == "":
		push_warning("Could not find matching texture for outfit style: " + outfit_style)
	
	var scene = load(gltf_path)
	if not scene:
		push_error("Failed to load scene: " + gltf_path)
		return
		
	var temp_instance = scene.instantiate()
	if not temp_instance:
		push_error("Failed to instantiate scene: " + gltf_path)
		return
		
	var node_name = "Part_" + part_name
	var existing_node = main_skeleton.get_node_or_null(node_name)
	if existing_node:
		existing_node.queue_free()
		existing_node.name = "Old_" + node_name
		
	var meshes: Array[MeshInstance3D] = []
	_find_meshes_recursive(temp_instance, meshes)
	
	if meshes.is_empty():
		push_error("No MeshInstance3D found in instanced modular scene: " + gltf_path)
		temp_instance.queue_free()
		return
		
	for i in range(meshes.size()):
		var mesh_instance = meshes[i]
		mesh_instance.get_parent().remove_child(mesh_instance)
		main_skeleton.add_child(mesh_instance)
		
		if i == 0:
			mesh_instance.name = node_name
		else:
			mesh_instance.name = node_name + "_" + str(i)
			
		mesh_instance.skeleton = NodePath("..")
		mesh_instance.transform = Transform3D.IDENTITY
		mesh_instance.owner = main_skeleton.owner
		_sanitize_mesh_materials(mesh_instance)
		
		if texture_path != "":
			var texture = load(texture_path)
			if texture:
				for s in range(mesh_instance.get_surface_count()):
					var material: StandardMaterial3D = mesh_instance.get_surface_override_material(s)
					if not material:
						var mesh_material = mesh_instance.mesh.surface_get_material(s)
						if mesh_material and mesh_material is StandardMaterial3D:
							material = mesh_material.duplicate()
						else:
							material = StandardMaterial3D.new()
					
					material.albedo_texture = texture
					_configure_player_standard_material(material, mesh_instance.name, s)
					mesh_instance.set_surface_override_material(s, material)
					
	temp_instance.queue_free()
	print("Loaded modular part: ", part_name, " with style: ", outfit_style, " from: ", gltf_path)

func _get_animation_player() -> AnimationPlayer:
	if has_node("%AnimationPlayer"):
		return get_node("%AnimationPlayer") as AnimationPlayer
	var path_options = [
		"ual1_standard/AnimationPlayer",
		"UAL1_Standard/AnimationPlayer",
		"3DGodotRobot/AnimationPlayer",
		"3DGodotRobot/RobotArmature/AnimationPlayer"
	]
	for path in path_options:
		var node = get_node_or_null(path)
		if node and node is AnimationPlayer:
			return node
	if _body and "animation_player" in _body and _body.animation_player:
		return _body.animation_player
	return null

func animate_locomotion(vel: Vector3) -> void:
	if _body and _body.has_method("animate"):
		_body.animate(vel)
		return
		
	var anim_player = _get_animation_player()
	if not anim_player:
		return
		
	if not is_on_floor():
		if vel.y < 0:
			_play_anim("Fall")
		else:
			var current_anim = anim_player.current_animation
			if current_anim != "Jump" and current_anim != "Jump_Start":
				_play_anim("Jump")
		return

	if vel:
		if is_running() and is_on_floor():
			_play_anim("Sprint")
			return

		_play_anim("Run")
		return

	_play_anim("Idle")

func apply_locomotion_rotation(vel: Vector3) -> void:
	if _body:
		if _body.has_method("apply_rotation"):
			_body.apply_rotation(vel)
		else:
			var lerp_val = 0.15
			var new_rotation_y = lerp_angle(_body.rotation.y, atan2(-vel.x, -vel.z), lerp_val)
			_body.rotation.y = new_rotation_y

func _play_anim(anim_name: String) -> void:
	var anim_player_node = _get_animation_player()
	if not anim_player_node:
		return
		
	var target_anim = anim_name
	
	# Mapping table from Godot Robot animations to Quaternius UAL1_Standard animations
	var mapping = {
		"Run": "Jog_Fwd",
		"Sprint": "Sprint",
		"Idle": "Idle",
		"Jump": "Jump",
		"Jump2": "Jump",
		"Fall": "Jump",  # Fallback since UAL1 has no Fall, we use Jump
		"Attack1": "Sword_Attack",
		"Hurt": "Hit_Chest"
	}
	
	if mapping.has(anim_name):
		target_anim = mapping[anim_name]
		
	if anim_player_node.has_animation(target_anim):
		anim_player_node.play(target_anim)
	elif anim_player_node.has_animation(anim_name):
		anim_player_node.play(anim_name)
	else:
		push_warning("Animation not found: " + anim_name + " (mapped to: " + target_anim + ")")

func _get_main_skeleton() -> Skeleton3D:
	if main_skeleton:
		return main_skeleton
	if has_node("%Skeleton3D"):
		return get_node("%Skeleton3D") as Skeleton3D
	var path_options = [
		"ual1_standard/Skeleton3D",
		"UAL1_Standard/Skeleton3D",
		"3DGodotRobot/RobotArmature/Skeleton3D"
	]
	for path in path_options:
		var node = get_node_or_null(path)
		if node and node is Skeleton3D:
			return node
	return null

func _resolve_actual_path(path: String) -> String:
	if FileAccess.file_exists(path):
		return path
		
	# Try case variations or folder name corrections:
	var corrected = path.replace(
		"Modular character outfits - fantasy/Exports/glTF/Outfits/", 
		"Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits/"
	)
	if "Male_ranger.gltf" in corrected:
		corrected = corrected.replace("Male_ranger.gltf", "Male_Ranger.gltf")
		
	if FileAccess.file_exists(corrected):
		return corrected
		
	return path

func set_character_model(gltf_path: String) -> void:
	main_skeleton = _get_main_skeleton()
	if not main_skeleton:
		push_error("Cannot find main skeleton to attach model!")
		return

	# Reset skeleton Y position so feet stand correctly on the ground
	main_skeleton.position.y = 0.0

	# Resolve path (handles folder casing/naming mismatch)
	var resolved_path = _resolve_actual_path(gltf_path)

	# 1. Load the glTF scene
	var scene = load(resolved_path)
	if not scene:
		push_error("Failed to load character model: " + resolved_path)
		return
		
	# 2. Instance into memory
	var temp_instance = scene.instantiate()
	if not temp_instance:
		push_error("Failed to instantiate character model: " + resolved_path)
		return
		


	# 6. Hide default placeholder meshes (keep Mannequin visible for head/face but cut body)
	for child in main_skeleton.get_children():
		if child is MeshInstance3D:
			if child.name == "Mannequin":
				child.visible = false
			else:
				child.visible = false
				if child.name.begins_with("Part_"):
					child.queue_free()

	# 3. Locate MeshInstance3D nodes in the loaded asset
	var new_meshes: Array[MeshInstance3D] = []
	_find_meshes_recursive(temp_instance, new_meshes)
	
	if new_meshes.is_empty():
		push_error("No MeshInstance3D found in character model: " + resolved_path)
		temp_instance.queue_free()
		return
		
	# 4. Parent meshes directly to our active Skeleton3D node
	for i in range(new_meshes.size()):
		var mesh_instance = new_meshes[i]
		# Unset the owner of the instanced mesh first to avoid Godot scene tree consistency warnings
		mesh_instance.owner = null
		mesh_instance.get_parent().remove_child(mesh_instance)
		main_skeleton.add_child(mesh_instance)
		
		# 5. Set skeleton path
		mesh_instance.skeleton = NodePath("..")
		mesh_instance.transform = Transform3D.IDENTITY
		mesh_instance.owner = main_skeleton.owner
		mesh_instance.visible = true
		_sanitize_mesh_materials(mesh_instance)
			
	temp_instance.queue_free()
	print("Successfully set character model to: ", resolved_path)

func _sanitize_player_mesh_materials() -> void:
	main_skeleton = _get_main_skeleton()
	if not main_skeleton:
		return

	for child in main_skeleton.get_children():
		if child is MeshInstance3D:
			_sanitize_mesh_materials(child as MeshInstance3D)

func _sanitize_mesh_materials(mesh_instance: MeshInstance3D) -> void:
	if not mesh_instance or not mesh_instance.mesh:
		return

	for s in range(mesh_instance.mesh.get_surface_count()):
		var material: Material = mesh_instance.get_surface_override_material(s)
		if not material:
			material = mesh_instance.mesh.surface_get_material(s)
		if not material:
			continue

		var unique_material: Material = material.duplicate(true)
		if unique_material is Resource:
			(unique_material as Resource).resource_local_to_scene = true

		if unique_material is StandardMaterial3D:
			_configure_player_standard_material(unique_material as StandardMaterial3D, mesh_instance.name, s)
		elif unique_material is ShaderMaterial:
			(unique_material as ShaderMaterial).render_priority = 0

		mesh_instance.set_surface_override_material(s, unique_material)

func _configure_player_standard_material(material: StandardMaterial3D, mesh_name: String, surface_index: int = -1) -> void:
	material.no_depth_test = false
	material.render_priority = 0
	if _material_requires_transparency(mesh_name, material, surface_index):
		if material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		if material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			if material.alpha_scissor_threshold <= 0.0:
				material.alpha_scissor_threshold = 0.1
		return
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED

func _material_requires_transparency(mesh_name: String, material: StandardMaterial3D, surface_index: int = -1) -> bool:
	var lower_name := mesh_name.to_lower()
	if lower_name.contains("hair") or lower_name.contains("brow") or lower_name.contains("lash") or lower_name.contains("accent") or lower_name.contains("hood") or lower_name.contains("cap"):
		return true
	var material_name := material.resource_name.to_lower()
	if material_name.contains("hair") or material_name.contains("brow") or material_name.contains("lash") or material_name.contains("cap") or material_name.contains("hood"):
		return true
	if surface_index > 0 and (lower_name.contains("hair") or lower_name.contains("hood") or lower_name.contains("cap") or lower_name.contains("brow") or lower_name.contains("lash")):
		# Keep transparent treatment for known cutout-type mesh slots only.
		return true
	if material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH:
		return true
	if material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and material.albedo_color.a < 0.999:
		return true
	return false

func _is_mannequin_hidden_surface(material: Material, surface_index: int) -> bool:
	if surface_index == 1:
		return true
	if material is StandardMaterial3D:
		var mat_name := (material as StandardMaterial3D).resource_name.to_lower()
		return mat_name.contains("joint") or mat_name.contains("skeleton") or mat_name.contains("helper")
	return false

func _is_head_or_hair_surface(material: Material) -> bool:
	if material is StandardMaterial3D:
		var standard := material as StandardMaterial3D
		var mat_name := standard.resource_name.to_lower()
		if mat_name.contains("hair") or mat_name.contains("head") or mat_name.contains("face") or mat_name.contains("eye") or mat_name.contains("brow") or mat_name.contains("lash") or mat_name.contains("cap") or mat_name.contains("hood"):
			return true
		if standard.albedo_texture and standard.albedo_texture.resource_path != "":
			var texture_path := standard.albedo_texture.resource_path.to_lower()
			if texture_path.contains("hair") or texture_path.contains("head") or texture_path.contains("face") or texture_path.contains("eye") or texture_path.contains("cap") or texture_path.contains("hood"):
				return true
	return false

func _preserve_mannequin_surface_material(mannequin: MeshInstance3D, surface_index: int, material: Material) -> void:
	if material is StandardMaterial3D:
		var preserved := (material as StandardMaterial3D).duplicate(true) as StandardMaterial3D
		preserved.resource_local_to_scene = true
		_configure_player_standard_material(preserved, mannequin.name, surface_index)
		mannequin.set_surface_override_material(surface_index, preserved)
	elif material is ShaderMaterial:
		var preserved_shader := (material as ShaderMaterial).duplicate(true) as ShaderMaterial
		preserved_shader.resource_local_to_scene = true
		preserved_shader.render_priority = 0
		mannequin.set_surface_override_material(surface_index, preserved_shader)
func _apply_body_cut_shader(mannequin: MeshInstance3D) -> void:
	var shader = Shader.new()
	shader.code = "shader_type spatial;\n" \
		+ "render_mode depth_draw_opaque, cull_back;\n" \
		+ "uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;\n" \
		+ "uniform vec4 albedo_color : source_color = vec4(1.0);\n" \
		+ "uniform float metallic : hint_range(0.0, 1.0) = 0.0;\n" \
		+ "uniform float roughness : hint_range(0.0, 1.0) = 1.0;\n" \
		+ "uniform float cut_height = 1.48;\n" \
		+ "varying float local_y;\n" \
		+ "void vertex() {\n" \
		+ "    local_y = VERTEX.y;\n" \
		+ "}\n" \
		+ "void fragment() {\n" \
		+ "    if (local_y < cut_height) {\n" \
		+ "        discard;\n" \
		+ "    }\n" \
		+ "    vec4 tex = texture(albedo_texture, UV);\n" \
		+ "    ALBEDO = tex.rgb * albedo_color.rgb;\n" \
		+ "    METALLIC = metallic;\n" \
		+ "    ROUGHNESS = roughness;\n" \
		+ "}"

	# Load the base character skin texture to apply to the head
	var path_to_load = textures_dir.path_join("Base/T_Regular_Male_Dark_BaseColor.png") if textures_dir else ""
	if path_to_load == "" or not FileAccess.file_exists(path_to_load):
		path_to_load = "res://assets/Modular Character Outfits - Fantasy[Standard]/Textures/Base/T_Regular_Male_Dark_BaseColor.png"
		
	var skin_texture = load(path_to_load)

	for s in range(mannequin.mesh.get_surface_count() if mannequin.mesh else 0):
		var orig_mat = mannequin.get_surface_override_material(s)
		if not orig_mat:
			orig_mat = mannequin.mesh.surface_get_material(s)
		if not orig_mat:
			continue

		if _is_mannequin_hidden_surface(orig_mat, s):
			var invisible_mat = StandardMaterial3D.new()
			invisible_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
			invisible_mat.no_depth_test = false
			invisible_mat.render_priority = 0
			invisible_mat.albedo_color = Color(0, 0, 0, 0)
			mannequin.set_surface_override_material(s, invisible_mat)
			continue

		# Keep all non-primary surfaces (and explicit head/hair surfaces) untouched.
		if s != 0 or _is_head_or_hair_surface(orig_mat):
			_preserve_mannequin_surface_material(mannequin, s, orig_mat)
			continue
		
		# Apply the proper male skin texture (untinted with white albedo color)
		var orig_texture = skin_texture
		var orig_color = Color(1, 1, 1, 1) # Keep white if skin_texture is loaded
		var orig_metallic = 0.0
		var orig_roughness = 1.0
		if orig_mat and orig_mat is StandardMaterial3D:
			if not orig_texture:
				orig_texture = orig_mat.albedo_texture
				orig_color = orig_mat.albedo_color
			orig_metallic = orig_mat.metallic
			orig_roughness = orig_mat.roughness
			
		var mat = ShaderMaterial.new()
		mat.shader = shader
		mat.render_priority = 0
		if orig_texture:
			mat.set_shader_parameter("albedo_texture", orig_texture)
		mat.set_shader_parameter("albedo_color", orig_color)
		mat.set_shader_parameter("metallic", orig_metallic)
		mat.set_shader_parameter("roughness", orig_roughness)
		mat.set_shader_parameter("cut_height", 1.48) # Cut higher up to completely slice off neck joints
		mannequin.set_surface_override_material(s, mat)
