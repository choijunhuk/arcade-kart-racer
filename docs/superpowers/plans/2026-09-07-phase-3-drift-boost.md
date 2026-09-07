# Phase 3 Drift and Boost Implementation Plan

> **For agentic workers:** This plan is executed inline by the sole implementer. Subagents and branch changes are prohibited for this phase.

**Goal:** Deliver the complete Phase 3 drift, boost, trick, pad, feedback, sandbox, track, test, and documentation contract on `phase/03-drift-boost`.

**Architecture:** `DriftController` and `BoostController` own deterministic gameplay state and expose typed read-only APIs plus `KartPhysics` result objects. `KartPhysics` remains the sole writer of motion, while visuals, effects, camera, and HUD observe controller state or signals. Track elements invoke narrow kart APIs and do not own kart state.

**Tech Stack:** Godot 4.7, statically typed GDScript, `.tscn` scenes, typed `.tres` resources, GUT 9.6.1, headless validators.

**Spec:** `KART_RACING_DEV_PROMPT.md` sections 9.2, 9.3, 10, 11, 15.3, 16, 17, 24 Phase 3, and 29; plus the user-provided Phase 3 delivery contract dated 2026-09-07.

## Global Constraints

- Remain on `phase/03-drift-boost`; do not push or switch branches.
- Use no subagents and implement nothing from Phase 4 or later.
- Prefix every Godot command with `HOME="$PWD/.tmp-home"` and use only `--headless`.
- After new files are added, run `godot --headless --path . --import` and commit generated `*.uid` files.
- Preserve the `DriftResult` and `BoostResult` seams and fill Phase 3 TODOs without restructuring their ownership.
- Keep every `.gd` file below 400 lines, use static typing, public API docstrings, resource-backed tuning, and no magic gameplay numbers.
- Every production behavior begins with a failing test and every commit records fresh targeted verification.

---

### Task 1: Deterministic Drift State Machine

**Files:**
- Create: `tests/unit/test_drift_controller.gd`
- Create: `kart/drift_controller.gd`
- Modify: `data/tuning/physics_default.tres`

**Interfaces:**
- Consumes: `InputFrame`, `PhysicsTuning`, `KartData`, `MiniTurboTier`.
- Produces: `configure(tuning: PhysicsTuning, kart_data: KartData)`, `step(frame: InputFrame, speed: float, grounded: bool, air_time: float, yaw_rate: float, is_hit: bool, dt: float) -> KartPhysics.DriftResult`, read-only state/charge/tier/trick APIs, and drift/trick signals.

- [ ] Write table-driven failing tests for NONE/HOP/HOLD/RELEASE, direction lock, cancel paths, cooldown, monotonic charge, quality multiplier, tier thresholds, released boost spec, and trick arm/land.
- [ ] Run `HOME="$PWD/.tmp-home" ./tools/run_tests.sh` and confirm the new test file fails because `DriftController` is missing.
- [ ] Implement the smallest deterministic state machine and result construction that passes the tests.
- [ ] Re-run GUT and confirm the new tests plus all prior tests pass.
- [ ] Commit the controller, tuning table, tests, generated UID, and verification result.

### Task 2: Drift Physics and Runtime Wiring

**Files:**
- Modify: `tests/unit/test_kart_physics.gd`
- Modify: `tests/integration/test_kart_phase2_components.gd`
- Modify: `kart/kart_physics.gd`
- Modify: `kart/kart_controller.gd`
- Modify: `kart/kart.tscn`

**Interfaces:**
- Consumes: `KartPhysics.DriftResult` fields for active direction, steer influence, grip, speed retention, and visual angle.
- Produces: drift yaw that never reverses direction, per-second speed retention converted with `pow(retention, dt)`, `hop(vertical_impulse: float)`, controller state `DRIFTING` during HOLD, and controller read-only drift APIs.

- [ ] Add failing unit tests for inside/outside drift yaw, non-reversal, grip override, and frame-rate-independent speed retention; add scene composition assertions.
- [ ] Run targeted GUT and observe failures against the neutral Phase 2 seam.
- [ ] Extend `DriftResult`, integrate drift physics, wire controller tick order, and add the scene node.
- [ ] Run import, parse, and GUT; confirm the controller scene and physics behavior pass.
- [ ] Commit the drift runtime slice with UID files.

### Task 3: Boost Ownership and Stacking

**Files:**
- Create: `tests/unit/test_boost_controller.gd`
- Create: `kart/boost_controller.gd`
- Modify: `tests/unit/test_phase2_physics.gd`
- Modify: `kart/kart_controller.gd`
- Modify: `kart/kart.tscn`
- Modify: `kart/terrain_sensor.gd`
- Modify: `kart/slipstream_sensor.gd`

**Interfaces:**
- Consumes: `BoostSpecData`, drift released boost spec, slipstream exit spec, trick landing spec.
- Produces: `request(spec: BoostSpecData, source: StringName)`, `step(dt: float) -> KartPhysics.BoostResult`, pure `evaluate_start_input(frame: InputFrame, countdown_phase: float) -> StartInputResult`, current source/remaining APIs, and boost signals.

- [ ] Add failing stacking-table tests for stronger replacement, weaker/equal extension, duration cap, expiry, offroad flag, and start-input window/wheelspin outcomes.
- [ ] Run GUT and confirm failures are caused by the missing controller.
- [ ] Implement boost state and replace Phase 2's temporary slipstream multiplier path with `request()`.
- [ ] Wire terrain sampling to the active boost's `ignores_offroad` result and connect drift/trick requests.
- [ ] Run import, parse, and full GUT; commit with generated UIDs.

### Task 4: BoostPad, JumpPad, and Launch Integration

