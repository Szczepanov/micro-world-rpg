extends GutTest

var _inv: PlayerInventory

func before_each() -> void:
	_inv = PlayerInventory.new()

func test_inventory_initializes_with_correct_slot_count() -> void:
	assert_eq(
		_inv.slots.size(),
		PlayerInventory.INVENTORY_SIZE,
		"Inventory must have exactly INVENTORY_SIZE slots"
	)

func test_all_slots_empty_on_init() -> void:
	for slot in _inv.slots:
		assert_true(slot.is_empty(), "Every slot must start empty")

func test_add_item_returns_zero_remainder_when_space_available() -> void:
	var item: Item = ItemDatabase.get_item("health_potion")
	if not item:
		pending("health_potion not found in ItemDatabase - skipping")
		return

	var remaining: int = _inv.add_item(item, 3)
	assert_eq(remaining, 0, "All 3 potions must fit in an empty inventory")

func test_add_item_stacks_correctly() -> void:
	var item: Item = ItemDatabase.get_item("health_potion")
	if not item:
		pending("health_potion not found in ItemDatabase - skipping")
		return

	_inv.add_item(item, 5)
	_inv.add_item(item, 3)
	assert_eq(_inv.get_item_count("health_potion"), 8, "Stacked count must be 8")

func test_remove_item_reduces_count() -> void:
	var item: Item = ItemDatabase.get_item("health_potion")
	if not item:
		pending("health_potion not found in ItemDatabase - skipping")
		return

	_inv.add_item(item, 5)
	var removed: int = _inv.remove_item("health_potion", 2)
	assert_eq(removed, 2, "Two items must be removed")
	assert_eq(_inv.get_item_count("health_potion"), 3, "Three must remain")

func test_has_item_reflects_truth() -> void:
	var item: Item = ItemDatabase.get_item("wood")
	if not item:
		pending("wood not found in ItemDatabase - skipping")
		return

	_inv.add_item(item, 10)
	assert_true(_inv.has_item("wood", 10), "has_item(10) must be true with 10")
	assert_false(_inv.has_item("wood", 11), "has_item(11) must be false with only 10")

func test_serialise_deserialise_roundtrip() -> void:
	var item: Item = ItemDatabase.get_item("iron_ore")
	if not item:
		pending("iron_ore not found in ItemDatabase - skipping")
		return

	_inv.add_item(item, 7)
	var data: Dictionary = _inv.to_dict()

	var restored := PlayerInventory.new()
	restored.from_dict(data)

	assert_eq(
		restored.get_item_count("iron_ore"),
		7,
		"Serialise->deserialise must preserve item count exactly"
	)

func test_overflow_returns_positive_remainder() -> void:
	var sword: Item = ItemDatabase.get_item("iron_sword")
	if not sword or sword.stackable:
		pending("iron_sword not found or is stackable - skipping")
		return

	for _i in range(PlayerInventory.INVENTORY_SIZE):
		_inv.add_item(sword, 1)

	var remaining: int = _inv.add_item(sword, 1)
	assert_gt(remaining, 0, "Adding beyond capacity must return a positive remainder")
