# Phase 3 — Enemy Layer & Player Combat Pipeline
## Implementation Plan for Code Generation Agent

> **Context Lock:** This plan was authored against the **audited** repository state of 2026-05-28. All file paths, class names, collision layer values, RPC signatures, and node names are cross-referenced against the live source. Do not deviate from these unless explicitly noted.

---

## Repository Fingerprints (Do Not Change)

| Symbol | Value |
|---|---|
| Physics Layer 1 | `player` (bit 0, value `1`) |
| Physics Layer 2 | `world` (bit 1, value `2`) |
| Physics Layer 4 | `enemy` (bit 3, value `8`) — established by `WaveSpawner` and `enemy.tscn` |
| Level scene | `res://scenes/level/level.tscn` |
| Enemy scene | `res://scenes/level/enemy.tscn` |
| Player script | `res://scripts/player.gd` → `class_name Character` |
| Enemy script | `res://scripts/enemy.gd` → `class_name Enemy` |
| Health component | `res://scripts/health_component.gd` → `class_name HealthComponent` |
| Player `_unhandled_input` gate | `Input.mouse_mode == Input.MOUSE_MODE_VISIBLE` → **return early** |
| Attack input action | `"attack"` (LMB + `KEY_F`, registered in `_setup_input_actions()`) |
| Melee hit RPC | `request_combat_hit(target_path: NodePath)` → already defined in `player.gd` for `Character` targets only |

---

## Diagnosis: The Critical Gaps

After reading all source files the following **specific defects** block the gameplay loop:

1. **`enemy.tscn` is missing a `MultiplayerSpawner`-compatible registration** — the scene exists and has a `MultiplayerSynchronizer`, but `WaveSpawner._spawn_enemy()` calls `get_tree().current_scene.add_child(enemy, true)` with `force_readable_name=true`, which works, but the `MultiplayerSynchronizer`'s `root_path` defaults to the scene root, which is correct. **The scene file itself is complete.** The actual gap is purely in `player.gd`.

2. **`_perform_melee_attack()` in `player.gd` (L613–L627) only dispatches to `HarvestableNode` or `Character` targets.** Enemies (`class_name Enemy extends CharacterBody3D`) are `CharacterBody3D`, not `Character`, so they are **silently skipped** by the `elif target is Character` branch. There is zero code path for hitting an `Enemy`.

3. **`_find_closest_target()` (L659–L682) uses `interaction_area: Area3D`** which has `collision_mask = 6` (layers 1+2 = player+world). Layer 8 (enemies) is **not in the mask**, so enemies are invisible to the proximity scan.

4. **No enemy health bar** is rendered on clients. `HealthComponent` already has a `MultiplayerSynchronizer` that replicates `current_health` with `REPLICATION_MODE_ALWAYS`, so the data is present, but no 3D UI node consumes it on the client side.

5. **No VFX swing broadcast RPC exists** — `play_hurt_effect.rpc()` is called on the *target* player, not the *attacker*. There is no equivalent for broadcasting the attacker's swing animation to all peers.

---

## Module 1 — Enemy Entity Layer: `enemy.tscn` Repair

### 1.1 Scene Node Tree (Current State — Already Correct)

```
Enemy                          [CharacterBody3D]  ← root, script=enemy.gd
  ├── CollisionShape3D         [CapsuleShape3D r=0.35 h=1.6, y-offset=0.8]
  ├── EnemyMesh                [MeshInstance3D — red glowing capsule]
  ├── NavigationAgent3D        [path_desired=0.5, target_desired=0.5, avoidance=true]
  ├── AttackTimer              [Timer — wait=1.0, one_shot=false]
  ├── HealthComponent          [Node — max_health=50.0, script=health_component.gd]
  └── MultiplayerSynchronizer  [replicates position+rotation, REPLICATION_MODE_ALWAYS]
```

> [!IMPORTANT]
> The scene file `enemy.tscn` is **structurally complete**. The `MultiplayerSynchronizer` correctly replicates `position` and `rotation` with `spawn=true` and `replication_mode=1` (ALWAYS). **Do not modify `enemy.tscn`.** All work is in the scripts.

### 1.2 `enemy.gd` — Verification Checklist

The coder must **read and verify** each of the following contract points against the live file. If a point is already satisfied, skip it. If not, implement it.

