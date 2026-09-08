# Arcade Kart Racer Architecture

This document is the repository-specific architecture contract through Phase 5. It
translates sections 6–8 of `KART_RACING_DEV_PROMPT.md` into the concrete paths
used by this project. Later phases must update this document before changing a
major boundary or dependency direction.

## Architectural principles

1. Runtime domains are separated into `core/`, `kart/`, `race/`, `track/`,
   `items/`, `ai/`, `camera/`, `ui/`, `audio/`, `effects/`, and `data/`.
2. Cross-domain communication uses typed public APIs, local signals, and the
   global `EventBus`. Long relative node paths are not an integration API.
3. Gameplay tuning and content identity live in typed `Resource` schemas under
   `data/schemas/` and `.tres` instances under `data/`.
4. Gameplay state advances in `_physics_process()` at 60 Hz. Presentation is
   updated in `_process()` and reads gameplay state without mutating it.
5. A kart consumes `InputFrame`; it does not know whether the source is a
   player, AI, replay, network peer, or test double.
6. Scenes assemble nodes. Scripts own one focused behavior and stay below 400
   lines unless a documented exception is necessary.
7. Phase delivery is additive: kart physics, drift, track rules, and race flow are
   live; items, proper AI, final camera feel, and final UI remain behind their
   later-phase seams.

## Runtime composition

`project.godot` starts `res://scenes/main.tscn` and registers six autoloads:

- `GameState` — `core/autoload/game_state.gd`: current mode and selected
  identifiers, `pending_race_config`, and validated scene-change API.
- `EventBus` — `core/autoload/event_bus.gd`: global signal declarations only;
  it does not contain gameplay decisions.
- `SettingsManager` — `core/autoload/settings_manager.gd`: `ConfigFile`
  defaults, load/save, and immediate application of supported settings.
- `SaveManager` — `core/autoload/save_manager.gd`: versioned JSON save data,
  backup recovery, atomic-enough primary/backup replacement, and lower-is-better
  track best-lap/best-position updates.
- `AudioManager` — `core/autoload/audio_manager.gd`: Master/Music/SFX/Engine
  bus setup, linear volume accessors, and a reusable SFX-player pool.
- `DebugOverlay` — `core/autoload/debug_overlay.tscn` with
  `core/autoload/debug_overlay.gd`: F3 overlay, FPS/physics tick display,
  callable watches, and runtime sliders.

The main scene is now a minimal start prompt; accepting it stores the default
`RaceConfig` and changes to this Phase 5 runtime tree:

```text
scenes/main.tscn                                      [main.gd]
└── Main (Node)
    └── Center/VBox/StartButton

race/race.tscn                                       [race_manager.gd]
└── RaceScene (Node3D / RaceManager)
    ├── Track (dynamic TrackData.scene instance)
    ├── LapTracker
    ├── PositionTracker
    ├── RespawnSystem
    ├── KartCollisionResolver
    ├── Countdown
    ├── RaceResults
    ├── Karts
    │   ├── PlayerKart       (PlayerInputProvider)
    │   └── DummyKart x N    (ScriptedRaceInputProvider, Phase 5 only)
    ├── RaceCamera
    ├── HUD                  (CanvasLayer)
    │   └── DriftMeter
    ├── PauseMenu            (CanvasLayer, PROCESS_MODE_ALWAYS)
    └── ResultsScreen        (CanvasLayer)
```

The Phase 1-4 driving sandbox remains available directly at
`scenes/test/kart_sandbox.tscn`; it is no longer the main scene.

## Domain ownership and dependency direction

### Core and data

All runtime domains may depend on `core/` and read `data/` resources.
`core/` must not depend on a gameplay domain. `data/schemas/` contains no
scene-tree queries or gameplay orchestration.

### Kart

Kart code lives in `kart/`. It may read terrain information from `track/` and
request item use through an explicit `items/` API. It must not reference
`race/`, `ai/`, or `ui/` directly. Phase 3 fills the drift state machine and
general boost stacking seams left neutral since Phase 0/2.

#### Node tree (`kart/kart.tscn`, spec §6.3)

```text
Kart (CharacterBody3D, layer 2 / mask 1)  [kart_controller.gd]
├── CollisionShape3D          # BoxShape3D 1.6 x 0.6 x 2.2
├── BumpArea                  # Area3D, layer/mask 3; kart contact only
├── TerrainProbe              # Area3D, layer 0 / mask 5; OffroadZone overlap
├── GroundRays (Node3D)       # RayCast3D x 5: RayFL, RayFR, RayRL, RayRR, RayCenter (mask 1)
├── KartPhysics (Node)        [kart_physics.gd]
├── TerrainSensor (Node)      [terrain_sensor.gd]
├── SlipstreamSensor (Node)   [slipstream_sensor.gd]
│   └── ShapeCast3D           # mask 2, forward slipstream_range
├── HitReactor (Node)         [hit_reactor.gd]
├── DriftController (Node)    [drift_controller.gd]
├── BoostController (Node)    [boost_controller.gd]
├── DriftEffects (Node3D)     [effects/drift_effects.gd] tier sparks + terrain-tinted smoke
├── BoostEffects (Node3D)     [effects/boost_effects.gd] exhaust particles
└── Visuals (Node3D)          [kart_visuals.gd]
    ├── Body (MeshInstance3D, BoxMesh)
    ├── Driver (MeshInstance3D, CapsuleMesh)
    └── WheelFL / WheelFR / WheelRL / WheelRR (Node3D pivot + static-tilt Mesh child)
```

`ItemSlot` and `KartAudio` remain later slots. `DriftController` and
`BoostController` own their own gameplay state (see the Drift and Boost
subsections below) and hand `KartPhysics` only the immutable
`DriftResult`/`BoostResult` value objects each tick; `KartPhysics` remains the
sole writer of motion. `DriftEffects`/`BoostEffects`/`SkidMark` subscribe to
controller signals and read-only APIs only — no physics writes, capped at six
`GPUParticles3D` nodes per kart (spec §17, coding rule 6).

#### Drift (`kart/drift_controller.gd`, spec §10)

`DriftController.step(frame, speed, grounded, air_time, yaw_rate, is_hit, dt)`
drives a `NONE -> HOP -> HOLD -> RELEASE` state machine and returns one
`KartPhysics.DriftResult` per tick:

- **HOP** starts only when grounded, ungrounded-cooldown has elapsed, speed
  exceeds `drift_min_speed`, and `|steer| >= drift_min_steer`; it requests a
  vertical impulse via `hop_requested` (consumed by `KartPhysics.hop()`) and
  locks `direction` from the steer sign once `drift_hop_duration` elapses.
