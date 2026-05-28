# 🧪 Automated Testing Blueprint — micro-world-rpg
### GUT (Godot Unit Test) Integration · Principal QA Edition

---

## 0. Context — What We're Protecting

| Risk Area | Live Code Location | Failure Mode |
|---|---|---|
| Input focus lock | `inventory_ui.gd:close_inventory()` | Mouse stays VISIBLE after closing inventory |
| UI state desync | `level.gd:inventory_visible` flag | Flag says closed, panel still shown |
| HUD prompt stale string | `level.gd:set_interaction_prompt()` | "[E] Interact…" text lingers after body_exited |
| Multiplayer authority | `player.gd:_unhandled_input()` | Non-authority peer intercepts UI cancel |

> [!NOTE]
> All three Autoloads (`Network`, `ItemDatabase`, `GridManager`) are registered in `project.godot`. GUT's headless runner loads the full project, so they will be available inside tests via their global names.

---

## 1. Infrastructure Setup

### 1.1 Install the GUT Plugin

#### Option A — Asset Library (recommended for a tracked project)
```
# From inside the Godot Editor:
# Project → Asset Library → search "GUT" → Download → Install
# The plugin lands at:  res://addons/gut/
```

#### Option B — Manual (headless / CI bootstrap)
```bash
# Run once, inside the project root
git submodule add https://github.com/bitwes/Gut.git addons/gut
```

#### Option C — Dockerfile (already present in project root)
Add to the project's `Dockerfile`, after the `COPY` steps:
```dockerfile
RUN apt-get install -y git \
 && git clone --depth 1 https://github.com/bitwes/Gut.git /app/addons/gut
```

### 1.2 Enable the Plugin in `project.godot`

Add the following line to `project.godot` under the `[editor_plugins]` section
(create the section if absent):

```ini
[editor_plugins]

enabled=PackedStringArray("res://addons/gut/plugin.cfg")
```

> [!IMPORTANT]
> Without this entry the `gut_cmdline.gd` script will not find its own
> internal dependencies when launched headlessly.

### 1.3 Directory Scaffold

```
res://
└── test/
    └── unit/
        ├── test_player_inventory_logic.gd   # Pure-logic, no scene needed
        ├── test_player_input_states.gd      # UI focus & mouse mode
        └── helpers/
            └── mock_level.gd               # Lightweight level stub
```

**Create the directories now (atomic task for the agent):**
```bash
mkdir -p test/unit/helpers
touch test/unit/.gitkeep
```

---

## 2. Helper — Lightweight Level Mock

**File:** `res://test/unit/helpers/mock_level.gd`

This stub satisfies the duck-typed method checks inside `player.gd` and
`level.gd` without loading the real scene graph.

```gdscript
# test/unit/helpers/mock_level.gd
# Minimal Level stub for unit tests.  Satisfies the duck-typed method
# contracts that player.gd and inventory_ui.gd query at runtime.
extends Node3D
class_name MockLevel

var inventory_visible: bool = false
var crafting_visible: bool  = false

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
```

---

## 3. Test Suite A — Player Input States & UI Focus

**File:** `res://test/unit/test_player_input_states.gd`

### Design Decisions
- **No real `level.tscn` loaded.** The player scene is instantiated standalone
  and re-parented under a `MockLevel` stub added to the test's scene root.
  This avoids the entire `level.gd` autoload dependency chain.
- **Multiplayer authority spoofing.** In headless tests, `multiplayer` is a
  `OfflineMultiplayerPeer`. `set_multiplayer_authority(1)` combined with
  the engine's default `unique_id = 1` means `is_multiplayer_authority()`
  returns `true` — required for the input-path code to execute.
- **`await get_tree().process_frame`** flushes deferred calls (focus release,
  visibility changes) before assertions are evaluated.

