# Project Roadmap: Pocket Realms (Mini Action-RPG)

This document tracks the high-level milestones for our automated, AI-driven multiplayer game development. 

## Status Legend
- [ ] **Backlog:** Planned feature, not yet started.
- [-] **In Progress:** Actively being developed by coding agents.
- [x] **Completed:** Built, tested locally across multi-peers, and committed to main.

---

## Phase 1: The Core RPG Loop (Gathering & Economy)
- [x] **1.1 Interactive Resource Nodes:** Deploy village asset trees/ore models with `StaticBody3D` colliders that register local player 'E' interactions.
- [x] **1.2 Server-Authoritative Harvesting:** Implement server-side verification loops that decrement node health via RPCs and trigger destruction/scale Tweens across all clients.
- [x] **1.3 Inventory Integration:** Map harvest rewards directly into the template's baseline grid inventory array.
- [x] **1.4 Static Crafting Station:** Build an interaction zone verifying item inventory requirements to unlock basic gear/weapon crafting.

## Phase 2: Grid Management & Defense Structures
- [x] **2.1 Grid Placement Manager:** Create a global server script tracking world state via a coordinate matrix layout (`Grid[x, y, z] = structure_id`).
- [x] **2.2 Real-time Placement Preview:** Implement a client-side raycast system that projects a semi-transparent ghost mesh of a wall or turret, snapping cleanly to integer grid lines when "Build Mode" is active.
- [x] **2.3 Structure Deployment Validation:** Build server-side RPC logic that consumes deployment items from a player's inventory (e.g., `spiked_wall_item`) before spawning a physical building mesh across all connected peers.

## Phase 3: The Threat Matrix & Wave Loops
- [x] **3.1 Reusable Decoupled Health Component:** Create a modular `HealthComponent` node that tracks HP, handles network damage replication, and broadcasts death states. It will be attached to players, walls, turrets, and enemies.
- [x] **3.2 Dynamic Navigation Re-Baking:** Hook up Godot's `NavigationRegion3D` to automatically recalculate enemy pathfinding meshes in real-time whenever players place new walls to build defensive mazes.
- [x] **3.3 Automated Defense Turrets:** Create logic for placed turrets to scan a radial zone for targets, rotate smoothly toward the nearest enemy, and deal damage on a server-controlled heartbeat loop.
- [ ] **3.4 Enemy Spawner Hubs & Core Health:** Create server-controlled spawn locations that release enemy waves targeting a centralized "Base Heart" node. If the heart's health hits 0, broadcast a game-over screen.

## Phase 4: Infrastructure & Automation (No Manual Work)
- [ ] **4.1 Upgraded Asset Cooker:** Expand your current editor script tool to automatically classify incoming `.gltf`/`.glb` files, generate static convex collisions, attach appropriate scripts, and save them out as standalone scenes.
- [ ] **4.2 Linux Headless Containerization:** Dockerize the dedicated Godot server binary for deployment to your cloud environment.
- [ ] **4.3 Session State & Record Persistence:** Connect the server to a database backend to track player wave records and high scores between game instances.