- **HOLD** accumulates charge every tick the driver still holds drift and
  isn't opposite-steering hard: `rate = base_charge_rate * (1 +
  steer_alignment_bonus * alignment) * turn_quality * KartData.drift_factor`,
  where `alignment = max(0, steer * direction)` and `turn_quality` drops to
  `low_turn_quality_mult` whenever `|yaw_rate| < min_drift_yaw_rate`. Charge
  never decreases. Cancel paths: speed under `drift_cancel_speed` for
  `drift_cancel_delay`, `HIT` state, airborne longer than
  `drift_airborne_cancel_time`, or steer opposing `direction` past
  `drift_min_steer` for `drift_opposite_cancel_delay` (a milder opposite
  steer only widens the turn radius via `drift_steer_influence`, never
  reverses `direction`).
- **RELEASE** reads the highest `MiniTurboTier` whose `charge_seconds` the
  accumulated charge has crossed, requests that tier's `BoostSpecData` via
  `boost_requested`, and starts `drift_cooldown` before the next hop can begin.
- Airborne tricks: while ungrounded with `air_time >= trick_min_air_time`, a
  drift-button press arms a trick; landing while armed requests `trick_boost`
  and clears the arm flag.
- Signals (emitted locally and mirrored on `EventBus` with the owning kart):
  `drift_started(direction)`, `drift_tier_changed(tier)`,
  `drift_ended(released_tier)`.

#### Boost (`kart/boost_controller.gd`, spec §11)

`BoostController` owns one non-additive boost slot. `request(spec, source)`
replaces the active spec when the new one's `speed_mult` is strictly
stronger, or extends the remaining duration (capped at `max_boost_duration`)
when it is equal or weaker. `step(dt)` decays `remaining` and returns the
current `KartPhysics.BoostResult`, scaling `speed_mult`/`accel_mult` toward
neutral by `KartData.boost_power`. `ignores_offroad` on the active spec flows
into `TerrainSensor.sample(ignores_offroad)` so a boosted kart is not
penalized by terrain it is powering through. `evaluate_start_input(frame,
countdown_phase)` is a pure function (no controller state read or written)
implementing the §11 start-boost window and early-throttle wheelspin outcome,
kept for Phase 5's countdown UI to call. Boost sources currently in play:
mini-turbo release (`DriftController`), slipstream exit (`SlipstreamSensor`
via `KartController`), landing tricks (`DriftController`), and `BoostPad`.
Signals: `boost_started(spec)`, `boost_ended()`, mirrored on `EventBus` with
the owning kart.

#### Tick order (`KartController._physics_process`, spec §9.3)

Every step is real as of Phase 3:

```text
1. frame   = input_provider.get_frame()          [real] hit-filtered; zero while RESPAWNING/FROZEN
2. terrain = _sample_terrain(boost.ignores_offroad) [real] zone > collider metadata > asphalt
3. ground  = KartPhysics.probe_ground()          [real] 5-ray average, excludes >max_climb_angle hits
4. drift   = _update_drift(frame, ground)        [real] DriftController.step() -> DriftResult
5. boost   = _update_boost(delta)                [real] slipstream active mult + BoostController.step()
6. KartPhysics.integrate(frame, terrain, ground, drift, boost, delta)  [real]
7. _update_hit_reactor(delta)                    [real] reaction/invulnerability timers
8. _update_state(ground)                         [real] hit/respawn priority, DRIFTING while HOLD, airborne grace
```

`drift_controller.hop_requested` is connected to `KartPhysics.hop()` and
`drift_controller.boost_requested` to `boost_controller.request()` once at
`_ready()`, so a released mini-turbo or landed trick reaches the boost slot
without `KartController` routing the spec by hand.

`KartVisuals` and `RaceCamera` read only `KartController`'s public API
(`get_speed`, `get_lateral_speed`, `get_air_time`, `get_forward`, hit state and
progress, plus inherited `get_velocity`) inside `_process()`, never
`_physics_process()`, and never write back into physics state (coding rule 6).

#### Physics model (`kart/kart_physics.gd`)

- Longitudinal `speed` and lateral `lateral` are scalars in the kart's own
  frame; world `velocity` is reassembled every tick from
  `forward * speed + right * lateral + up * vertical_speed` before
  `move_and_slide()`.
- The kart's actual `Node3D` basis only ever yaws (`rotate(ground_normal or
  Vector3.UP, yaw_delta)`); it never pitches or rolls, so it structurally
  cannot flip (spec §9.7). Visual roll/pitch/bob live entirely in
  `KartVisuals` as a cosmetic offset on the `Visuals` sub-node.
- `CharacterBody3D.up_direction` is a separate, continuously-slerped value
  (ground normal when grounded, world up when airborne) used only for
  `move_and_slide()`'s own floor/wall classification — decoupled from the
  yaw-only visible basis.
- Wall response is factored into a pure static function,
  `KartPhysics.compute_wall_response(incidence_degrees, tuning) ->
  WallResponse`, so graze/head-on/interpolated speed-and-bounce math is
  unit-testable without a scene tree (spec §9.8).
- `TerrainSensor` resolves an overlapping `OffroadZone` before ground-collider
  `terrain` metadata and asphalt fallback. `KartData.offroad_resistance`
  lerps speed, grip, and drag penalties toward neutral values.
- `SlipstreamSensor` uses a forward `ShapeCast3D`, a same-direction dot gate,
  and deterministic charge time. Its active-window speed multiplier stays a
  timed value owned locally in `KartController._update_boost()`; only the
  exit bonus routes through `BoostController.request()`, since the active
  multiplier is a continuous terrain-like effect rather than a stacked boost.
- Drift yaw (`compute_drift_yaw_rate`) and grip/speed-retention are applied
  only while `DriftResult.is_drifting` is true; the locked `drift_dir` can
  never flip sign regardless of opposite steer (spec §10.2).
- Airborne state requires more than two consecutive failed ground probes.
  Landing speed loss is capped and large travel-heading misalignment retains
  only a tuned fraction of lateral speed.
- Wall incidence is measured from pre-slide velocity; a continuous wall
  contact receives one impact response rather than compounding loss per tick.

#### Camera (`camera/race_camera.gd`, spec §16)

`RaceCamera` extends `Camera3D` directly rather than being a kart child, and
reads only the target's public API. It implements spring-follow position,
velocity-direction look, speed-squared FOV, a sideways offset opposite the
active drift direction (lerped, from `get_drift_direction()`), and a
spring-damped FOV kick while `is_boosting()`. Shake and look-back are Phase 8.

### Race

`RaceManager` (`race/race_manager.gd`, root script of `race/race.tscn`) owns
only composition and legal transitions:
`LOADING -> COUNTDOWN -> RACING -> FINISHING -> RESULTS`, with `PAUSED`
reachable only from `COUNTDOWN`/`RACING`. It resolves
`GameState.pending_race_config` or creates the Track 01 / 3-lap / 8-kart /
medium fallback, instantiates the track, places karts on ordered StartGrid
slots, registers them with the four delegated runtime systems, and binds the
camera/HUD to the player. Every transition emits
`EventBus.race_state_changed(old, new)`; only the first
`COUNTDOWN -> RACING` edge emits `race_started`.

`Countdown` (`race/countdown.gd`) advances 3-2-1-GO from physics deltas using
`RaceTuning.countdown_step_seconds`. Karts continue polling their provider
while FROZEN, exposing only a defensive latest-frame snapshot to Countdown.
Start input is adjudicated once through
`BoostController.evaluate_start_input()`; boost/wheelspin is held pending and
applied at GO so boost duration is never consumed during COUNTDOWN.

`RaceManager` receives only `LapTracker.kart_finished`. A finished kart gets
`KartController.set_finished()` plus a fresh line follower capped at 50%; when
the player finishes the state enters FINISHING. All-finished or the 15-second
`RaceTuning.finish_timeout_seconds` closes the field, then PositionTracker's
finished-by-time / unfinished-by-progress ranking is finalized after the tuned
results delay. `RaceResults` derives per-lap times from cumulative
`lap_completed` events, counts accepted hits/item-use events, creates result
rows, and writes the player's lower best lap/position through SaveManager.

`restart()` clears registrations and dynamic track/kart instances in place,
then rebuilds the same config. This preserves UI references to RaceManager.
Pause sets `SceneTree.paused`; only RaceManager and PauseMenu run ALWAYS so
resume/restart/menu input remains available while all gameplay physics stops.

Phase 4 adds `LapTracker` and `PositionTracker`, both bound to a track via a
`setup(track)`/`setup(track, lap_tracker)` call and then per-kart
`register_kart(kart)`. `LapTracker` owns `next_checkpoint_index`/`lap`/
`checkpoints_hit`/wrong-way state per kart and exposes the pure static
`evaluate_checkpoint_transition(index, next_checkpoint_index, checkpoint_count)`
so the sequential-pass/re-entry-ignored/lap-on-checkpoint-zero rule (spec
§14.3) is unit-testable without a scene tree. It emits `EventBus.lap_completed`
and `EventBus.wrong_way`, but its own `kart_finished(kart, time)` signal is
local (not on `EventBus`) since only `RaceManager` (Phase 5) needs it.
`PositionTracker` runs at 5Hz off a tick counter and exposes the pure static
`rank_karts(previous_order, ids, progress_by_id, finished_by_id,
finish_time_by_id, hysteresis)` (finished-by-time, then unfinished by
progress with a hysteresis reorder pass) so ranking is testable with plain
int ids and dictionaries standing in for karts. `RespawnSystem` gained a
static `resolve_respawn_transform(kart, lap_tracker, racing_line,
other_karts)` that orients the spawn along the line and steps back 3 m at a
time if another kart occupies the spot (spec §14.5); the existing per-kart
`register_kart(kart, get_respawn_transform: Callable)` API is unchanged, so a
caller (the sandbox, later `RaceManager`) just binds a callable to the new
resolver instead of writing its own lookup. `HazardRelay` mirrors
`RespawnSystem`'s bridge role for `Hazard` -> `KartController.apply_hit()`.
`RaceConfig` includes a zero-based `player_slot`; `StartGrid.generate()` remains
the pure staggered layout fallback for tracks with fewer than 8 markers.

### Track

Track scenes live below `track/tracks/`; reusable elements live below
`track/elements/`. `OffroadZone` declares `TerrainData`; `KillZone` emits typed
kart entry for `RespawnSystem`. Both flat/hills test tracks have y=-5 kill
planes; the flat loop has two grass patches, hills has dirt, a 1.5 m drop, and
an east-wall gap. `track/track.gd` still validates structure without
referencing karts. `BoostPad` (layer 5 `Area3D`) and `JumpPad` narrow their
kart interaction to `KartController.boost_controller.request()` and
`KartController.launch()` respectively; neither owns kart state. `test_loop`
carries two boost pads on its back straight, `test_loop_hills` carries one
jump pad and a landing zone, and `track/tracks/test_hairpin/` is a third
greybox track (a paperclip oval with two ~18 m radius hairpins built from
evenly spaced arc points plus S-curve chicanes) sized so a drifted lap clears
mini-turbo tier 2 and beats a non-drifted lap.

Phase 4 replaces the placeholder racing line with a real offset API and adds
the checkpoint/element contract from spec §15:

- `RacingLine` (`track/racing_line.gd`) bakes `curve` into a local point
  array + cumulative-distance table once (`bake()`, lazily invoked by every
  query) and exposes `length()`, `offset_at(global_pos, hint_offset := -1.0)`
  (full scan when no hint, otherwise a `hint_window`-sized local search
  around the hint's baked index, per spec §26), `sample(offset)`,
  `tangent_at(offset)`, `right_at(offset)`, `curvature_at(offset)` (a 3-point
  circle fit over `curvature_window`), and `max_curvature_in(offset,
  distance)`. Subclasses that fully replace `_ready()` to author their own
  curve (`hairpin_racing_line.gd`, `track_01_line.gd`) still work: baking
  never depends on `RacingLine._ready()` running, only on `curve` being set
  by the time a query first runs.
- `Checkpoint` (`track/elements/checkpoint.gd`) is an `Area3D` (layer 5, mask
  2) with a `RespawnPoint` `Marker3D` child. It never looks upward for its
  own order/offset; `Track._configure_checkpoints()` calls
  `checkpoint.configure(index, racing_line)` once per child in `_ready()`
  (guaranteed to run after `RacingLine`'s own `_ready()`, since children
  ready before parents). It emits a generic `body_passed(body, index)` so
  `Track` never references `Kart`; `LapTracker` (race/) does the cast.
- `Track` (`track/track.gd`) now also exposes `get_checkpoints()`,
  `get_racing_line()`, `get_start_grid()` (padded to 8 slots via
  `StartGrid.generate()` if the scene has fewer), `get_item_box_anchors()`,
  and `get_lap_length()`.
- New elements: `ItemBox` (hide/respawn-on-tick + generic `collected(body)`
  signal only; item effects are Phase 7), `Hazard` + `HazardRelay` (mirrors
  `KillZone`/`RespawnSystem`'s bridge pattern for `KartController.apply_hit()`),
  `MovingObstacle` (an `AnimatableBody3D` that samples a `Path3D`'s baked
  curve directly each tick rather than parenting under a `PathFollow3D`,
  which would force it under the path node instead of carrying its own
  mesh/collision), and `TrackShortcut` (`track/elements/shortcut.gd` — named
  `TrackShortcut`, not `Shortcut`, because that collides with Godot's
  built-in `Resource`-based `Shortcut` class used by `InputMap`/`BaseButton`;
  GDScript's static analyzer resolves the built-in one and rejects a `Node`
  being cast to it). `TrackShortcut.progress_at(global_pos)` interpolates
  `entry_offset..exit_offset` from the kart's position on `alt_curve`;
  `PositionTracker` substitutes this for the normal checkpoint-window
  progress while a kart is inside the shortcut's `TriggerArea`.
- `track_validator.gd` now runs every §15.5 check for real (item-box count
  and 8 m proximity, kill-zone AABB coverage of the track's own geometry)
  instead of skipping two of them with a warning.
- `track/tracks/track_01_ridgeline_circuit/` is the Vertical Slice track
  (spec §15.7): see the dedicated section below.

### Items and AI

Item behavior will live in `items/`; Phase 0 created only its directory
contracts and data schemas, and it stays that way until Phase 7.
`race/scripted_race_input_provider.gd` still exists — RaceManager now uses it
only for the FINISHING-state player fallback (a human's kart after they cross
the line) and can still be used directly by tests/sims that want a
deterministic non-AI driver. It is no longer the game's default opponent.

#### AI node tree and tick (spec §13)

`AIController` (`ai/ai_controller.gd`, `extends Node3D`) is added as a child
of a `KartController` whenever `RaceManager`/`kart_sandbox.gd` spawns a
non-player kart:

```text
Kart (CharacterBody3D)
└── AIController (Node3D)
    └── AISensors (Node3D)
        ├── ShapeCast3D (forward-left)
        ├── ShapeCast3D (forward-center)
        ├── ShapeCast3D (forward-right)
        └── ShapeCast3D (rear)
