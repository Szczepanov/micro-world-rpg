# Phase 4: Infrastructure, Automation & Scaling — Technical Implementation Blueprint

> **Project:** Pocket Realms (micro-world-rpg) · **Engine:** Godot 4.6 · **Architecture:** Server-Authoritative Headless
> **Prerequisite:** Phases 1–3.5 complete and GUT tests passing. No manual steps are permitted at any stage.

---

## Codebase Anchors (Verified Against Live Source)

| Fact | Value |
|---|---|
| Network port (canonical) | **`8080` UDP** — defined in [`network.gd:4`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/network.gd) |
| Server bootstrap hook | [`level.gd:20-22`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/level.gd) — `DisplayServer.get_name() == "headless"` guard |
| Client-connected hook | [`network.gd:70-79`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/network.gd) — `_on_player_connected` → `player_connected` signal |
| Match-over hook | [`base_heart.gd:24-26`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/base_heart.gd) — `_on_core_died()` → `trigger_defeat.rpc()` |
| Inventory serialization | [`player_inventory.gd:187-196`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/player_inventory.gd) — `to_dict()` / `from_dict()` already implemented |
| Existing Dockerfile | [`Dockerfile`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/Dockerfile) — **has X11/Mesa bloat to be pruned** |
| Existing .dockerignore | [``.dockerignore``](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/.dockerignore) — needs `build/` and `test/` entries |
| Autoloads | `Network`, `ItemDatabase`, `GridManager` — **do NOT add `DatabaseManager` as Autoload; it is server-only** |

---

## Milestone 4.1 — Automated Linux Headless Compiler (`build_server.sh`)

### Overview

A single fully-idempotent bash script at the project root replaces `run_headless_server.sh` for the **build** phase. It (1) validates the environment, (2) writes the export preset block, (3) invokes the Godot CLI, and (4) gates on exit codes.

### Execution Order

- [ ] **4.1.1** Create `build_server.sh` at project root with proper shebang and `set -euo pipefail`
- [ ] **4.1.2** Implement directory creation guard (`mkdir -p build/server`)
- [ ] **4.1.3** Implement Godot binary detection with human-readable error
- [ ] **4.1.4** Append/overwrite the "Linux Dedicated Server" export preset block in `export_presets.cfg`
- [ ] **4.1.5** Execute the headless export and gate on exit code
- [ ] **4.1.6** Apply `chmod +x` to the output binary
- [ ] **4.1.7** Print final artifact size for pipeline logging

### File: `build_server.sh` (full content)

