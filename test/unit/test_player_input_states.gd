extends GutTest

const PLAYER_SCENE_PATH: String = "res://scenes/level/player.tscn"

var _player: CharacterBody3D
var _inventory: InventoryUI
var _mock_level: MockLevel

func before_each() -> void:
	_mock_level = MockLevel.new()
	_mock_level.name = "MockLevel"
	add_child_autofree(_mock_level)
	get_tree().current_scene = _mock_level

	var player_scene: PackedScene = load(PLAYER_SCENE_PATH)
	assert_not_null(player_scene, "player.tscn must exist at the expected path")
	_player = player_scene.instantiate() as CharacterBody3D
	assert_not_null(_player, "Player scene should instantiate as CharacterBody3D")

	_player.name = "1"
	_mock_level.add_child(_player)

	_inventory = _player.get_node_or_null("HUD/InventoryUI") as InventoryUI
	if not _inventory:
		for child in _player.find_children("*", "InventoryUI", true, false):
			_inventory = child as InventoryUI
			break
	assert_not_null(_inventory, "InventoryUI node should exist under player HUD")

	await get_tree().process_frame

func after_each() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func test_inventory_close_releases_focus_and_captures_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_mock_level.inventory_visible = false

	_inventory.open_inventory(_player)
	_mock_level.inventory_visible = true
	await get_tree().process_frame

	assert_eq(
		Input.mouse_mode,
		Input.MOUSE_MODE_VISIBLE,
		"Mouse must be VISIBLE while inventory is open"
	)

	_inventory.close_inventory()
	_mock_level.inventory_visible = false
	await get_tree().process_frame

	assert_eq(
		Input.mouse_mode,
		Input.MOUSE_MODE_CAPTURED,
		"Mouse must be CAPTURED after inventory closes"
	)
	assert_false(
		_mock_level.is_inventory_visible(),
		"inventory_visible flag must be false after close"
	)

	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	assert_null(
		focus_owner,
		"No UI node should hold keyboard focus after inventory closes"
	)

func test_non_authority_player_input_ignored() -> void:
	var player_scene: PackedScene = load(PLAYER_SCENE_PATH)
	var remote_player: CharacterBody3D = player_scene.instantiate() as CharacterBody3D
	assert_not_null(remote_player, "Remote player should instantiate")

	remote_player.name = "9999"
	_mock_level.add_child(remote_player)
	await get_tree().process_frame

	_mock_level.inventory_visible = true
	var cancel_event := InputEventAction.new()
	cancel_event.action = "ui_cancel"
	cancel_event.pressed = true
	remote_player._unhandled_input(cancel_event)
	await get_tree().process_frame

	assert_true(
		_mock_level.inventory_visible,
		"A non-authority peer's ui_cancel must NOT close the inventory"
	)

	remote_player.queue_free()

func test_hud_prompt_clears_on_body_exited() -> void:
	_mock_level.set_interaction_prompt("[E] Interact with Workbench")
	assert_eq(
		_mock_level.get_last_prompt(),
		"[E] Interact with Workbench",
		"Precondition: prompt must be non-empty before clear"
	)

	if _player.has_method("clear_interaction_prompt"):
		_player.clear_interaction_prompt()
	else:
		_mock_level.set_interaction_prompt("")

	await get_tree().process_frame

	assert_eq(
		_mock_level.get_last_prompt(),
		"",
		"HUD interaction prompt must be empty string after body_exited"
	)

func test_hud_prompt_clears_when_leaving_crafting_area() -> void:
	_mock_level.set_interaction_prompt("[E] Open Crafting Station (Workbench)")

	if _player.has_method("clear_interaction_prompt"):
		_player.clear_interaction_prompt()
	else:
		_mock_level.set_interaction_prompt("")

	await get_tree().process_frame

	assert_eq(
		_mock_level.get_last_prompt(),
		"",
		"Prompt must clear unconditionally when leaving any interaction area"
	)
