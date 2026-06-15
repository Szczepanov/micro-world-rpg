extends Control
class_name MultiplayerChatUI

@onready var message: LineEdit = $Panel/MarginContainer/VBoxContainer/HBoxContainer/Message
@onready var send: Button = $Panel/MarginContainer/VBoxContainer/HBoxContainer/Send
@onready var chat: TextEdit = $Panel/MarginContainer/VBoxContainer/Chat

signal message_sent(message_text: String)

var chat_visible: bool = false

func _ready() -> void:
	send.pressed.connect(_on_send_pressed)
	message.text_submitted.connect(func(_new_text: String) -> void: _on_send_pressed())
	clear_chat()

	# Add HUDContainer programmatically
	var hud := VBoxContainer.new()
	hud.name = "HUDContainer"
	hud.layout_mode = 1
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)

	# Add Close button dynamically next to Send
	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "X"
	close_btn.pressed.connect(toggle_chat)
	var hbox := get_node_or_null("Panel/MarginContainer/VBoxContainer/HBoxContainer")
	if hbox:
		hbox.add_child(close_btn)

	# Start with Panel closed, but HUDContainer visible
	chat_visible = false
	$Panel.visible = false
	hud.visible = true
	show()

func toggle_chat() -> void:
	chat_visible = !chat_visible
	show()
	var hud := get_node_or_null("HUDContainer") as VBoxContainer
	if chat_visible:
		$Panel.visible = true
		if hud:
			hud.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		await get_tree().process_frame
		message.grab_focus()
	else:
		$Panel.visible = false
		if hud:
			hud.visible = true
		message.text = ""
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()

func is_chat_visible() -> bool:
	return chat_visible

func _on_send_pressed() -> void:
	var message_text := message.text.strip_edges()
	if message_text.is_empty():
		toggle_chat()
		return

	message_sent.emit(message_text)
	message.text = ""
	toggle_chat()

func add_message(nick: String, msg: String) -> void:
	var time := Time.get_time_string_from_system()
	var formatted_message := "[" + time + "] " + nick + ": " + msg
	chat.text += formatted_message + "\n"
	chat.scroll_vertical = chat.get_line_count()
	_limit_chat_history()
	_add_hud_message(formatted_message)

func _add_hud_message(text: String) -> void:
	var hud := get_node_or_null("HUDContainer") as VBoxContainer
	if not hud:
		return

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 4)

	var custom_font := load("res://assets/fonts/Kurland.ttf")
	if custom_font:
		lbl.add_theme_font_override("font", custom_font)

	hud.add_child(lbl)

	# Keep max 5 messages in HUD
	while hud.get_child_count() > 5:
		var oldest := hud.get_child(0)
		hud.remove_child(oldest)
		oldest.queue_free()

	# Automatically remove after 15 seconds
	get_tree().create_timer(15.0).timeout.connect(func() -> void:
		if is_instance_valid(lbl) and lbl.get_parent() == hud:
			hud.remove_child(lbl)
			lbl.queue_free()
	)

func _limit_chat_history() -> void:
	var lines := chat.text.split("\n")
	if lines.size() > 100:
		var start_index := lines.size() - 100
		chat.text = "\n".join(lines.slice(start_index))

func clear_chat() -> void:
	chat.text = ""

func _input(event: InputEvent) -> void:
	if chat_visible and event.is_action_pressed("ui_cancel"):
		toggle_chat()
		get_viewport().set_input_as_handled()
