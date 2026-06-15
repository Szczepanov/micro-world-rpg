extends Control
class_name InventoryUI

@onready var grid_container: GridContainer = $Panel/MarginContainer/VBoxContainer/GridContainer
@onready var title_label: Label = $Panel/MarginContainer/VBoxContainer/TitleBar/Title
@onready var close_button: Button = $Panel/MarginContainer/VBoxContainer/TitleBar/CloseButton
@onready var tooltip: Control = $ItemTooltip
@onready var tooltip_label: RichTextLabel = $ItemTooltip/Panel/MarginContainer/TooltipText

var current_player: Node
var slot_ui_scene: PackedScene
var slot_uis: Array[InventorySlotUI] = []
var equipment_slots: Dictionary = {}

signal inventory_closed

func _ready():
	slot_ui_scene = preload("res://scenes/ui/inventory_slot_ui.tscn")
	grid_container.columns = 4
	close_button.pressed.connect(_on_close_pressed)
	tooltip.visible = false
	
	# Explicitly set focus mode to NONE to prevent keyboard focus capture
	focus_mode = Control.FOCUS_NONE
	
	_reconstruct_layout()
	_create_slot_uis()

func _reconstruct_layout() -> void:
	# 1. Expand Panel size
	var panel: Panel = $Panel as Panel
	if panel:
		panel.offset_left = -240.0
		panel.offset_right = 240.0
		
	# 2. Get the VBoxContainer parent of grid_container
	var vbox: VBoxContainer = grid_container.get_parent() as VBoxContainer
	
	# 3. Create HBoxContainer for side-by-side layout
	var h_split: HBoxContainer = HBoxContainer.new()
	h_split.name = "HSplitLayout"
	h_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h_split.add_theme_constant_override("separation", 15)
	
	# 4. Remove grid_container from vbox
	vbox.remove_child(grid_container)
	vbox.add_child(h_split)
	
	# 5. Create Equipment panel VBox
	var eq_vbox: VBoxContainer = VBoxContainer.new()
	eq_vbox.name = "EquipmentPanel"
	eq_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eq_vbox.size_flags_stretch_ratio = 0.8
	
	# Add title
	var eq_title: Label = Label.new()
	eq_title.text = "Equipment"
	eq_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eq_title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.1)) # gold
	eq_title.add_theme_font_size_override("font_size", 14)
	eq_vbox.add_child(eq_title)
	
	var eq_title_sep: HSeparator = HSeparator.new()
	eq_vbox.add_child(eq_title_sep)
	
	# Create GridContainer for equipment slots
	var eq_grid: GridContainer = GridContainer.new()
	eq_grid.name = "EquipmentGrid"
	eq_grid.columns = 1
	eq_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	eq_grid.add_theme_constant_override("v_separation", 10)
	eq_vbox.add_child(eq_grid)
	
	h_split.add_child(eq_vbox)
	
	# Add VSeparator
	var v_sep: VSeparator = VSeparator.new()
	h_split.add_child(v_sep)
	
	# 6. Create Backpack panel VBox
	var bp_vbox: VBoxContainer = VBoxContainer.new()
	bp_vbox.name = "BackpackPanel"
	bp_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bp_vbox.size_flags_stretch_ratio = 1.2
	
	# Add title
	var bp_title: Label = Label.new()
	bp_title.text = "Backpack"
	bp_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bp_title.add_theme_color_override("font_color", Color(0.1, 0.7, 0.9)) # cyan
	bp_title.add_theme_font_size_override("font_size", 14)
	bp_vbox.add_child(bp_title)
	
	var bp_title_sep: HSeparator = HSeparator.new()
	bp_vbox.add_child(bp_title_sep)
	
	# Add grid_container to Backpack column
	grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bp_vbox.add_child(grid_container)
	
	h_split.add_child(bp_vbox)
	
	# 7. Instantiate the equipment slots
	var slots_to_create: Array = [
		{"key": "weapon_0", "label": "Primary Weapon"},
		{"key": "weapon_1", "label": "Secondary Weapon"},
		{"key": "armor", "label": "Body Armor"}
	]
	
	for slot_info in slots_to_create:
		var slot_hbox: HBoxContainer = HBoxContainer.new()
		slot_hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
		slot_hbox.add_theme_constant_override("separation", 8)
		
		var slot_ui: InventorySlotUI = slot_ui_scene.instantiate() as InventorySlotUI
		slot_ui.custom_minimum_size = Vector2(56, 56)
		slot_ui.parent_inventory = self
		slot_ui.set_meta("is_equipment", true)
		slot_ui.set_meta("equipment_type", slot_info["key"])
		
		# Connect equipment slot signals
		slot_ui.slot_clicked.connect(_on_equipment_slot_clicked.bind(slot_info["key"]))
		slot_ui.item_hovered.connect(_on_equipment_item_hovered.bind(slot_info["key"]))
		slot_ui.item_unhovered.connect(_on_item_unhovered)
		
		slot_hbox.add_child(slot_ui)
		equipment_slots[slot_info["key"]] = slot_ui
		
		var label: Label = Label.new()
		label.text = slot_info["label"]
		label.add_theme_font_size_override("font_size", 12)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot_hbox.add_child(label)
		
		eq_grid.add_child(slot_hbox)

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

	# Update Weapon 0 Slot
	var w0_id: String = current_player.weapon_loadout[0] if "weapon_loadout" in current_player else ""
	var w0_data: InventorySlot = InventorySlot.new()
	w0_data.item_id = w0_id
	w0_data.quantity = 1 if w0_id != "" else 0
	if equipment_slots.has("weapon_0"):
		equipment_slots["weapon_0"].set_slot_data(w0_data, 0)
		_update_equipment_highlight("weapon_0", current_player.active_weapon_index == 0 if "active_weapon_index" in current_player else false)

	# Update Weapon 1 Slot
	var w1_id: String = current_player.weapon_loadout[1] if "weapon_loadout" in current_player else ""
	var w1_data: InventorySlot = InventorySlot.new()
	w1_data.item_id = w1_id
	w1_data.quantity = 1 if w1_id != "" else 0
	if equipment_slots.has("weapon_1"):
		equipment_slots["weapon_1"].set_slot_data(w1_data, 1)
		_update_equipment_highlight("weapon_1", current_player.active_weapon_index == 1 if "active_weapon_index" in current_player else false)

	# Update Armor Slot
	var arm_id: String = current_player.equipped_armor if "equipped_armor" in current_player else ""
	var arm_data: InventorySlot = InventorySlot.new()
	arm_data.item_id = arm_id
	arm_data.quantity = 1 if arm_id != "" else 0
	if equipment_slots.has("armor"):
		equipment_slots["armor"].set_slot_data(arm_data, 2)

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
			if item.item_type == Item.ItemType.WEAPON or item.item_type == Item.ItemType.TOOL:
				# Equip weapon: prioritize the active slot, but if slot 0 is empty equip there, or if slot 1 is empty equip there.
				var target_slot: int = current_player.active_weapon_index if "active_weapon_index" in current_player else 0
				if "weapon_loadout" in current_player:
					if current_player.weapon_loadout[0] == "":
						target_slot = 0
					elif current_player.weapon_loadout[1] == "" and current_player.weapon_loadout[0] != "":
						target_slot = 1
				
				if current_player.has_method("request_equip_to_slot"):
					current_player.request_equip_to_slot.rpc_id(1, item.id, "weapon", target_slot)
			elif item.item_type == Item.ItemType.ARMOR:
				if current_player.has_method("request_equip_to_slot"):
					current_player.request_equip_to_slot.rpc_id(1, item.id, "armor", 0)