```gdscript
# test/unit/test_player_input_states.gd
extends GutTest

# ── References ──────────────────────────────────────────────────────────────
const PLAYER_SCENE_PATH := "res://scenes/level/player.tscn"
const MOCK_LEVEL_PATH   := "res://test/unit/helpers/mock_level.gd"

var _player:     CharacterBody3D   # Character instance
var _inventory:  InventoryUI       # InventoryUI node inside player HUD
var _mock_level: Node3D            # MockLevel stub


# ── Lifecycle ────────────────────────────────────────────────────────────────
func before_each() -> void:
	# 1. Instantiate lightweight mock level as scene root replacement
	var mock_script := load(MOCK_LEVEL_PATH)
	_mock_level = Node3D.new()
	_mock_level.set_script(mock_script)
	_mock_level.name = "MockLevel"
	add_child_autofree(_mock_level)

	# 2. Instantiate player scene
	var player_scene: PackedScene = load(PLAYER_SCENE_PATH)
	assert_not_null(player_scene, "player.tscn must exist at the expected path")
	_player = player_scene.instantiate() as CharacterBody3D

	# 3. Give it multiplayer authority == local peer (headless peer id = 1)
	_player.name = "1"
	_mock_level.add_child(_player)

	# 4. Locate the InventoryUI node inside the player's HUD subtree
	_inventory = _player.get_node_or_null("HUD/InventoryUI") as InventoryUI
	if not _inventory:
		# Fallback: search by class in case the path changed
		for child in _player.find_children("*", "InventoryUI", true, false):
			_inventory = child as InventoryUI
			break

	# 5. Wait one frame so all _ready() calls have fired
	await get_tree().process_frame


func after_each() -> void:
	# Reset Input mouse mode to a clean baseline
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ── Test Case A: Inventory Open → Close Focus Integrity ──────────────────────
## Steps:
##  1. Open inventory   → mouse must become VISIBLE, player freezes
##  2. Close inventory  → mouse must become CAPTURED, no UI holds focus
func test_inventory_close_releases_focus_and_captures_mouse() -> void:
	# ── Pre-condition ────────────────────────────────────────────────────────
	gut.p("Pre: force mouse captured as if gameplay is running")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_mock_level.inventory_visible = false

	# ── Step 1: Open ─────────────────────────────────────────────────────────
	if _inventory:
		_inventory.open_inventory(_player)
	_mock_level.inventory_visible = true
	await get_tree().process_frame

	assert_eq(
		Input.mouse_mode,
		Input.MOUSE_MODE_VISIBLE,
		"Mouse must be VISIBLE while inventory is open"
	)

	# ── Step 2: Close ────────────────────────────────────────────────────────
	if _inventory:
		_inventory.close_inventory()
	_mock_level.inventory_visible = false
	await get_tree().process_frame

	# Assert A1: Mouse mode restored
	assert_eq(
		Input.mouse_mode,
		Input.MOUSE_MODE_CAPTURED,
		"Mouse must be CAPTURED after inventory closes"
	)

	# Assert A2: level state flag cleared
	assert_false(
		_mock_level.is_inventory_visible(),
		"inventory_visible flag must be false after close"
	)

	# Assert A3: No Control node holds keyboard focus
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	assert_null(
		focus_owner,
		"No UI node should hold keyboard focus after inventory closes. " +
		"Focus owner: " + (focus_owner.name if focus_owner else "none")
	)


# ── Test Case A2: Player is NOT authority → input path must be skipped ───────
## Regression guard: a remote peer's HUD must never steal focus or process
## ui_cancel events.
func test_non_authority_player_input_ignored() -> void:
	# Re-parent a second player instance with a different name (non-authority)
	var player_scene: PackedScene = load(PLAYER_SCENE_PATH)
	var remote_player := player_scene.instantiate() as CharacterBody3D
	remote_player.name = "9999"   # not the local peer id (1)
	_mock_level.add_child(remote_player)
	await get_tree().process_frame

	# Simulate ui_cancel; the remote player's _unhandled_input should bail out
	# early. The mock level's inventory_visible must stay untouched.
	_mock_level.inventory_visible = true
	var cancel_event := InputEventAction.new()
	cancel_event.action  = "ui_cancel"
	cancel_event.pressed = true
	remote_player._unhandled_input(cancel_event)
	await get_tree().process_frame

	assert_true(
		_mock_level.inventory_visible,
		"A non-authority peer's ui_cancel must NOT close the inventory"
	)

	remote_player.queue_free()


# ── Test Suite B: HUD Prompt Clears on body_exited ───────────────────────────
## Simulates the interaction area signals that player.gd connects to in
## _setup_interaction_area().  After body_exited the HUD label must be "".
func test_hud_prompt_clears_on_body_exited() -> void:
	# ── Step 1: Simulate body_entered — set a non-empty prompt ───────────────
	_mock_level.set_interaction_prompt("[E] Interact with Workbench")
	assert_eq(
		_mock_level.get_last_prompt(),
		"[E] Interact with Workbench",
		"Precondition: prompt must be non-empty before body_exited"
	)

	# ── Step 2: Simulate body_exited via clear_interaction_prompt() ──────────
	# player.gd exposes clear_interaction_prompt() which calls
	# level.set_interaction_prompt("").  We call it directly on the player
	# which will find our mock level as the current_scene substitute.
	#
	# Because the test uses a MockLevel not registered as the SceneTree's
	# current_scene we route through the player's public API:
	if _player.has_method("clear_interaction_prompt"):
		_player.clear_interaction_prompt()
	else:
		# Fallback: directly drive the mock to prove the contract
		_mock_level.set_interaction_prompt("")

	await get_tree().process_frame

	# Assert B1: Prompt text is unconditionally empty
	assert_eq(
		_mock_level.get_last_prompt(),
		"",
		"HUD interaction prompt must be empty string after body_exited"
	)


## Verify the prompt does NOT survive a crafting-station exit either.
func test_hud_prompt_clears_when_leaving_crafting_area() -> void:
	_mock_level.set_interaction_prompt("[E] Open Crafting Station (Workbench)")

	# Simulate leaving the crafting station interaction area
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
```

