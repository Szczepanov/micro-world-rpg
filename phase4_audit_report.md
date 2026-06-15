# Phase 4 Infrastructure Audit Report
**Project:** Pocket Realms (`micro-world-rpg`)
**Auditor:** Principal DevOps / Architecture Auditor
**Date:** 2026-05-29
**Scope:** Milestones 4.1, 4.2, 4.3

---

## Audit Summary

| Milestone | Check | Status |
|-----------|-------|--------|
| 4.1 | Asset Stripping Syntax — `export_filter` quoted | ✅ PASS |
| 4.1 | Isolation Flag — `.gdignore` in demo/plugin folder | ⚠️ WARNING |
| 4.1 | Artifact Permissions — `chmod +x` on binary | ✅ PASS |
| 4.2 | Home Directory Permissions — `--create-home --home-dir` | ✅ PASS |
| 4.2 | Recursive `chown -R` on `/app` and `/home/gameserver` | ✅ PASS |
| 4.2 | GDExtension Whitelist — negation rules in `.dockerignore` | ⚠️ WARNING |
| 4.3 | Async Spawning Race — `child_entered_tree` await guard | ✅ PASS |
| 4.3 | Hook A (Load) — `network.gd` calls `load_player_session()` | ✅ PASS |
| 4.3 | Hook B (Save Match) — `base_heart.gd` calls `save_match_result()` | ✅ PASS |
| 4.3 | Hook C (Graceful Exit) — `NOTIFICATION_WM_CLOSE_REQUEST` flush | ✅ PASS |
| 4.3 | Autoload — `DatabaseManager` registered in `project.godot` | ✅ PASS |

**Overall:** 9 PASS · 0 FAIL · 2 WARNING (non-blocking but should be resolved)

---

## Milestone 4.1 — Headless Compiler Automation

### CHECK 1.1 — Asset Stripping Syntax: `export_filter` Value Quoting

| Field | Value |
|-------|-------|
| **File** | [`build_server.sh`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/build_server.sh) (L44–L85) and [`export_presets.cfg`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/export_presets.cfg) (L407–L445) |
| **Expected** | `export_filter="custom_resources"` (string, quoted) |
| **Actual** | `export_filter="custom_resources"` is present on **L52** of `build_server.sh` inside the heredoc, and on **L414** of `export_presets.cfg` in the final canonical `[preset.1]` block named `"Linux Dedicated Server"` |
| **Status** | ✅ **PASS** |

> **Finding:** The preset block in `build_server.sh` correctly uses `export_filter="custom_resources"` (string form). The final block in `export_presets.cfg` (L407–L445) also uses the correct string form. Godot's INI parser requires this to be a quoted string identifier, not a bare enum name.

> [!WARNING]
> **Structural Defect in `export_presets.cfg`:** The file contains **11 duplicate `[preset.1]` / `[preset.1.options]` blocks** (L47–L406), all orphaned without a `name=` declaration. These are the residue of repeated `build_server.sh` executions whose `sed` deletion logic only removes blocks where `name="Linux Dedicated Server"` appears, leaving the `[preset.1]` header and the `[preset.1.options]` block behind. While Godot parses only the *last* complete preset, this bloat causes the file to be 446 lines instead of ~60, makes git history unreadable, and could confuse CI tooling.
>
> **Corrective Action for Coding Agent:** Rewrite the `build_server.sh` sed/Python block replacement section to use a robust state-machine approach that deletes the entire orphaned block (both `[preset.1]` header and the subsequent `[preset.1.options]` section) regardless of whether a `name=` line is present. Then truncate `export_presets.cfg` to just `[preset.0]` (the Linux client preset) and the single clean `[preset.1]` dedicated server block.

---

### CHECK 1.2 — Isolation Flag: `.gdignore` in Plugin Demo Folders

| Field | Value |
|-------|-------|
| **File** | `res://godot-sqlite-4.6/demo/.gdignore` (expected) |
| **Actual** | No `godot-sqlite-4.6/` directory exists at the project root. The SQLite addon is installed at `addons/godot-sqlite/` with no separate demo subfolder present. |
| **Status** | ⚠️ **WARNING — Not Applicable / Unverifiable** |

> **Finding:** The audit spec references `res://godot-sqlite-4.6/demo` as a potential asset-bleed source. This path does not exist in the repository. The addon was installed cleanly under `addons/godot-sqlite/` with no demo content bundled. No `.gdignore` is required because there is no demo folder to isolate.
>
> However, **no `.gdignore` file exists anywhere in the repo** (grep returned zero results). If a future contributor adds a plugin with a demo subfolder, there is no established convention. 

