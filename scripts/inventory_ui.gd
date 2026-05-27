extends Control
class_name InventoryUI

@onready var grid_container: GridContainer = $Panel/MarginContainer/VBoxContainer/GridContainer
@onready var title_label: Label = $Panel/MarginContainer/VBoxContainer/TitleBar/Title
@onready var close_button: Button = $Panel/MarginContainer/VBoxContainer/TitleBar/CloseButton
@onready var tooltip: Control = $ItemTooltip
@onready var tooltip_label: RichTextLabel = $ItemTooltip/Panel/MarginContainer/TooltipText

var current_player: Character
var slot_ui_scene: PackedScene
var slot_uis: Array[InventorySlotUI] = []

signal inventory_closed

func _ready():
	slot_ui_scene = preload("res://scenes/ui/inventory_slot_ui.tscn")
	grid_container.columns = 4
	close_button.pressed.connect(_on_close_pressed)
	tooltip.visible = false
	_create_slot_uis()

func _create_slot_uis():
	for child in grid_container.get_children():
		child.queue_free()
	slot_uis.clear()

	for i in range(PlayerInventory.INVENTORY_SIZE):
		var slot_ui = slot_ui_scene.instantiate() as InventorySlotUI
		slot_ui.custom_minimum_size = Vector2(64, 64)
		slot_ui.parent_inventory = self

		slot_ui.slot_clicked.connect(_on_slot_clicked)
		slot_ui.item_hovered.connect(_on_item_hovered)
		slot_ui.item_unhovered.connect(_on_item_unhovered)

		slot_ui.set_slot_data(null, i)

		grid_container.add_child(slot_ui)
		slot_uis.append(slot_ui)

func update_inventory_display():
	if not current_player or not current_player.get_inventory():
		return

	var player_inventory = current_player.get_inventory()
	print("Debug: Updating inventory display with ", player_inventory.slots.size(), " slots")
	for i in range(slot_uis.size()):
		if i < PlayerInventory.INVENTORY_SIZE:
			slot_uis[i].set_slot_data(player_inventory.get_slot(i), i)

func _on_slot_clicked(slot_index: int, button: int):
	print("Slot ", slot_index, " clicked with button ", button)

	match button:
		MOUSE_BUTTON_LEFT:
			pass
		MOUSE_BUTTON_RIGHT:
			_handle_right_click(slot_index)

func _handle_right_click(slot_index: int):
	if not current_player or not current_player.get_inventory():
		return

	var player_inventory = current_player.get_inventory()
	var slot = player_inventory.get_slot(slot_index)
	if slot and not slot.is_empty():
		var item = ItemDatabase.get_item(slot.item_id)
		if item:
			print("Right clicked on: ", item.name)
			# TODO: Show context menu or perform quick action

func _on_item_hovered(_slot_index: int, item: Item):
	_show_tooltip(item)

func _on_item_unhovered():
	_hide_tooltip()

func _show_tooltip(item: Item):
	if not item:
		return

	var tooltip_content = "[b][color=#FFD700]" + item.name + "[/color][/b]\n"
	tooltip_content += "[color=#CCCCCC]" + item.description + "[/color]\n\n"
	tooltip_content += "[color=#87CEEB]Type:[/color] " + _get_item_type_string(item.item_type) + "\n"
	tooltip_content += "[color=#FF69B4]Rarity:[/color] " + _get_rarity_string(item.rarity) + "\n"
	tooltip_content += "[color=#FFD700]Value:[/color] " + str(item.value) + " gold"

	if item.stackable:
		tooltip_content += "\n[color=#98FB98]Max Stack:[/color] " + str(item.max_stack)

	tooltip_label.text = tooltip_content
	tooltip.visible = true

	_position_tooltip_smartly()

func _hide_tooltip():
	tooltip.visible = false

func _position_tooltip_smartly():
	var mouse_pos = get_global_mouse_position()
	var tooltip_size = tooltip.size

	var viewport_size = get_viewport().get_visible_rect().size
	var tooltip_pos = mouse_pos + Vector2(10, 10)

	if tooltip_pos.x + tooltip_size.x > viewport_size.x:
		tooltip_pos.x = mouse_pos.x - tooltip_size.x - 10

	if tooltip_pos.y + tooltip_size.y > viewport_size.y:
		tooltip_pos.y = mouse_pos.y - tooltip_size.y - 10

	if tooltip_pos.x < 0:
		tooltip_pos.x = 10

	if tooltip_pos.y < 0:
		tooltip_pos.y = 10

	tooltip.global_position = tooltip_pos

func _get_item_type_string(type: Item.ItemType) -> String:
	match type:
		Item.ItemType.WEAPON: return "Weapon"
		Item.ItemType.ARMOR: return "Armor"
		Item.ItemType.CONSUMABLE: return "Consumable"
		Item.ItemType.TOOL: return "Tool"
		Item.ItemType.MISC: return "Miscellaneous"
		_: return "Unknown"

func _get_rarity_string(rarity: Item.ItemRarity) -> String:
	match rarity:
		Item.ItemRarity.COMMON: return "Common"
		Item.ItemRarity.UNCOMMON: return "Uncommon"
		Item.ItemRarity.RARE: return "Rare"
		Item.ItemRarity.EPIC: return "Epic"
		Item.ItemRarity.LEGENDARY: return "Legendary"
		_: return "Unknown"

func handle_item_drop(from_slot: int, to_slot: int, inventory_type: String):
	print("Moving item from slot ", from_slot, " to slot ", to_slot)

	if inventory_type == "player" and current_player:
		current_player.request_move_item.rpc_id(1, from_slot, to_slot)

func _on_close_pressed():
	inventory_closed.emit()
	visible = false

func open_inventory(player: Character = null):
	if player:
		current_player = player
		update_inventory_display()
	visible = true

func close_inventory():
	visible = false

func refresh_display():
	print("Debug: InventoryUI refresh_display called")
	update_inventory_display()

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE and visible:
			_on_close_pressed()