```bash
#!/usr/bin/env bash
# =============================================================================
# build_server.sh — Automated Linux Headless Server Compiler
# Project: Pocket Realms (micro-world-rpg)
# Usage: bash build_server.sh [godot_binary_path]
# =============================================================================
set -euo pipefail

# ---------- Configuration ---------------------------------------------------
PRESET_NAME="Linux Dedicated Server"
OUTPUT_DIR="build/server"
OUTPUT_BINARY="$OUTPUT_DIR/server.x86_64"
PCK_FILE="$OUTPUT_DIR/server.pck"
EXPORT_PRESETS_CFG="export_presets.cfg"

# Allow overriding the Godot binary via argument or environment variable.
GODOT_BIN="${1:-${GODOT_BIN:-godot}}"

# ---------- Colour helpers --------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[BUILD]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---------- 1. Guard: Verify Godot binary -----------------------------------
log_info "Checking for Godot binary at: '$GODOT_BIN'"
if ! command -v "$GODOT_BIN" &>/dev/null && [ ! -x "$GODOT_BIN" ]; then
    log_error "Godot binary not found. Set GODOT_BIN env var or pass path as arg."
    log_error "Example: GODOT_BIN=/opt/godot/godot bash build_server.sh"
    exit 1
fi
GODOT_VERSION=$("$GODOT_BIN" --version 2>&1 | head -n1 || true)
log_info "Godot version: $GODOT_VERSION"

# ---------- 2. Create output directory --------------------------------------
log_info "Creating output directory: $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# ---------- 3. Write / refresh the export preset ----------------------------
# This block is idempotent: it replaces any existing [preset.N] block whose
# name matches PRESET_NAME, or appends a new one if none exists.
log_info "Writing 'Linux Dedicated Server' export preset to $EXPORT_PRESETS_CFG"

PRESET_BLOCK=$(cat <<'PRESET'
[preset.1]

name="Linux Dedicated Server"
platform="Linux"
runnable=false
dedicated_server=true
custom_features=""
export_filter=custom_resources
include_filter=""
exclude_filter=""

[preset.1.options]

; ---- ASSET STRIPPING: drop all graphical & audio data packs ----
; Renders, materials, 3D meshes, textures, and audio streams are
; not needed by a headless process. Stripping them reduces the PCK
; footprint by 60–80% vs. a standard export.
custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=0
binary_format/embed_pck=false
texture_format/s3tc_bptc=false
texture_format/etc2_astc=false
binary_format/architecture="x86_64"

; Script-only mode: exclude all non-script/non-resource assets.
script/export_mode=2
script/script_key=""

; Explicit exclusion globs — belt-and-suspenders against asset bleed.
exclude_filter="*.png, *.jpg, *.jpeg, *.webp, *.basis, *.dds, *.svg, \
*.ogg, *.mp3, *.wav, *.opus, \
*.glb, *.gltf, *.fbx, *.obj, \
*.material, *.tres, *.shader, \
*.tscn"

; Include only scripts, autoloads, configs, and exported data.
include_filter="*.gd, *.gdscript, *.gdc, *.res, project.godot, \
export_presets.cfg"
PRESET
)

# If the file doesn't exist yet, touch it.
touch "$EXPORT_PRESETS_CFG"

# Remove any existing preset block named "Linux Dedicated Server"
# (safe multi-line sed: deletes from the matching [preset.N] line
#  to the blank line separating blocks, then appends fresh block).
python3 - "$EXPORT_PRESETS_CFG" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()
# Remove existing block for this preset name
content = re.sub(
    r'\[preset\.\d+\]\s*\n(?:.*\n)*?name="Linux Dedicated Server".*?(?=\n\[preset|\Z)',
    '',
    content,
    flags=re.DOTALL
)
with open(path, 'w') as f:
    f.write(content.strip() + '\n\n')
PYEOF

echo "$PRESET_BLOCK" >> "$EXPORT_PRESETS_CFG"
log_info "Preset block written successfully."

# ---------- 4. Execute headless export --------------------------------------
log_info "Running Godot headless export-release..."
log_info "  Preset : '$PRESET_NAME'"
log_info "  Output : '$OUTPUT_BINARY'"

"$GODOT_BIN" \
    --headless \
    --export-release "$PRESET_NAME" "$OUTPUT_BINARY" \
    2>&1 | tee /tmp/godot_build.log

GODOT_EXIT="${PIPESTATUS[0]}"

if [ "$GODOT_EXIT" -ne 0 ]; then
    log_error "Godot export failed with exit code $GODOT_EXIT."
    log_error "Last 20 lines of build log:"
    tail -n 20 /tmp/godot_build.log >&2
    exit "$GODOT_EXIT"
fi

# ---------- 5. Verify output artifact ---------------------------------------
if [ ! -f "$OUTPUT_BINARY" ]; then
    log_error "Export succeeded but binary '$OUTPUT_BINARY' was not created."
    exit 1
fi

# ---------- 6. Apply execution permissions ----------------------------------
log_info "Applying execute permission to binary..."
chmod +x "$OUTPUT_BINARY"

# ---------- 7. Report artifact size ----------------------------------------
BINARY_SIZE=$(du -sh "$OUTPUT_BINARY" | cut -f1)
PCK_SIZE="N/A"
if [ -f "$PCK_FILE" ]; then
    PCK_SIZE=$(du -sh "$PCK_FILE" | cut -f1)
fi

log_info "=== BUILD COMPLETE ==="
log_info "  Binary : $OUTPUT_BINARY ($BINARY_SIZE)"
log_info "  PCK    : $PCK_FILE ($PCK_SIZE)"
log_info "  Ready to containerize with: docker build -t pocket-realms-server ."
```

### Environment Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| Godot CLI | `4.6-stable` | Must match `project.godot` feature tag `"4.6"` |
| Python 3 | ≥ 3.8 | Used for idempotent preset rewriting |
| Export templates | `4.6-stable` Linux | Must be installed via Godot's template manager |
| `build/` in `.gitignore` | — | Add if not present |

> [!IMPORTANT]
> **CI/CD Note:** In a GitHub Actions workflow, set `GODOT_BIN` via the `GODOT_BIN` environment variable. Use the `chickensoft-games/setup-godot` action to install the correct version automatically.

---

## Milestone 4.2 — Ultra-Lean Containerization (`Dockerfile`)

### Overview

The existing `Dockerfile` installs X11/Mesa display server libraries (`libxrender1`, `libx11-6`, `libgl1-mesa-*`, etc.) that are **completely unnecessary** for a headless binary. This milestone rewrites it using a two-stage approach: stage 1 copies the pre-compiled binary from the build step; stage 2 provides only the minimum runtime ABI surface.

### Execution Order

