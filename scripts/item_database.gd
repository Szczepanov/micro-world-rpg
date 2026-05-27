extends Node

var items: Dictionary = {}

func _ready():
	_load_items()

func get_item(item_id: String) -> Item:
	return items.get(item_id)

func has_item(item_id: String) -> bool:
	return items.has(item_id)

func get_all_items() -> Dictionary:
	return items

func _load_items():
	_create_sample_items()

func _create_sample_items():
	var placeholder_icon = load("res://icon.png")

	# Basic sword
	var iron_sword = Item.new()
	iron_sword.id = "iron_sword"
	iron_sword.name = "Iron Sword"
	iron_sword.description = "A sturdy iron sword. Good for combat."
	iron_sword.item_type = Item.ItemType.WEAPON
	iron_sword.rarity = Item.ItemRarity.COMMON
	iron_sword.stackable = false
	iron_sword.value = 50
	iron_sword.icon = placeholder_icon
	items[iron_sword.id] = iron_sword

	# Health potion
	var health_potion = Item.new()
	health_potion.id = "health_potion"
	health_potion.name = "Health Potion"
	health_potion.description = "Restores health when consumed."
	health_potion.item_type = Item.ItemType.CONSUMABLE
	health_potion.rarity = Item.ItemRarity.COMMON
	health_potion.stackable = true
	health_potion.max_stack = 10
	health_potion.value = 25
	health_potion.icon = placeholder_icon
	items[health_potion.id] = health_potion

	# Leather armor
	var leather_armor = Item.new()
	leather_armor.id = "leather_armor"
	leather_armor.name = "Leather Armor"
	leather_armor.description = "Basic protection made from leather."
	leather_armor.item_type = Item.ItemType.ARMOR
	leather_armor.rarity = Item.ItemRarity.UNCOMMON
	leather_armor.stackable = false
	leather_armor.value = 75
	leather_armor.icon = placeholder_icon
	items[leather_armor.id] = leather_armor

	# Magic gem
	var magic_gem = Item.new()
	magic_gem.id = "magic_gem"
	magic_gem.name = "Magic Gem"
	magic_gem.description = "A mysterious gem that glows with inner light."
	magic_gem.item_type = Item.ItemType.MISC
	magic_gem.rarity = Item.ItemRarity.RARE
	magic_gem.stackable = true
	magic_gem.max_stack = 5
	magic_gem.value = 200
	magic_gem.icon = placeholder_icon
	items[magic_gem.id] = magic_gem

	# Pickaxe tool
	var pickaxe = Item.new()
	pickaxe.id = "iron_pickaxe"
	pickaxe.name = "Iron Pickaxe"
	pickaxe.description = "A mining tool for gathering resources."
	pickaxe.item_type = Item.ItemType.TOOL
	pickaxe.rarity = Item.ItemRarity.COMMON
	pickaxe.stackable = false
	pickaxe.value = 100
	pickaxe.icon = placeholder_icon
	items[pickaxe.id] = pickaxe

func add_item_to_database(item: Item) -> bool:
	if item.id.is_empty():
		push_error("Cannot add item with empty ID to database")
		return false

	if items.has(item.id):
		push_warning("Item with ID '" + item.id + "' already exists in database. Overwriting.")

	items[item.id] = item
	return true

func remove_item_from_database(item_id: String) -> bool:
	if items.has(item_id):
		items.erase(item_id)
		return true
	return false
