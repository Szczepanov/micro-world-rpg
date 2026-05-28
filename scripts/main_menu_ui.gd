extends Control
class_name MainMenuUI

signal host_pressed(nickname: String, skin: String)
signal join_pressed(nickname: String, skin: String, address: String)
signal quit_pressed

@onready var skin_input: LineEdit = $MainContainer/MainMenu/Option2/SkinInput
@onready var nick_input: LineEdit = $MainContainer/MainMenu/Option1/NickInput
@onready var address_input: LineEdit = $MainContainer/MainMenu/Option3/AddressInput

var error_label: Label = null

func _ready():
	pass

func _on_host_pressed():
	clear_error()
	var nickname = nick_input.text.strip_edges()
	var skin = skin_input.text.strip_edges().to_lower()
	host_pressed.emit(nickname, skin)

func _on_join_pressed():
	clear_error()
	var nickname = nick_input.text.strip_edges()
	var skin = skin_input.text.strip_edges().to_lower()
	var address = address_input.text.strip_edges()
	join_pressed.emit(nickname, skin, address)

func _on_quit_pressed():
	quit_pressed.emit()

func show_menu():
	show()

func hide_menu():
	hide()

func show_error(text: String) -> void:
	if not error_label:
		error_label = Label.new()
		error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		error_label.add_theme_color_override("font_color", Color.RED)
		error_label.add_theme_font_size_override("font_size", 24)
		var custom_font = load("res://assets/fonts/Kurland.ttf")
		if custom_font:
			error_label.add_theme_font_override("font", custom_font)
		
		var container = get_node_or_null("MainContainer")
		if container:
			container.add_child(error_label)
			container.move_child(error_label, 1)
			
	error_label.text = text
	error_label.show()

func clear_error() -> void:
	if error_label:
		error_label.hide()

func is_menu_visible() -> bool:
	return visible

func get_nickname() -> String:
	return nick_input.text.strip_edges()

func get_skin() -> String:
	return skin_input.text.strip_edges().to_lower()

func get_address() -> String:
	return address_input.text.strip_edges()
