# Phase 0 Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the complete, executable Phase 0 foundation for Turbo Circuit on the current `phase/00-setup` branch.

**Architecture:** Six small autoloads provide cross-cutting services, typed `Resource` schemas own content/tuning contracts, and a provider-owned `InputFrame` isolates future kart code from physical input. A greybox track and sandbox scene prove the scene contract without implementing later-phase gameplay.

**Tech Stack:** Godot 4.7 stable, statically typed GDScript 4.x, GUT 9.6.1, text `.tscn`/`.tres` resources, POSIX shell tools.

**Spec:** `KART_RACING_DEV_PROMPT.md` and `ARCHITECTURE.md`

## Global Constraints

- Work only on Phase 0 and the current `phase/00-setup` branch; do not push.
- Use `/opt/homebrew/bin/godot` 4.7 stable and GDScript 4.x syntax only.
- Use existing `addons/gut/`; add no dependencies.
- Use static types, named constants, public-function docstrings, and files below 400 lines.
- Do not implement kart physics, drift, race logic, item behavior, or AI behavior.
- Verify every scene edit with a headless parse and finish with tests and track validation.
- Commit small units with Conventional Commit headers and decision-context trailers.

---

### Task 1: Project contract and skeleton

**Files:**
- Create: `project.godot`
- Create: every Phase 0 directory from spec section 7
- Modify: `.gitignore`
- Create: `.gitkeep` only in directories without real Phase 0 content

**Interfaces:**
- Produces: project settings, InputMap actions, collision layer names, autoload registration, and stable repository paths.

- [ ] Verify the active branch is `phase/00-setup` and preserve pre-existing worktree changes.
- [ ] Create `project.godot` with main scene, Forward+, 60 Hz interpolation, gravity, 1600×900 canvas stretch, nine named 3D layers, six autoloads, GUT plugin, and keyboard/gamepad events.
- [ ] Create the full section 7 directory tree and add `.gitkeep` only to otherwise-empty directories.
- [ ] Add `.tmp-home/` to `.gitignore` for sandboxed Godot runs.
- [ ] Run `/opt/homebrew/bin/godot --headless --path . --quit` and resolve configuration/registration errors.
- [ ] Commit as `chore(project): establish Phase 0 Godot skeleton`.

### Task 2: Input contracts using TDD

**Files:**
- Test: `tests/unit/test_input_frame.gd`
- Test: `tests/unit/test_player_input_provider.gd`
- Create: `core/input/input_frame.gd`
- Create: `core/input/input_provider.gd`
- Create: `core/input/player_input_provider.gd`
- Create: `core/input/input_actions.gd`

**Interfaces:**
- Produces: `InputFrame.zero() -> InputFrame`, `InputFrame.clone() -> InputFrame`, `InputProvider.get_frame() -> InputFrame`, and `PlayerInputProvider(device_id: int)` with `set_strength_override(Callable)`.

- [ ] Write GUT tests proving a zero frame is neutral, clone preserves all fields without aliasing, and steering approaches/reverses target according to smoothing.
- [ ] Run the focused tests and verify they fail because the input classes do not exist.
- [ ] Implement typed input classes; the injectable callable accepts `(action: StringName, device_id: int) -> float`.
- [ ] Re-run focused tests and the full suite until all pass without script errors.
- [ ] Commit as `feat(input): establish deterministic input frame providers`.

### Task 3: Save and settings boundaries using TDD

**Files:**
- Test: `tests/unit/test_save_manager.gd`
- Test: `tests/unit/test_settings_manager.gd`
- Create: `core/autoload/save_manager.gd`
- Create: `core/autoload/settings_manager.gd`

**Interfaces:**
- Produces: versioned JSON `load_data()`, `save_data(data: Dictionary)`, defaults, backup recovery, ConfigFile load/save/apply, and test path overrides.

- [ ] Write tests proving default save version, corrupt-primary backup recovery, and settings defaults round-trip through an isolated file.
- [ ] Run focused tests and verify the missing implementations fail for the intended reason.
- [ ] Implement `SaveManager` with version `1`, primary/backup parsing, and stable default keys.
- [ ] Implement `SettingsManager` with audio/video/controls/accessibility/gameplay defaults and safe headless application.
- [ ] Re-run focused and full tests until green.
- [ ] Commit as `feat(core): add resilient save and settings services`.

### Task 4: Remaining autoloads and debug UI

**Files:**
- Create: `core/autoload/game_state.gd`
- Create: `core/autoload/event_bus.gd`
- Create: `core/autoload/audio_manager.gd`
- Create: `core/autoload/debug_overlay.gd`
- Create: `core/autoload/debug_overlay.tscn`

