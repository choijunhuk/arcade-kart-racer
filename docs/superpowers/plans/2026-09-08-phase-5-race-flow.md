# Phase 5 Race Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the complete Phase 5 race lifecycle from menu start through countdown, racing, finishing, results, pause, restart, persistence, and a real headless simulation.

**Architecture:** `RaceManager` owns scene composition and legal state transitions only. `Countdown`, `LapTracker`, `PositionTracker`, `RespawnSystem`, `KartCollisionResolver`, and `RaceResults` each retain one gameplay responsibility; UI observes through `EventBus` and kart read-only APIs. A deliberately simple racing-line input provider stands in for Phase 6 AI and is marked for replacement.

**Tech Stack:** Godot 4.7, statically typed GDScript, GUT 9.6.1, `.tscn` scenes, `.tres` resources, POSIX shell.

**Spec:** `KART_RACING_DEV_PROMPT.md` sections 6.2, 6.5, 8, 11, 14, 21, 24 Phase 5, and 29, plus the approved Phase 5 user brief dated 2026-09-08.

## Global Constraints

- Stay on `phase/05-race-flow`; do not push or switch branches.
- Use only `godot --headless` for automated Godot commands and prefix them with `HOME=$PWD/.tmp-home`.
- Import immediately after adding Godot files and commit generated `*.uid` files.
- Never add a `[network]` or TLS section to `project.godot`.
- Keep every `.gd` file below 400 lines, use static typing, named constants/resources, and public `##` docstrings.
- Implement no Phase 6 AI decision-making and no Phase 7 item behavior.
- Use Conventional Commits with `git commit -m` and decision trailers.

---

### Task 1: Lock the race-domain contracts with unit tests

**Files:**
- Create: `tests/unit/test_race_tuning.gd`
- Create: `tests/unit/test_countdown.gd`
- Create: `tests/unit/test_race_manager.gd`
- Create: `tests/unit/test_race_results.gd`
- Modify: `tests/unit/test_save_manager.gd`
- Create: `tests/unit/test_finished_kart.gd`

**Interfaces:**
- Produces expectations for `RaceTuning`, `Countdown.advance(delta, frames)`, `RaceManager.can_transition(from, to)`, `RaceManager.finishing_complete(...)`, `RaceResults`, `SaveManagerService.record_race_result(...)`, and `KartController.set_finished(provider)`.

- [ ] Write literal, behavior-focused tests for countdown tick order/timing, one-shot start outcomes, legal transitions, all-finished/timeout completion, result metrics, best-value persistence, and stable FINISHED state.
- [ ] Run the six tests and confirm they fail because the new classes/APIs do not exist.
- [ ] Commit the RED tests with a `test(race): define Phase 5 flow contracts` commit.

### Task 2: Implement pure race timing, results, persistence, and kart state seams

**Files:**
- Create: `data/schemas/race_tuning.gd`
- Create: `data/tuning/race_default.tres`
- Create: `race/countdown.gd`
- Create: `race/race_results.gd`
- Create: `race/scripted_race_input_provider.gd`
- Modify: `race/race_state.gd`
- Modify: `kart/kart_controller.gd`
- Modify: `core/autoload/event_bus.gd`
- Modify: `core/autoload/save_manager.gd`

**Interfaces:**
- `Countdown.setup(tuning, karts)`, `start()`, `advance(delta) -> bool`, and `get_phase_seconds() -> float`.
- `RaceResults.setup(track_id, karts)`, `finalize(ranking, lap_tracker) -> Array[Entry]`, and `get_entries() -> Array[Entry]`.
- `KartController.set_frozen(bool)`, `set_finished(provider)`, and `get_input_frame_snapshot() -> InputFrame`.
- `SaveManagerService.record_race_result(track_id, best_lap_ms, position) -> Error`.

