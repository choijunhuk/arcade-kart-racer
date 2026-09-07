# Arcade Kart Racer Architecture

This document is the repository-specific architecture contract through Phase 2. It
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
7. Phase delivery is additive: Phase 2 owns advanced arcade physics while drift,
   race flow, items, and AI remain behind their later-phase seams.

## Runtime composition

`project.godot` starts `res://scenes/main.tscn` and registers six autoloads:

- `GameState` — `core/autoload/game_state.gd`: current mode and selected
  driver, kart, and track identifiers; scene-change request API.
- `EventBus` — `core/autoload/event_bus.gd`: global signal declarations only;
  it does not contain gameplay decisions.
- `SettingsManager` — `core/autoload/settings_manager.gd`: `ConfigFile`
  defaults, load/save, and immediate application of supported settings.
- `SaveManager` — `core/autoload/save_manager.gd`: versioned JSON save data,
  backup recovery, and atomic-enough primary/backup replacement.
- `AudioManager` — `core/autoload/audio_manager.gd`: Master/Music/SFX/Engine
  bus setup, linear volume accessors, and a reusable SFX-player pool.
- `DebugOverlay` — `core/autoload/debug_overlay.tscn` with
  `core/autoload/debug_overlay.gd`: F3 overlay, FPS/physics tick display,
  callable watches, and runtime sliders.

The scene graph remains small in Phase 2:

```text
scenes/main.tscn
└── Main (Node)
    └── KartSandbox (instanced scenes/test/kart_sandbox.tscn)  [kart_sandbox.gd]
        ├── TestLoop or TestLoopHills (switchable with T)
        ├── Kart (instanced kart/kart.tscn)          [kart_controller.gd]
        ├── RaceCamera (instanced camera/race_camera.tscn)
        ├── KartCollisionResolver                    [kart_collision_resolver.gd]
        └── RespawnSystem                            [respawn_system.gd]
```

The sandbox wires a `PlayerInputProvider`, camera, collision resolver, and
respawn system. `R` resets, `T` swaps the two test tracks, `1/2/3` selects the
weight class, and `B` creates three input-neutral collision targets. Debug
watches expose terrain, slipstream, hit, invulnerability, and air time.

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

Future race orchestration lives in `race/`. `RaceManager` will own only the
race state machine and composition. Phase 2 adds `KartCollisionResolver` and
`RespawnSystem` as separate nodes. The resolver handles BumpArea pairs without
HIT; respawn runs FADE -> teleport/protect -> FROZEN from physics ticks. A
caller-supplied transform callable keeps track lookup out of the kart domain.

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

### Items and AI

Item behavior will live in `items/`; AI behavior will live in `ai/`. Phase 0
creates their directory contracts and data schemas, not runtime behavior.
Future AI produces `InputFrame` objects and never changes kart physics state
directly.

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
The headless validator additionally checks the Phase 0 facts it can prove:
checkpoint count, grid count and proximity to the racing line, respawn marker
presence and ground contact, increasing checkpoint offsets, and racing-line
closure. Checks requiring item boxes or kill-zone coverage are reported as
Phase-later warnings rather than false failures.

## Testing and verification

- Unit tests: `tools/run_tests.sh` runs GUT over `tests/` recursively.
- Simulation: `tools/run_sim.sh` is a successful Phase 0 placeholder and states
  that simulation begins in Phase 6.
- Track contract: `tools/validate_tracks.sh` runs `track/track_validator.gd`
  headlessly against both `test_loop.tscn` and `test_loop_hills.tscn`.
- Parse/import: `/opt/homebrew/bin/godot --headless --path . --import` runs
  before the final parse check; generated `*.uid` files are committed.
- Phase 2 integration tests exercise mass contact, terrain cap/recovery, wall
  BUMP/recovery, ledge airborne/landing, and kill-zone respawn using real scenes.

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