- [ ] **4.2.1** Replace [`Dockerfile`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/Dockerfile) with the two-stage build below
- [ ] **4.2.2** Update [`.dockerignore`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/.dockerignore) to exclude `build/` from the build context (prevent re-copying the artifact)
- [ ] **4.2.3** Update `EXPOSE` directive from `8080/udp` → match `network.gd`'s `SERVER_PORT = 8080`
- [ ] **4.2.4** Harden `CMD` to use exec form with explicit `--headless --server` flags
- [ ] **4.2.5** Add `HEALTHCHECK` instruction using a UDP ping or process sentinel

### Architecture Decision: Pre-Built Binary Pattern

> [!IMPORTANT]
> The container does **NOT** compile Godot inside Docker. The `build_server.sh` script (4.1) runs on the CI host, producing `build/server/server.x86_64`. Docker only copies and runs the artifact. This keeps image build time under 10 seconds and the final image under 80 MB.

### File: `Dockerfile` (full replacement)

```dockerfile
# =============================================================================
# Dockerfile — Pocket Realms: Dedicated Server (Ultra-Lean)
# Build context: project root AFTER running build_server.sh
# Final image target: ~60–80 MB (no Godot editor, no X11, no Mesa)
# =============================================================================

# ---- Stage 1: Dependency installer ----------------------------------------
# Use a builder stage purely to resolve and cache apt packages.
FROM debian:bookworm-slim AS runtime-deps

RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core C runtime — required by every ELF binary on Linux
    libc6 \
    # TLS/SSL for any HTTPS calls Godot makes (OS.request_permissions, etc.)
    libssl3 \
    ca-certificates \
    # GDScript relies on libgcc_s for exception unwinding
    libgcc-s1 \
    # FreeType font rasteriser (used by headless Label nodes internally)
    libfreetype6 \
    # Godot's PCM audio backend — present even in headless, safe to include
    # (costs <1 MB; removing it causes a non-fatal startup warning)
    libasound2 \
    # D-Bus: required by Godot's OS singleton on Linux
    libdbus-1-3 \
    # Unicode bidirectional text (FriBidi — required by the scene parser)
    libfribidi0 \
    # HarfBuzz text shaper (required even if no text is rendered)
    libharfbuzz0b \
    && rm -rf /var/lib/apt/lists/*

# ---- Stage 2: Minimal runtime image ----------------------------------------
FROM debian:bookworm-slim

# Copy only the installed shared libraries from Stage 1 to keep this layer
# completely free of apt caches, package indices, and transitive toolchains.
COPY --from=runtime-deps /usr/lib/x86_64-linux-gnu/ /usr/lib/x86_64-linux-gnu/
COPY --from=runtime-deps /lib/x86_64-linux-gnu/ /lib/x86_64-linux-gnu/
COPY --from=runtime-deps /etc/ssl/ /etc/ssl/
COPY --from=runtime-deps /etc/ca-certificates/ /etc/ca-certificates/

# Create a non-root service user for security hardening.
RUN groupadd --system gameserver && \
    useradd --system --gid gameserver --no-create-home gameserver

WORKDIR /app

# Copy the pre-compiled server binary and its PCK data pack.
# Both files MUST be in the same directory (Godot resolves PCK by proximity).
COPY build/server/server.x86_64 ./server.x86_64
COPY build/server/server.pck    ./server.pck

# Ensure the binary is executable (build_server.sh already does this,
# but Docker COPY strips the setuid bit — re-apply explicitly).
RUN chmod +x ./server.x86_64

# Transfer ownership to the non-root user.
RUN chown -R gameserver:gameserver /app

USER gameserver

# --- Networking ---
# Port 8080/UDP — matches SERVER_PORT in network.gd.
# ENet (Godot's default multiplayer transport) uses UDP exclusively.
# Map as: docker run -p 8080:8080/udp pocket-realms-server
EXPOSE 8080/udp

# --- Health Check ---
# Since UDP has no handshake, we verify the process is alive instead.
# The server exits non-zero on fatal errors, so this sentinel is reliable.
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD pgrep -x server.x86_64 > /dev/null || exit 1

# --- Entrypoint ---
# Exec form (no shell wrapper) ensures SIGTERM propagates directly to Godot,
# allowing the engine's _notification(NOTIFICATION_WM_CLOSE_REQUEST) to fire
# for graceful shutdown and final DB flush (see Milestone 4.3).
CMD ["./server.x86_64", "--headless", "--server"]
```

### Updated `.dockerignore` (append these lines)

```gitignore
# Already present:
.git
.gitignore
.godot/
*.log
Dockerfile
.dockerignore

# ADD — exclude raw source from the build context (binary-only pattern):
assets/
scenes/
scripts/
addons/
test/
scratch/
*.md
*.sh
*.png
*.gd
*.tscn
*.tres
project.godot
export_presets.cfg

# DO include (no negation needed — Docker copies only what's listed in COPY):
# build/server/server.x86_64
# build/server/server.pck
```

