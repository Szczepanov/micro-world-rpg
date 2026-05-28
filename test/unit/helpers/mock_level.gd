extends Node3D
class_name MockLevel

var inventory_visible: bool = false
var crafting_visible: bool = false

var _last_prompt: String = ""

func is_inventory_visible() -> bool:
	return inventory_visible

func is_crafting_visible() -> bool:
	return crafting_visible

func is_chat_visible() -> bool:
	return false

func toggle_inventory() -> void:
	inventory_visible = !inventory_visible

func set_interaction_prompt(text: String) -> void:
	_last_prompt = text

func get_last_prompt() -> String:
	return _last_prompt
