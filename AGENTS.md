# Pocket Realms — AI Agent Operational Guidelines

## 🛑 1. Core Architectural Constraints & Guardrails
- **Strict Static Typing:** All GDScript modifications must implement explicit static typing (e.g., `var id: int = 0`, `func _ready() -> void:`). Untyped variables, unmapped functions, or dynamic variant slip-ups are strict failure states.
- **No Manual Editor Scene Work:** All scene adjustments, node wiring, and reference routing must occur programmatically in `_ready()` using explicit code hooks (`add_child()`, `get_node_or_null()`). Agents must never assume an operator will manually adjust `.tscn` configurations via the Godot editor interface.
- **RPC Validation Mandate:** No player client-facing RPC handlers can use raw, un-vetted parameters. Every `@rpc("any_peer")` entrypoint must execute an immediate sender identity verification pass check against `get_multiplayer_authority()` and enforce spatial proximity checks or state layer verification before executing changes on the server simulation.
- **Idempotent Config Intercepts:** Any python or shell utility script designed to edit system configuration variables (like `export_presets.cfg`) must use state-aware pattern matching to overwrite targets cleanly, completely stripping out matching duplicate or orphaned headers.

## 🛠️ 2. Repository Framework Fingerprints
- **Core Autoload Singletons:** Registered in `project.godot` exactly as: `Network`, `ItemDatabase`, `GridManager`, `DatabaseManager`.
- **Exclusion Safeguards:** Banned runtime footprints (`.godot/` cache layers, local testing `.db` binaries, and `build/` files) are strictly isolated via our standardized `.gitignore` and `.dockerignore`. Never attempt to track, stage, or modify these file categories.
- **Test Framework:** Driven strictly headlessly via the GUT module. All tests are located inside `test/unit/`.

## 📉 3. Token-Saving & Budget Optimization Rules
- **Surgical Workspace Evaluation:** Read only the files explicitly requested by the operator or tied directly to the current implementation task. Do NOT recursively inspect binary files or scan raw resource asset directories.
- **Diff-Only Output Mappings:** When presenting structural or logic code modifications, output ONLY the modified code segments, precise functions, or unified diff fragments. Never waste token budget reproducing massive blocks of unchanged source lines.
- **Local Verification Requirement:** Before declaring any task, script, or bug fix complete, you must locally run `./run_tests.sh` inside the environment and ensure that the full automated test matrix executes completely free of failures.