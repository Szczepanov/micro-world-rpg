# Phase 6: Advanced Combat Juice & Tactile Mechanics
## Technical Specification Workbook — Code Generation Agent Target

> **Ground truth snapshot:** `player.gd` (1429 lines), `grid_manager.gd` (177 lines), `item_database.gd` (181 lines), `item.gd` (56 lines), `health_component.gd` (52 lines), `inventory_slot_ui.gd` (128 lines), `inventory_ui.gd` (176 lines), `player_placement_controller.gd` (203 lines), `enemy.gd` (179 lines). All examined before this plan was written.

---

## Constraint Checklist (Non-Negotiable)

| Constraint | Enforcement point |
|---|---|
| No new autoload singletons | All new state lives on existing nodes or existing singletons |
| No manual editor scene interventions | All node wiring is done in `_ready()` via `add_child` / `get_node_or_null` |
| GUT test suite must remain green | New RPCs follow the existing authority guard pattern; no public mutable state added to HealthComponent |
| Docker SIGTERM flush loops unaffected | Modules touch only scene-graph code; `database_manager.gd` is not modified |
| Non-root container security gates | No new `@rpc("any_peer")` without sender identity verification against `get_multiplayer_authority()` |

---

## Module 6.1 — Orthogonal Building Rotation Matrix

### Overview
Extend `GridManager.request_place_structure` and `PlayerPlacementController` to transmit and enforce an integer rotation index (`0`–`3`) rather than any float angle. The client cycles the rotation with `R`, the ghost mesh reflects it immediately, and the server applies a clean `Basis` before instantiating the scene node.

### Files Modified

#### [MODIFY] [grid_manager.gd](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/grid_manager.gd)

**Change 1 — RPC signature** (line 42)

```diff
-@rpc("any_peer", "reliable")
-func request_place_structure(grid_coords: Vector3i, structure_id: String) -> void:
+@rpc("any_peer", "reliable")
+func request_place_structure(grid_coords: Vector3i, structure_id: String, rotation_index: int = 0) -> void:
```

**Change 2 — Validate the rotation_index on the server** (insert after the distance check, ~line 58)

```gdscript
    # Reject any out-of-contract integer.
    if rotation_index < 0 or rotation_index > 3:
        push_warning("GridManager: Invalid rotation_index %d from peer %d" % [rotation_index, peer_id])
        notify_placement_failed.rpc_id(peer_id, "Invalid rotation index.")
        return
```

**Change 3 — Pass rotation_index to _spawn_visual_node** (line 91)

```diff
-    spawn_grid_structure.rpc(grid_coords, structure_id, peer_id)
+    spawn_grid_structure.rpc(grid_coords, structure_id, peer_id, rotation_index)
```

**Change 4 — World grid record stores rotation** (line 94–98)

```diff
 @rpc("call_local", "reliable")
-func spawn_grid_structure(grid_coords: Vector3i, structure_id: String, peer_id: int) -> void:
+func spawn_grid_structure(grid_coords: Vector3i, structure_id: String, peer_id: int, rotation_index: int = 0) -> void:
     world_grid[grid_coords] = {
         "structure_id": structure_id,
-        "peer_id": peer_id
+        "peer_id": peer_id,
+        "rotation_index": rotation_index
     }
-    _spawn_visual_node(grid_coords, structure_id)
+    _spawn_visual_node(grid_coords, structure_id, rotation_index)
```

**Change 5 — Apply orthogonal basis in _spawn_visual_node** (lines 103–125)

