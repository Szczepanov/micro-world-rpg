extends GutTest

const PLAYER_SCENE_PATH: String = "res://scenes/level/player.tscn"
const INVENTORY_SCENE_PATH: String = "res://scenes/ui/inventory_ui.tscn"

var _player: Character
var _inventory_ui: InventoryUI

func before_each() -> void:
	var player_scene: PackedScene = load(PLAYER_SCENE_PATH)
	_player = player_scene.instantiate() as Character
	get_tree().root.add_child(_player)
	_player.set_multiplayer_authority(0) # Pass security checks for RPC tests

	var inventory_scene: PackedScene = load(INVENTORY_SCENE_PATH)
	_inventory_ui = inventory_scene.instantiate() as InventoryUI
	get_tree().root.add_child(_inventory_ui)

func after_each() -> void:
	if is_instance_valid(_player):
		_player.queue_free()
	if is_instance_valid(_inventory_ui):
		_inventory_ui.queue_free()

func test_equip_weapon_to_slots() -> void:
	# Equip a weapon to slot 0
	_player.request_equip_to_slot("iron_sword", "weapon", 0)
	assert_eq(_player.weapon_loadout[0], "iron_sword", "Slot 0 should be equipped with iron_sword")

	# Equip pickaxe to slot 1
	_player.request_equip_to_slot("iron_pickaxe", "weapon", 1)
	assert_eq(_player.weapon_loadout[1], "iron_pickaxe", "Slot 1 should be equipped with iron_pickaxe")

	# Enforce type validation (rejecting consumable as weapon)
	_player.request_equip_to_slot("health_potion", "weapon", 0)
	assert_eq(_player.weapon_loadout[0], "iron_sword", "Slot 0 should remain unchanged (consumable rejected)")

func test_equip_armor_to_slot() -> void:
	# Equip armor
	_player.request_equip_to_slot("leather_armor", "armor", 0)
	assert_eq(_player.equipped_armor, "leather_armor", "Armor slot should be equipped with leather_armor")

	# Enforce type validation (rejecting sword as armor)
	_player.request_equip_to_slot("iron_sword", "armor", 0)
	assert_eq(_player.equipped_armor, "leather_armor", "Armor slot should remain unchanged (weapon rejected)")

func test_armor_damage_reduction() -> void:
	# Initial health setup
	var hp_comp = _player.health_component
	hp_comp.max_health = 100.0
	hp_comp.current_health = 100.0

	# Test 1: No armor damage
	_player.equipped_armor = ""
	_player.take_damage(20.0, null)
	assert_eq(hp_comp.current_health, 80.0, "Should take full 20 damage without armor")

	# Reset health
	hp_comp.current_health = 100.0

	# Test 2: With leather armor (25% reduction -> 15 damage instead of 20)
	_player.equipped_armor = "leather_armor"
	_player.take_damage(20.0, null)
	assert_eq(hp_comp.current_health, 85.0, "Should take only 15 damage with leather_armor equipped")

func test_ui_layout_reconstruction() -> void:
	# Verify that the equipment slots exist in the UI dictionary
	assert_true(_inventory_ui.equipment_slots.has("weapon_0"), "UI must contain weapon_0 slot")
	assert_true(_inventory_ui.equipment_slots.has("weapon_1"), "UI must contain weapon_1 slot")
	assert_true(_inventory_ui.equipment_slots.has("armor"), "UI must contain armor slot")

	# Verify metadata
	var slot_w0 = _inventory_ui.equipment_slots["weapon_0"] as InventorySlotUI
	assert_true(slot_w0.has_meta("is_equipment"), "Slot must be flagged as equipment")
	assert_eq(slot_w0.get_meta("equipment_type"), "weapon_0", "Slot type must match weapon_0")