**Files:**
- Create: `track/elements/boost_pad.gd`
- Create: `track/elements/boost_pad.tscn`
- Create: `track/elements/jump_pad.gd`
- Create: `track/elements/jump_pad.tscn`
- Create: `tests/integration/test_phase3_track_elements.gd`
- Modify: `kart/kart_physics.gd`
- Modify: `kart/kart_controller.gd`
- Modify: `track/tracks/test_loop/test_loop.tscn`
- Modify: `track/tracks/test_loop_hills/test_loop_hills.tscn`

**Interfaces:**
- Consumes: `KartController.request_boost(spec, source)` and `KartController.launch(local_velocity)`.
- Produces: layer-5 trigger scenes, arrow/ramp placeholders, two flat-loop pads, one hills jump pad, and a landing zone.

- [ ] Add failing tests that instantiate both elements, verify collision contracts, trigger boost, and prove launch transitions through AIRBORNE to landing trick boost.
- [ ] Implement `KartPhysics.launch(local_velocity: Vector3)` and narrow kart forwarding APIs.
- [ ] Build the element scenes and place them on the required tracks.
- [ ] Run import, parse, targeted integration tests, and track validation.
- [ ] Commit track gameplay elements and UIDs.

### Task 5: Hairpin Track and Drift-Aware Scripted Driver

**Files:**
- Create: `track/tracks/test_hairpin/test_hairpin.gd`
- Create: `track/tracks/test_hairpin/test_hairpin.tscn`
- Create: `tests/integration/test_phase3_hairpin.gd`
- Modify: `tests/support/scripted_input_provider.gd`
- Modify: `tools/validate_tracks.sh`

**Interfaces:**
- Consumes: closed `Curve3D`, track validator contract, and DriftController input frame semantics.
- Produces: an approximately 18 m 180-degree hairpin plus fast S-curve, and optional drift-on-corners scripted input that defaults off.

- [ ] Add failing tests for legacy default input, curvature-gated drift press/hold/release, hairpin validation, tier attainment, and drift-vs-no-drift lap-time ratio.
- [ ] Implement the optional driver mode using independent upcoming tangent samples and edge detection.
- [ ] Author the greybox track with validator-required checkpoints, respawn points, grid markers, and containers.
- [ ] Tune only resource-backed Phase 3 values until the automated driver reaches at least Tier 2 and is at least 3% faster.
- [ ] Run all three track validators and commit the track, tests, driver changes, and UIDs.

### Task 6: Signal-Driven Feedback, Visuals, Camera, and HUD

**Files:**
- Create: `effects/drift_effects.gd`
- Create: `effects/drift_effects.tscn`
- Create: `effects/boost_effects.gd`
- Create: `effects/boost_effects.tscn`
- Create: `effects/skid_mark.gd`
- Create: `ui/hud/drift_meter.gd`
- Create: `ui/hud/drift_meter.tscn`
- Create: `tests/integration/test_phase3_feedback.gd`
- Modify: `data/schemas/feel_tuning.gd`
- Modify: `data/tuning/feel_default.tres`
- Modify: `kart/kart_visuals.gd`
- Modify: `kart/kart.tscn`
- Modify: `camera/race_camera.gd`
- Modify: `scenes/test/kart_sandbox.tscn`

**Interfaces:**
- Consumes: drift/boost local signals and controller read-only APIs only.
- Produces: tier sparks, terrain-colored smoke, bounded skid strip, exhaust, visual drift yaw/trick spin, camera side offset/FOV spring, and read-only meter.

- [ ] Add failing composition and observer-boundary tests for node count, signal wiring, tier colors, HUD readout, visual target angles, and camera targets.
- [ ] Add FeelTuning fields for colors, lerp/spring rates, skid segment cap, and particle behavior.
- [ ] Implement feedback scenes with no physics writes and no more than six particle nodes per kart.
- [ ] Wire visuals, camera, and HUD through public APIs/signals and run import/parse/GUT.
- [ ] Commit the presentation slice and UIDs.

### Task 7: Sandbox, Snapshot, Documentation, and Final Proof

**Files:**
- Modify: `scenes/test/kart_sandbox.gd`
- Modify: `scenes/test/kart_sandbox.tscn`
- Modify: `scenes/test/drive_snapshot.gd`
- Modify: `ARCHITECTURE.md`
- Modify: `DEVLOG.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: controller read-only drift/boost/trick APIs and three track scenes.
- Produces: key hints, key `4` hairpin selection, five Phase 3 debug watches, drift snapshot option, architecture signal list/decisions, Phase report, and Korean play-test instructions.

- [ ] Add failing sandbox tests for key `4`, HUD composition, and debug-watch lifecycle.
- [ ] Implement sandbox/snapshot updates and confirm old scripted-drive mode remains default.
- [ ] Update architecture, decision log, DEVLOG Phase 3 report, README controls, headless commands, and play instructions.
- [ ] Run `HOME="$PWD/.tmp-home" /opt/homebrew/bin/godot --headless --path . --import`, parse, full GUT, all track validators, script-length check, TODO inventory, forbidden-network-setting scan, and clean-status review.
- [ ] Commit final docs and any verification-only fixes without pushing.

## Final Verification Commands

```sh
HOME="$PWD/.tmp-home" /opt/homebrew/bin/godot --headless --path . --import
HOME="$PWD/.tmp-home" /opt/homebrew/bin/godot --headless --path . --quit
HOME="$PWD/.tmp-home" ./tools/run_tests.sh
HOME="$PWD/.tmp-home" ./tools/validate_tracks.sh
find . -name '*.gd' -not -path './addons/*' -print0 | xargs -0 wc -l
rg -n 'TODO\(phase-[0-9]+\)' --glob '*.gd' --glob '*.md'
rg -n 'tls/certificate_bundle_override|^\[network\]' project.godot
git status --short --branch
```
