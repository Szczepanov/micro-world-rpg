extends CharacterBody3D
class_name Character

const NORMAL_SPEED = 6.0
const SPRINT_SPEED = 10.0
const JUMP_VELOCITY = 10

enum SkinColor { BLUE, YELLOW, GREEN, RED }

@onready var nickname: Label3D = $PlayerNick/Nickname

var player_inventory: PlayerInventory

# RPG Mechanics & Combat States
@export var max_health: int = 100
@export var current_health: int = 100:
	set(val):
		current_health = val
		update_nickname_display()
@export var is_dead: bool = false
var is_attacking: bool = false
var current_nick: String = "Player"
var interaction_area: Area3D = null

@export_category("Objects")
@export var _body: Node3D = null
@export var _spring_arm_offset: Node3D = null

@export_category("Skin Colors")
@export var blue_texture : CompressedTexture2D
@export var yellow_texture : CompressedTexture2D
@export var green_texture : CompressedTexture2D
@export var red_texture : CompressedTexture2D

@onready var _bottom_mesh: MeshInstance3D = get_node("3DGodotRobot/RobotArmature/Skeleton3D/Bottom")
@onready var _chest_mesh: MeshInstance3D = get_node("3DGodotRobot/RobotArmature/Skeleton3D/Chest")
@onready var _face_mesh: MeshInstance3D = get_node("3DGodotRobot/RobotArmature/Skeleton3D/Face")
@onready var _limbs_head_mesh: MeshInstance3D = get_node("3DGodotRobot/RobotArmature/Skeleton3D/Llimbs and head")

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

	if _body and _body.animation_player:
		_body.animation_player.animation_finished.connect(_on_animation_finished)

	_setup_input_actions()
	_setup_interaction_area()
	_setup_health_replication()

	if is_local_player:
		player_inventory = PlayerInventory.new()
		_add_starting_items()
	elif multiplayer.is_server():
		player_inventory = PlayerInventory.new()
		_add_starting_items()
	else:
		if get_multiplayer_authority() == local_client_id:
			request_inventory_sync.rpc_id(1)

func _physics_process(delta):
	if not is_multiplayer_authority(): return

	if is_dead:
		freeze()
		return

	var current_scene = get_tree().get_current_scene()
	if current_scene and is_on_floor():
		var should_freeze = false
		if current_scene.has_method("is_chat_visible") and current_scene.is_chat_visible():
			should_freeze = true
		elif current_scene.has_method("is_inventory_visible") and current_scene.is_inventory_visible():
			should_freeze = true

		if should_freeze:
			freeze()
			return

	# Handle Attack & Interaction
	if not is_attacking:
		if Input.is_action_just_pressed("attack"):
			_perform_melee_attack(false)
		elif Input.is_action_just_pressed("interact"):
			_perform_melee_attack(true)

	if is_on_floor():
		can_double_jump = true
		has_double_jumped = false

		if Input.is_action_just_pressed("jump") and not is_attacking:
			velocity.y = JUMP_VELOCITY
			can_double_jump = true
			_body.play_jump_animation("Jump")
	else:
		velocity.y -= gravity * delta

		if can_double_jump and not has_double_jumped and Input.is_action_just_pressed("jump") and not is_attacking:
			velocity.y = JUMP_VELOCITY
			has_double_jumped = true
			can_double_jump = false
			_body.play_jump_animation("Jump2")

	velocity.y -= gravity * delta

	_move()
	move_and_slide()
	if not is_attacking:
		_body.animate(velocity)

func _process(_delta):
	if not is_multiplayer_authority(): return
	_check_fall_and_respawn()
	_update_interaction_ui()

func freeze():
	velocity.x = 0
	velocity.z = 0
	_current_speed = 0
	if not is_attacking:
		_body.animate(Vector3.ZERO)

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
		_body.apply_rotation(velocity)
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
		var material := mesh_instance.get_surface_override_material(0)
		if material and material is StandardMaterial3D:
			var new_material := material
			new_material.albedo_texture = texture
			mesh_instance.set_surface_override_material(0, new_material)

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

func get_inventory() -> PlayerInventory:
	return player_inventory

func _add_starting_items():
	if not player_inventory:
		return

	var sword = ItemDatabase.get_item("iron_sword")
	var potion = ItemDatabase.get_item("health_potion")

	if sword:
		player_inventory.add_item(sword, 1)
	if potion:
		player_inventory.add_item(potion, 3)

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
	# Detect world (2) and interactables (4). binary 110 = 6.
	interaction_area.collision_mask = 6
	interaction_area.collision_layer = 0 # Doesn't need to be detected
	
	var col_shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 2.5
	col_shape.shape = sphere
	interaction_area.add_child(col_shape)
	
	add_child(interaction_area)

func _setup_health_replication():
	var synchronizer = get_node_or_null("MultiplayerSynchronizer")
	if synchronizer:
		var config = synchronizer.replication_config
		var hp_path = NodePath(".:current_health")
		if not config.has_property(hp_path):
			config.add_property(hp_path)
			config.property_set_replication_mode(hp_path, 1) # 1: REPLICATION_MODE_ALWAYS / CONTINUOUS
			
		var dead_path = NodePath(".:is_dead")
		if not config.has_property(dead_path):
			config.add_property(dead_path)
			config.property_set_replication_mode(dead_path, 1) # 1: REPLICATION_MODE_ALWAYS / CONTINUOUS

func _on_animation_finished(anim_name: String):
	if anim_name == "Attack1":
		is_attacking = false

func _perform_melee_attack(is_interact: bool):
	is_attacking = true
	if _body and _body.animation_player:
		_body.animation_player.play("Attack1")
		
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
		if body is Character and body.is_dead:
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
		
	var target = _find_closest_target()
	if target:
		if target is HarvestableNode:
			level.set_interaction_prompt("[E] Harvest " + target.node_name + " (HP: " + str(target.current_health) + ")")
		elif target is Character:
			level.set_interaction_prompt("[Left-Click] Attack " + target.current_nick)
	else:
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

func take_damage(amount: int, attacker: Character):
	if not multiplayer.is_server():
		return
	if is_dead:
		return
		
	current_health = max(0, current_health - amount)
	play_hurt_effect.rpc()
	
	if current_health <= 0:
		die(attacker)

@rpc("call_local", "reliable")
func play_hurt_effect():
	if _body and _body.animation_player:
		_body.animation_player.play("Hurt")

func die(attacker: Character):
	if not multiplayer.is_server():
		return
	is_dead = true
	
	var level = get_tree().current_scene
	if level and level.has_method("msg_rpc"):
		level.msg_rpc.rpc("System", current_nick + " was slain by " + attacker.current_nick + "!")
		
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