> [!NOTE]
> **Proactive Hardening Action for Coding Agent:** Create an empty `addons/gut/.gdignore` file. The GUT testing framework (`addons/gut/`) contains test runner scenes and example scripts that should not be included in any server export. Add a `.gdignore` to its root to prevent any accidental inclusion if the export filter configuration drifts.

---

### CHECK 1.3 — Artifact Permissions: `chmod +x` Applied to Binary

| Field | Value |
|-------|-------|
| **File** | [`build_server.sh`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/build_server.sh) L125–L127 |
| **Expected** | `chmod +x "$OUTPUT_BINARY"` after successful export verification |
| **Actual** | `chmod +x "$OUTPUT_BINARY"` is present on **L127**, guarded by the artifact existence check on L120 |
| **Status** | ✅ **PASS** |

> **Finding:** Execution permission is applied in step 6, after both the Godot exit code check (L112) and the file existence guard (L120). The ordering is correct — the binary cannot be `chmod`'d before it is confirmed to exist.

---

## Milestone 4.2 — Ultra-Lean Containerization

### CHECK 2.1 — Home Directory Permissions: `--create-home --home-dir`

| Field | Value |
|-------|-------|
| **File** | [`Dockerfile`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/Dockerfile) L43–L44 |
| **Expected** | `useradd --system --create-home --home-dir /home/gameserver --gid gameserver gameserver` |
| **Actual** | Exact match on L44: `useradd --system --create-home --home-dir /home/gameserver --gid gameserver gameserver` |
| **Status** | ✅ **PASS** |

> **Finding:** Both `--create-home` and `--home-dir /home/gameserver` are present. This is critical because Godot's `user://` path resolves to `~/.local/share/godot/` at runtime. Without a valid writable home directory, the SQLite `user://pocket_realms.db` path in `database_manager.gd` would throw a fatal write error on container startup.

---

### CHECK 2.2 — Recursive `chown -R` Across `/app` and `/home/gameserver`

| Field | Value |
|-------|-------|
| **File** | [`Dockerfile`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/Dockerfile) L47–L48, L66 |
| **Expected** | `chown -R gameserver:gameserver /app /home/gameserver` |
| **Actual** | L47–L48: `mkdir -p /app /home/gameserver && chown -R gameserver:gameserver /app /home/gameserver`. L66 repeats `chown -R gameserver:gameserver /app` after the `COPY` instructions. |
| **Status** | ✅ **PASS** |

> **Finding:** Ownership is applied twice: once pre-COPY to establish the directories, and again post-COPY (L66) to capture any files introduced by the `COPY` instructions on L54–L59. This double-application is intentional and correct — Docker's `COPY` can introduce files owned by root, and the second `chown` ensures the `gameserver` user has write access to everything under `/app`.

---

### CHECK 2.3 — GDExtension Whitelist: Negation Rules in `.dockerignore`

| Field | Value |
|-------|-------|
| **File** | [`.dockerignore`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/.dockerignore) L31–L37 |
| **Expected** | `!addons/godot-sqlite/`, `!addons/godot-sqlite/gdsqlite.gdextension`, `!addons/godot-sqlite/bin/*linux*.so` |
| **Actual** | L34: `!addons/godot-sqlite/`, L35: `!addons/godot-sqlite/gdsqlite.gdextension`, L36: `!addons/godot-sqlite/bin/`, L37: `!addons/godot-sqlite/bin/*linux*.so` |
| **Status** | ⚠️ **WARNING — Logic Gap Detected** |

> **Finding:** The three required negation patterns are present. However, there is a structural defect in the negation chain. Because the top-level rule `*.gd` (L27) is present and `.dockerignore` glob matching does not recurse automatically through whitelisted directories, the file `.gitignore` and `.gd` files within the whitelisted `addons/godot-sqlite/` subdirectory are explicitly excluded. Crucially, `godot-sqlite.gd` (the addon loader script) may be stripped from the build context.
>
> More critically: `.dockerignore` does **not** have a blanket `addons/` ignore rule, which means ALL addon content (including `addons/gut/` with its 300+ test files) is passed to the Docker build context by default. The `addons/godot-sqlite/` whitelist is therefore redundant — the problem is that non-SQLite addon content is *not being excluded*, not that SQLite content is being included.