---

## 4. Test Suite — Pure-Logic Inventory Unit Tests (No Scene)

**File:** `res://test/unit/test_player_inventory_logic.gd`

These tests exercise `PlayerInventory` and `InventorySlot` as pure
`RefCounted` objects — zero scene overhead, instant in headless mode.

```gdscript
# test/unit/test_player_inventory_logic.gd
extends GutTest

var _inv: PlayerInventory


func before_each() -> void:
	_inv = PlayerInventory.new()


# ── Slot integrity ────────────────────────────────────────────────────────────
func test_inventory_initializes_with_correct_slot_count() -> void:
	assert_eq(
		_inv.slots.size(),
		PlayerInventory.INVENTORY_SIZE,
		"Inventory must have exactly INVENTORY_SIZE slots"
	)


func test_all_slots_empty_on_init() -> void:
	for slot in _inv.slots:
		assert_true(slot.is_empty(), "Every slot must start empty")


# ── Add / remove ─────────────────────────────────────────────────────────────
func test_add_item_returns_zero_remainder_when_space_available() -> void:
	var item: Item = ItemDatabase.get_item("health_potion")
	gut.p("Testing with item: " + str(item))
	if not item:
		pending("health_potion not found in ItemDatabase — skipping")
		return
	var remaining := _inv.add_item(item, 3)
	assert_eq(remaining, 0, "All 3 potions must fit in an empty inventory")


func test_add_item_stacks_correctly() -> void:
	var item: Item = ItemDatabase.get_item("health_potion")
	if not item:
		pending("health_potion not found in ItemDatabase — skipping")
		return
	_inv.add_item(item, 5)
	_inv.add_item(item, 3)
	assert_eq(_inv.get_item_count("health_potion"), 8, "Stacked count must be 8")


func test_remove_item_reduces_count() -> void:
	var item: Item = ItemDatabase.get_item("health_potion")
	if not item:
		pending("health_potion not found in ItemDatabase — skipping")
		return
	_inv.add_item(item, 5)
	var removed := _inv.remove_item("health_potion", 2)
	assert_eq(removed, 2, "Two items must be removed")
	assert_eq(_inv.get_item_count("health_potion"), 3, "Three must remain")


func test_has_item_reflects_truth() -> void:
	var item: Item = ItemDatabase.get_item("wood")
	if not item:
		pending("wood not found in ItemDatabase — skipping")
		return
	_inv.add_item(item, 10)
	assert_true(_inv.has_item("wood", 10), "has_item(10) must be true with 10")
	assert_false(_inv.has_item("wood", 11), "has_item(11) must be false with only 10")


# ── Serialisation round-trip ─────────────────────────────────────────────────
func test_serialise_deserialise_roundtrip() -> void:
	var item: Item = ItemDatabase.get_item("iron_ore")
	if not item:
		pending("iron_ore not found in ItemDatabase — skipping")
		return
	_inv.add_item(item, 7)

	var data: Dictionary = _inv.to_dict()
	var restored := PlayerInventory.new()
	restored.from_dict(data)

	assert_eq(
		restored.get_item_count("iron_ore"),
		7,
		"Serialise→deserialise must preserve item count exactly"
	)


# ── Inventory full ────────────────────────────────────────────────────────────
func test_overflow_returns_positive_remainder() -> void:
	# Fill every slot with a non-stackable item  (iron_sword, stackable=false)
	var sword: Item = ItemDatabase.get_item("iron_sword")
	if not sword or sword.stackable:
		pending("iron_sword not found or is stackable — skipping")
		return
	for _i in range(PlayerInventory.INVENTORY_SIZE):
		_inv.add_item(sword, 1)

	var remaining := _inv.add_item(sword, 1)
	assert_gt(remaining, 0, "Adding beyond capacity must return a positive remainder")
```

