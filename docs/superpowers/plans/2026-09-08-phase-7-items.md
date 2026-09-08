# Phase 7 Items Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. This phase is explicitly single-implementer; do not dispatch subagents.

**Goal:** Deliver the seven-item vertical slice, deterministic item orchestration, AI use, temporary HUD/effects, simulation statistics, balance gate, and Phase 7 documentation.

**Architecture:** `ItemManager` is a race-local physics-tick orchestrator. It owns seeded selection, roulettes, cooldowns, scene-keyed pools, active-item registries, and item-box wiring; each concrete scene is instantiated only through `ItemData.scene` and the common `ItemBase` API. Karts own a one-slot `ItemSlot`, while category bases own reusable item behavior and receive immutable race access through `ItemContext`.

**Tech Stack:** Godot 4.7, statically typed GDScript, GUT 9.6.1, text `.tscn`/`.tres` resources, headless verification only.

**Spec:** `KART_RACING_DEV_PROMPT.md` sections 6.4, 6.5, 8, 12, 13.5, 17, 24 Phase 7, 25.3 Items, 26, and 29.

## Global Constraints

- Work only on `phase/07-items`; never switch branches or push.
- Use no subagents and no new dependencies.
- Prefix every Godot command with `HOME="$PWD/.tmp-home"`; use `--headless` only.
- After adding scripts/scenes, run `/opt/homebrew/bin/godot --headless --path . --import` and commit generated `*.uid` files.
- Never add a `[network]` or TLS section to `project.godot`.
- Public functions use `##` documentation; production GDScript stays statically typed and below 400 lines.
- All gameplay timers advance from physics delta/ticks; item nodes have no `_physics_process()`.
- Every behavior change follows RED → GREEN → refactor and ends in a small Lore/Conventional commit using `git commit -m`.

---

### Task 1: Pure selection, roulette, slot, and pool contracts

**Files:**
- Create: `items/item_table.gd`
- Create: `items/item_roulette.gd`
- Create: `kart/item_slot.gd`
- Create: `core/object_pool.gd`
- Modify: `ai/item_slot_view.gd`
- Test: `tests/unit/test_item_table.gd`
- Test: `tests/unit/test_item_roulette.gd`
- Test: `tests/unit/test_item_slot.gd`
- Test: `tests/unit/test_object_pool.gd`

**Interfaces:**
- Produces: `ItemTable.pick(table: ItemTableData, rank_normalized: float, previous_id: StringName, rng: RandomNumberGenerator) -> StringName`.
- Produces: `ItemTable.normalize_rank(rank: int, kart_count: int) -> float` and interpolated row weights with previous-item weight halved before the seeded roll.
- Produces: `ItemRoulette.start(result: ItemData)`, `tick(dt: float) -> bool`, `is_active() -> bool`, and `get_result() -> ItemData`, with a 1.2-second constant duration.
- Produces: `ItemSlot extends ItemSlotView`, `set_item`, `clear_item`, `begin_roulette`, `tick_roulette`, `capture_input`, `consume_use_request`, `has_item`, `get_category`, `get_item_id`, and `get_item_data`.
- Produces: `ObjectPool.configure(scene: PackedScene, parent: Node, capacity: int)`, `acquire() -> Node`, `release(instance: Node)`, and observable available/active counts.

- [ ] Write literal-weight tests for all eight 100-point rows, 4/6/12-kart normalized ranks, interpolation, previous-item halving, and seeded selection boundaries.
- [ ] Run focused GUT and confirm failures are missing-class/API failures.
- [ ] Implement the four pure/runtime helpers without scene-specific item branches.
- [ ] Run focused tests and the existing item/AI tests; confirm green.
- [ ] Import, stage scripts/tests/UIDs, and commit with Lore trailers.

### Task 2: Common item lifecycle and category behaviors

**Files:**
- Create: `items/base/item_context.gd`
- Create: `items/base/item_base.gd`
- Create: `items/base/projectile_item.gd`
- Create: `items/base/homing_item.gd`
- Create: `items/base/trap_item.gd`
- Create: `items/base/boost_item.gd`
- Create: `items/base/shield_item.gd`
- Create: `items/base/area_item.gd`
- Create: `items/base/leader_strike_item.gd`
- Test: `tests/unit/test_item_bases.gd`
- Test: `tests/unit/test_item_effects.gd`

**Interfaces:**
- Produces: abstract `ItemBase.setup(data: ItemData, owner_kart: KartController, context: ItemContext)`, `activate(frame: InputFrame)`, `tick(dt: float)`, `on_hit(target: KartController)`, `expire()`, and `finished(item: ItemBase)`.
- Produces: read-only `ItemContext` getters for karts, `PositionTracker`, `RacingLine`, RNG, and `ItemManager`.
- Produces pure helpers for projectile reflection/lifetime, homing next-ahead selection, trap arming/cap, area telegraph, and leader target/usability.

- [ ] Add tests that fail for missing reflection count/lifetime, next-ahead target, trap arming/cap, shield one-shot state, area telegraph/drift cancellation, and leader target/immunity/rank-one rejection.
- [ ] Implement shared setup/activation/tick/expiry and category behavior using only `ItemData` plus exported category tuning constants.
- [ ] Route accepted hits through `HitReactor.apply`, emit `EventBus.item_hit`, and return every finished instance through the manager.
- [ ] Run focused tests, import UIDs, and commit.

### Task 3: Data-driven manager and seven scene instances