```

`AIController` extends `Node3D` (not a plain `Node`) purely so `AISensors`'s
`ShapeCast3D` children inherit the kart's transform correctly — `Node3D` only
looks at its *direct* parent for a world transform, so a plain-`Node`
container in the middle would leave the casts stuck at the world origin.
`AISensors` is `Node3D` for the same reason.

`AIController._physics_process(delta)` accumulates `delta` (which already
carries any `Engine.time_scale`, spec §13.8's up-to-8x headless sim) and, once
the accumulator reaches `1 / profile.ai_tick_hz` (30 Hz), drains the *whole*
accumulated span and runs one tick with that real elapsed time — not a fixed
nominal interval. Passing a fixed interval while draining only that much per
physics frame silently understates every downstream timer (PD `kd`, EMA
smoothing, stuck timers) the instant one scaled `delta` exceeds a tick's
worth, which is exactly what happened before this was fixed (see the Phase 6
decision log entry). Each kart's tick is phase-offset (a starting fraction of
one tick interval) so seven-plus AI karts do not all re-run their `ShapeCast3D`
queries on the same physics frame (spec §26).

One AI tick composes, in order:

```text
AISensors.tick() -> SensorReport
  -> AIDriver.compute_avoid_bias / compute_overtake_bias(SensorReport, profile)
  -> AINavigator.compute(pos, speed, profile, bias, dt, rng) -> NavResult
  -> AIDriver.compute_frame(kart, profile, NavResult, SensorReport, context, dt) -> InputFrame
     (delegates cornering-drift entry/hold to AIDriftPlanner)
  -> AIItemBrain.should_use(ItemSlotView, ...) -> InputFrame.item
  -> AIInputProvider.set_frame(InputFrame)