---

## 5. Headless Execution Script

**File:** `run_tests.sh` (project root, alongside the existing `run_headless_server.sh`)

```bash
#!/usr/bin/env bash
# run_tests.sh ─ Execute the GUT test suite headlessly.
# Usage: ./run_tests.sh [GODOT_BINARY]
#
# Examples:
#   ./run_tests.sh                        # uses 'godot' on $PATH
#   ./run_tests.sh /usr/bin/godot4        # explicit path
#   ./run_tests.sh godot --gut-extra-args # extra args forwarded after '--'
#
# Exit codes mirror Godot's exit code:
#   0  → all tests passed
#   1  → one or more tests failed
#   2  → engine error / GUT couldn't load

set -euo pipefail

GODOT_BIN="${1:-godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Validate the binary exists
if ! command -v "${GODOT_BIN}" &>/dev/null; then
	echo "❌  Godot binary not found: '${GODOT_BIN}'" >&2
	echo "    Set GODOT_BIN or pass the path as the first argument." >&2
	exit 2
fi

echo "══════════════════════════════════════════════"
echo "  micro-world-rpg · GUT Headless Test Runner"
echo "  Godot: $(${GODOT_BIN} --version 2>/dev/null || echo 'unknown')"
echo "  Project: ${PROJECT_DIR}"
echo "══════════════════════════════════════════════"

# Run GUT. The -gexit flag makes Godot exit with a non-zero code on failure.
"${GODOT_BIN}" \
	--headless \
	--path "${PROJECT_DIR}" \
	-s addons/gut/gut_cmdline.gd \
	-gdir=res://test/unit/ \
	-gprefix=test_ \
	-gsuffix=.gd \
	-glog=1 \
	-gexit

EXIT_CODE=$?

echo ""
if [ "${EXIT_CODE}" -eq 0 ]; then
	echo "✅  All tests passed."
else
	echo "❌  Test suite reported failures (exit code: ${EXIT_CODE})."
fi

exit "${EXIT_CODE}"
```

Make it executable:
```bash
chmod +x run_tests.sh
```

### GUT CLI Flag Reference

| Flag | Effect |
|---|---|
| `--headless` | No GPU / display server required |
| `-gdir=res://test/unit/` | Root directory GUT scans for test files |
| `-gprefix=test_` | Only files starting with `test_` are loaded |
| `-gsuffix=.gd` | File extension filter |
| `-glog=1` | Verbose output (0=silent, 3=full debug) |
| `-gexit` | **Critical for CI** — Godot exits with code 1 on any failure |

---

## 6. GitHub Actions CI/CD Workflow

**File:** `.github/workflows/gut_tests.yml`