**Files:**
- Create: `items/item_manager.gd`
- Create: `items/instances/{rocket_dart,hunter_drone,spike_mine,nitro_can,aegis_bubble,pulse_blast,storm_beacon}/*.{gd,tscn}`
- Create: `assets/placeholder/items/*.svg`
- Modify: `data/items/*.tres`
- Modify: `core/autoload/event_bus.gd`
- Test: `tests/unit/test_item_manager.gd`
- Test: `tests/integration/test_item_instances.gd`

**Interfaces:**
- Produces: `ItemManager.setup(position_tracker, racing_line, collision_resolver, seed)`, `register_kart`, `unregister_kart`, `register_item_box`, `give_item`, `use_item`, `get_active_projectiles`, `get_active_projectile_count`, and `notify_leader_immunity`.
- Adds `EventBus.threat_warning(target, item_id, seconds)` and uses existing `item_used`/`item_hit` signals.
- Concrete scenes bind one existing `.tres`; manager code loads no item id and contains no per-item `match`/`if` branch.

- [ ] Add manager tests for immediate seeded roulette decision, 1.2-second reveal, cooldown rejection, generic `ItemData.scene` creation, active-projectile cap, and pool reuse.
- [ ] Implement manager dictionaries keyed by kart instance id and scene resource path, with stable array iteration and deferred removals.
- [ ] Create colored primitive scenes and scripts for all seven items; populate `scene` and placeholder `icon` fields in every existing item resource.
- [ ] Run import, assert all scenes instantiate through `ItemBase`, run focused tests, and commit scenes plus generated UIDs.

### Task 4: Kart, hit, collision, AI, race, HUD, and sandbox integration

**Files:**
- Modify: `kart/kart.tscn`, `kart/kart_controller.gd`, `kart/hit_reactor.gd`, `kart/kart_visuals.gd`, `kart/drift_controller.gd`
- Modify: `race/race.tscn`, `race/race_manager.gd`, `race/kart_collision_resolver.gd`, `race/race_config.gd`
- Modify: `ai/ai_controller.gd`, `ai/ai_sensors.gd`, `ai/ai_navigator.gd`, `ai/ai_race_context.gd`, `ai/ai_item_brain.gd`
- Modify: `ui/hud/hud.gd`, `ui/hud/hud.tscn`
- Modify: `track/elements/boost_pad.gd`
- Modify: `scenes/test/kart_sandbox.gd`, `scenes/test/kart_sandbox.tscn`
- Create: `effects/impact_effect.gd`, `effects/impact_effect.tscn`
- Test: `tests/integration/test_phase7_items.gd`
- Test: `tests/unit/test_ai_item_brain.gd`
- Test: `tests/unit/test_ai_navigator.gd`

**Interfaces:**
- Kart exposes `item_slot`, `has_shield`, `install_shield`, `consume_shield`, and shield remaining seconds; shield blocks one non-BUMP hit only.
- Drift exposes `cancel()` for area hits; collision resolver adds a light shield contact impulse without changing normal kart-contact semantics.
- AI receives manager through `AIRaceContext`, reads the real slot/use profile, senses approaching active projectiles, sets dodge lane bias using `projectile_dodge_prob`, and seeks boxes only while the slot is empty.
- HUD binds `ItemManager`, displays slot/roulette/shield state, and handles threat warnings for the player.

- [ ] Add failing integration assertions for required scene nodes, real AI slot use, projectile sensing, shielded dart state preservation, area drift cancel, threat HUD, hit recovery within 1.5 seconds, sandbox `I` cycling, and four-kart one-lap item use/hit.
- [ ] Wire the manager into race and sandbox composition, capture item input in KartController, and connect every track ItemBox.
- [ ] Replace Phase 6 null-view/TODO paths with real slot/sensor/navigator state.
- [ ] Add temporary HUD/effects and shield contact behavior, run focused integration tests, import, and commit.

### Task 5: Simulation statistics and balance gate

**Files:**
- Modify: `tests/sim/run_ai_race.gd`
- Modify: `tools/run_sim.sh`
- Modify: `tests/unit/test_race_sim.gd`
- Modify: `data/item_tables/default_8_karts.tres` only if the measured gate fails.

**Interfaces:**
- `parse_options` adds `items: bool`, default true, accepting `--items on|off`.
- Every race reports items-used/hits dictionaries, rank-one hits, and the starting rank-eight kart's rank gain.
- Summary reports per-item hit rate, average rank-one hits per race, and mean rank-eight gain; exit status fails when items are on and either balance threshold fails.

- [ ] Add failing parser/statistics/gate tests with hand-derived dictionaries.
- [ ] Implement event-backed collection and stable summary output.
- [ ] Run one-race smoke, then `--races 20 --difficulty normal --karts 8 --laps 3`.
- [ ] If thresholds fail, tune only `.tres` weights/item power, rerun until rank-one hits average ≤3 and rank-eight gain ≥1.5, then commit measured tuning and simulator changes.

### Task 6: Documentation and exhaustive verification

**Files:**
- Modify: `ARCHITECTURE.md`
- Modify: `DEVLOG.md`
- Modify: `README.md`

- [ ] Document the item class tree, race-local manager tick order, pooling/registries, signals, data-only extension contract, final balance numbers, limitations, TODO/PLACEHOLDER inventory, and Korean play instructions.
- [ ] Run import and headless parse; reject any `SCRIPT ERROR`/project `ERROR` output.
- [ ] Run `tools/run_tests.sh`, `tools/validate_tracks.sh`, and the final 20-race normal simulation with local HOME.
- [ ] Audit four validator passes, all `.gd` line counts, static typing warnings/errors, `TODO(phase-7)`, item-id branches in `ItemManager`, clean `project.godot` network/TLS state, and `git status`.
- [ ] Commit documentation and any final verified fixes with Lore trailers; do not push.

