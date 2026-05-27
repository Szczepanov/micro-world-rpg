extends Control
class_name MultiplayerChatUI

@onready var message: LineEdit = $Panel/MarginContainer/VBoxContainer/HBoxContainer/Message
@onready var send: Button = $Panel/MarginContainer/VBoxContainer/HBoxContainer/Send
@onready var chat: TextEdit = $Panel/MarginContainer/VBoxContainer/Chat

signal message_sent(message_text: String)

var chat_visible = false

func _ready():
	send.pressed.connect(_on_send_pressed)
	message.text_submitted.connect(_on_send_pressed)
	clear_chat()
	hide()

func toggle_chat():
	chat_visible = !chat_visible
	if chat_visible:
		show()
		await get_tree().process_frame
		message.grab_focus()
	else:
		hide()
		message.text = ""
		get_viewport().set_input_as_handled()

func is_chat_visible() -> bool:
	return chat_visible

func _on_send_pressed():
	var message_text = message.text.strip_edges()
	if message_text.is_empty():
		return

	message_sent.emit(message_text)

	message.text = ""
	message.grab_focus()

func add_message(nick: String, msg: String):
	var time = Time.get_time_string_from_system()
	var formatted_message = "[" + time + "] " + nick + ": " + msg + "\n"
	chat.text += formatted_message
	chat.scroll_vertical = chat.get_line_count()
	_limit_chat_history()

func _limit_chat_history():
	var lines = chat.text.split("\n")
	if lines.size() > 100:
		var start_index = lines.size() - 100
		chat.text = "\n".join(lines.slice(start_index))

func clear_chat():
	chat.text = ""