| # | Contract Point | Status |
|---|---|---|
| A | `set_physics_process(false)` and `set_process(false)` on clients in `_ready()` | ✅ L33–37 |
| B | `health_component.died.connect(_on_died)` — server-only | ✅ L40–41 |
| C | `_on_died()` is idempotent via `_death_triggered` flag | ✅ L122–125 |
| D | Death zeros `collision_layer` and `collision_mask` before queue_free | ✅ L137–138 |
| E | Death cleanup uses a self-owned `Timer` (not `SceneTreeTimer`) | ✅ L148–154 |
| F | `nav_agent.velocity_computed` connected to `_on_velocity_computed` | ✅ L50 |
| G | `_physics_process` continuously refreshes `nav_agent.target_position` | ✅ L76–77 |
| H | Gravity applied every frame when not on floor | ✅ L80–81 |

**`enemy.gd` requires no changes.** It is production-ready.

### 1.3 `MultiplayerSynchronizer` Replication Contract

```
Properties replicated server → all clients:
  ".:position"   spawn=true   replication_mode=ALWAYS   transfer=UNRELIABLE_ORDERED
  ".:rotation"   spawn=true   replication_mode=ALWAYS   transfer=UNRELIABLE_ORDERED

HealthComponent/MultiplayerSynchronizer (created at runtime by health_component.gd):
  ".:current_health"  replication_mode=ALWAYS
  ".:max_health"      replication_mode=ALWAYS
```

> [!NOTE]
> `REPLICATION_MODE_ALWAYS` uses the synchronizer's default transfer mode. In `enemy.tscn` the synchronizer has no explicit `replication_interval` set, which defaults to the project's `MultiplayerSynchronizer` default (every physics frame). For 5–20 enemies this is acceptable. If enemy count exceeds 50, add `replication_interval = 0.05` to the synchronizer node in the `.tscn` to cap at 20Hz.

---

## Module 2 — Player Combat Interaction Pipeline

This module requires **three targeted edits to `res://scripts/player.gd`**.

### 2.1 Fix: Expand `interaction_area` collision mask to detect Enemies

**Location:** `_setup_interaction_area()` — Line 585–598

**Current code:**
```gdscript
interaction_area.collision_mask = 6  # layers 1+2 = player+world
```

**Required change:**
```gdscript
# Layer 1 (player=1) + Layer 2 (world=2) + Layer 4 (enemy=8) = 11
interaction_area.collision_mask = 11
```

**Rationale:** Without bit 3 (value 8) in the mask, `interaction_area.get_overlapping_bodies()` never returns enemy `CharacterBody3D` nodes, so `_find_closest_target()` can never select one. This is a single-integer change.

---

### 2.2 Fix: Add Enemy branch to `_find_closest_target()`

**Location:** `_find_closest_target()` — Lines 659–682

The existing loop already skips `self`, depleted `HarvestableNode`s, and dead `Character`s. A new guard for dead enemies must be added.

**Current filter chain (lines 668–676):**
```gdscript
for body in bodies:
    if body == self:
        continue
    if body is HarvestableNode and body.is_depleted:
        continue
    if "is_depleted" in body and body.is_depleted:
        continue
    if body is Character and body.is_dead:
        continue
```

**Add this guard immediately after the `Character` dead-check:**
```gdscript
    # Skip dead enemies (Enemy._is_dead is not exported, check collision_layer instead)
    if body is Enemy and body.collision_layer == 0:
        continue
```

> [!NOTE]
> `Enemy._is_dead` is a private var (no `@export`). The safest dead-check from outside the class is `collision_layer == 0`, because `_on_died()` explicitly sets it to `0` as its first cleanup step (L137). This is a stable contract enforced by the existing code.

---

### 2.3 Fix: Add Enemy dispatch branch to `_perform_melee_attack()`

**Location:** `_perform_melee_attack()` — Lines 613–627

**Current code:**
```gdscript
func _perform_melee_attack(is_interact: bool):
    is_attacking = true
    _play_anim("Attack1")

    get_tree().create_timer(1.3).timeout.connect(func():
        is_attacking = false
    )

    var target = _find_closest_target()
    if target:
        if target is HarvestableNode:
            request_harvest_hit.rpc_id(1, target.get_path())
        elif target is Character and target != self:
            request_combat_hit.rpc_id(1, target.get_path())
```

