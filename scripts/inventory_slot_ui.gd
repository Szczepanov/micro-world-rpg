extends Control
class_name InventorySlotUI

@onready var background: NinePatchRect = $Background
@onready var item_icon: TextureRect = $ItemIcon
@onready var quantity_label: Label = $QuantityLabel
@onready var rarity_border: NinePatchRect = $RarityBorder

var slot_index: int = 0
var inventory_data: InventorySlot
var parent_inventory: Control

signal slot_clicked(slot_index: int, button: int)
signal item_hovered(slot_index: int, item: Item)
signal item_unhovered

var RARITY_COLORS: Dictionary = {
	Item.ItemRarity.COMMON: Color.WHITE,
	Item.ItemRarity.UNCOMMON: Color.GREEN,
	Item.ItemRarity.RARE: Color.BLUE,
	Item.ItemRarity.EPIC: Color.PURPLE,
	Item.ItemRarity.LEGENDARY: Color.ORANGE
}

## Background fill color keyed to ItemType, used when no real texture is available.
const TYPE_COLORS: Dictionary = {
	Item.ItemType.WEAPON:     Color(0.698, 0.133, 0.133),  # Crimson
	Item.ItemType.ARMOR:      Color(0.275, 0.510, 0.706),  # Steel Blue
	Item.ItemType.CONSUMABLE: Color(0.133, 0.545, 0.133),  # Forest Green
	Item.ItemType.TOOL:       Color(0.545, 0.396, 0.212),  # Brown
	Item.ItemType.MISC:       Color(0.255, 0.255, 0.255),  # Dark Gray
}

## Three-character shorthand label per item ID, falling back to type abbreviation.
const ITEM_SHORTHAND: Dictionary = {
	"iron_sword":           "SWD",
	"health_potion":        "POT",
	"leather_armor":        "ARM",
	"iron_pickaxe":         "PCK",
	"wood":                 "WOD",
	"iron_ore":             "ORE",
	"magic_gem":            "GEM",
	"spiked_wall_item":     "WAL",
	"automated_turret_item":"TUR",
}

const TYPE_SHORTHAND_FALLBACK: Dictionary = {
	Item.ItemType.WEAPON:     "WPN",
	Item.ItemType.ARMOR:      "ARM",
	Item.ItemType.CONSUMABLE: "CSM",
	Item.ItemType.TOOL:       "TLO",
	Item.ItemType.MISC:       "MSC",
}

func _ready() -> void:
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	_build_prototype_overlay()
	update_display()

func set_slot_data(slot_data: InventorySlot, index: int) -> void:
	inventory_data = slot_data
	slot_index = index
	update_display()

func update_display() -> void:
	if not inventory_data or inventory_data.is_empty():
		_show_empty_slot()
	else:
		_show_item_slot()

func _show_empty_slot() -> void:
	if item_icon:
		item_icon.texture = null
	if quantity_label:
		quantity_label.visible = false
	if rarity_border:
		rarity_border.visible = false
	if background:
		background.modulate = Color.WHITE

	var proto_bg := get_node_or_null("PrototypeBG") as ColorRect
	var proto_lbl := get_node_or_null("PrototypeLabel") as Label
	if proto_bg:  proto_bg.visible  = false
	if proto_lbl: proto_lbl.visible = false

func _show_item_slot() -> void:
	var item: Item = ItemDatabase.get_item(inventory_data.item_id)
	if not item:
		_show_empty_slot()
		return

	var proto_bg:  ColorRect = get_node_or_null("PrototypeBG")  as ColorRect
	var proto_lbl: Label     = get_node_or_null("PrototypeLabel") as Label

	# Determine if we have a real texture (not the placeholder icon.png).
	var has_real_texture: bool = item.icon != null and \
		item.icon.resource_path != "res://icon.png" and \
		item.icon.resource_path != ""

	if has_real_texture:
		# Standard texture path.
		item_icon.texture = item.icon
		item_icon.visible = true
		if proto_bg:  proto_bg.visible  = false
		if proto_lbl: proto_lbl.visible = false
	else:
		# Prototype icon: hide texture, show colored background + label.
		item_icon.texture = null
		item_icon.visible = false

		if proto_bg:
			proto_bg.color   = TYPE_COLORS.get(item.item_type, Color(0.2, 0.2, 0.2))
			proto_bg.visible = true

		if proto_lbl:
			var shorthand: String = ITEM_SHORTHAND.get(
				item.id,
				TYPE_SHORTHAND_FALLBACK.get(item.item_type, "???")
			)
			proto_lbl.text    = shorthand
			proto_lbl.visible = true

	# Quantity and rarity border logic is unchanged.
	if item.stackable and inventory_data.quantity > 1:
		quantity_label.text    = str(inventory_data.quantity)
		quantity_label.visible = true
	else:
		quantity_label.visible = false

	if RARITY_COLORS.has(item.rarity):
		rarity_border.modulate = RARITY_COLORS[item.rarity]
		rarity_border.visible  = true
	else:
		rarity_border.visible = false

## Creates two overlay nodes (ColorRect + Label) to render text-based icons.
## These are children of this Control; they sit on top of item_icon.
func _build_prototype_overlay() -> void:
	var bg := ColorRect.new()
	bg.name = "PrototypeBG"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.visible = false
	add_child(bg)

	var lbl := Label.new()
	lbl.name = "PrototypeLabel"
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.visible = false
	add_child(lbl)

func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.pressed:
			slot_clicked.emit(slot_index, event.button_index)

func _on_mouse_entered():
	if inventory_data and not inventory_data.is_empty():
		var item = ItemDatabase.get_item(inventory_data.item_id)
		if item:
			item_hovered.emit(slot_index, item)

	background.modulate = Color(1.2, 1.2, 1.2)

func _on_mouse_exited():
	item_unhovered.emit()

	background.modulate = Color.WHITE

func _can_drop_data(_position: Vector2, data) -> bool:
	return data is Dictionary and data.has("slot_index") and data.has("inventory_type")

func _drop_data(_position: Vector2, data):
	if parent_inventory and parent_inventory.has_method("handle_item_drop"):
		parent_inventory.handle_item_drop(data.slot_index, slot_index, data.inventory_type)

func _get_drag_data(_position: Vector2):
	if not inventory_data or inventory_data.is_empty():
		return null

	var item = ItemDatabase.get_item(inventory_data.item_id)
	if not item:
		return null

	var preview = Control.new()
	var preview_icon = TextureRect.new()
	preview_icon.texture = item.icon
	preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_icon.size = Vector2(32, 32)
	preview.add_child(preview_icon)

	preview.modulate = Color(1, 1, 1, 0.8)
	set_drag_preview(preview)

	item_icon.modulate = Color(0.5, 0.5, 0.5)

	return {
		"slot_index": slot_index,
		"item_id": inventory_data.item_id,
		"quantity": inventory_data.quantity,
		"inventory_type": "player"  # Can be extended for different inventory types
	}

func _notification(what):
	if what == NOTIFICATION_DRAG_END:
		item_icon.modulate = Color.WHITE