**Interfaces:**
- Produces: selection state and scene requests; all 16 specified global signals; four audio buses and linear volume accessors; F3 overlay, callable watches, and runtime sliders.

- [ ] Implement `GameState` without race logic.
- [ ] Declare every exact EventBus signal from the Phase 0 request with broadly compatible typed payloads only where stable.
- [ ] Implement idempotent Master/Music/SFX/Engine bus setup and a 16-player `AudioStreamPlayer3D` pool skeleton.
- [ ] Implement overlay labels updated in `_process()`, physics tick counting in `_physics_process()`, `watch()`, `unwatch()`, `add_slider()`, and visibility control.
- [ ] Parse headlessly and commit as `feat(core): add runtime service autoloads`.

### Task 5: Resource schemas and defaults using TDD

**Files:**
- Test: `tests/unit/test_item_table_data.gd`
- Create: all scripts in `data/schemas/`
- Create: defaults in `data/{tuning,karts,terrain,ai,item_tables,items}/`

**Interfaces:**
- Produces: `KartData`, `DriverData`, `ItemData`, `AIItemUseProfile`, `TrackData`, `AIDifficultyProfile`, `PhysicsTuning`, `FeelTuning`, `CameraTuning`, `TerrainData`, and `ItemTableData` resources.

- [ ] Write eight rank-row assertions proving each `ItemTableData` row totals exactly 100.
- [ ] Run the item table test and verify it fails because the schema/default resource is absent.
- [ ] Implement every section 20 field, every section 13.6 AI field, and every named section 9–11/16–17 tuning field including typed `Curve` and mini-turbo resources.
- [ ] Create three weight-class karts, five terrains, three AI profiles, seven item resources, and the exact section 12.3 8×7 weight table.
- [ ] Load all `.tres` resources through the tests and headless parser; resolve type or serialization errors.
- [ ] Commit as `feat(data): define Phase 0 resource catalog`.

### Task 6: Track, sandbox, and validator

**Files:**
- Create: `race/race_state.gd`
- Create: `kart/kart_state.gd`
- Create: `track/track.gd`
- Create: `track/track_validator.gd`
- Create: `track/track_template.tscn`
- Create: `track/tracks/test_loop/test_loop.tscn`
- Create: `scenes/test/kart_sandbox.tscn`
- Create: `scenes/main.tscn`
- Create: `tools/run_tests.sh`
- Create: `tools/run_sim.sh`
- Create: `tools/validate_tracks.sh`

**Interfaces:**
- Produces: enum-only race/kart state vocabularies, required-node track validation, a visible flat oval and placeholder kart, and executable verification commands.

- [ ] Add enum-only state scripts with the exact specified members.
- [ ] Build a 14 m-wide flat oval from primitive static segments, 2 m walls, a closed racing line, four checkpoint areas with respawn markers, and eight start markers.
- [ ] Add environment/light, instantiate the track in the sandbox, add an unmoving `CharacterBody3D` kart and fixed active camera, then instantiate the sandbox from main.
- [ ] Implement current-node validator checks and explicit warnings for Phase 4-only checks.
- [ ] Make tool scripts executable and run parse plus validation.
- [ ] Commit as `feat(track): add executable greybox sandbox`.

### Task 7: Import, final verification, and reporting

**Files:**
- Modify: generated `*.uid`
- Modify: `ARCHITECTURE.md`
- Create: `DEVLOG.md`
- Modify: `README.md`

**Interfaces:**
- Produces: reproducible import metadata, Phase 0 report, and developer run/test instructions.

- [ ] Run Godot import once using workspace-local HOME only if required and stage generated `*.uid` files.
- [ ] Run `/opt/homebrew/bin/godot --headless --path . --quit`; assert exit 0 and no `ERROR` or `SCRIPT ERROR` lines.
- [ ] Run `tools/run_tests.sh`; assert at least eight passing tests and zero failures.
- [ ] Run `tools/validate_tracks.sh`; assert the test loop passes.
- [ ] Run `tools/run_sim.sh`; assert the required Phase 0 message and exit 0.
- [ ] Update `ARCHITECTURE.md` to match actual paths, update README status/run commands, and write `DEVLOG.md` with the section 30.5 headings and summarized real output.
- [ ] Re-run all verification after documentation changes, confirm no untracked or unstaged Phase 0 files remain, and commit as `docs(project): report verified Phase 0 foundation`.