**Replace with:**
```gdscript
func _perform_melee_attack(is_interact: bool) -> void:
    is_attacking = true
    _play_anim("Attack1")
    # Always broadcast the swing VFX so all peers see the animation.
    play_strike_vfx.rpc()

    get_tree().create_timer(1.3).timeout.connect(func():
        is_attacking = false
    )

    var target = _find_closest_target()
    if target:
        if target is HarvestableNode:
            request_harvest_hit.rpc_id(1, target.get_path())
        elif target is Character and target != self:
            request_combat_hit.rpc_id(1, target.get_path())
        elif target is Enemy:
            # NEW: Lightweight notification — no damage calculated client-side.
            request_enemy_melee_hit.rpc_id(1, target.get_path())
```

---

### 2.4 New RPC: `request_enemy_melee_hit` — Server Spatial Validation

Add this function to `player.gd` after `request_combat_hit` (after line 765).

```gdscript
## Player melee hit request against an Enemy.
## Client sends only the node path — zero gameplay data.
## Server does all spatial validation and damage application.
@rpc("any_peer", "call_local", "reliable")
func request_enemy_melee_hit(enemy_path: NodePath) -> void:
    # ── Server-only guard ──────────────────────────────────────────────
    if not multiplayer.is_server():
        return

    # ── Sender identity check: only this player's authority peer may call ──
    var sender_id: int = multiplayer.get_remote_sender_id()
    if sender_id != get_multiplayer_authority() and sender_id != 1:
        push_warning("Security: Peer %d tried to trigger melee for player %d" \
                % [sender_id, get_multiplayer_authority()])
        return

    # ── Resolve the enemy node from the path ──────────────────────────
    var enemy: Enemy = get_node_or_null(enemy_path) as Enemy
    if not enemy or not is_instance_valid(enemy):
        return  # Enemy was freed between RPC send and receipt.

    # ── Dead-state guard: collision_layer == 0 means _on_died() was already called ──
    if enemy.collision_layer == 0:
        return

    # ── Spatial validation: ShapeCast3D (server-side, ephemeral) ──────
    # Cast a short sphere from the server-authoritative player position
    # toward the enemy. Accept hit only if within melee range (2.5 m).
    const MELEE_REACH: float = 2.5
    var dist: float = global_position.distance_to(enemy.global_position)
    if dist > MELEE_REACH:
        push_warning("Melee rejected: dist=%.2f > reach=%.2f (player=%s)" \
                % [dist, MELEE_REACH, name])
        return

    # ── Damage application ─────────────────────────────────────────────
    const MELEE_DAMAGE: float = 20.0
    var target_health: HealthComponent = \
            enemy.get_node_or_null("HealthComponent") as HealthComponent
    if target_health and target_health.current_health > 0.0:
        target_health.request_damage(MELEE_DAMAGE)
```

> [!IMPORTANT]
> The spatial check above uses `distance_to()` (O(1)) rather than spawning a real `ShapeCast3D` node, because the server processes this on the main thread inside an RPC handler. Creating a `PhysicsShapeQueryParameters3D` and calling `direct_space_state.intersect_shape()` is the more accurate option if anti-cheat precision is required. See the **Alternative: Full ShapeCast Validation** section below.

#### Alternative: Full ShapeCast Validation (High-Security Path)

Use this instead of the `distance_to()` check if the project needs to prevent position-spoofing exploits:

```gdscript
# Inside request_enemy_melee_hit(), replace the dist check with:
const MELEE_REACH: float = 2.5
var space := get_world_3d().direct_space_state
var cast_params := PhysicsShapeQueryParameters3D.new()
var sphere := SphereShape3D.new()
sphere.radius = MELEE_REACH
cast_params.shape = sphere
cast_params.transform = Transform3D(Basis.IDENTITY, global_position)
cast_params.collision_mask = 8  # Layer 4 = enemies only

var hits: Array[Dictionary] = space.intersect_shape(cast_params, 8)
var hit_confirmed: bool = false
for hit in hits:
    if hit.get("collider") == enemy:
        hit_confirmed = true
        break

if not hit_confirmed:
    push_warning("ShapeCast melee rejected for player %s vs %s" % [name, enemy.name])
    return
```

---

### 2.5 New RPC: `play_strike_vfx` — Swing Animation Broadcast

Add this function to `player.gd` after `play_hurt_effect` (after line 779).

