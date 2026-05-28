extends Control
class_name InGameMenu

# ---------------------------------------------------------------------------
# Node References
# ---------------------------------------------------------------------------
@onready var _main_panel: PanelContainer    = %MainPanel
@onready var _resume_btn: Button            = %ResumeButton
@onready var _options_btn: Button           = %OptionsButton
@onready var _leave_btn: Button             = %LeaveButton
@onready var _options_panel: PanelContainer = %OptionsPanel
@onready var _volume_slider: HSlider        = %VolumeSlider
@onready var _back_btn: Button              = %BackButton

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	# Start fully hidden; the player will toggle us via ESC
	hide()
	_options_panel.hide()

	_resume_btn.pressed.connect(_on_resume_pressed)
	_options_btn.pressed.connect(_on_options_pressed)
	_leave_btn.pressed.connect(_on_leave_pressed)
	_back_btn.pressed.connect(_on_back_pressed)
	_volume_slider.value_changed.connect(_on_volume_changed)

	# Sync slider to current master volume
	var master_bus_idx: int = AudioServer.get_bus_index("Master")
	var linear_volume: float = db_to_linear(AudioServer.get_bus_volume_db(master_bus_idx))
	_volume_slider.value = linear_volume

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Toggle the menu visibility and update mouse mode accordingly.
func toggle() -> void:
	if visible:
		_close()
	else:
		_open()

func is_open() -> bool:
	return visible

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------
func _open() -> void:
	show()
	_options_panel.hide()
	_main_panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _close() -> void:
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Release keyboard focus from UI elements to restore player movement
	var focused_node = get_viewport().gui_get_focus_owner()
	if focused_node and is_ancestor_of(focused_node):
		focused_node.release_focus()

# ---------------------------------------------------------------------------
# Button callbacks
# ---------------------------------------------------------------------------
func _on_resume_pressed() -> void:
	_close()

func _on_options_pressed() -> void:
	_main_panel.hide()
	_options_panel.show()

func _on_back_pressed() -> void:
	_options_panel.hide()
	_main_panel.show()

func _on_leave_pressed() -> void:
	# Restore cursor before any scene change
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# 1. Cleanly close the ENet connection
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	# 2. Reset network autoload state
	Network.players.clear()
	Network.is_network_active = false

	# 3. Return to the title/lobby scene (level.tscn acts as the main scene)
	get_tree().change_scene_to_file("res://scenes/level/level.tscn")

func _on_volume_changed(value: float) -> void:
	var master_bus_idx: int = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master_bus_idx, linear_to_db(value))