- [ ] Implement only enough behavior to satisfy Task 1 tests.
- [ ] Add `EventBus.countdown_tick`, and reuse existing hit/item/lap signals for aggregation.
- [ ] Mark the scripted follower with `TODO(phase-6)` and cap its normal/finished target speed ratios without AI tactics.
- [ ] Run `godot --headless --path . --import`, stage every generated UID, run the Task 1 tests, and commit GREEN production plus UIDs.

### Task 3: Build and test race scene composition

**Files:**
- Create: `tests/integration/test_race_flow.gd`
- Create: `race/race_manager.gd`
- Create: `race/race.tscn`
- Modify: `race/lap_tracker.gd`
- Modify: `race/position_tracker.gd`

**Interfaces:**
- `RaceManager.configure(config, player_provider_override)`, `restart()`, `back_to_menu()`, `pause_race()`, `resume_race()`, `get_state()`, `get_karts()`, and `get_results()`.
- Tracker reset/cadence APIs allow restart without stale registrations or lap time.

- [ ] Write the integration test for `test_loop`, one lap, four scripted karts, full state order, four result rows, restart reset, and pause position freeze.
- [ ] Run it and confirm failure because `race.tscn` is absent.
- [ ] Implement loading, StartGrid spawning, subsystem registration, player camera binding, countdown freeze, finish handling, timeout ranking, and results transition.
- [ ] Import UIDs, run the integration test, and commit the working race scene.

### Task 4: Add temporary HUD, pause, results, and main entry flow

**Files:**
- Create: `ui/hud/hud.gd`
- Create: `ui/hud/hud.tscn`
- Create: `ui/menus/pause_menu.gd`
- Create: `ui/menus/pause_menu.tscn`
- Create: `ui/results/results_screen.gd`
- Create: `ui/results/results_screen.tscn`
- Create: `scenes/main.gd`
- Modify: `scenes/main.tscn`
- Modify: `core/autoload/game_state.gd`
- Create: `tests/integration/test_race_ui.gd`

**Interfaces:**
- HUD binds read-only race/kart/tracker references and subscribes to `EventBus` for countdown, lap, position, wrong-way, and finish notices.
- Menus emit button intent to `RaceManager`; first buttons receive focus when shown.
- `GameState.pending_race_config: RaceConfig` and `change_scene(path) -> Error` own scene switching.

- [ ] Write integration assertions for scene nodes, focus neighbors/default focus, and main-to-race configuration.
- [ ] Run them RED, implement plain temporary controls, import UIDs, run GREEN, and commit.

### Task 5: Replace the simulator placeholder

**Files:**
- Create: `tests/sim/run_ai_race.gd`
- Modify: `tools/run_sim.sh`
- Create: `tests/integration/test_race_sim_contract.gd`

**Interfaces:**
- Script arguments: `--laps N --karts N --races N`.
- JSON output contains per-race `finish_order`, `times`, `respawns`, and `wall_head_on_count`; process exits 1 if any kart does not finish.

- [ ] Test argument parsing and output keys against one fast `test_loop` race.
- [ ] Run RED against the placeholder shell script.
- [ ] Implement an all-scripted headless runner with `Engine.time_scale <= 8.0`, then run one Track 01 lap with four karts and confirm exit 0.
- [ ] Commit the simulator and contract test.

### Task 6: Documentation and final verification

**Files:**
- Modify: `ARCHITECTURE.md`
- Modify: `DEVLOG.md`
- Modify: `README.md`

- [ ] Document the concrete Phase 5 node tree, signal flow, subsystem ownership, temporary follower boundary, actual commands/results, and Korean play instructions.
- [ ] Run fresh import and parse checks, full GUT, track validation, Track 01 simulation, `project.godot` forbidden-section scan, static typing scan, and `.gd` line-count audit.
- [ ] Fix every recoverable failure with a reproducing test, rerun the complete validation suite, and commit documentation/final fixes separately.
- [ ] Confirm the worktree contains no uncommitted Phase 5 files and no Phase 6+ implementation.
