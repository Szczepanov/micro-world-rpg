extends Node

var items: Dictionary = {}

var recipes: Dictionary = {
	"iron_sword": {
		"wood": 2,
		"iron_ore": 2
	},
	"health_potion": {
		"magic_gem": 1,
		"wood": 1
	},
	"leather_armor": {
		"wood": 3,
		"magic_gem": 1
	},
	"iron_pickaxe": {
		"wood": 2,
		"iron_ore": 3
	},
	"spiked_wall_item": {
		"wood": 3,
		"iron_ore": 1
	},
	"automated_turret_item": {
		"wood": 5,
		"iron_ore": 3
	}
}

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

	# Wood resource
	var wood = Item.new()
	wood.id = "wood"
	wood.name = "Wood"
	wood.description = "A basic crafting material gathered from trees."
	wood.item_type = Item.ItemType.MISC
	wood.rarity = Item.ItemRarity.COMMON
	wood.stackable = true
	wood.max_stack = 99
	wood.value = 5
	wood.icon = placeholder_icon
	items[wood.id] = wood

	# Iron Ore resource
	var iron_ore = Item.new()
	iron_ore.id = "iron_ore"
	iron_ore.name = "Iron Ore"
	iron_ore.description = "Raw iron ore mined from rocks."
	iron_ore.item_type = Item.ItemType.MISC
	iron_ore.rarity = Item.ItemRarity.COMMON
	iron_ore.stackable = true
	iron_ore.max_stack = 99
	iron_ore.value = 10
	iron_ore.icon = placeholder_icon
	items[iron_ore.id] = iron_ore

	# Spiked Wall item
	var spiked_wall_item = Item.new()
	spiked_wall_item.id = "spiked_wall_item"
	spiked_wall_item.name = "Spiked Wall"
	spiked_wall_item.description = "A defensive wall with sharp spikes on top."
	spiked_wall_item.item_type = Item.ItemType.MISC
	spiked_wall_item.rarity = Item.ItemRarity.COMMON
	spiked_wall_item.stackable = true
	spiked_wall_item.max_stack = 20
	spiked_wall_item.value = 15
	spiked_wall_item.icon = placeholder_icon
	items[spiked_wall_item.id] = spiked_wall_item

	# Automated Turret item
	var automated_turret_item = Item.new()
	automated_turret_item.id = "automated_turret_item"
	automated_turret_item.name = "Automated Turret"
	automated_turret_item.description = "An automated defense turret that scans and shoots enemies."
	automated_turret_item.item_type = Item.ItemType.MISC
	automated_turret_item.rarity = Item.ItemRarity.UNCOMMON
	automated_turret_item.stackable = true
	automated_turret_item.max_stack = 10
	automated_turret_item.value = 40
	automated_turret_item.icon = placeholder_icon
	items[automated_turret_item.id] = automated_turret_item


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