> [!IMPORTANT]
> **Corrective Action for Coding Agent:** Restructure `.dockerignore` to:
> 1. Add `addons/` as a blanket ignore rule.
> 2. Then re-add the three negation rules for `addons/godot-sqlite/` (the whitelist). This ensures only the SQLite driver enters the build context. Also add `!addons/godot-sqlite/godot-sqlite.gd` and `!addons/godot-sqlite/plugin.cfg` to the whitelist.
>
> ```
> # Ignore all addons (test frameworks, editor tools, etc.)
> addons/
> # CRITICAL WHITELIST: Only the compiled SQLite runtime is needed
> !addons/godot-sqlite/
> !addons/godot-sqlite/godot-sqlite.gd
> !addons/godot-sqlite/plugin.cfg
> !addons/godot-sqlite/gdsqlite.gdextension
> !addons/godot-sqlite/bin/
> !addons/godot-sqlite/bin/*linux*.so
> ```

---

## Milestone 4.3 — Session State & SQLite Persistence

### CHECK 3.1 — Async Spawning Race: `child_entered_tree` Await Guard

| Field | Value |
|-------|-------|
| **File** | [`level.gd`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/level.gd) L73–L112 |
| **Expected** | If `player_node` is null, `await players_container.child_entered_tree` before calling `inventory.from_dict()` |
| **Actual** | L79–L87: null check fires, emits log line, then `await players_container.child_entered_tree`. L82 re-fetches the node. L85–L87: second null check with `push_error` and `return`. L94–L95: `is_node_ready()` guard with `await player_node.ready`. L103: `inventory.from_dict(inv_dict)` is only called after all guards pass. |
| **Status** | ✅ **PASS** |

> **Finding:** The race condition is fully guarded. The implementation uses a two-stage await: first waiting for any child to be added (`child_entered_tree`), then waiting for the specific node's `ready` signal. This is the correct pattern for Godot's deferred scene tree insertion flow.

---

### CHECK 3.2 — Hook A (Load): `network.gd:_on_player_connected` → `load_player_session()`

| Field | Value |
|-------|-------|
| **File** | [`network.gd`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/network.gd) L70–L76 |
| **Expected** | `_on_player_connected` calls `DatabaseManager.load_player_session(id, username)` |
| **Actual** | L71–L76: `if DisplayServer.get_name() == "headless":` guard, then `get_node("/root/DatabaseManager").load_player_session(id, username)` |
| **Status** | ✅ **PASS** |

> **Finding:** The call is correctly gated behind a headless display check, ensuring it only runs on the dedicated server. The `username` is derived from `players.get(id, {}).get("nick", "Player_%d" % id)`, which has a safe fallback. The `has_node("/root/DatabaseManager")` guard on L74 prevents crashes if the autoload is missing.

> [!NOTE]
> **Minor Race Risk:** At the time `_on_player_connected(id)` fires, the client has just connected at the TCP/ENet level. The `Network.players` dictionary may not yet contain the `id` entry (it is populated via the `_register_player` RPC on L80–L83, which is sent *after* this callback). The username lookup on L73 (`players.get(id, {})`) will therefore return the fallback `"Player_%d"` for every connection except the host. This means the database player record created on first connection will have a generated ID instead of the real nickname.
>
> **Corrective Action:** Move `load_player_session` to fire inside `_register_player` (after the `players` dict is populated), or connect the session load to a signal emitted after player info exchange is complete.

---

### CHECK 3.3 — Hook B (Save Match): `base_heart.gd:_on_core_died` → `save_match_result()`

| Field | Value |
|-------|-------|
| **File** | [`base_heart.gd`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/base_heart.gd) L24–L48 |
| **Expected** | `save_match_result()` is called **before** `trigger_defeat.rpc()` |
| **Actual** | L27–L45: full `save_match_result()` call with wave count, final HP, and duration calculation. L48: `trigger_defeat.rpc()` fires after. |
| **Status** | ✅ **PASS** |

> **Finding:** Ordering is correct — the DB write completes synchronously before the broadcast RPC. The duration calculation on L37–L39 correctly reads `_match_start_time_unix` from `DatabaseManager` (set in `level.gd:_ready()` on L25–L26). The `get(...) if true else 0` construct on L38 is a defensive workaround for Godot's property access on unknown nodes — it is functional but inelegant.
>
> **Minor Note:** The `if true else 0` pattern on L38 is dead code (the condition is always `true`). It should be cleaned up to a direct `get_node("/root/DatabaseManager").get("_match_start_time_unix")` or an exported property.

---

### CHECK 3.4 — Hook C (Graceful Exit): `NOTIFICATION_WM_CLOSE_REQUEST` Flush