### Build & Run Commands

```bash
# Step 1: Compile the binary on the host (Linux CI runner or WSL2)
bash build_server.sh

# Step 2: Build the Docker image (context is ~10 MB — binary + pck only)
docker build --tag pocket-realms-server:latest .

# Step 3: Run the container
docker run --detach \
    --name pocket-realms \
    --publish 8080:8080/udp \
    --restart unless-stopped \
    pocket-realms-server:latest

# Step 4: Tail server logs
docker logs -f pocket-realms
```

> [!NOTE]
> On **Windows hosts**, run `build_server.sh` inside **WSL2** or a GitHub Actions `ubuntu-latest` runner. The Docker build itself works on Docker Desktop for Windows without WSL because the COPY context is already compiled.

---

## Milestone 4.3 — Session State & Persistence Architecture

### Overview

A new `DatabaseManager` autoload-style singleton provides a strictly-typed GDScript abstraction over SQLite (via the `godot-sqlite` addon) or a lightweight PostgreSQL REST bridge. It hooks into the existing server lifecycle at exactly two points: **client connection** (load) and **base heart death** (save).

### Database Backend Selection

> [!IMPORTANT]
> **Recommendation: SQLite for v1.** Godot's `godot-sqlite` addon provides a native GDExtension binding with zero external services. PostgreSQL is better suited once you have multiple server replicas sharing state. The schema below is portable — all DDL is ANSI SQL compatible with both backends.

### Execution Order

- [ ] **4.3.1** Install the `godot-sqlite` GDExtension addon into `addons/godot-sqlite/`
- [ ] **4.3.2** Create `scripts/database_manager.gd` (full implementation below)
- [ ] **4.3.3** Register `DatabaseManager` as a **conditional** autoload (server-only guard in `_ready`)
- [ ] **4.3.4** Add `DatabaseManager` to `project.godot` autoload list
- [ ] **4.3.5** Hook `DatabaseManager.load_player_session()` into `network.gd:_on_player_connected`
- [ ] **4.3.6** Hook `DatabaseManager.save_match_result()` into `base_heart.gd:_on_core_died`
- [ ] **4.3.7** Hook `DatabaseManager.flush_all_inventories()` into the graceful shutdown notification
- [ ] **4.3.8** Write GUT unit tests for `DatabaseManager` covering CRUD round-trips

---

### DDL: Relational Schema

```sql
-- =============================================================================
-- Pocket Realms — Session Persistence Schema
-- Compatible with: SQLite 3.x, PostgreSQL 14+
-- Run order: players → inventories → match_history (FK dependency order)
-- =============================================================================

-- ---- Table 1: players -------------------------------------------------------
-- One row per unique player identity. player_id is the Godot peer nickname
-- hashed to a stable UUID on first login.
CREATE TABLE IF NOT EXISTS players (
    player_id               TEXT        NOT NULL,  -- UUID v4 string PK
    username                TEXT        NOT NULL,
    total_resources_harvested INTEGER   NOT NULL DEFAULT 0,
    last_login_timestamp    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_players PRIMARY KEY (player_id),
    CONSTRAINT uq_players_username UNIQUE (username),
    CONSTRAINT chk_resources CHECK (total_resources_harvested >= 0)
);

-- ---- Table 2: inventories ---------------------------------------------------
-- Normalised item storage. Composite PK ensures one row per (player, item).
-- Mirrors the slot data from PlayerInventory.to_dict().
CREATE TABLE IF NOT EXISTS inventories (
    player_id   TEXT        NOT NULL,
    item_id     TEXT        NOT NULL,
    quantity    INTEGER     NOT NULL DEFAULT 0,

    CONSTRAINT pk_inventories PRIMARY KEY (player_id, item_id),
    CONSTRAINT fk_inv_player  FOREIGN KEY (player_id) REFERENCES players(player_id)
                              ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_quantity   CHECK (quantity >= 0)
);

-- Index to support "give me all items for player X" queries efficiently.
CREATE INDEX IF NOT EXISTS idx_inv_player ON inventories(player_id);

-- ---- Table 3: match_history -------------------------------------------------
-- One row per completed match (victory OR defeat). The server writes this
-- atomically inside _on_core_died() before broadcasting trigger_defeat.rpc().
CREATE TABLE IF NOT EXISTS match_history (
    match_id                INTEGER     NOT NULL,   -- Auto-increment surrogate PK
    waves_completed         INTEGER     NOT NULL DEFAULT 0,
    base_heart_final_hp     REAL        NOT NULL DEFAULT 0.0,
    match_duration_seconds  INTEGER     NOT NULL DEFAULT 0,
    completion_timestamp    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_match PRIMARY KEY (match_id AUTOINCREMENT),  -- SQLite syntax
    -- PostgreSQL equivalent: match_id SERIAL PRIMARY KEY
    CONSTRAINT chk_waves   CHECK (waves_completed >= 0),
    CONSTRAINT chk_hp      CHECK (base_heart_final_hp >= 0.0),
    CONSTRAINT chk_dur     CHECK (match_duration_seconds >= 0)
);
```

