# MultiplayerSpawner Automatic Mode — Refactoring Blueprint

## Problem Statement

The current system calls `spawner.spawn(data)` with a `Dictionary` payload to hand off initialization data (name, position) to a custom `spawn_function` callback on `Enemy`. The engine crashes at runtime because the `spawn_function` property of the `MultiplayerSpawner` node was never assigned a valid `Callable` — it is `null` by default when using automatic scene mode, and Godot 4's internals reject the call immediately.

**Root cause (verified in source):**

| File | Offending Line | Why It Fails |
|---|---|---|
| [wave_spawner.gd](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/wave_spawner.gd#L122) | `spawner.spawn(spawn_data)` | `spawn_function` is `null`; engine throws the reported error |
| [enemy.gd](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/enemy.gd#L41-L63) | `func spawn_data_handler(data)` | Dead code — never called via the automatic pipeline |
| [level.gd](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/level.gd#L330) | `spawner.add_spawnable_scene(...)` | Must remain; just needs pairing with the correct add_child flow |

**Correct engine contract (Automatic Scene Mode):**
1. Server calls `enemy_scene.instantiate()`.
2. Server sets any initial state on the node **before** `add_child()`.
3. Server calls `add_child(enemy, true)` inside the `spawn_path` target.
4. `MultiplayerSpawner` detects the new child, matches the scene against its `spawnable_scenes` registry, and sends the spawn notification + initial `MultiplayerSynchronizer` state to all peers automatically.
5. Clients receive the node in their own scene tree, already initialized with the server-set state.

No `spawn_function`, no Dictionary serialization loop is needed.

---

## Proposed Changes

### Module 1 — `wave_spawner.gd`

**File:** [wave_spawner.gd](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/wave_spawner.gd)

#### [MODIFY] `_spawn_enemy()` — strip custom spawn path, use `add_child`

**Before (lines 101–139):**
```gdscript
func _spawn_enemy() -> void:
    if not multiplayer.is_server():
        return
    print("WaveSpawner: _spawn_enemy() called")
    # Get the MultiplayerSpawner from the level scene
    var level = get_tree().current_scene
    var spawner: MultiplayerSpawner = level.get_node_or_null("EnemySpawner") as MultiplayerSpawner
    if not spawner:
        push_error("WaveSpawner: EnemySpawner (MultiplayerSpawner) node not found in level scene!")
        return

    # Assign a globally unique name for tracking
    _global_enemy_counter += 1
    var spawn_data: Dictionary = {
        "spawn_name": "Enemy_%d" % _global_enemy_counter,
        "spawn_position": global_position
    }
    print("WaveSpawner: About to call spawner.spawn() with data: ", spawn_data)

    # Use MultiplayerSpawner.spawn() to trigger replication to all clients
    # The scene is already registered in level.gd via add_spawnable_scene()
    var enemy: Node = spawner.spawn(spawn_data)
    print("WaveSpawner: spawner.spawn() returned: ", enemy)
    if not enemy:
        push_error("WaveSpawner: MultiplayerSpawner.spawn() failed to instantiate enemy.")
        return

    print("WaveSpawner: Enemy node valid, name=", enemy.name, " type=", enemy.get_class())
    # Ensure the enemy is tagged in the "Enemies" physics group
    enemy.add_to_group("Enemies")

    # Set collision layer to 8 (Layer 4 in Godot's 1-indexed UI = bit 3 = value 8)
    # so the AutomatedTurret's DetectionArea (collision_mask = 8) can detect it.
    if enemy is CollisionObject3D:
        (enemy as CollisionObject3D).collision_layer = 8
        (enemy as CollisionObject3D).collision_mask  = 3  # Floor(1) + Players(2)

    _spawned_count += 1
    print("WaveSpawner [%s]: Spawned %s via MultiplayerSpawner (%d/%d)" % [name, enemy.name, _spawned_count, wave_size])
```

**After (full replacement):**
```gdscript
func _spawn_enemy() -> void:
    if not multiplayer.is_server():
        return

    # Locate the container node that the MultiplayerSpawner is watching.
    # spawn_path on EnemySpawner is set to get_path() of the Level root in
    # level.gd::_setup_enemy_spawner(), so enemies become direct children of Level.
    var level: Node3D = get_tree().current_scene

    # Increment the global counter BEFORE instantiation so the name is
    # embedded at construction time, before any network traffic is sent.
    _global_enemy_counter += 1
    var enemy_name: String = "Enemy_%d" % _global_enemy_counter

    # --- Step 1: Instantiate (server only, not yet in the tree) ---
    var enemy: CharacterBody3D = _cached_enemy_scene.instantiate() as CharacterBody3D
    if not enemy:
        push_error("WaveSpawner: _cached_enemy_scene.instantiate() returned null.")
        return

    # --- Step 2: Set ALL initial state BEFORE add_child() ---
    # The MultiplayerSynchronizer inside enemy.tscn has spawn=true on
    # global_position and global_rotation, so these values are captured and
    # sent to clients as part of the spawn packet automatically.
    enemy.name            = enemy_name
    enemy.global_position = global_position  # Use the WaveSpawner's world position.

    # collision_layer/mask are baked into enemy.tscn (layer=8, mask=3),
    # so no manual override is needed here; left as an explicit assertion
    # for clarity during debugging.
    assert(enemy.collision_layer == 8, "enemy.tscn collision_layer must be 8 (layer 4)")

    # --- Step 3: add_child with force_readable_name=true ---
    # This is the trigger that makes MultiplayerSpawner notice the new node
    # and replicate it. After this line returns, all connected clients will
    # receive the instantiated node with the state set in Step 2.
    level.add_child(enemy, true)

    # --- Step 4: Post-tree server-side setup ---
    # add_to_group must be called after add_child so it is properly propagated.
    enemy.add_to_group("Enemies")

    _spawned_count += 1
    print("WaveSpawner [%s]: Spawned %s at %s (%d/%d)" % [
        name, enemy.name, enemy.global_position, _spawned_count, wave_size
    ])
```

> [!IMPORTANT]
> `_cached_enemy_scene` is already loaded once in `start_next_wave()`. No change to that loading logic is required. Only `_spawn_enemy()` changes.

---

### Module 2 — `enemy.gd`

**File:** [enemy.gd](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/enemy.gd)

The `spawn_data_handler` function (lines 41–63) is dead code in the automatic pipeline. It must be removed and its logic absorbed into `_ready()`. `_ready()` is called on the server **after** `add_child()`, so `global_position` is already set (as assigned in Step 2 above).

#### [MODIFY] Remove `spawn_data_handler`, move server-init into `_ready()`

**Before (lines 28–63):**
```gdscript
func _ready() -> void:
    # Ensure group membership is set (WaveSpawner also sets this before add_child,
    # but we add it here as a failsafe for manual scene placement).
    add_to_group("Enemies")

    if not multiplayer.is_server():
        # Clients only need position sync; disable all gameplay logic.
        set_physics_process(false)
        set_process(false)
        return

## Called by MultiplayerSpawner.spawn() with custom spawn data.
## Sets the enemy's name and position before the node enters the tree.
func spawn_data_handler(data: Dictionary) -> void:
    if "spawn_name" in data:
        name = data.spawn_name
    if "spawn_position" in data:
        global_position = data.spawn_position

    # --- Server-only setup ---
    if health_component:
        health_component.died.connect(_on_died)

    if attack_timer:
        attack_timer.wait_time = attack_interval
        attack_timer.one_shot = false
        attack_timer.timeout.connect(_on_attack_timer_timeout)
        attack_timer.start()

    # Hook up the NavigationAgent path-changed callback (Godot 4.x).
    nav_agent.velocity_computed.connect(_on_velocity_computed)

    # Defer the target assignment so NavigationServer has had one frame to
    # register the agent before we request a path.
    call_deferred("_assign_pathfinding_target")
```

**After (full replacement of those lines):**
```gdscript
func _ready() -> void:
    # Group membership is a failsafe for manual scene placement.
    # WaveSpawner also calls add_to_group("Enemies") after add_child().
    add_to_group("Enemies")

    if not multiplayer.is_server():
        # Clients: position/rotation are replicated by MultiplayerSynchronizer.
        # All gameplay logic is server-authoritative; disable it here.
        set_physics_process(false)
        set_process(false)
        return

    # --- Server-only initialisation (replaces spawn_data_handler) ---
    # global_position is already set by WaveSpawner before add_child(),
    # so no position assignment is needed here.

    if health_component:
        health_component.died.connect(_on_died)

    if attack_timer:
        attack_timer.wait_time = attack_interval
        attack_timer.one_shot = false
        attack_timer.timeout.connect(_on_attack_timer_timeout)
        attack_timer.start()

    # Hook up the NavigationAgent avoidance callback (Godot 4.x).
    nav_agent.velocity_computed.connect(_on_velocity_computed)

    # Defer so NavigationServer registers the agent before path is requested.
    call_deferred("_assign_pathfinding_target")
```

> [!NOTE]
> `spawn_data_handler` is deleted entirely. No other file references it, so there are no cascading removals needed.

---

### Module 3 — `level.gd`

**File:** [level.gd](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/level.gd)

`_setup_enemy_spawner()` (lines 321–333) is almost correct. The only structural change: `auto_spawning = false` is the right choice (we are triggering spawns manually via `WaveSpawner`), and `spawner.spawn_path = get_path()` correctly points the spawner at the `Level` node. **No changes needed to `level.gd`** — but an explicit comment clarifying the automatic-mode contract must be added for maintainability.

#### [MODIFY] `_setup_enemy_spawner()` — add clarifying comment only

```gdscript
func _setup_enemy_spawner() -> void:
    if not multiplayer.is_server():
        return
    print("Debug: _setup_enemy_spawner() running on server")
    var spawner: MultiplayerSpawner = get_node_or_null("EnemySpawner") as MultiplayerSpawner
    if not spawner:
        push_error("Level: EnemySpawner (MultiplayerSpawner) node is missing from level.tscn!")
        return

    # Register the enemy scene so the spawner can track children that match it.
    # Automatic Scene Mode: the spawner watches spawn_path for new children whose
    # PackedScene matches an entry in spawnable_scenes. When WaveSpawner calls
    # level.add_child(enemy, true), the spawner detects the match and replicates
    # the node + its MultiplayerSynchronizer initial state to all clients.
    # No spawn_function / custom callable is needed or configured.
    spawner.add_spawnable_scene("res://scenes/level/enemy.tscn")
    spawner.spawn_path = get_path()
    print("Debug: EnemySpawner configured — Automatic Scene Mode, spawn_path=", spawner.spawn_path)
```

---

### Module 4 — `enemy.tscn` (MultiplayerSynchronizer Configuration Audit)

**File:** [enemy.tscn](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scenes/level/enemy.tscn)

The `SceneReplicationConfig` (lines 26–32) is already correctly configured. The table below is a verification audit:

#### Property Configuration Table — `SceneReplicationConfig_enemy`

| Property Path | `spawn` | `replication_mode` | Effect |
|---|---|---|---|
| `.:global_position` | `true` | `1` (= `ALWAYS`) | Sent in spawn packet + continuously synced |
| `.:global_rotation` | `true` | `1` (= `ALWAYS`) | Sent in spawn packet + continuously synced |

**Replication mode values (Godot 4 enum):**

| Integer | `ReplicationMode` Constant | When data is sent |
|---|---|---|
| `0` | `NEVER` | Not replicated |
| `1` | `ALWAYS` | Every network tick |
| `2` | `ON_CHANGE` | Only when the value changes |

> [!IMPORTANT]
> `spawn = true` is the critical flag. It tells the engine to **include the current value in the initial spawn packet** that is sent to newly-connected or late-joining peers. Because `global_position` is set on the server *before* `add_child()`, the value is already correct when the synchronizer captures it. **No code change to `enemy.tscn` is required.**

#### `level.tscn` — `EnemySpawner` node audit

Current definition (lines 54–56):
```ini
[node name="EnemySpawner" type="MultiplayerSpawner" parent="."]
spawn_path = NodePath("..")
auto_spawning = false
```

> [!WARNING]
> `spawn_path = NodePath("..")` points to the **parent of Level**, which is the scene root's parent — likely invalid or pointing one level too high. The code in `_setup_enemy_spawner()` correctly overrides this at runtime with `spawner.spawn_path = get_path()` (which resolves to `NodePath(".")` = the Level node itself). The `.tscn` value is harmless because it is overwritten, but should be corrected to avoid confusion.

**Fix in `level.tscn` (line 55):**

```diff
-spawn_path = NodePath("..")
+spawn_path = NodePath(".")
```

---

### Module 5 — NetFox Alignment Note & Architecture Documentation

> [!NOTE]
> **Future Integration Path: NetFox**
>
> The current architecture (server-authoritative, `MultiplayerSynchronizer` with `ALWAYS` replication) is the correct foundation. If latency compensation, client-side prediction, or entity interpolation is required in a future milestone, the project can integrate [`NetFox`](https://github.com/foxssake/netfox) without structural disruption:
>
> - `TickManager` / `NetworkTime` plug into `_process` and `_physics_process` as drop-in wrappers — no scene hierarchy changes.
> - `RollbackSynchronizer` replaces `MultiplayerSynchronizer` on the `Enemy` node; the `replication_config` schema is the same format.
> - `NetworkAnimator` handles skeletal animation blending across ticks.
>
> The `DatabaseManager` autoload and all GUT test suites are completely decoupled from the networking layer and are **unaffected** by both this refactor and any future NetFox integration.

---

## Files Not Touched

| File | Reason |
|---|---|
| [database_manager.gd](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/database_manager.gd) | Autoload; no spawn dependency |
| [test/unit/test_database_manager.gd](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/test/unit/test_database_manager.gd) | No spawn logic tested here |
| [test/unit/test_health_component.gd](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/test/unit/test_health_component.gd) | Tests `HealthComponent` in isolation |
| [test/unit/test_player_input_states.gd](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/test/unit/test_player_input_states.gd) | No spawn dependency |
| [test/unit/test_turret_targeting.gd](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/test/unit/test_turret_targeting.gd) | Turret detection tested independently |
| [health_component.gd](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/health_component.gd) | No spawn logic |
| `automated_turret.gd` | Reads `Enemies` group; group assignment is preserved |
| `network.gd` | Transport layer; unchanged |

---

## Execution Sequence (Ordered Task List)

```
[ ] 1. Edit wave_spawner.gd — replace _spawn_enemy() body with automatic add_child() path
[ ] 2. Edit enemy.gd — delete spawn_data_handler(); merge its server-init block into _ready()
[ ] 3. Edit level.gd — add clarifying comment to _setup_enemy_spawner() (no logic change)
[ ] 4. Edit level.tscn — fix EnemySpawner spawn_path from ".." to "."
[ ] 5. Smoke test: run headless server, press F3, verify enemies spawn without crash
[ ] 6. Run full GUT suite: bash run_tests.sh — all 29 tests must still pass
```

---

## Verification Matrix

| Test | Pass Criterion | Tool |
|---|---|---|
| No crash on F3 | No `spawn_function` error in log | Headless server stdout |
| Enemy visible on client | Client sees capsule mesh at spawner position | In-editor multiplayer |
| Enemy position correct on frame 1 | Client position matches server `global_position` before movement | Debug print + MultiplayerSynchronizer |
| `Enemies` group populated | `get_tree().get_nodes_in_group("Enemies").size() > 0` after spawn | In-editor debug |
| Turret detects enemy | AutomatedTurret logs target acquisition | Server stdout |
| Enemy dies & frees | `queue_free()` called after 0.5s delay timer | Server stdout |
| GUT: health component | `test_health_component.gd` — 0 failures | `run_tests.sh` |
| GUT: turret targeting | `test_turret_targeting.gd` — 0 failures | `run_tests.sh` |
| GUT: database | `test_database_manager.gd` — 0 failures | `run_tests.sh` |
| GUT: inventory | `test_player_inventory_logic.gd` — 0 failures | `run_tests.sh` |
| GUT: player input | `test_player_input_states.gd` — 0 failures | `run_tests.sh` |
| GUT: workbench | `test_workbench_proximity.gd` — 0 failures | `run_tests.sh` |

---

## Open Questions

> [!IMPORTANT]
> **Q1 — Spawn point variety:** Should `global_position` in `_spawn_enemy()` always equal the `WaveSpawner`'s own `global_position`, or should there be a random offset around the spawner's origin to prevent N enemies stacking at the exact same point on frame 1?

> [!IMPORTANT]
> **Q2 — Late-join peers:** If a client connects mid-wave, the `MultiplayerSpawner` will replicate already-spawned enemies. Their *current* `global_position` will be correct (synced via `ALWAYS` mode), but `add_to_group("Enemies")` is a local call — late-joining clients will not have enemies in the `Enemies` group. Is this acceptable, or should group membership be stored in a replicated variable?