func _update_equipment_highlight(slot_key: String, is_active: bool) -> void:
	var slot_ui = equipment_slots.get(slot_key)
	if slot_ui and slot_ui.background:
		if is_active:
			slot_ui.background.modulate = Color(1.5, 1.3, 0.5) # Gold highlight
		else:
			slot_ui.background.modulate = Color.WHITE

func _on_equipment_slot_clicked(slot_index: int, button: int, slot_key: String) -> void:
	if button == MOUSE_BUTTON_RIGHT and current_player:
		# Unequip on right click
		if slot_key == "weapon_0" or slot_key == "weapon_1":
			var idx: int = 0 if slot_key == "weapon_0" else 1
			if current_player.has_method("request_equip_to_slot"):
				current_player.request_equip_to_slot.rpc_id(1, "", "weapon", idx)
		elif slot_key == "armor":
			if current_player.has_method("request_equip_to_slot"):
				current_player.request_equip_to_slot.rpc_id(1, "", "armor", 0)

func _on_equipment_item_hovered(slot_index: int, item: Item, slot_key: String) -> void:
	_show_tooltip(item)

func handle_item_drop_v2(drag_data: Dictionary, target_slot_ui: InventorySlotUI) -> void:
	if not current_player:
		return

	var from_is_equipment: bool = drag_data.get("inventory_type") == "equipment"
	var target_is_equipment: bool = target_slot_ui.has_meta("is_equipment")

	# Case 1: Backpack Slot -> Backpack Slot (Normal moving/swapping)
	if not from_is_equipment and not target_is_equipment:
		var from_slot: int = int(drag_data.get("slot_index"))
		var to_slot: int = target_slot_ui.slot_index
		current_player.request_move_item.rpc_id(1, from_slot, to_slot)
		return

	# Case 2: Backpack Slot -> Equipment Slot (Equipping)
	if not from_is_equipment and target_is_equipment:
		var target_eq_type: String = str(target_slot_ui.get_meta("equipment_type"))
		var item_id: String = str(drag_data.get("item_id"))
		
		var item: Item = ItemDatabase.get_item(item_id)
		if not item:
			return
			
		if target_eq_type == "weapon_0" or target_eq_type == "weapon_1":
			if item.item_type == Item.ItemType.WEAPON or item.item_type == Item.ItemType.TOOL:
				var slot_index: int = 0 if target_eq_type == "weapon_0" else 1
				if current_player.has_method("request_equip_to_slot"):
					current_player.request_equip_to_slot.rpc_id(1, item_id, "weapon", slot_index)
		elif target_eq_type == "armor":
			if item.item_type == Item.ItemType.ARMOR:
				if current_player.has_method("request_equip_to_slot"):
					current_player.request_equip_to_slot.rpc_id(1, item_id, "armor", 0)
		return

	# Case 3: Equipment Slot -> Backpack Slot (Unequipping)
	if from_is_equipment and not target_is_equipment:
		var from_eq_type: String = str(drag_data.get("equipment_type"))
		if from_eq_type == "weapon_0" or from_eq_type == "weapon_1":
			var slot_index: int = 0 if from_eq_type == "weapon_0" else 1
			if current_player.has_method("request_equip_to_slot"):
				current_player.request_equip_to_slot.rpc_id(1, "", "weapon", slot_index)
		elif from_eq_type == "armor":
			if current_player.has_method("request_equip_to_slot"):
				current_player.request_equip_to_slot.rpc_id(1, "", "armor", 0)
		return

	# Case 4: Equipment Slot -> Equipment Slot (Swapping or moving between weapon slots)
	if from_is_equipment and target_is_equipment:
		var from_eq_type: String = str(drag_data.get("equipment_type"))
		var target_eq_type: String = str(target_slot_ui.get_meta("equipment_type"))
		
		if (from_eq_type == "weapon_0" or from_eq_type == "weapon_1") and (target_eq_type == "weapon_0" or target_eq_type == "weapon_1"):
			var from_slot_idx: int = 0 if from_eq_type == "weapon_0" else 1
			var target_slot_idx: int = 0 if target_eq_type == "weapon_0" else 1
			
			var from_val: String = current_player.weapon_loadout[from_slot_idx] if "weapon_loadout" in current_player else ""
			var target_val: String = current_player.weapon_loadout[target_slot_idx] if "weapon_loadout" in current_player else ""
			
			if current_player.has_method("request_equip_to_slot"):
				current_player.request_equip_to_slot.rpc_id(1, target_val, "weapon", from_slot_idx)
				current_player.request_equip_to_slot.rpc_id(1, from_val, "weapon", target_slot_idx)
		return

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
	close_inventory()
	inventory_closed.emit()

func open_inventory(player: Node = null):
	if player:
		current_player = player
		update_inventory_display()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close_inventory():
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# AGGRESSIVE FOCUS EVICTION: Force ALL UI elements to release focus
	var current_focus: Control = get_viewport().gui_get_focus_owner()
	if current_focus:
		current_focus.release_focus()
	
	# Force viewport to re-capture input handling
	get_viewport().set_input_as_handled()

func refresh_display():
	print("Debug: InventoryUI refresh_display called")
	update_inventory_display()

# ESC handling is centralised in player.gd's _unhandled_input() state stack.
# Do not add KEY_ESCAPE here to avoid double-consuming the event.