```gdscript
## Broadcast the weapon swing animation to all connected peers.
## Called by the authority client; executes locally on every peer.
## Uses unreliable transport — a dropped packet means a missed swing
## frame, not a gameplay desynced state. This is intentional.
@rpc("any_peer", "call_local", "unreliable")
func play_strike_vfx() -> void:
    # Run on all peers including the caller (call_local).
    # Only play if not already in an attack animation (prevents spam).
    if not is_attacking:
        _play_anim("Attack1")
```

> [!NOTE]
> `play_strike_vfx` uses `"any_peer"` so the **authority client calls it** and all peers receive it. The server does not produce input, so there's no authority inversion. The existing `play_hurt_effect` RPC uses `"call_local", "reliable"` because it's called by the server after damage confirmation — a different contract. Keep them separate.

---

### 2.6 Input Gate Verification

**No changes required.** `_unhandled_input()` at line 195 already implements the correct gating hierarchy:

```
_unhandled_input(event):
    if not is_multiplayer_authority(): return          ← remote players silenced
    if Input.mouse_mode == MOUSE_MODE_VISIBLE: return  ← any UI open silences attack
    if event.is_action_pressed("attack"):
        if not is_attacking and not is_building:
            _perform_melee_attack(false)               ← dispatches to new Enemy branch
        get_viewport().set_input_as_handled()
        return
```

The guard `Input.mouse_mode == Input.MOUSE_MODE_VISIBLE` covers **all** UI states — the cursor is freed by `toggle_inventory()`, `toggle_crafting()`, `toggle_chat()`, and the `InGameMenu.toggle()`. This is the single canonical gate and it is sufficient.

---

## Module 3 — Visual & State Feedback

### 3.1 Enemy 3D Health Bar (Client-Side Consumer)

The `HealthComponent` already synchronizes `current_health` and `max_health` to all clients via its dynamically-created `MultiplayerSynchronizer`. The missing piece is a visible 3D bar that **reads** those values.

#### 3.1.1 New node to add to `enemy.tscn`

Add to the enemy scene file (insert before `[node name="MultiplayerSynchronizer"...]`):

```gdscript
[sub_resource type="BoxMesh" id="BoxMesh_hpbg"]
size = Vector3(0.6, 0.07, 0.01)

[sub_resource type="StandardMaterial3D" id="HealthBarBG"]
albedo_color = Color(0.15, 0.15, 0.15, 0.85)
transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
no_depth_test = true
shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

[sub_resource type="BoxMesh" id="BoxMesh_hpfg"]
size = Vector3(0.6, 0.07, 0.01)

[sub_resource type="StandardMaterial3D" id="HealthBarFG"]
albedo_color = Color(0.20, 0.85, 0.25, 1.0)
no_depth_test = true
shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

[node name="HealthBar3D" type="Node3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.9, 0)

[node name="Background" type="MeshInstance3D" parent="HealthBar3D"]
mesh = SubResource("BoxMesh_hpbg")
surface_material_override/0 = SubResource("HealthBarBG")

[node name="Foreground" type="MeshInstance3D" parent="HealthBar3D"]
mesh = SubResource("BoxMesh_hpfg")
surface_material_override/0 = SubResource("HealthBarFG")
```

#### 3.1.2 New script: `res://scripts/enemy_health_bar_3d.gd`

```gdscript
## enemy_health_bar_3d.gd
## Attach to the HealthBar3D node inside enemy.tscn.
## Reads HealthComponent.current_health and max_health (already replicated)
## and updates the foreground bar scale every frame.
## Runs on ALL peers — it is pure cosmetic, never server-authoritative.
extends Node3D

@onready var foreground: MeshInstance3D = $Foreground
@onready var background: MeshInstance3D = $Background

var _health_component: HealthComponent = null
var _camera: Camera3D = null

func _ready() -> void:
    _health_component = get_parent().get_node_or_null("HealthComponent") as HealthComponent
    if not _health_component:
        push_error("EnemyHealthBar3D: HealthComponent not found on parent.")
        queue_free()
        return
    _health_component.health_changed.connect(_on_health_changed)

func _process(_delta: float) -> void:
    # Billboard: always face the active camera.
    _camera = get_viewport().get_camera_3d()
    if _camera:
        look_at(_camera.global_position, Vector3.UP)

func _on_health_changed(new_health: float, max_health: float) -> void:
    if max_health <= 0.0:
        return
    var ratio: float = clamp(new_health / max_health, 0.0, 1.0)
    # Scale the foreground mesh on the X axis only.
    foreground.scale.x = ratio
    # Shift foreground left so it shrinks from the right edge.
    foreground.position.x = (ratio - 1.0) * 0.3  # half the full width * (ratio-1)
    # Color shift: green → yellow → red as health decreases.
    var bar_mat: StandardMaterial3D = foreground.get_surface_override_material(0)
    if bar_mat:
        bar_mat.albedo_color = Color(1.0 - ratio, ratio * 0.85, 0.05)
```