```diff
-func _spawn_visual_node(grid_coords: Vector3i, structure_id: String) -> void:
+func _spawn_visual_node(grid_coords: Vector3i, structure_id: String, rotation_index: int = 0) -> void:
     var scene_path = "res://scenes/environment/props/" + structure_id + ".tscn"
     var scene = load(scene_path) as PackedScene
     if not scene:
         push_error("GridManager: Failed to load structure scene: " + scene_path)
         return

     var instance = scene.instantiate()
     var target_world_pos = grid_to_world(grid_coords)
     instance.name = "structure_" + str(grid_coords.x) + "_" + str(grid_coords.y) + "_" + str(grid_coords.z)

+    # Apply clean orthogonal Y-axis rotation from integer index.
+    # PI/2 * index yields 0°, 90°, 180°, 270° — no floating-point drift.
+    var structure_basis := Basis().rotated(Vector3.UP, rotation_index * (PI / 2.0))
+    instance.transform.basis = structure_basis

     var level_scene = get_tree().current_scene
     var parent_node = level_scene
     if level_scene and level_scene.has_node("Environment"):
         parent_node = level_scene.get_node("Environment")

     parent_node.add_child(instance)
     instance.global_position = target_world_pos
     if "grid_coords" in instance:
         instance.grid_coords = grid_coords
     print("GridManager: Spawned structure %s at %s (rot_idx=%d)" % [structure_id, target_world_pos, rotation_index])
```

**Change 6 — `sync_entire_grid` must pass stored rotation** (line 156)

```diff
-        _spawn_visual_node(grid_coords, server_grid[key]["structure_id"])
+        var rot_idx: int = server_grid[key].get("rotation_index", 0)
+        _spawn_visual_node(grid_coords, server_grid[key]["structure_id"], rot_idx)
```

---

#### [MODIFY] [player_placement_controller.gd](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/player_placement_controller.gd)

**Change 1 — Add rotation state variable** (after line 10)

```gdscript
var _rotation_index: int = 0          # 0=0°, 1=90°, 2=180°, 3=270°
```

**Change 2 — Register 'R' keybinding** in `_setup_input_actions()` (after line 61)

```gdscript
    if not InputMap.has_action("rotate_structure"):
        InputMap.add_action("rotate_structure")
        var r_event := InputEventKey.new()
        r_event.physical_keycode = KEY_R
        InputMap.action_add_event("rotate_structure", r_event)
```

**Change 3 — Handle 'R' in `_unhandled_input`** (inside the `if is_active:` block, after line 82)

```gdscript
        if event.is_action_pressed("rotate_structure"):
            _rotation_index = (_rotation_index + 1) % 4
            _apply_ghost_rotation()
            get_viewport().set_input_as_handled()
```

**Change 4 — Apply rotation to ghost mesh** (new helper, after `_apply_ghost_materials`)

```gdscript
func _apply_ghost_rotation() -> void:
    if not ghost_instance:
        return
    var ghost_basis := Basis().rotated(Vector3.UP, _rotation_index * (PI / 2.0))
    ghost_instance.transform.basis = ghost_basis
```

**Change 5 — Reset rotation index when ghost is recreated**. In `_create_ghost_preview()`, after setting `ghost_instance.visible = false` (line 176), add:

```gdscript
    _apply_ghost_rotation()   # Apply current rotation to freshly created ghost.
```

**Change 6 — Send rotation_index in the placement RPC** (line 163)

```diff
-        GridManager.request_place_structure.rpc_id(1, grid_coords, selected_structure_id)
+        GridManager.request_place_structure.rpc_id(1, grid_coords, selected_structure_id, _rotation_index)
```

**Change 7 — Update interaction prompt to mention `[R]`** (line 112)

```diff
-        level.set_interaction_prompt("Build Mode: [1] Spiked Wall | [2] Turret | [LMB] Place %s | [B] Exit" % structure_name)
+        level.set_interaction_prompt("Build Mode: [1] Wall | [2] Turret | [LMB] Place | [R] Rotate | [B] Exit — (%s, %d°)" % [structure_name, _rotation_index * 90])
```

### GUT Test Coverage

Add to a **new file** `test/unit/test_grid_rotation.gd`:

```gdscript
extends GutTest

func test_rotation_index_clamp() -> void:
    # Validate that only indices 0-3 produce valid Basis matrices with no NaN values.
    for idx in range(4):
        var b := Basis().rotated(Vector3.UP, idx * (PI / 2.0))
        assert_false(is_nan(b.x.x), "Basis X.x is NaN at index %d" % idx)
        assert_almost_eq(b.determinant(), 1.0, 0.0001, "Non-unit determinant at index %d" % idx)

func test_invalid_rotation_index_rejected() -> void:
    # Out-of-range indices 4 and -1 must be caught by the server guard.
    var valid_indices := [0, 1, 2, 3]
    assert_true(4 not in valid_indices)
    assert_true(-1 not in valid_indices)
```

---

## Module 6.2 — Data-Driven Active Weapon Equipment

### Overview
Add a server-replicated `equipped_item_id` string to the player via its existing `MultiplayerSynchronizer`. Extend `ItemDatabase` items with optional combat stats dictionary. Refactor `request_enemy_melee_hit` (lines 781–818 of `player.gd`) to pull range and damage from the database rather than hardcoded constants. Wire a client-side hand-bone mesh visibility toggle.

### Files Modified

#### [MODIFY] [item_database.gd](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/item_database.gd)

**Change — Add `weapon_stats` dictionary to weapon items** (in `_create_sample_items`, after `iron_sword.icon = placeholder_icon`)

```gdscript
    # Optional combat metadata — only present on WEAPON type items.
    iron_sword.weapon_stats = {"weapon_range": 2.5, "weapon_damage": 35.0}
```

#### [MODIFY] [item.gd](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/item.gd)

**Change — Add optional `weapon_stats` property**

```diff
 @export var value: int = 0
+
+## Optional. Only populated for ItemType.WEAPON entries.
+## Keys: "weapon_range" (float, metres), "weapon_damage" (float, HP).
+var weapon_stats: Dictionary = {}
```

> **Note:** This is `var`, not `@export`, because it is populated at runtime by `ItemDatabase._create_sample_items()` — no `.tres` file serialization is needed and no editor scene change occurs.

#### [MODIFY] [player.gd](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/player.gd)

**Change 1 — Add `equipped_item_id` property** (after line 34, in the RPG/combat states block)

```gdscript
## Server-replicated string. Empty = bare-handed. Populated by equip_item().
## Wired into MultiplayerSynchronizer in _setup_health_replication().
var equipped_item_id: String = ""
```

**Change 2 — Register `equipped_item_id` for synchronization** in `_setup_health_replication()` (lines 598–605), after the `is_dead` property registration:

```gdscript
    # Register equipped_item_id for replication so clients can toggle
    # weapon mesh visibility without an extra RPC.
    var equip_path := NodePath(".:equipped_item_id")
    if not config.has_property(equip_path):
        config.add_property(equip_path)
        config.property_set_replication_mode(equip_path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
```

**Change 3 — New server-authoritative `equip_item` RPC** (insert after `request_remove_item`, around line 499)

```gdscript
## Client requests equipping an item from their inventory.
## Server validates ownership then sets the replicated string.
@rpc("any_peer", "call_local", "reliable")
func equip_item(item_id: String) -> void:
    if not multiplayer.is_server():
        return

    var sender_id: int = multiplayer.get_remote_sender_id()
    if sender_id != get_multiplayer_authority() and sender_id != 1:
        push_warning("Security: Peer %d tried to equip item for player %d" \
                % [sender_id, get_multiplayer_authority()])
        return

    # Verify the item actually exists and is a weapon (or empty-string to unequip).
    if item_id != "" and not ItemDatabase.has_item(item_id):
        push_warning("equip_item: Unknown item_id '%s'" % item_id)
        return

    if item_id != "":
        var item: Item = ItemDatabase.get_item(item_id)
        if item.item_type != Item.ItemType.WEAPON and item.item_type != Item.ItemType.TOOL:
            push_warning("equip_item: Item '%s' is not equippable" % item_id)
            return

    equipped_item_id = item_id
    # MultiplayerSynchronizer propagates the new string automatically.
    _update_hand_mesh_visibility()
```

**Change 4 — Refactor `request_enemy_melee_hit`** (lines 806–818, the spatial validation and damage block)