```

`AIInputProvider` (an `InputProvider`) is the only thing `KartController` ever
polls; it just returns whatever `InputFrame` the last AI tick produced; the
same frame is served across the ~2 physics ticks between 30 Hz AI ticks and
60 Hz physics ticks. `AISensors` (3 forward + 1 rear `ShapeCast3D`, layer mask
`world | kart_body`) only re-queries on an AI tick, never every physics frame.
`AINavigator` owns the smoothed per-kart lane offset (random base + a
biased target the sensors/overtake logic feed in) and shortcut entry/
following; it exposes both an *unsigned* windowed curvature
(`max_curvature_in`, for corner-speed/apex checks) and a *signed*
single-point curvature (`curvature_at` a fixed distance ahead, for which way
to lock a drift) — collapsing those into one unsigned value was a real Phase 6
bug (decision log). `AIDriver` owns steering (PD), the corner-speed/rubber-band
throttle-brake governor, stuck/reverse/respawn handling, and start-boost
timing; `AIDriftPlanner` (split out to keep `ai_driver.gd` under the spec §29
400-line budget) owns only curvature-gated drift entry/hold/release.
`AIItemBrain` evaluates a rule table against `ItemSlotView` — a null Phase 6
stub (`view.has_item()` is always `false`) so the full pipeline runs
structurally without Phase 7's `ItemSlot` existing yet.

`AIRaceContext` (`ai/ai_race_context.gd`) is the one upward-reaching seam:
`RaceManager`/`kart_sandbox.gd` build a single shared instance per race
(`racing_line`, `track`, `position_tracker`, `player_kart` — nullable for an
all-AI race, `request_respawn`, `get_countdown_phase_seconds`) and pass it to
every `AIController.setup()`. Every field has a concrete consumer; it is not
a general-purpose grab-bag. AI never reaches upward through
`get_node("../..")` (spec §29 rule 5) — everything it needs about the race
comes through this one object or its own `setup()` parameters.

`AIDifficultyProfile` (`data/schemas/ai_difficulty_profile.gd`,
`data/ai/{easy,normal,hard}.tres`) holds every tunable from spec §13.6.
Fields split into two groups: skill (`speed_confidence`, `steer_kp/kd`,
`steer_noise`, `drift_skill`/`target_tier`, `late_brake_prob`,
`shortcut_take_prob`, `item_decision_delay`/`item_use_accuracy`,
`start_boost_skill`, `trick_prob`, `rubber_band_strength`) differs per
difficulty; sensing/mechanical fields (`max_lateral_accel`,
`brake_look_ahead`, `drift_curvature_threshold`, `overtake_range`,
`ai_tick_hz`, `lane_offset_min/max`) are deliberately identical across all
three — spec §13.6's last bullet is "difficulty is judgment quality, never a
speed or perception cheat," and Hard never exceeds `speed_confidence = 1.0`
(`AIDifficulty.validate()` enforces this and pushes an error rather than
silently clamping). `AIDifficulty` also derives `tick_interval()` and rolls
each kart's seeded base lane offset — small helpers, not a God object.

Rubber banding (spec §13.7) lives in `AIDriver._rubber_band_gap()`: it reads
`PositionTracker.get_progress()` for both the AI kart and
`context.player_kart` (0 if there is none), and
`AIDriver.compute_rubber_band_mult()` clamps the result to `±max_band`
(0.05). `AIController.get_rubber_band_mult()`/`get_target_speed()`/
`get_lane_offset()` exist purely so `kart_sandbox.gd`'s `DebugOverlay`
watches can show it happening — spec §13.7 explicitly calls this out as
something that must never become an invisible cheat.

### Camera, UI, audio, and effects

Presentation domains read state or subscribe to signals. They do not alter
physics or race truth. `AudioManager` subscribes to events rather than
containing gameplay rules. `DebugOverlay` is a development-only observer and
runtime tuning surface.

The allowed direction is:

```text
Core ← all domains
Data ← all domains (read-only resources)
Kart ← Track, Items
Race → Kart, Track
AI → Kart, Track, Race, Items
Items → Kart, Race
Camera → Kart
UI → Race, Kart, Items
Audio → EventBus
Effects → Kart/Items signals
```

## Concrete repository layout

```text
res://
├── project.godot
├── ARCHITECTURE.md
├── DEVLOG.md
├── README.md
├── addons/gut/
├── core/
│   ├── autoload/
│   │   ├── game_state.gd
│   │   ├── event_bus.gd
│   │   ├── settings_manager.gd
│   │   ├── save_manager.gd
│   │   ├── audio_manager.gd
│   │   ├── debug_overlay.gd
│   │   └── debug_overlay.tscn
│   ├── input/
│   │   ├── input_frame.gd
│   │   ├── input_provider.gd
│   │   ├── player_input_provider.gd
│   │   └── input_actions.gd
│   └── math/.gitkeep
├── kart/
│   ├── kart.tscn
│   ├── kart_controller.gd
│   ├── kart_physics.gd
│   ├── kart_state.gd
│   └── kart_visuals.gd
├── camera/race_camera.gd, race_camera.tscn
├── race/race_state.gd
├── track/
│   ├── track.gd
│   ├── racing_line.gd
│   ├── track_validator.gd
│   ├── track_template.tscn
│   └── tracks/{test_loop,test_loop_hills}/*.tscn
├── items/
│   ├── base/
│   └── instances/{rocket_dart,hunter_drone,spike_mine,nitro_can,
│                  aegis_bubble,pulse_blast,storm_beacon}/
├── ai/.gitkeep
├── camera/.gitkeep
├── ui/{theme,hud,menus,results,components}/
├── audio/placeholder/
├── effects/.gitkeep
├── data/
│   ├── schemas/
│   ├── karts/
│   ├── drivers/
│   ├── items/
│   ├── tracks/
│   ├── ai/
│   ├── terrain/
│   ├── item_tables/
│   └── tuning/
├── scenes/{main.tscn,test/kart_sandbox.tscn}
├── assets/{placeholder,models,textures,audio,fonts}/
├── tests/{unit,integration,sim}/
└── tools/{run_tests.sh,run_sim.sh,validate_tracks.sh}
```

Directories without Phase 0 content contain `.gitkeep`. A `.gitkeep` is
removed when the directory gains a real tracked file.

## Core interfaces established in Phase 0

### Input abstraction

`core/input/input_frame.gd` is a typed `RefCounted` snapshot containing
throttle, brake, steer, held/edge buttons, look-back state, and physics tick.
`InputFrame.zero()` creates a neutral frame and `clone()` copies a frame for
recording, replay, or network buffering.

`core/input/input_provider.gd` defines `get_frame() -> InputFrame`.
`core/input/player_input_provider.gd` reads the `InputMap`, supports a device
identifier, smooths digital steering, and exposes an input-strength override
for deterministic unit tests. Future kart code consumes this provider API.

### Save and settings boundaries

`SaveManager` stores gameplay progress as JSON because the format is portable,
versioned, and easy to migrate. `SettingsManager` uses `ConfigFile` because it
natively represents sections and scalar values. Both managers accept an
override path so tests use isolated temporary files rather than real user data.

### Resource contracts

Every schema named in section 20 has one script in `data/schemas/`. Resources
contain exported data only, plus narrow validation helpers where tests require
observable invariants. `ItemTableData` owns row-total validation because it is
the boundary that consumes the rank table.

## Track contract

A track root uses `track/track.gd` and requires these direct children:

- `Geometry`
- `Environment`
- `RacingLine` (`Path3D` with a closed `Curve3D`)
- `Checkpoints` (at least four `Area3D` children)
- `StartGrid` (at least eight `Marker3D` children)
- Phase-later element containers (`ItemBoxes`, `BoostPads`, `JumpPads`,
  `OffroadZones`, `Hazards`, `KillZones`, `MovingObstacles`, `Shortcuts`)

Runtime `_ready()` validation reports missing required nodes with `push_error`.
The headless validator (`track/track_validator.gd`, `tools/validate_tracks.sh`)
runs the full spec §15.5 checklist: checkpoint count and monotonically
increasing offsets, grid count and proximity to the racing line, respawn
marker presence and ground contact, racing-line closure, item-box count and
proximity, and kill-zone coverage of the track's own geometry footprint (an
axis-aligned-rectangle union/containment check against every `CollisionShape3D`
under `Geometry` and `KillZones`, not exact polygon coverage).

## Track 01 — "Ridgeline Circuit" (`track/tracks/track_01_ridgeline_circuit/`)

The Vertical Slice greybox (spec §15.7): a ~1,499 m closed loop (two 680 m
straights joined by two 20 m-radius 180-degree end turns) built the same way
as `test_hairpin` — a `RacingLine` subclass (`track_01_line.gd`) constructs
its `Curve3D` from arc points at `_ready()` — but everything else about it
(road, walls, checkpoints, and every other element) is authored to spec
§15.7's feature list:

- `Track01` (`track_01_track.gd`, `extends TrackRoot`) overrides `_ready()`
  to call `super._ready()` (validates the contract, configures checkpoints)
  and then builds `Geometry`'s road and wall meshes/collision procedurally
  from the now-baked `RacingLine` via `tools/track_builder.gd`'s
  `build_road_segments()`/`add_box_segment()`. This has to happen in the
  *track root's* `_ready()`, not `Geometry`'s own script: `Geometry` and
  `RacingLine` are sibling children, and Godot readies children in scene
  order, not by whichever one a script "needs" — only the parent is
  guaranteed to run after every child.
- The outer wall ribbon skips the last ~9% of the lap (the closing east
  arc), producing the mandatory guardrail-less cliff corner over the shared
  kill-zone plane below.
- A single S-curve chicane sits on the outbound straight; the west end-turn
  is the mandatory drift-Tier-3 hairpin.
- `TrackShortcut` cuts directly across the hairpin (a 40 m chord vs. the
  arc's ~63 m sweep) over a `dirt.tres` `OffroadZone`; its trigger box is
  sized so a kart actually driving the paved hairpin (which bulges 20 m
  further out) never enters it, keeping the deterministic auto-drive lap
  test unaffected by a feature it never intentionally uses.
- Two `MovingObstacle`s sweep across the return straight but are centered
  off the exact racing line (biased toward one edge of the 14 m road) so a
  scripted/line-following driver mostly clears them; a human or future AI
  drifting wide still has to react to them.
- 3 boost pads, 1 jump pad (landing on continuous flat road, not a gap — a
  greybox simplification so the mandatory jump/trick feature doesn't add
  auto-drive-test flakiness), 3 item-box rows of 5/5/4, 8 checkpoints, and 8
  start-grid slots round out the §15.7 checklist.
- Checkpoint gate `CollisionShape3D` orientation matters and is *not* the
  scene default: `checkpoint.tscn`'s own shape (14 m wide on X, 2 m thick on
  Z) is correct only where travel runs along Z (the two arc apexes); every
  checkpoint on the two X-direction straights overrides it with the
  transposed box (2 m thick on X, 14 m wide on Z) so the gate is thin across
  the direction of travel and wide across the road, matching `test_loop`'s
  established convention.

## Testing and verification

- Unit tests: `tools/run_tests.sh` runs GUT over `tests/` recursively.
- Simulation: `tools/run_sim.sh --laps N --karts N --races N` boots
  `tests/sim/run_ai_race.tscn` with normal project autoloads, runs real Track 01
  races with scripted providers at `Engine.time_scale = 4`, prints JSON finish
  order/times/respawns/head-on count, and exits 1 if any kart is a DNF.
- Track contract: `tools/validate_tracks.sh` runs `track/track_validator.gd`
  headlessly against `test_loop.tscn`, `test_loop_hills.tscn`,
  `test_hairpin.tscn`, and `track_01_ridgeline_circuit.tscn`.
- Parse/import: `/opt/homebrew/bin/godot --headless --path . --import` runs
  before the final parse check; generated `*.uid` files are committed.
- Phase 2 integration tests exercise mass contact, terrain cap/recovery, wall
  BUMP/recovery, ledge airborne/landing, and kill-zone respawn using real scenes.
- Phase 4 integration tests drive the real Track 01 scene end to end: a
  3-lap `ScriptedInputProvider` (drift mode) run against `LapTracker` proves
  the jump pad/shortcut/moving-obstacles/S-curve/hairpin combination doesn't
  break lap completion, plus dedicated checks for wrong-way set/clear,
  skipped-checkpoint lap withholding, and cliff-fall respawn resolving to the
  last passed checkpoint's `RespawnPoint`.
- Phase 5 unit/integration tests cover transition and timeout tables, exact
  countdown cadence, start boost/wheelspin application, result aggregation and
  save bests, stable FROZEN/FINISHED kart states, the real four-kart test-loop
  state cycle, pause immobility, restart reset, HUD events, UI focus, and main
  config creation.

## Decision log

- Phase 0 uses the original game name **Turbo Circuit** to avoid derivative
  branding while keeping the project identity concise.
- `InputFrame` is a class-backed `RefCounted` value object because GDScript has
  no user-defined value structs and later replay/network layers need cloning.
- Player input injection is a callable strength override, keeping tests
  deterministic without adding test-only methods to Godot's `Input` singleton.
- Save and settings managers accept file-path overrides so corrupt-file and
  round-trip tests never mutate a developer's real `user://` files.
- Save recovery preserves the last known-good primary as `save.json.bak` and
  restores defaults only when both primary and backup are invalid.
- Audio buses are created idempotently at startup; the SFX pool is a reusable
  skeleton without Phase 10 content or playback policy.
- The greybox oval is assembled from static primitive segments rather than a
  procedural mesh, making the `.tscn` inspectable and editable without tools.
- The Phase 0 racing line is constructed through `Curve3D.add_point()` from a
  typed point list because hand-authoring Godot's private packed curve payload
  produced invalid control-point data; authored metadata replaces it in Phase 4.
- The Phase 0 validator treats Phase 4-only requirements as explicit warnings,
  preventing scaffolding from pretending to provide item/kill-zone guarantees.
- macOS uses `/etc/ssl/cert.pem` through a platform-specific project override
  so sandboxed headless runs do not require keychain access; other platforms
  keep Godot's system-certificate default.
- Existing vendored GUT 9.6.1 is used unchanged and enabled through
  `project.godot`; no dependency download step is introduced.

### Phase 1

- `PhysicsTuning` gained three fields Phase 0 did not anticipate exactly:
  `hover_snap_speed`, `up_align_speed_grounded`, `up_align_speed_airborne`.
  All other Phase 1 physics constants (ground/air/wall/drift groups) were
  already present in Phase 0's schema, confirming the schema was authored
  ahead of need; these three fill the one real gap (hover/up-alignment rate).
- Hover height is enforced as a direct proportional correction
  (`height_error * hover_snap_speed`, clamped) rather than letting
  `CharacterBody3D`'s own floor collision support the kart's weight. This
  keeps the "hover" feel exact and tunable independent of collision-shape
  geometry, matching §9.7's "hover snap" language.
- Up-vector alignment reuses a hand-written spherical interpolation
  (`KartPhysics._slerp_up_vector`) instead of `Vector3.slerp()`. Godot's
  built-in implementation asserts on a degenerate rotation axis whenever the
  two up vectors are (near-)parallel or (near-)antiparallel — both happen
  constantly here (flat ground repeats the same normal every tick). The
  hand-written version special-cases both without changing the interpolated
  result for the general case.
- `KartController.get_velocity()` was dropped from the public API list in
  favor of `CharacterBody3D`'s own native `get_velocity()` — GDScript treats
  overriding it as a fatal parse error. The inherited method returns the same
  `velocity` property Phase 1 would have exposed anyway.
- `DebugOverlayService` gained `remove_slider()` alongside its existing
  `unwatch()`. Phase 0's watch/slider API had no counterpart for sliders, so
  a scene that registers sliders and is later freed (the sandbox, repeatedly
  instantiated across tests) left stale getter/setter closures that the
  overlay's `_process()` called on freed objects every frame afterward.
- The scripted lap-following test driver (`tests/support/scripted_input_provider.gd`)
  eases off the throttle in proportion to its steering command instead of
  holding full throttle everywhere. Cornering at a constant full throttle
  round the placeholder racing line clipped walls hard enough to trip the
  DoD's 10 m line-deviation budget; slowing for corners is what any real
  driver (human or AI) would do and is not a physics tuning change.
- `track/tracks/test_loop_hills/test_loop_hills.tscn` adds its ramp and
  banked-corner geometry as additional collision/mesh overlays on top of the
  existing flat floor rather than editing the shared floor slab or the
  existing curve pieces. Raycasts and `move_and_slide()` naturally prefer
  whichever surface is higher/closer, so overlay geometry does not require
  cutting the base mesh. Both ramp segments are authored longer than their
  visible span with their low ends dipped below y=0 on purpose, burying the
  box's end-cap face under the pre-existing flat floor instead of exposing
  a vertical face a kart could clip as a false "wall".
- The banked corner is a `# PLACEHOLDER` fixed-roll overlay approximating
  banking, not geometry aligned to the curve's own tangent frame at every
  point along it. TODO(phase-4): replace with tangent-aligned banked
  geometry once `RacingLine` carries authored per-track curve data.
- `tools/run_tests.sh` now runs with `--fixed-fps 240`. GUT's
  `wait_physics_frames()` used by the new kart integration tests advances
  real engine frames; without decoupling from wall-clock time, a 90
  simulated-second lap test would take roughly 90 real seconds. Godot's
  physics tick rate stays governed by `physics/common/physics_ticks_per_second`
  (60) regardless of this flag — it only lets the engine advance faster than
  real time, not more physics ticks per simulated second.
- `tools/validate_tracks.sh` now validates both `test_loop.tscn` and
  `test_loop_hills.tscn` in one run instead of only the default track.

### Phase 2

- Terrain identity travels in `TerrainSample` as the particle/audio hook; no
  presentation system is pulled forward from later phases.
- Slipstream exit stays in `BoostResult` and is marked for Phase 3 routing
  through `BoostController`; no parallel boost stack exists.
- Wall angles use pre-`move_and_slide()` velocity because the post-slide vector
  has already lost its normal component. Continuous contact is latched so a
  head-on penalty is applied once per impact rather than every physics tick.
- Hit physics remains scalar and deterministic; spin/flip/squash are transforms
  on `KartVisuals` only. BUMP weakens control, SpinOut/Tumble disable it, and
  Squash retains control under a speed cap.
- Respawn timing uses physics-tick counters, never coroutine timers. The
  StartGrid locator is injected by the sandbox and will be replaced by
  checkpoint RespawnPoints in Phase 4.
- The macOS TLS certificate bundle override points to `/etc/ssl/cert.pem` so
  sandboxed headless runs do not attempt restricted Keychain access.

### Phase 3

- `DriftController`/`BoostController` are configured via `configure(tuning,
  kart_data)` and driven with an explicit `step()`/`request()` API instead of
  reading `KartController` directly, so both are unit-testable by feeding
  fake frames/speeds without a scene tree — the same pattern Phase 1's
  `KartPhysics` and Phase 2's `SlipstreamSensor` established.
- Mini-turbo charge rate is pinned so `steer = 0.0` (no alignment bonus)
  charges at exactly `base_charge_rate` (1.0/second), making
  `MiniTurboTier.charge_seconds` literally seconds of full-quality holding.
  This is asserted by a unit test and is a hard constraint on any future
  tuning pass: `base_charge_rate` and `steer_alignment_bonus` must not change
  without re-deriving the §10.4 tier table, since Phase 3's own hairpin
  auto-drive proof depends on the exact 1.0s/2.2s/3.6s boundaries. This also
  means the automated hairpin lap comparison could not be made to pass by
  loosening those two gameplay values — only track geometry and the scripted
  test driver were tuned (see below).
- The Phase 2 slipstream *exit* bonus now routes through
  `BoostController.request(tuning.slipstream_exit_boost, &"slipstream_exit")`
  on the active-to-inactive edge, removing the old TODO. The slipstream
  *active* window's own speed multiplier stays a separate, continuous
  terrain-like effect applied directly in `KartController._update_boost()`
  rather than a boost-stack entry, since a same-direction draft is ongoing
  contact, not a discrete pickup.
- `track/tracks/test_hairpin/hairpin_racing_line.gd` builds each ~18 m hairpin
  from evenly spaced 30-degree arc points around a real circle rather than a
  single sharp vertex. A single-vertex "hairpin" reads as a brief curvature
  spike to any 3-point finite-difference curvature estimator (including the
  sandbox's own scripted driver), not a sustained tight turn — too short a
  signal to hold a drift through.
- `tests/support/scripted_input_provider.gd`'s optional drift-on-corners mode
  needed three additions beyond a bare curvature threshold to actually clear
  mini-turbo tier 2 on that hairpin: (1) a lower exit threshold than the
  entry threshold (hysteresis), so a mid-corner dip in sampled curvature
  doesn't release the drift before the kart has actually exited the turn;
  (2) a steer "flick" — pure line-tracking steer rarely reaches
  `drift_min_steer` on its own, so once a turn is sharp enough to be worth
  drifting the provider boosts steer magnitude toward the turn's locked
  direction, sustained for the whole hop (a natural, gentler steer value on
  even one intervening tick fails `DriftController`'s per-tick minimum-steer
  hop check and cancels it); (3) during the hold, steer is clamped (never
  boosted) to the locked direction's side so ordinary pursuit-steering noise
  cannot cross zero and trip the opposite-steer cancel. None of this touches
  `PhysicsTuning` — it is scripted-AI-only, calibrated against the fixed
  1.0 charge/second constraint above.
- The same provider brakes ahead of any upcoming turn tighter than
  `sqrt(a representative grip constant * radius)` regardless of drift mode,
  because pure line-tracking alone cannot hold an 18 m turn at cruising speed
  on ordinary (non-drift) grip — it slides wide by tens of meters. This
  braking is suspended for the ticks actually spent in `DriftState.HOLD`:
  stacking it on top of `drift_speed_retention` starves charge time and
  trips the low-speed cancel.
- `tests/integration/test_phase3_hairpin.gd` measures lap completion by
  cumulative world-space distance traveled plus a return within a radius of
  the post-warmup start position, not `Curve3D.get_closest_offset()` deltas
  like `test_kart_lap.gd` uses on the single-loop tracks. This track's two
  straights run close and parallel, so a kart's closest point on the curve
  can be genuinely ambiguous between them; distance-plus-return sidesteps
  that ambiguity entirely.
- HOP→NONE also on button release during hop: a tap is a hop, not a drift;
  avoids zero-charge releases.

### Phase 4

- `LapTracker.evaluate_checkpoint_transition()` and `PositionTracker.rank_karts()`
  (plus its private `_reorder_with_hysteresis()` step) are `static` and take
  only plain ids/dictionaries/enums — no `KartController` — so the sequential
  checkpoint rule and the ranking/hysteresis behavior are unit-tested without
  a scene tree at all, the same "pure core, thin instance wrapper" split
  Phase 3 used for `DriftController`/`BoostController`.
- `LapTracker.register_kart()` seeds `next_checkpoint_index = 1`, not `0`.
  Checkpoint 0 is both the first gate a kart can physically overlap at the
  starting grid *and* the lap-completing gate; seeding at 0 would let the
  opening-grid overlap itself complete "lap 1" with zero checkpoints
  actually driven. Seeding at 1 makes that overlap match the
  re-entering-the-previous-checkpoint rule (ignored) instead.
- `RacingLine` cannot bake in its own `_ready()`, because `test_hairpin` and
  `track_01` both fully override `_ready()` on subclasses (to author their
  own `Curve3D`) without calling `super._ready()`. Baking is instead lazy —
  every public query calls `_ensure_baked()` — so it works regardless of
  which `_ready()` set `curve`, or whether one ran at all.
- `Track._configure_checkpoints()` (assigning `index`/`offset` per child)
  lives in `Track._ready()`, not `Checkpoint._ready()`, for the same
  ordering reason: `Track` is guaranteed to ready *after* `RacingLine` (its
  own child), so `racing_line.offset_at()` is always safe to call there;
  `Checkpoint` has no such guarantee relative to its `RacingLine` sibling,
  and looking upward for it would also violate spec §29 rule 5.
- `ItemBox` toggles its `CollisionShape3D.disabled` via `set_deferred()`
  instead of a direct assignment inside its own `body_entered` handler.
  Godot's physics server asserts (`flushing_queries`) if an `Area3D`'s
  collision state changes synchronously while it is still the one flushing
  that very query's callbacks; deferring one frame is the same fix
  `CharacterBody3D`-adjacent code already uses elsewhere for this class of
  reentrancy.
- `MovingObstacle` samples its `Path3D`'s baked curve directly every physics
  tick instead of using an actual child `PathFollow3D` node. `PathFollow3D`
  must be parented under the `Path3D` it follows, which would put the
  obstacle's own mesh/collision under a node it does not otherwise own;
  reading `curve.sample_baked()` gets the identical position with a plain
  sibling-node scene layout.
- The new `Shortcut` track element is named `TrackShortcut` in code (files
  stay `shortcut.gd`/`shortcut.tscn`): Godot ships a built-in `Shortcut`
  `Resource` (used by `InputMap`/`BaseButton`, and by GUT's own editor
  panels), and GDScript's static type resolver bound the name to that
  built-in instead of the new `Node3D`-based class, hard-failing every
  `instantiate() as Shortcut` cast with "Cannot convert from Node to
  Shortcut". Renaming the `class_name` was the only fix; a global class name
  collision like this produces no warning at define time.
- Track 01's road/wall geometry is generated by the *track script*
  (`Track01._build_geometry()`), not authored as static mesh/collision nodes
  in the `.tscn`, and not a per-child-node script on `Geometry` either (see
  the Track 01 section above for why the latter can't rely on `RacingLine`
  being baked yet). Every other curve in this project (including this one)
  is also built from GDScript rather than a hand-serialized `Curve3D`
  resource in a `.tscn` — the text-scene format for `Curve3D`'s internal
  `_data` layout is undocumented, and an early draft of Track 01's moving
  obstacle paths and shortcut alt-curve, written by hand, produced scenes
  that failed to parse.

### Phase 5

- `RaceManager` owns transitions and composition but calls public reset/setup
  seams on the existing trackers. It does not duplicate lap, progress,
  respawn, or collision state. In-place restart was chosen over
  `SceneTree.reload_current_scene()` so pause/results controls keep a valid
  manager reference across unlimited restart cycles.
- `KartController` now distinguishes race freeze, start-wheelspin freeze, and
  finished-state persistence. Race freeze skips physics integration and clears
  motion while still polling one raw provider frame per tick; Countdown reads
  a clone of that frame rather than polling the provider a second time.
- Start outcomes are decided on the throttle edge but applied only at GO.
  Applying a Tier 1/2 request when it was judged would spend its duration while
  the kart was still frozen; delaying only the effect preserves the existing
  pure `BoostController.evaluate_start_input()` contract.
- `RaceResults` treats `EventBus.lap_completed`'s third argument as cumulative
  race time and subtracts the prior cumulative value per kart. No LapTracker
  signal contract changed, and best-lap persistence stays owned by the result
  boundary.
- `race/scripted_race_input_provider.gd` is a Phase 5 completion harness, not an
  early AI implementation. Proper perception, navigation, driving decisions,
  difficulty, overtaking, avoidance, shortcuts, items, and rubber banding stay
  in Phase 6+.
- The simulator boots a `.tscn` rather than using `godot -s` as a custom
  `SceneTree`. Direct script-main-loop execution did not compose project
  autoloads, so scripts referencing `EventBus`, `GameState`, or `SaveManager`
  failed compilation before the runner could return a meaningful exit code.

### Phase 6

- `AIController`/`AISensors` extend `Node3D`, not a plain `Node`. `Node3D`
  only inherits a world transform from its *direct* parent; a plain-`Node`
  container in between (which "a Node added as child of the kart" more
  literally suggests) left every `ShapeCast3D` probe stuck at the world
  origin instead of following the kart, and every AI kart perceived a
  permanent wall dead ahead from the moment it left the grid.
- `AINavigator.NavResult` exposes both an unsigned windowed curvature
  (`curvature_ahead`, from `RacingLine.max_curvature_in`) and a signed
  single-point one (`signed_curvature_ahead`, from `RacingLine.curvature_at`
  a fixed distance ahead). The first pass fed the drift planner the unsigned
  value, so `curvature > 0.0` was true on every corner including left turns —
  the AI locked "drift right" on every corner and fought its own correct PD
  steering, deadlocking at any genuinely tight turn. Corner-speed and
  apex-proximity checks (which only need magnitude) still use the unsigned
  one.
- `AIController._physics_process` drains the whole accumulated `delta` span
  each AI tick and passes that real elapsed time downstream, instead of
  subtracting a fixed nominal `1 / ai_tick_hz` and passing that fixed value
  as `dt`. The fixed-interval version silently ran every timer and the PD
  `kd` term on the wrong clock the moment a single `Engine.time_scale`-scaled
  physics `delta` exceeded one AI tick's worth (true above roughly 2x scale
  at the project's 60 Hz physics rate) — exactly the regime the headless sim
  runs in (spec §13.8, up to 8x).
- The AI's emergency "brake now, something is dead ahead" override
  (`AIDriver._apply_head_on_brake`) checks a genuine near-collision distance
  (3 m) and only while the kart still carries real speed, not "anything
  within the sensor's full forward range" (originally 6 m). A straight
  `ShapeCast3D` ray sees a curving corridor's outer wall constantly while
  cornering — that is normal track geometry, not an emergency — and the
  looser version permanently overrode the corner-speed governor's throttle
  decision, braking the kart past standstill into full reverse and pinning
  it there.
- Stuck detection (`AIDriver._update_stuck`) smooths speed with a 1-second-
  time-constant EMA before comparing it to `STUCK_SPEED_THRESHOLD`, instead
  of comparing instantaneous speed. A kart wedged against a wall and
  bouncing between ~0 and ~2 m/s every tick reset the instantaneous-speed
  timer every single tick and never accumulated the 2s/5s needed to trigger
  reverse/respawn recovery.
- **`track/tracks/track_01_ridgeline_circuit/track_01_ridgeline_circuit.tscn`'s
  `Shape_gate_ns` checkpoint shape was `(2, 3, 14)`; it needed to be
  `(14, 3, 2)`.** Six of the track's eight checkpoints override their gate's
  default `CollisionShape3D` with this shape to pair with a ±90° Y rotation
  (so the gate still faces across the track where travel runs along world X
  instead of world Z). The override swapped the two horizontal dimensions
  from what that rotation needs, producing a real gate only 2 m wide *across*
  the track (instead of the intended 14 m) and 2 m *along* it swapped to 14 m
  deep. `LapTracker`'s sequential-only rule means missing one checkpoint once
  permanently stalls that kart's lap count for the rest of the race — no
  self-correction on a later, cleaner pass. Phase 5's scripted follower drove
  dead-centerline and never drifted the ~1m needed to notice; real AI (lane
  offsets, avoidance, overtaking) reliably does. This is the reason a full
  8-kart AI race never finished before the fix despite every kart visibly
  still racing — found by connecting to `Checkpoint.body_passed` directly and
  logging the accepted/rejected index sequence for one kart, not by reasoning
  about the AI.
- `RaceManager` only transitioned `RACING -> FINISHING` on the human player's
  own finish. An all-AI race (`RaceConfig.player_slot == -1`, which the
  headless sim now uses so every kart is AI-driven) has no player finish to
  wait for, so it now also transitions on the first kart to finish whenever
  there is no player.
- `tests/sim/run_ai_race.gd` varies `RaceConfig.seed` by race number
  (`config.seed = race_number`) instead of leaving it at the default `0` for
  every `--races` repetition. Identical seeds produced byte-identical
  finish orders and times across "repeated" races, which defeats the point
  of sampling multiple races for the DoD's mean-lap-time comparison.
- `AIRaceContext` intentionally does not carry a live list of all karts in
  the race. `AISensors` finds nearby karts through its own `ShapeCast3D`
  physics queries (self-sufficient), and rubber banding only ever needs
  `player_kart` + `PositionTracker`. A field with no consumer is exactly the
  kind of speculative surface spec §29 rule 11 warns against.