> [!NOTE]
> `HealthComponent.health_changed` signal is emitted on **all peers** because `current_health`'s property setter fires it whenever the value changes (see `health_component.gd` L12–13). The `MultiplayerSynchronizer` triggers the setter on clients when it applies the replicated value. This means the 3D health bar updates purely reactively — no polling, no extra RPCs.

---

### 3.2 Death Sync — Client Visual Cleanup

**No new code required.** When the server calls `queue_free()` on the enemy node (via `_deferred_free()` in `enemy.gd` L156–160), the `MultiplayerSpawner`-compatible removal propagates the `queue_free()` to all clients because the node was added with `add_child(enemy, true)` (force readable name = true, which enables replication tracking). All clients will receive the node removal and call `queue_free()` locally.

The `HealthBar3D` node is a child of the enemy, so it is freed automatically when the parent is freed.

> [!IMPORTANT]
> If enemies are not de-spawning on clients, verify that `level.tscn` has a `MultiplayerSpawner` node configured with the enemy scene path. **Currently `level.tscn` has NO `MultiplayerSpawner`.** See Task 3.3 below.

---

### 3.3 ⚠️ Critical Missing Infrastructure: `MultiplayerSpawner` in `level.tscn`

**This is the root cause of enemies not rendering on clients.**

When `WaveSpawner` calls `get_tree().current_scene.add_child(enemy, true)`, the server adds the node locally. But clients will **only receive the node** if a `MultiplayerSpawner` in the scene is configured to track that scene path.

#### Required addition to `level.tscn`

Add the following node entry to `level.tscn` (after the `PlayersContainer` node, before `MainMenuUI`):

```
[node name="EnemySpawner" type="MultiplayerSpawner" parent="."]
spawn_path = NodePath("..")
auto_spawning = false
```

Then in `res://scripts/level.gd`, inside `_ready()`, add after `spawn_resources()`:

```gdscript
func _ready():
    # ... existing code ...
    _setup_enemy_spawner()

func _setup_enemy_spawner() -> void:
    if not multiplayer.is_server():
        return
    var spawner: MultiplayerSpawner = get_node_or_null("EnemySpawner") as MultiplayerSpawner
    if not spawner:
        push_error("Level: EnemySpawner (MultiplayerSpawner) node is missing from level.tscn!")
        return
    # Register the enemy scene so the spawner can track it.
    spawner.add_spawnable_scene("res://scenes/level/enemy.tscn")
    # Set the spawn path to the scene root (where WaveSpawner places enemies).
    spawner.spawn_path = get_path()
```