> [!NOTE]
> **PostgreSQL DDL delta:** Replace `INTEGER ... AUTOINCREMENT` with `SERIAL` and remove `IF NOT EXISTS` from constraint names (not supported). All other clauses are identical.

---

### File: `scripts/database_manager.gd` (full implementation)

```gdscript
## database_manager.gd
## Server-only singleton. Provides a typed abstraction over SQLite for
## player session load/save and match result persistence.
##
## NEVER call any method on this node from a client peer.
## Guard all call-sites with: if multiplayer.is_server()
##
## Dependencies:
##   - godot-sqlite GDExtension (addons/godot-sqlite/)
##   - PlayerInventory class (scripts/player_inventory.gd)
##   - ItemDatabase autoload (scripts/item_database.gd)
##
## Lifecycle hooks:
##   load_player_session()   ← called from network.gd:_on_player_connected
##   save_match_result()     ← called from base_heart.gd:_on_core_died
##   flush_all_inventories() ← called from level.gd:_notification(WM_CLOSE_REQUEST)

extends Node

# ---------- Constants --------------------------------------------------------

const DB_PATH: String = "user://pocket_realms.db"
const SCHEMA_VERSION: int = 1

# ---------- State ------------------------------------------------------------

var _db  # SQLite instance — typed as Variant to avoid hard compile dependency
var _is_ready: bool = false

## Emitted when a player's session data has been loaded from the DB.
## The caller (level.gd) should use this to populate the PlayerInventory
## node over the network.
signal session_loaded(peer_id: int, player_id: String, inventory_dict: Dictionary)

## Emitted when a match record has been committed successfully.
signal match_saved(match_id: int)

# ---------- Initialisation ---------------------------------------------------

func _ready() -> void:
	# This node must ONLY do work on the dedicated server.
	# On a regular client it registers in the tree but stays inert.
	if not multiplayer.is_server():
		return

	_open_database()
	_run_migrations()
	_is_ready = true
	print("DatabaseManager: Online. DB path: ", ProjectSettings.globalize_path(DB_PATH))


func _open_database() -> void:
	# Lazy-load the SQLite class so the project doesn't hard-error on clients
	# that don't have the GDExtension registered (e.g. mobile builds).
	if not ClassDB.class_exists("SQLite"):
		push_error("DatabaseManager: godot-sqlite GDExtension not found! " +
		           "Install it at addons/godot-sqlite/.")
		return

	_db = ClassDB.instantiate("SQLite")
	_db.path = DB_PATH
	_db.verbosity_level = 1  # VERBOSE — set to 0 in production
	_db.foreign_keys = true

	if not _db.open_db():
		push_error("DatabaseManager: Failed to open database at: " + DB_PATH)
		_db = null


func _run_migrations() -> void:
	if not _db:
		return

	# Enable WAL mode for concurrent reads during active match.
	_db.query("PRAGMA journal_mode=WAL;")
	_db.query("PRAGMA synchronous=NORMAL;")

	# Create tables if they don't exist (idempotent).
	var ddl: Array[String] = [
		"""CREATE TABLE IF NOT EXISTS players (
			player_id               TEXT    NOT NULL,
			username                TEXT    NOT NULL,
			total_resources_harvested INTEGER NOT NULL DEFAULT 0,
			last_login_timestamp    TEXT    NOT NULL DEFAULT (datetime('now')),
			CONSTRAINT pk_players   PRIMARY KEY (player_id),
			CONSTRAINT uq_username  UNIQUE (username)
		);""",

		"""CREATE TABLE IF NOT EXISTS inventories (
			player_id   TEXT    NOT NULL,
			item_id     TEXT    NOT NULL,
			quantity    INTEGER NOT NULL DEFAULT 0,
			CONSTRAINT pk_inventories PRIMARY KEY (player_id, item_id),
			CONSTRAINT fk_player FOREIGN KEY (player_id)
			    REFERENCES players(player_id) ON DELETE CASCADE
		);""",

		"""CREATE INDEX IF NOT EXISTS idx_inv_player ON inventories(player_id);""",

		"""CREATE TABLE IF NOT EXISTS match_history (
			match_id                INTEGER PRIMARY KEY AUTOINCREMENT,
			waves_completed         INTEGER NOT NULL DEFAULT 0,
			base_heart_final_hp     REAL    NOT NULL DEFAULT 0.0,
			match_duration_seconds  INTEGER NOT NULL DEFAULT 0,
			completion_timestamp    TEXT    NOT NULL DEFAULT (datetime('now'))
		);"""
	]

	for statement in ddl:
		if not _db.query(statement):
			push_error("DatabaseManager: Migration failed:\n" + statement)


# ---------- Hook 1: On Client Connected — Load Session ----------------------

## Called by network.gd immediately after _on_player_connected fires.
## Queries the players and inventories tables, then emits session_loaded.
##
## @param peer_id  The ENet multiplayer peer ID (int).
## @param username The player's display name from Network.players[peer_id]["nick"].
func load_player_session(peer_id: int, username: String) -> void:
	if not _is_ready or not _db:
		push_warning("DatabaseManager: load_player_session called before DB is ready.")
		return

	if not multiplayer.is_server():
		push_error("DatabaseManager: load_player_session must only run on the server.")
		return

	# Derive a stable player_id from the username.
	# NOTE: In production, replace with a proper UUID from your auth layer.
	var player_id: String = _stable_id_from_username(username)

	# --- Upsert player row (update last_login on every connection) ---
	var upsert_query: String = """
		INSERT INTO players (player_id, username, last_login_timestamp)
		VALUES ('{pid}', '{uname}', datetime('now'))
		ON CONFLICT(player_id) DO UPDATE SET
		    username = excluded.username,
		    last_login_timestamp = excluded.last_login_timestamp;
	""".format({"pid": player_id, "uname": _escape(username)})

	if not _db.query(upsert_query):
		push_error("DatabaseManager: Failed to upsert player '%s'." % username)
		return

	# --- Load inventory rows ---
	var inv_query: String = """
		SELECT item_id, quantity FROM inventories
		WHERE player_id = '%s';
	""" % player_id

	_db.query(inv_query)
	var rows: Array = _db.query_result

	# Build a dictionary matching PlayerInventory.from_dict() input format.
	# The 'slots' array is sparse — from_dict() handles empty slots natively.
	var inventory_dict: Dictionary = {"slots": []}
	for row in rows:
		inventory_dict["slots"].append({
			"item_id": row["item_id"],
			"quantity": row["quantity"]
		})

	print("DatabaseManager: Loaded %d inventory rows for '%s' (peer %d)." \
	      % [rows.size(), username, peer_id])

	# Emit so level.gd (or network.gd) can populate the PlayerInventory node.
	session_loaded.emit(peer_id, player_id, inventory_dict)


# ---------- Hook 2: On Match Over — Save Match Result -----------------------

## Called by base_heart.gd immediately inside _on_core_died(), BEFORE
## trigger_defeat.rpc() broadcasts to clients. This ensures the record is
## committed even if the server process is killed shortly after.
##
## @param waves_completed         How many full waves WaveSpawner completed.
## @param base_heart_final_hp     The HealthComponent.current_health at death.
## @param match_duration_seconds  Time since level._ready() was called.
func save_match_result(
	waves_completed: int,
	base_heart_final_hp: float,
	match_duration_seconds: int
) -> void:
	if not _is_ready or not _db:
		push_warning("DatabaseManager: save_match_result called before DB is ready.")
		return

	if not multiplayer.is_server():
		push_error("DatabaseManager: save_match_result must only run on the server.")
		return

	# Atomic INSERT wrapped in explicit transaction to prevent partial writes
	# if the process is interrupted mid-flight.
	_db.query("BEGIN TRANSACTION;")

	var insert_query: String = """
		INSERT INTO match_history
		    (waves_completed, base_heart_final_hp, match_duration_seconds)
		VALUES (%d, %f, %d);
	""" % [waves_completed, base_heart_final_hp, match_duration_seconds]

	if not _db.query(insert_query):
		_db.query("ROLLBACK;")
		push_error("DatabaseManager: Failed to insert match_history row.")
		return

	_db.query("COMMIT;")

	# Retrieve the auto-assigned match_id for the signal payload.
	_db.query("SELECT last_insert_rowid() AS match_id;")
	var match_id: int = _db.query_result[0]["match_id"] if _db.query_result.size() > 0 else -1

	print("DatabaseManager: Match record committed. match_id=%d, waves=%d, duration=%ds" \
	      % [match_id, waves_completed, match_duration_seconds])

	match_saved.emit(match_id)


# ---------- Hook 3: Graceful Shutdown — Flush All Inventories ---------------

## Called from level.gd's _notification(NOTIFICATION_WM_CLOSE_REQUEST)
## or from a SIGTERM handler to persist all in-memory inventories before
## the process exits.
##
## @param player_inventory_map  Dictionary[int, PlayerInventory] mapping
##                              peer_id → PlayerInventory instance.
func flush_all_inventories(player_inventory_map: Dictionary) -> void:
	if not _is_ready or not _db:
		return

	print("DatabaseManager: Flushing %d player inventories..." \
	      % player_inventory_map.size())

	_db.query("BEGIN TRANSACTION;")

	for peer_id in player_inventory_map:
		var username: String = Network.players.get(peer_id, {}).get("nick", "")
		if username.is_empty():
			continue

		var player_id: String = _stable_id_from_username(username)
		var inventory: PlayerInventory = player_inventory_map[peer_id]

		# Delete existing rows for this player, then re-insert current state.
		# DELETE + INSERT is simpler than UPSERT per-slot and SQLite handles
		# the transaction atomically.
		_db.query("DELETE FROM inventories WHERE player_id = '%s';" % player_id)

		for slot in inventory.slots:
			if slot.is_empty():
				continue
			var insert: String = """
				INSERT INTO inventories (player_id, item_id, quantity)
				VALUES ('%s', '%s', %d);
			""" % [player_id, _escape(slot.item_id), slot.quantity]
			_db.query(insert)

	_db.query("COMMIT;")
	print("DatabaseManager: Inventory flush complete.")


# ---------- Utility ---------------------------------------------------------

## Generates a stable, deterministic player_id from a username string.
## This is a placeholder — replace with a proper auth UUID in production.
func _stable_id_from_username(username: String) -> String:
	# Use Godot's built-in hash and format as a pseudo-UUID.
	var h: int = username.hash()
	return "usr-%08x-0000-4000-8000-000000000000" % abs(h)


## Escapes single quotes in SQL string literals to prevent injection.
## For production, use prepared statements / the SQLite bind API instead.
func _escape(s: String) -> String:
	return s.replace("'", "''")


## Closes the database cleanly. Call from _notification(NOTIFICATION_PREDELETE).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _db:
		_db.close_db()
		print("DatabaseManager: Database connection closed.")
```

