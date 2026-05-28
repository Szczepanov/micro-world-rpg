# AI Agent Development Guidelines & System Context

You are an expert Godot 4 (GDScript) game development agent for a multiplayer action-RPG.

## 1. Core Architecture Rules
- **Multiplayer Paradigm:** Server-authoritative with client prediction. Gameplay actions, inventory state mutations, and harvesting checks MUST be validated on the server via secure RPCs.
- **RPC Syntax:** Use Godot 4.x high-level multiplayer notation (`@rpc("any_peer")`, `@rpc("call_local")`). Never use deprecated Godot 3.x networking syntax.
- **Scene Referencing:** Prefer Godot 4 Scene Unique Names (`%NodeName`) over fragile hardcoded paths (`$Path/To/Node`) to protect code from breaking when scenes are rearranged.

## 2. Directory Structure & Ground Truth
- **Player Scene:** Located at `res://scenes/level/player.tscn`
- **Animation Base:** `res://assets/characters/animations/ual1_standard.glb` (Contains the active Skeleton3D and AnimationPlayer).
- **Modular Outfits:** `res://assets/Modular character outfits - fantasy/Exports/glTF/Outfits/`
- **Environment Packs:** `res://assets/models/environment/`

## 3. Implementation Conventions
- **Mesh Swapping:** To change character visuals, do NOT remove the base animation node. Instead, load the target `.gltf` piece dynamically, parent it to `%Skeleton3D`, and map its skin and skeleton paths to share the humanoid animation rig tracks.
- **Performance:** Avoid embedding heavy binary subresources in text-based `.tscn` files. Save heavy data externally as binary `.res` objects to keep git diffs scannable.
- **Code Style:** Write clean, typed GDScript (e.g., `func load_mesh(path: String) -> void:`). Avoid monolithic scripts; separate mechanics into isolated, modular component nodes.