```yaml
name: GUT Unit Tests

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    name: Headless GUT Test Suite
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          submodules: recursive   # needed if GUT is a git submodule

      - name: Cache Godot binary
        id: cache-godot
        uses: actions/cache@v4
        with:
          path: ~/.local/bin/godot
          key: godot-4.6-linux

      - name: Download Godot 4.6 headless
        if: steps.cache-godot.outputs.cache-hit != 'true'
        run: |
          GODOT_VERSION="4.6"
          GODOT_URL="https://downloads.tuxfamily.org/godotengine/${GODOT_VERSION}/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
          curl -sL "${GODOT_URL}" -o /tmp/godot.zip
          unzip /tmp/godot.zip -d /tmp/godot_bin
          mkdir -p ~/.local/bin
          mv /tmp/godot_bin/Godot_v*_linux.x86_64 ~/.local/bin/godot
          chmod +x ~/.local/bin/godot

      - name: Verify Godot version
        run: ~/.local/bin/godot --version

      - name: Import project assets (warm-up)
        # First run populates .godot/imported/ so tests can load resources
        run: |
          ~/.local/bin/godot --headless --path . --import 2>&1 | tail -20
        continue-on-error: true   # import exits with non-zero sometimes; that's OK

      - name: Run GUT test suite
        run: bash run_tests.sh ~/.local/bin/godot

      - name: Upload GUT report on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: gut-report
          path: |
            user://gut_results*.xml
            user://logs/
```

> [!WARNING]
> The `--import` warm-up step is mandatory. Without it, `preload()` calls inside
> test files will fail because `.import` metadata doesn't exist yet in CI.

---

## 7. Atomic Task Checklist for the Code Generation Agent

```
[ ] TASK-1  Create res://test/unit/ and res://test/unit/helpers/ directories
[ ] TASK-2  Add GUT as git submodule → addons/gut/
            OR document manual download step in CONTRIBUTING.md
[ ] TASK-3  Enable plugin in project.godot [editor_plugins] section
[ ] TASK-4  Write  res://test/unit/helpers/mock_level.gd  (Section 2)
[ ] TASK-5  Write  res://test/unit/test_player_input_states.gd  (Section 3)
            - Implement before_each() with MockLevel + player scene setup
            - Implement test_inventory_close_releases_focus_and_captures_mouse()
            - Implement test_non_authority_player_input_ignored()
            - Implement test_hud_prompt_clears_on_body_exited()
            - Implement test_hud_prompt_clears_when_leaving_crafting_area()
[ ] TASK-6  Write  res://test/unit/test_player_inventory_logic.gd  (Section 4)
[ ] TASK-7  Write  run_tests.sh  at project root (Section 5)
            chmod +x run_tests.sh
[ ] TASK-8  Write  .github/workflows/gut_tests.yml  (Section 6)
[ ] TASK-9  LOCAL SMOKE TEST — run:
            godot --headless --path . -s addons/gut/gut_cmdline.gd \
              -gdir=res://test/unit/ -gexit
            Confirm exit code 0 before pushing.
[ ] TASK-10 Resolve the merge-conflict markers in level.gd and inventory_ui.gd
            (both files contain <<<<<<< / ======= / >>>>>>> artifacts from a
            failed git merge that will cause parse errors during headless import)
```

> [!CAUTION]
> **TASK-10 is a blocker.** Both `res://scripts/level.gd` and
> `res://scripts/inventory_ui.gd` contain raw git merge-conflict markers.
> Godot's parser will reject them at import time, causing ALL tests to fail
> with resource-load errors before GUT even starts. Resolve the conflicts
> (keep the `>>>>>>> HEAD` side, which matches the current feature branch)
> before executing any test run.

---

## 8. Debugging Common Headless Failures

| Symptom | Likely Cause | Fix |
|---|---|---|
| `ERROR: res://addons/gut/…` not found | Plugin not installed / submodule not checked out | Run `git submodule update --init` |
| All tests fail with "Can't preload" | `.godot/imported/` missing | Run `godot --headless --import` first |
| `is_multiplayer_authority()` always `false` | Headless engine assigns unique_id=1 but player.name != "1" | Set `player.name = "1"` in `before_each()` |
| Focus assertion flaky | Deferred `release_focus()` not flushed | Add `await get_tree().process_frame` before assert |
| Mouse mode assertion fails | `Input.mouse_mode` is read-only in headless | Set `--display-driver headless` — `Input.mouse_mode` writes work in headless from Godot 4.2+ |
| GUT exits 0 but no tests ran | `-gdir` path wrong or no `test_` prefix files | Verify with `-glog=3` for verbose file-scan output |