| Field | Value |
|-------|-------|
| **File** | [`level.gd`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/level.gd) L443–L459 |
| **Expected** | `_notification(what)` intercepts `NOTIFICATION_WM_CLOSE_REQUEST` and calls `DatabaseManager.flush_all_inventories(inv_map)` |
| **Actual** | L450–L459: `if what == NOTIFICATION_WM_CLOSE_REQUEST and multiplayer.is_server():` guard, builds `inv_map` dict from all children with `get_inventory()`, calls `get_node("/root/DatabaseManager").flush_all_inventories(inv_map)`, then calls `get_tree().quit()` |
| **Status** | ✅ **PASS** |

> **Finding:** The implementation correctly handles the Docker `SIGTERM` → Godot `NOTIFICATION_WM_CLOSE_REQUEST` propagation path. This works because the `Dockerfile` entrypoint uses exec form (`CMD ["./server.x86_64", ...]`) rather than a shell wrapper, allowing SIGTERM to reach the Godot process directly.

> [!IMPORTANT]
> **Critical Gap — Missing `get_tree().set_quit_on_go_back(false)` or `get_viewport().set_input_as_handled()`:** On Linux/Docker, `NOTIFICATION_WM_CLOSE_REQUEST` is only delivered if `get_tree().auto_accept_quit` is set to `false`. If it remains `true` (the Godot default), the engine will quit *before* `_notification` is called, skipping the flush entirely.
>
> **Corrective Action for Coding Agent:** Add the following to `level.gd:_ready()`:
> ```gdscript
> # Ensure _notification(NOTIFICATION_WM_CLOSE_REQUEST) fires before the engine quits.
> # Required for graceful DB flush on SIGTERM in headless/Docker deployments.
> if DisplayServer.get_name() == "headless":
>     get_tree().auto_accept_quit = false
> ```

---

### CHECK 3.5 — Autoload Configuration: `DatabaseManager` in `project.godot`

| Field | Value |
|-------|-------|
| **File** | [`project.godot`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/project.godot) L24–L29 |
| **Expected** | `DatabaseManager="*res://scripts/database_manager.gd"` present alongside `GridManager`, `Network`, `ItemDatabase` |
| **Actual** | L26: `Network="*res://scripts/network.gd"`, L27: `ItemDatabase="*res://scripts/item_database.gd"`, L28: `GridManager="*res://scripts/grid_manager.gd"`, L29: `DatabaseManager="*res://scripts/database_manager.gd"` |
| **Status** | ✅ **PASS** |

> **Finding:** All four required autoloads are registered in the correct order. The `*` prefix (Godot's "enabled" flag) is present on all entries. `DatabaseManager` is the last entry, which is appropriate since it depends on `Network` being available at `_ready()` time.

---

## Critical Corrective Actions — Priority Queue for Coding Agent

The following items require code changes, ordered by severity:

| Priority | Severity | Action | File |
|----------|----------|--------|------|
| 1 | 🔴 HIGH | Add `get_tree().auto_accept_quit = false` in headless `_ready()` to enable `NOTIFICATION_WM_CLOSE_REQUEST` | `level.gd` |
| 2 | 🟠 MEDIUM | Restructure `.dockerignore` to add `addons/` blanket ignore then re-whitelist only `addons/godot-sqlite/` contents | `.dockerignore` |
| 3 | 🟠 MEDIUM | Move `load_player_session()` call to fire after `players` dict is populated (inside or after `_register_player` RPC) to get the real username | `network.gd` |
| 4 | 🟡 LOW | Scrub duplicate orphaned `[preset.1]` blocks from `export_presets.cfg`; fix `build_server.sh` sed logic | `export_presets.cfg`, `build_server.sh` |
| 5 | 🟡 LOW | Create `addons/gut/.gdignore` to exclude GUT test framework from any future export scans | new file |
| 6 | 🟢 COSMETIC | Remove dead `if true else 0` guard in `base_heart.gd:_on_core_died` duration calculation | `base_heart.gd` L38 |

---

## ROADMAP.md Status Recommendation

Based on this audit, the Phase 4 milestones should be updated as follows:

- **4.1** → `[-]` In Progress (functional but `export_presets.cfg` is corrupt with duplicate blocks; sed replacement logic needs fixing)
- **4.2** → `[-]` In Progress (core structure correct but `.dockerignore` has an addons blanket-exclude gap and `auto_accept_quit` is unset)
- **4.3** → `[-]` In Progress (all hooks present but `load_player_session` username race and missing `auto_accept_quit` are blocking correctness in production)