> [!CAUTION]
> `MultiplayerSpawner.spawn_path` must point to the **same node** that `WaveSpawner` passes to `add_child()`. Currently `WaveSpawner` does `get_tree().current_scene.add_child(enemy, true)`, which is the `Level` root node. The `spawn_path = NodePath("..")` in the `.tscn` (relative to `EnemySpawner`'s parent `"."` = Level root) resolves correctly to the Level root. Verify this matches exactly.

---

## Execution Order (Sequential Task List for Code Agent)

Perform these tasks **in order**. Each task is atomic and independently testable.

### Task 1 — Add `MultiplayerSpawner` to `level.tscn`
- **File:** `res://scenes/level/level.tscn`
- **Action:** Add `[node name="EnemySpawner" type="MultiplayerSpawner" parent="."]` with `spawn_path = NodePath("..")` and `auto_spawning = false`.
- **Test:** Launch server + 1 client. Press F3 to start a wave. Verify enemies appear on the client viewport.

### Task 2 — Expand `interaction_area` collision mask
- **File:** `res://scripts/player.gd`
- **Function:** `_setup_interaction_area()` — Line 589
- **Change:** `collision_mask = 6` → `collision_mask = 11`
- **Test:** Walk the player toward an enemy. Verify `_find_closest_target()` returns it (add a `print(target)` debug line temporarily).

### Task 3 — Add Enemy dead-check to `_find_closest_target()`
- **File:** `res://scripts/player.gd`
- **Function:** `_find_closest_target()` — after line 675
- **Change:** Add `if body is Enemy and body.collision_layer == 0: continue`
- **Test:** Kill an enemy (e.g., via turret). Confirm the player's attack no longer targets the corpse.

### Task 4 — Add `request_enemy_melee_hit` RPC
- **File:** `res://scripts/player.gd`
- **Action:** Insert the full `request_enemy_melee_hit` function (Module 2.4) after `request_combat_hit` (after line 765).
- **Test:** Via print statements, verify the RPC reaches the server and distance check executes.

### Task 5 — Add `play_strike_vfx` RPC
- **File:** `res://scripts/player.gd`
- **Action:** Insert the full `play_strike_vfx` function (Module 2.5) after `play_hurt_effect` (after line 779).
- **Test:** Verify that attacking calls `play_strike_vfx.rpc()` and all peers see the swing animation.

### Task 6 — Patch `_perform_melee_attack` dispatch table
- **File:** `res://scripts/player.gd`
- **Function:** `_perform_melee_attack()` — Lines 613–627
- **Change:** Add `play_strike_vfx.rpc()` call + `elif target is Enemy:` branch (Module 2.3).
- **Test:** Walk into melee range of an enemy and attack. Verify enemy HP decreases via the health bar.

### Task 7 — Add Health Bar nodes to `enemy.tscn`
- **File:** `res://scenes/level/enemy.tscn`
- **Action:** Insert sub_resources and `HealthBar3D` node tree (Module 3.1.1).
- **Test:** Spawn an enemy. Verify the bar is visible above it.

### Task 8 — Create `enemy_health_bar_3d.gd`
- **File:** `res://scripts/enemy_health_bar_3d.gd` ← new file
- **Action:** Write the full script (Module 3.1.2).
- **Attach:** Set `script` on the `HealthBar3D` node in `enemy.tscn`.
- **Test:** Attack an enemy. Verify bar shrinks and color shifts from green → red.

### Task 9 — Wire `_setup_enemy_spawner()` in `level.gd`
- **File:** `res://scripts/level.gd`
- **Action:** Add `_setup_enemy_spawner()` function (Module 3.3) and call it from `_ready()`.
- **Test:** Full integration test — server + 2 clients, start a wave, all peers see enemies, player attacks reduce HP visible on all clients, enemy dies and despawns on all clients.

---

## Verification Matrix

| Test Scenario | Expected Result | Failure Indicator |
|---|---|---|
| Start wave (F3) on server, observe client | Enemies spawn and move on client | Enemies visible only on server |
| Player walks within 2.5m of enemy, press LMB | Enemy HP bar decreases | No damage, console warning "Melee rejected" |
| Second client watches first client attack | First client's swing animation plays on second client's screen | No animation broadcast |
| Enemy reaches Base Heart and attacks | Base Heart HP decreases | No damage (check `collision_layer` mask on enemy) |
| Kill enemy (turret or player) | Enemy despawns on all clients within 0.5s | Enemy lingers as ghost on clients |
| Open inventory (I), press LMB | No attack fired | Attack fires through UI |
| Open ESC pause menu, press LMB | No attack fired | Attack fires through pause menu |

---

## Data Schemas

### `request_enemy_melee_hit` RPC Payload
```
Caller:  Authority client (is_multiplayer_authority() == true)
Target:  Peer ID 1 (server only)
Args:    enemy_path: NodePath  — absolute path from scene root to Enemy node

Example: NodePath("/root/Level/Enemy_3")

Validation chain (server-side):
  1. sender_id == get_multiplayer_authority()    ← identity
  2. enemy node resolves and is_instance_valid() ← existence
  3. enemy.collision_layer != 0                 ← alive
  4. distance_to(enemy) <= 2.5                  ← spatial
  5. target_health.current_health > 0           ← redundant safety
```

### `play_strike_vfx` RPC Payload
```
Caller:  Authority client
Targets: All peers including self (call_local)
Args:    none

Transport: unreliable (missed frames = cosmetic artifact, not gameplay bug)
```

### `HealthComponent.health_changed` Signal Contract
```
Signal:    health_changed(new_health: float, max_health: float)
Emitter:   current_health property setter — fires on ALL peers after replication
Consumer:  EnemyHealthBar3D._on_health_changed()
           Player HUD health display (existing)
No RPC:    Signal fires locally from MultiplayerSynchronizer property write
```