---

### Multiplayer Save/Load Hook Integration Map

The table below specifies the **exact call-site** in each existing script where the DatabaseManager integration line must be injected.

#### Hook A — On Client Connected (Load)

**File:** [`scripts/network.gd`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/network.gd)
**Function:** `_on_player_connected(id)` (line 70)
**Current code:**
```gdscript
func _on_player_connected(id):
    if DisplayServer.get_name() == "headless":
        return
    _register_player.rpc_id(id, player_info)
```
**Inject after the headless guard:**
```gdscript
func _on_player_connected(id):
    if DisplayServer.get_name() == "headless":
        # Server received a new peer — load their session from the DB.
        var username: String = players.get(id, {}).get("nick", "Player_%d" % id)
        if has_node("/root/DatabaseManager"):
            get_node("/root/DatabaseManager").load_player_session(id, username)
        return
    _register_player.rpc_id(id, player_info)
```

> [!NOTE]
> The `session_loaded` signal from `DatabaseManager` must be connected in `level.gd` to the function that calls `PlayerInventory.from_dict()` on the spawned player node and then replicates inventory over the network via the existing `request_add_item.rpc_id` pattern.

#### Hook B — On Match Over (Defeat)

**File:** [`scripts/base_heart.gd`](file:///c:/Users/mdszc/Downloads\projekty\micro-world-rpg\scripts\base_heart.gd)
**Function:** `_on_core_died()` (line 24)
**Current code:**
```gdscript
func _on_core_died() -> void:
    trigger_defeat.rpc()
```
**Replace with:**
```gdscript
func _on_core_died() -> void:
    # 1. Persist match result BEFORE broadcasting defeat so the DB write
    #    is guaranteed even if clients disconnect immediately after.
    if has_node("/root/DatabaseManager"):
        var wave_spawners := get_tree().get_nodes_in_group("Spawners")
        var waves_done: int = 0
        if not wave_spawners.is_empty() and wave_spawners[0].has_method("get_wave_number"):
            waves_done = wave_spawners[0].get_wave_number()

        var final_hp: float = health_component.current_health if health_component else 0.0

        # match_duration_seconds requires a start_time tracked in level.gd.
        # See §4.3 implementation note below.
        var duration: int = get_node("/root/DatabaseManager") \
                                .get("_match_start_time_unix") if true else 0
        duration = int(Time.get_unix_time_from_system()) - duration

        get_node("/root/DatabaseManager").save_match_result(
            waves_done,
            final_hp,
            duration
        )

    # 2. Broadcast defeat to all peers.
    trigger_defeat.rpc()
```

> [!IMPORTANT]
> `WaveSpawner` currently has no `get_wave_number()` accessor. **Add this one-liner** to [`wave_spawner.gd`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/wave_spawner.gd):
> ```gdscript
> func get_wave_number() -> int:
>     return _wave_number
> ```

#### Hook C — Match Start Timestamp

**File:** [`scripts/level.gd`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/level.gd)
**Function:** `_ready()` (line 17), inside the `if DisplayServer.get_name() == "headless":` block.
**Inject:**
```gdscript
if DisplayServer.get_name() == "headless":
    print("Dedicated server starting...")
    Network.start_host("", "")
    # Record match start epoch for duration calculation on match end.
    if has_node("/root/DatabaseManager"):
        get_node("/root/DatabaseManager").set("_match_start_time_unix",
            int(Time.get_unix_time_from_system()))
```

#### Hook D — Graceful Shutdown (Inventory Flush)

**File:** [`scripts/level.gd`](file:///c:/Users/mdszc/Downloads/projekty/micro-world-rpg/scripts/level.gd)
**Add new function:**
```gdscript
func _notification(what: int) -> void:
    # Intercept the OS close/SIGTERM signal on the server to flush inventories.
    if what == NOTIFICATION_WM_CLOSE_REQUEST and multiplayer.is_server():
        if has_node("/root/DatabaseManager"):
            # Build the peer→inventory map from all spawned player nodes.
            var inv_map: Dictionary = {}
            for child in players_container.get_children():
                var peer_id: int = int(child.name)
                if child.has_method("get_inventory"):
                    inv_map[peer_id] = child.get_inventory()
            get_node("/root/DatabaseManager").flush_all_inventories(inv_map)
        get_tree().quit()
```

---

### `project.godot` Autoload Addition

```ini
[autoload]

Network="*res://scripts/network.gd"
ItemDatabase="*res://scripts/item_database.gd"
GridManager="*res://scripts/grid_manager.gd"
DatabaseManager="*res://scripts/database_manager.gd"
```

> [!CAUTION]
> `DatabaseManager._ready()` guards with `if not multiplayer.is_server(): return`, so it is safe to register as an autoload on all peers. However, it will print a startup warning on clients if the `godot-sqlite` GDExtension is not present in the client's export. To silence this, wrap the autoload with `OS.has_feature("dedicated_server")` inside `_ready()` instead of `multiplayer.is_server()`.

---

## Summary Checklist (Code Generation Agent Execution Order)

```
Phase 4.1 — Build Script
  [4.1.1] Create build_server.sh at project root
  [4.1.2] Implement mkdir -p guard
  [4.1.3] Implement Godot binary detection
  [4.1.4] Write export preset DDL block
  [4.1.5] Execute export + gate on exit code
  [4.1.6] chmod +x output binary
  [4.1.7] Print artifact size

Phase 4.2 — Dockerfile
  [4.2.1] Replace Dockerfile with two-stage lean build
  [4.2.2] Update .dockerignore (add source exclusions)
  [4.2.3] Verify EXPOSE 8080/udp matches network.gd
  [4.2.4] Harden CMD to exec form with --headless --server
  [4.2.5] Add HEALTHCHECK via pgrep sentinel

Phase 4.3 — Database
  [4.3.1] Install godot-sqlite GDExtension into addons/
  [4.3.2] Create scripts/database_manager.gd
  [4.3.3] Add DatabaseManager to project.godot autoloads
  [4.3.4] Add get_wave_number() to wave_spawner.gd
  [4.3.5] Inject Hook A into network.gd:_on_player_connected
  [4.3.6] Inject Hook B into base_heart.gd:_on_core_died
  [4.3.7] Inject Hook C into level.gd:_ready (headless block)
  [4.3.8] Inject Hook D into level.gd:_notification
  [4.3.9] Connect DatabaseManager.session_loaded signal in level.gd
           to a new _on_player_session_loaded(peer_id, player_id, inv_dict)
           that calls player_node.player_inventory.from_dict(inv_dict)
           and then replicates slots to the client via existing RPC pattern
  [4.3.10] Write GUT tests: test_database_manager.gd covering:
            - open/create DB in temp user:// path
            - upsert player row, read back
            - inventory flush + reload round-trip
            - match_history INSERT + last_insert_rowid assertion
```

---

## Dependency Graph

```
build_server.sh
    └── export_presets.cfg (written by script)
        └── Godot CLI --export-release
            └── build/server/server.x86_64  ──┐
            └── build/server/server.pck       ├── Dockerfile COPY
                                              └── docker run

database_manager.gd
    ├── godot-sqlite (GDExtension)
    ├── PlayerInventory.to_dict() / from_dict()
    ├── network.gd:_on_player_connected  → load_player_session()
    ├── base_heart.gd:_on_core_died     → save_match_result()
    └── level.gd:_notification          → flush_all_inventories()
```
