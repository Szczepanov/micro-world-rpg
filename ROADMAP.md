# Project Roadmap: Pocket Realms (Mini Action-RPG)

This document tracks the high-level milestones for our automated, AI-driven multiplayer game development. 

## Status Legend
- ⬜ **Backlog:** Planned feature, not yet started.
- 🚧 **In Progress:** Actively being developed by coding agents.
- ✅ **Completed:** Built, tested locally across multi-peers, and committed to main.

---

## Phase 1: The Core RPG Loop (Gathering & Economy)
- [x] **1.1 Interactive Resource Nodes:** Deploy village asset trees/ore models with `StaticBody3D` colliders that register local player 'E' interactions.
- [x] **1.2 Server-Authoritative Harvesting:** Implement server-side verification loops that decrement node health via RPCs and trigger destruction/scale Tweens across all clients.
- [ ] **1.3 Inventory Integration:** Map harvest rewards directly into the template's baseline grid inventory array.
- [ ] **1.4 Static Crafting Station:** Build an interaction zone verifying item inventory requirements to unlock basic gear/weapon crafting.

## Phase 2: Threats & Health Vectors (Combat & Vitality)
- [ ] **2.1 Decoupled Health Component:** Create a reusable `HealthComponent` node that tracks HP, handles network damage replication, and broadcasts death states.
- [ ] **2.2 Hitbox/Hurtbox Sync:** Attach precise spatial detection collision zones to weapon swing animation frames.
- [ ] **2.3 Basic Combat Loop Validation:** Synchronize weapon swing triggers across clients via `@rpc("call_local")`.
- [ ] **2.4 Sandbag Enemy AI:** Implement a basic wandering monster mesh that processes network damage, updates its local HP bar, and drops loot upon depletion.

## Phase 3: Infrastructure, Persistence & Social Play
- [ ] **3.1 Linux Headless Export:** Configure Godot 4 export templates to run the server pipeline without rendering visual buffers.
- [ ] **3.2 Containerization (Docker):** Wrap the server build into an optimized container image ready for cloud deployment.
- [ ] **3.3 DB State Persistence:** Integrate the dedicated server with a lightweight database backend to serialize/deserialize player transforms and inventory arrays on session changes.
- [ ] **3.4 Main Menu & Lobby Matchmaking:** Expose connection inputs so online clients can cleanly target the cloud host IP and spawn seamlessly.