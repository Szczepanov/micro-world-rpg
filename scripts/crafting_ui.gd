extends Control
class_name CraftingUI

@onready var recipe_list_container: VBoxContainer = $Panel/MarginContainer/VBoxContainer/ContentSplit/RecipeListScroll/RecipeListContainer
@onready var title_label: Label = $Panel/MarginContainer/VBoxContainer/TitleBar/Title
@onready var close_button: Button = $Panel/MarginContainer/VBoxContainer/TitleBar/CloseButton

# Detail panel elements
@onready var detail_panel: VBoxContainer = $Panel/MarginContainer/VBoxContainer/ContentSplit/DetailPanel
@onready var item_name_label: Label = $Panel/MarginContainer/VBoxContainer/ContentSplit/DetailPanel/ItemName
@onready var item_description_label: RichTextLabel = $Panel/MarginContainer/VBoxContainer/ContentSplit/DetailPanel/ItemDescription
@onready var ingredients_container: VBoxContainer = $Panel/MarginContainer/VBoxContainer/ContentSplit/DetailPanel/IngredientsContainer
@onready var craft_button: Button = $Panel/MarginContainer/VBoxContainer/ContentSplit/DetailPanel/CraftButton

var current_player: Node = null
var selected_recipe_id: String = ""

signal crafting_closed

func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)
	craft_button.pressed.connect(_on_craft_pressed)
	detail_panel.visible = false
	visible = false
	
	# Explicitly set focus mode to NONE to prevent keyboard focus capture
	focus_mode = Control.FOCUS_NONE

func open_crafting(player: Node) -> void:
	current_player = player
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_populate_recipes()
	
	# Select first recipe by default if available
	if ItemDatabase.recipes.size() > 0:
		var first_recipe = ItemDatabase.recipes.keys()[0]
		_on_recipe_selected(first_recipe)
	else:
		detail_panel.visible = false

func close_crafting() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# AGGRESSIVE FOCUS EVICTION: Force ALL UI elements to release focus
	var current_focus: Control = get_viewport().gui_get_focus_owner()
	if current_focus:
		current_focus.release_focus()
	
	# Force viewport to re-capture input handling
	get_viewport().set_input_as_handled()
	
	crafting_closed.emit()

func refresh_display() -> void:
	if visible and selected_recipe_id != "":
		_on_recipe_selected(selected_recipe_id)

func _populate_recipes() -> void:
	# Clear existing list items
	for child in recipe_list_container.get_children():
		child.queue_free()
		
	for recipe_id in ItemDatabase.recipes:
		var item = ItemDatabase.get_item(recipe_id)
		if not item:
			continue
			
		var button = Button.new()
		button.text = item.name
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 45)
		
		# Add a bit of visual flair to buttons
		button.flat = false
		
		# Connect pressed signal
		button.pressed.connect(func(): _on_recipe_selected(recipe_id))
		recipe_list_container.add_child(button)

func _on_recipe_selected(recipe_id: String) -> void:
	selected_recipe_id = recipe_id
	var item = ItemDatabase.get_item(recipe_id)
	if not item:
		return
		
	detail_panel.visible = true
	item_name_label.text = item.name
	item_description_label.text = "[color=#CCCCCC]%s[/color]" % item.description
	
	# Clear previous ingredients
	for child in ingredients_container.get_children():
		child.queue_free()
		
	var recipe = ItemDatabase.recipes[recipe_id]
	var can_craft = true
	
	for ing_id in recipe:
		var required_qty = recipe[ing_id]
		var actual_qty = 0
		
		if current_player and current_player.get_inventory():
			actual_qty = current_player.get_inventory().get_item_count(ing_id)
			
		var ing_item = ItemDatabase.get_item(ing_id)
		var ing_name = ing_item.name if ing_item else ing_id
		
		var h_box = HBoxContainer.new()
		var label_name = Label.new()
		label_name.text = ing_name
		label_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var label_qty = Label.new()
		label_qty.text = "%d / %d" % [actual_qty, required_qty]
		
		# Color code status
		if actual_qty >= required_qty:
			label_qty.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2)) # Green
		else:
			label_qty.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2)) # Red
			can_craft = false
			
		h_box.add_child(label_name)
		h_box.add_child(label_qty)
		ingredients_container.add_child(h_box)
		
	craft_button.disabled = not can_craft

func _on_craft_pressed() -> void:
	if selected_recipe_id == "" or not current_player:
		return
		
	print("CraftingUI: Requesting to craft ", selected_recipe_id)
	current_player.request_craft.rpc_id(1, selected_recipe_id)

func _on_close_pressed() -> void:
	close_crafting()

# ESC handling is centralised in player.gd's _unhandled_input() state stack.
# Do not add KEY_ESCAPE here to avoid double-consuming the event.