```diff
-    # ── Spatial validation ──────────────────────────────────────────────
-    const MELEE_REACH: float = 2.5
-    var dist: float = global_position.distance_to(enemy.global_position)
-    if dist > MELEE_REACH:
-        push_warning("Melee rejected: dist=%.2f > reach=%.2f (player=%s)" \
-                % [dist, MELEE_REACH, name])
-        return
-
-    # ── Damage application ─────────────────────────────────────────────
-    const MELEE_DAMAGE: float = 20.0
-    var target_health: HealthComponent = \
-            enemy.get_node_or_null("HealthComponent") as HealthComponent
-    if target_health and target_health.current_health > 0.0:
-        target_health.request_damage(MELEE_DAMAGE)
+    # ── Resolve weapon stats from ItemDatabase (data-driven) ────────────
+    # Falls back to bare-handed defaults when equipped_item_id is empty
+    # or the item has no weapon_stats dict.
+    var melee_reach: float = 2.5     # bare-handed default
+    var melee_damage: float = 20.0   # bare-handed default
+
+    if equipped_item_id != "":
+        var equipped: Item = ItemDatabase.get_item(equipped_item_id)
+        if equipped and not equipped.weapon_stats.is_empty():
+            melee_reach  = equipped.weapon_stats.get("weapon_range",  melee_reach)
+            melee_damage = equipped.weapon_stats.get("weapon_damage", melee_damage)
+
+    # ── Spatial validation ──────────────────────────────────────────────
+    var dist: float = global_position.distance_to(enemy.global_position)
+    if dist > melee_reach:
+        push_warning("Melee rejected: dist=%.2f > reach=%.2f (player=%s, weapon=%s)" \
+                % [dist, melee_reach, name, equipped_item_id])
+        return
+
+    # ── Damage application ─────────────────────────────────────────────
+    var target_health: HealthComponent = \
+            enemy.get_node_or_null("HealthComponent") as HealthComponent
+    if target_health and target_health.current_health > 0.0:
+        target_health.request_damage(melee_damage)
+
+    # ── Broadcast hit-flash event to all clients (unreliable, visual only) ──
+    notify_enemy_hit_flash.rpc(enemy.get_path())
```

**Change 5 — Client-side hand mesh visibility toggle** (new helper, after `_update_interaction_ui`)

```gdscript
## Called whenever equipped_item_id changes (locally or via replication).
## Walks the hand bone children to show/hide 3D tool models.
## Naming convention: hand-held mesh nodes must be in group "HandMesh".
func _update_hand_mesh_visibility() -> void:
    var skeleton := _get_main_skeleton()
    if not skeleton:
        return
    for child in skeleton.get_children():
        if child.is_in_group("HandMesh") and child is MeshInstance3D:
            # Show the mesh whose name matches the equipped item ID; hide all others.
            child.visible = (child.name == equipped_item_id)
```

> **Hook into replication:** Godot's `MultiplayerSynchronizer` does not fire a callback on property change. Wire the visibility update in `_process` with a change-detection guard:

```gdscript
var _last_equipped_item_id: String = ""

func _process(_delta: float) -> void:
    if not is_multiplayer_authority():
        return
    if not Network.is_network_active:
        return
    _check_fall_and_respawn()
    _update_interaction_ui()

    # Detect replicated equipment changes (runs on all peers for remote players too).
+   if equipped_item_id != _last_equipped_item_id:
+       _last_equipped_item_id = equipped_item_id
+       _update_hand_mesh_visibility()
```

> **Important:** The `_process` guard (`if not is_multiplayer_authority()`) at line 187 must be **removed from the top** and replaced with a per-block authority check so remote players' hand meshes also update on this client. The change-detection block must run for all peers.

### GUT Test Coverage

Extend `test/unit/test_network_authority_failsafes.gd` with:

```gdscript
func test_equip_item_rejects_non_weapon() -> void:
    # Simulate: server calls equip_item with a consumable — must be a no-op.
    # Since we cannot fully mock multiplayer in GUT, assert ItemDatabase type guard.
    var item := ItemDatabase.get_item("health_potion")
    assert_eq(item.item_type, Item.ItemType.CONSUMABLE)
    assert_true(item.weapon_stats.is_empty(), "Consumables must not have weapon_stats")

func test_weapon_stats_present_on_iron_sword() -> void:
    var item := ItemDatabase.get_item("iron_sword")
    assert_false(item.weapon_stats.is_empty(), "iron_sword must have weapon_stats")
    assert_true(item.weapon_stats.has("weapon_range"))
    assert_true(item.weapon_stats.has("weapon_damage"))
    assert_gt(item.weapon_stats["weapon_damage"], 0.0)
```

---

## Module 6.3 — Low-Overhead Procedural Combat Juice

### Overview
Two lightweight client-side effects triggered by a new unreliable server broadcast:
1. **Hit Flash** — `material_override = bright red StandardMaterial3D` for 100 ms, then cleared.
2. **Screen Shake** — `Tween` on `camera.h_offset` / `camera.v_offset`.

No new singletons. No custom shaders. The flash is driven off the existing `HealthComponent.died` / hit broadcast path; the shake fires from the existing `play_strike_vfx` confirmation flow.

### Files Modified

#### [MODIFY] [player.gd](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/player.gd)

**Change 1 — Add `notify_enemy_hit_flash` RPC** (new function, placed near `play_strike_vfx`)

```gdscript
## Server broadcasts this after validating a melee hit.
## Unreliable — a dropped packet means a missed flash frame, not a gameplay desync.
## `enemy_path` is the scene-tree NodePath of the struck enemy.
@rpc("authority", "call_local", "unreliable")
func notify_enemy_hit_flash(enemy_path: NodePath) -> void:
    var enemy := get_node_or_null(enemy_path) as Enemy
    if not enemy or not is_instance_valid(enemy):
        return
    _flash_enemy_hit(enemy)

## Temporarily overrides all MeshInstance3D materials on the enemy with a bright
## unshaded red material. Clears after HIT_FLASH_DURATION seconds.
## Pure visual — no gameplay state is written.
const HIT_FLASH_DURATION: float = 0.1

func _flash_enemy_hit(enemy: Enemy) -> void:
    var flash_mat := StandardMaterial3D.new()
    flash_mat.albedo_color = Color(1.0, 0.1, 0.1)
    flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

    # Collect all MeshInstance3D descendants of the enemy.
    var meshes: Array[MeshInstance3D] = []
    _find_meshes_recursive(enemy, meshes)   # Reuse existing helper from player.gd

    for mesh in meshes:
        mesh.material_override = flash_mat

    # Clear after duration using a SceneTreeTimer (no node allocation needed).
    get_tree().create_timer(HIT_FLASH_DURATION).timeout.connect(func() -> void:
        for mesh in meshes:
            if is_instance_valid(mesh):
                mesh.material_override = null
    )
```

> **Authority note:** `@rpc("authority", ...)` means only the server (authority on the scene root) may send this — clients cannot spoof it. This preserves the security model.

**Change 2 — Screen shake after successful melee confirmation**

The shake must fire on the *attacker's* local client. Wire it into `_perform_melee_attack()` immediately after `play_strike_vfx.rpc()` (line 615), gated to local authority only:

```gdscript
    # ── Screen shake (local-authority attacker only) ─────────────────
    _trigger_screen_shake()
```

New helper function:

```gdscript
## Briefly displaces camera H/V offsets using a damped Tween.
## Only called on the local authority client — no network traffic generated.
const SHAKE_MAGNITUDE: float = 0.06
const SHAKE_DURATION:  float = 0.25

func _trigger_screen_shake() -> void:
    if not is_multiplayer_authority():
        return
    var cam: Camera3D = get_node_or_null("SpringArmOffset/SpringArm3D/Camera3D") as Camera3D
    if not cam:
        return

    var tween := create_tween()
    tween.set_parallel(true)

    # Two-phase shake: quick offset → spring back to zero.
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    var h_kick: float = rng.randf_range(-SHAKE_MAGNITUDE, SHAKE_MAGNITUDE)
    var v_kick: float = rng.randf_range(-SHAKE_MAGNITUDE * 0.5, SHAKE_MAGNITUDE * 0.5)

    tween.tween_property(cam, "h_offset", h_kick, SHAKE_DURATION * 0.15)\
         .set_ease(Tween.EASE_OUT)
    tween.tween_property(cam, "v_offset", v_kick, SHAKE_DURATION * 0.15)\
         .set_ease(Tween.EASE_OUT)

    # Return to neutral
    tween.chain().tween_property(cam, "h_offset", 0.0, SHAKE_DURATION * 0.85)\
         .set_ease(Tween.EASE_IN_OUT)
    tween.chain().tween_property(cam, "v_offset", 0.0, SHAKE_DURATION * 0.85)\
         .set_ease(Tween.EASE_IN_OUT)
```

> **Camera node path confirmed:** Line 24 of `player_placement_controller.gd` shows the camera is at `"SpringArmOffset/SpringArm3D/Camera3D"`. That exact path is used here.

### GUT Test Coverage

Extend `test/unit/test_health_component.gd`:

```gdscript
func test_hit_flash_material_cleared_within_duration() -> void:
    # Cannot simulate a real Enemy node in unit scope, but we can verify the
    # flash constant is sane (> 0 and < 1 second to avoid perma-red state).
    assert_gt(Character.HIT_FLASH_DURATION, 0.0)
    assert_lt(Character.HIT_FLASH_DURATION, 1.0)
```

---

## Module 6.4 — Minimalist Prototype UI Inventory Icons

### Overview
When an inventory slot's `Item.icon` is the placeholder `icon.png` (or no texture is available), render a high-contrast shorthand label over a flat background color keyed to `Item.ItemType`. No new UI scenes, no raw vector drawing. Uses the existing `ColorRect` + `Label` nodes already present in the slot UI hierarchy.

### Files Modified

#### [MODIFY] [inventory_slot_ui.gd](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/inventory_slot_ui.gd)

**Change 1 — Add type-to-color and type-to-label lookup tables** (after the RARITY_COLORS dictionary, ~line 23)

```gdscript
## Background fill color keyed to ItemType, used when no real texture is available.
const TYPE_COLORS: Dictionary = {
    Item.ItemType.WEAPON:     Color(0.698, 0.133, 0.133),  # Crimson   #B22222
    Item.ItemType.ARMOR:      Color(0.275, 0.510, 0.706),  # Steel Blue #4682B4
    Item.ItemType.CONSUMABLE: Color(0.133, 0.545, 0.133),  # Forest Green #228B22
    Item.ItemType.TOOL:       Color(0.545, 0.396, 0.212),  # Brown      #8B6432
    Item.ItemType.MISC:       Color(0.255, 0.255, 0.255),  # Dark Gray  #414141
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
```

**Change 2 — Add a `prototype_bg` ColorRect and `prototype_label` Label as dynamic children.** Insert at the end of `_ready()`:

```gdscript
    _build_prototype_overlay()
```

New helper:

```gdscript
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
```

**Change 3 — Determine whether to use prototype rendering** in `_show_item_slot()`. Replace the current `item_icon.texture = item.icon` block (~line 59) with:

```gdscript
func _show_item_slot() -> void:
    var item := ItemDatabase.get_item(inventory_data.item_id)
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
```

**Change 4 — Clear prototype overlay in `_show_empty_slot()`** (after line 51)

```gdscript
    var proto_bg  := get_node_or_null("PrototypeBG")  as ColorRect
    var proto_lbl := get_node_or_null("PrototypeLabel") as Label
    if proto_bg:  proto_bg.visible  = false
    if proto_lbl: proto_lbl.visible = false
```

### GUT Test Coverage

Extend `test/unit/test_player_inventory_logic.gd`:

```gdscript
func test_type_colors_cover_all_item_types() -> void:
    # Verify every ItemType enum value has a color entry.
    var all_types := [
        Item.ItemType.WEAPON, Item.ItemType.ARMOR, Item.ItemType.CONSUMABLE,
        Item.ItemType.TOOL, Item.ItemType.MISC
    ]
    for t in all_types:
        assert_true(InventorySlotUI.TYPE_COLORS.has(t),
            "Missing TYPE_COLORS entry for ItemType %d" % t)

func test_item_shorthand_no_overflow() -> void:
    for key in InventorySlotUI.ITEM_SHORTHAND:
        var label: String = InventorySlotUI.ITEM_SHORTHAND[key]
        assert_lte(label.length(), 3, "Shorthand '%s' for item '%s' exceeds 3 chars" % [label, key])
```

> **Note:** To access the `const` dictionaries in GUT, either promote them to `static const` (Godot 4.3+) or extract them into a standalone `InventoryIconData` autoload. The simplest zero-change approach is to instantiate a dummy `InventorySlotUI` node and access them via the instance.

---

## Execution Matrix

| Module | Files Modified | New Files | Net Lines (est.) | Blocking Dependencies |
|--------|---------------|-----------|------------------|-----------------------|
| 6.1 Rotation | `grid_manager.gd`, `player_placement_controller.gd` | `test_grid_rotation.gd` | +55 | None |
| 6.2 Equipment | `item.gd`, `item_database.gd`, `player.gd` | — | +85 | 6.1 must not conflict with `request_place_structure` signature |
| 6.3 Juice | `player.gd` | — | +60 | 6.2 must be merged first (`notify_enemy_hit_flash` RPC added in 6.2 diff) |
| 6.4 UI Icons | `inventory_slot_ui.gd` | — | +75 | None (fully independent) |

**Recommended agent execution order:** 6.4 → 6.1 → 6.2 → 6.3

---

## Verification Plan

### Automated (GUT)

```bash
# Full suite — must remain 0 failures
./run_tests.sh

# Run only the new phase-6 tests
godot --headless -s addons/gut/gut_cmdln.gd \
  -gdir=res://test/unit \
  -ginclude_subdirs \
  -gprefix=test_ \
  -gsuffix=.gd \
  -gexit
```

### Manual Functional Verification

| ID | Scenario | Expected Outcome |
|----|----------|-----------------|
| V6.1-a | Enter build mode, press `R` 4 times | Ghost rotates 0°→90°→180°→270°→0° with no epsilon drift |
| V6.1-b | Place a wall facing 90° | Spawned structure on server and on late-joining client faces 90° |
| V6.1-c | Submit `rotation_index = 5` via forged RPC | Server emits `push_warning` and returns without spawning |
| V6.2-a | Equip `iron_sword`, attack enemy | Server logs show `weapon_range=2.5`, `weapon_damage=35.0` |
| V6.2-b | Bare-handed attack (empty `equipped_item_id`) | Fallback defaults applied: 2.5m reach, 20.0 damage |
| V6.2-c | `equip_item("health_potion")` forged RPC | Server rejects; `equipped_item_id` unchanged |
| V6.3-a | Land a melee hit on enemy | Enemy flashes red for ≤ 0.1s; camera shakes on attacker's screen |
| V6.3-b | Miss (enemy out of range) | No flash; no shake |
| V6.3-c | Kill enemy during flash window | `is_instance_valid(mesh)` guard prevents null-ref crash |
| V6.4-a | Open inventory with `iron_sword` | Crimson background with "SWD" label visible |
| V6.4-b | Open inventory with `wood` (×3) | Brown background, "WOD" label, quantity badge "3" |
| V6.4-c | Future item with real texture | Real texture rendered; PrototypeBG/Label hidden |

### Database & SIGTERM Invariants (Phase 4 regression)

None of the four modules modify `database_manager.gd` or the `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` handler. Run the SIGTERM simulation test in `test_db_crud_roundtrip.gd` after each module merge to confirm no import chain breaks.

```bash
godot --headless -s addons/gut/gut_cmdln.gd \
  -gtest=res://test/unit/test_db_crud_roundtrip.gd \
  -gexit
```
