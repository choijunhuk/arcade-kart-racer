# Turbo Circuit architecture — Phase 12

This is the current-code contract for the expanded four-track game. Historical decisions and
verification results live in `DEVLOG.md`; the product specification remains
`KART_RACING_DEV_PROMPT.md`. Phase 12 adds content, Grand Prix and deterministic single-player lap ghosts.

## Boundaries and invariants

- `core/` provides shared services; `data/` contains typed Resources. Runtime
  domains read these resources and duplicate them before applying driver modifiers.
- `KartController` consumes `InputFrame` through `InputProvider`. Player, AI and
  scripted test input use the same kart physics, item slot and boost/hit rules.
- `KartPhysics` owns scalar forward/lateral/vertical integration and
  `CharacterBody3D.move_and_slide()`. Motion changes from other domains use explicit
  kart APIs. Visual descendants may pitch/roll; the physical body only yaws.
- `RaceManager` composes systems and owns legal state transitions. Lap, position,
  countdown, results, collisions, respawn and items each retain their own owner.
- Physics and gameplay timers advance in `_physics_process(delta)`. Presentation
  uses `_process()`, signals and read-only state. Gameplay does not use await timers.
- Resources and named constants hold tuning. Project GDScript stays at most 400
  lines per file. GUT is vendored; there are no added runtime dependencies.

Allowed dependencies:

```text
All domains -> Core / Data
Kart -> Track terrain / Items slot API
Race -> Kart / Track / AI / Items, with explicit presentation binding
AI -> Kart / Track / Race context / Items read views
Items -> Kart / Race position and collision APIs
Camera -> Kart read APIs
UI -> Race / Kart / Items reads and public navigation/pause commands
Audio adapters / Effects -> EventBus and their bound owner
```

Core audio infrastructure (`audio_voice.gd`, `sfx_pool.gd`, `bgm_crossfade.gd`)
contains no gameplay imports. `RaceConfigBuilder` and `ResourceScanner` are outside
UI so race composition never depends on a menu implementation.

## Boot and persistent services

`project.godot` starts `scenes/main.tscn`, whose `MainMenu` resets transient session
selection and enters MENU mode. Six autoloads live under `core/autoload/`:

| Service | Ownership |
|---|---|
| GameState | Mode, selected ids, pending RaceConfig, validated scene requests |
| EventBus | Typed global signals, no gameplay decisions |
| SettingsManager | ConfigFile defaults, remaps, immediate settings application |
| SaveManager | Versioned JSON, backup recovery, best laps/positions, last selection |
| AudioManager | Audio buses, fixed voice pool, BGM and event-facing audio API |
| DebugOverlay | F3 watches/sliders and performance monitors; development only |

`GameState.change_scene()` validates the PackedScene, adds one root-level
`TransitionOverlay`, fades out, calls `SceneTree.change_scene_to_file()`, fades in,
and frees the overlay. Busy transitions return `ERR_BUSY`. Scenes are replaced by
the real SceneTree lifecycle; restart within a race is deliberately different.

Save and settings managers accept alternate paths for isolated tests. JSON primary
and backup files must have a supported integral version and correctly typed known
fields; corrupt primary data falls back to the valid backup, then defaults. Best
record values must be positive finite numbers. Settings loading validates values
against default types before numeric conversion/application. Invalid remap entries
cannot erase the existing action bindings. ConfigFile syntax errors produce an
engine diagnostic and a recovery warning, then load defaults.

Neither project nor tools introduce a network/TLS project setting. macOS sandbox
certificate and Dummy-renderer shutdown diagnostics are retained in verification
logs, not hidden by the soak gate.

## Menu and UI flow

```text
MainMenu -> ModeSelect -> DriverSelect -> KartSelect -> TrackSelect
  -> DifficultySelect -> RaceConfigBuilder -> pending_race_config -> race.tscn
  -> ResultsScreen -> restart / TrackSelect / MainMenu
Race PauseMenu -> embedded SettingsMenu -> PauseMenu
```

`ui/menus/menu_screen.gd` owns Back, deferred initial focus and explicit
focus-neighbor wiring. Menus share `ui/theme/default_theme.tres`. Keyboard/gamepad
and mouse activation converge on the same Button signals. `ResourceScanner`
recognizes `.tres`, `.res`, and exported `.tres.remap` paths, sorts them, and loads
resources. Driver/kart/track/difficulty menus filter by schema instead of maintaining
separate content registries.

`RaceConfigBuilder` resolves the selected Resources and applies five allowlisted
stats to deep KartData duplicates, clamped to ±5%. Eight drivers, six karts (two per weight class), four selectable tracks and three
difficulties are live. Kart cards wrap in a three-column scrolling grid. The
difficulty screen exposes items on/off; time trial forces one human and items off.
Grand Prix skips individual track selection and uses the ordered four-track cup.

`RaceHud` binds the player, lap/position trackers, item manager, racing line and
roster. It owns rank/lap, countdown, wrong-way/threat banners, roulette/cooldown,
drift meter and optional speedometer. The minimap caches baked X/Z line points,
projects with an aspect-preserving scale, and updates cached kart dots at 10 Hz.
Top/right/bottom anchors keep HUD regions visible under viewport changes. The
item panel starts below the top-right DebugOverlay.

`ResultsScreen` builds rank-sorted driver/kart/total/best-lap/new-record rows and
focuses Restart. Stable `RaceResults.Entry.kart_name` identifies the scene node;
`kart_display_name` and `driver_name` are presentation fields. `PauseMenu` runs
ALWAYS while gameplay is paused, embeds Settings without changing scenes, and
pauses local player races on the owning Window's `focus_exited` signal. Returning
focus does not resume automatically. All-AI observer/profiling races keep running.

## Race composition and state

```text
race/race.tscn [RaceManager, Node3D]
├── Track [dynamic TrackData.scene]
├── LapTracker / PositionTracker / Countdown / RaceResults
├── RespawnSystem / KartCollisionResolver / ItemManager
├── RaceAudio / FeedbackEffects / HitStop / ParticleBudgetController
├── Karts [PlayerKart + seven AI by default]
├── RaceCamera / SpeedLines / HUD
└── PauseMenu [embedded SettingsMenu] / ResultsScreen
```

The legal cycle is LOADING -> COUNTDOWN -> RACING -> FINISHING -> RESULTS.
COUNTDOWN/RACING can enter PAUSED and resume to the exact previous state. Only
COUNTDOWN -> RACING emits `race_started`. Restart explicitly rebuilds from LOADING,
clearing dynamic karts/track, tracker registrations, items, countdown, rows and
result state while preserving the manager/UI references.

`RaceConfig` contains track, laps, kart_count, player_slot, difficulty, player kart
and driver, items_enabled and seed. `player_slot = -1` is all AI; kart_count accepts
1–12. `race_mode` selects single race, GP or time trial. Optional `kart_roster` and
`driver_roster` supply stable per-grid-slot identities for a GP or mixed simulations;
empty retains the selected player's kart class for the whole field. Driver mods
are applied after choosing the slot's base kart. A player-provider factory remains
an explicit test seam. Start grids extend existing authored slots for the 12-kart
performance probe.

Countdown samples already-polled frozen-kart input through a deferred callback.
Start boost/wheelspin is judged on the throttle edge and applied at GO so frozen
countdown does not consume the reward. `RaceTuning` owns countdown cadence,
FINISHING timeout, results delay and ranking frequency.

`LapTracker` accepts checkpoints only in order and awards a lap at checkpoint zero
after all required gates. It owns cumulative race time, per-kart lap/checkpoint
state, wrong-way dwell and finished times. `RaceResults` derives individual lap
times from cumulative lap events, records item/hit counts, finalizes rank rows and
persists only the human player's bests.

`PositionTracker` computes lap progress within the valid checkpoint window and
uses active shortcut progress when applicable. It sorts at the configured 5 Hz
using elapsed game seconds, including scaled simulations; hysteresis is 0.5 m.
Finished karts rank by finish time. The player's finish starts FINISHING; with no
player, the first AI finish does. All finished or the 15-second timeout closes the
field, then the results delay runs. DNFs remain explicit negative result times.

`RespawnSystem` drives fade/teleport/frozen phases from delta timers. It receives a
callable resolving the last checkpoint's RespawnPoint, facing the racing line and
stepping back in 3 m increments to avoid occupied positions. KillZone signals and
stuck detection request this same recovery path. `KartCollisionResolver` applies
mass-dependent arcade impulses; kart bodies do not physically collide with each
other. `HazardRelay` bridges generic track hazards to accepted kart hits.

## Kart, drift and boost

`kart/kart.tscn` contains collision shape, BumpArea, TerrainProbe, five GroundRays,
KartPhysics, TerrainSensor, SlipstreamSensor, HitReactor, DriftController,
BoostController, ItemSlot, KartAudio, DriftEffects, BoostEffects and Visuals.
Body layer is kart_body (2), mask world (1); BumpArea uses layer/mask 3.

The controller polls input, samples terrain/ground, steps drift and boost, integrates
physics, advances hit state, then updates the public KartState. Race freeze still
polls input for Countdown. Finished state persists and uses a safe 50% follower or
the existing AI's finished-driving path.

Terrain precedence is overlapping OffroadZone > ground collider metadata > asphalt.
KartData.offroad_resistance blends terrain penalties toward neutral. Slipstream's
active boost is continuous; its exit reward uses BoostController.request(). Wall
incidence uses pre-slide velocity and latches continuous contact to avoid repeating
loss every frame. Hit reactions alter motion through explicit physics APIs; their
spin/tumble/squash transforms belong to Visuals. Item hits can consume a shield,
while kart bump impulses cannot. Accepted item BUMP applies the authored slowdown.

DriftController is configured independently and steps NONE -> HOP -> HOLD ->
RELEASE from input/speed/ground/air/hit state. Direction locks at hop completion;
mild opposite steering widens a turn, sustained hard opposition cancels. Charge
never decreases. Release chooses the highest reached MiniTurboTier. Speed retention
is frame-rate-correct `pow(retention, delta)`. Airborne drift-button edges arm tricks;
landing requests the configured reward.

BoostController owns one non-additive slot: stronger speed multiplier replaces it,
equal/weaker requests extend its duration up to the tuning cap. `get_result()` is a
read-only snapshot; `step(delta)` alone advances expiry. KartData.boost_power scales
multipliers toward neutral. Boost sources include drift, tricks, pads, start,
slipstream exit and Nitro. The same earned boost cap is available to player and AI.

## AI pipeline and simulation

An AIController Node3D child owns four ShapeCast sensors and composes:

```text
AISensors -> SensorReport
AINavigator -> target point / curvature / lane / shortcut
AIDriver + AIDriftPlanner -> throttle / brake / steer / drift / trick
AIItemBrain + ItemSlotView -> item edge
AIInputProvider -> KartController
```

AIController and AISensors are Node3D so their casts inherit kart transforms.
Controllers stagger their configured 30 Hz decisions, drain accumulated delta,
and stamp monotonically increasing InputFrame ticks so ItemSlot does not discard
new item-use requests. `AIRaceContext` supplies track/line, position tracker, nullable
player, item manager, countdown phase and respawn callable; no upward node lookup.

Navigator uses bounded baked-line lookup hints, profile look-ahead, seeded base lane
plus smoothed avoid/overtake bias, item-box seeking and shortcut decisions. Signed
curvature determines drift direction; unsigned maximum curvature determines safe
speed. AIDriver uses PD steering/noise, corner grip, delayed braking, drift skill,
start timing, EMA-based stuck/reverse/respawn handling and profile item decisions.
The drift planner preserves opposing steering corrections: KartPhysics locks the
direction, so countersteering can widen the radius without reversing the drift.
Profiles control judgment quality, not a faster physics implementation. Rubber
banding is limited to ±5% and cannot exceed the kart's currently earned boost cap;
all-AI races have no player gap. Boosts raise the straight target but do not bypass
the corner-grip limit. Debug watches expose target speed, lane and rubber banding.

`tests/sim/run_ai_race.gd` runs real AI races with seeded configurations and scaled
physics while retaining a 1/60-second gameplay step (480 Hz at 8× time scale).
The runner renders/presents at fixed 60 FPS; eight physics steps per frame preserve
the same seeded outcome as fixed 480 FPS. `RaceSimMetrics` owns pure aggregation and gate math. The runner preserves
per-race finish orders/times, DNFs with lap/checkpoint/position, respawns/head-ons,
drifts/shortcuts, item uses/hits, leader hits and lap-1-last rank gain. The first-to-
last spread is the whole-race gap from §13.8, separate from average per-lap time.

Twenty or more races default to strict item balance. The exact 8-kart/3-lap/items-on
sample automatically runs same-seed items-off controls; both arms must meet finish,
respawn (≤2/kart) and head-on (≤3/lap/kart) budgets. The gate requires measured
on-minus-off lap-1-last rank gain ≥0.4 and leader hits ≤3/race. Explicit
`--strict-balance off` is advisory and remains visible in the JSON. Mixed rosters
rotate light/medium/heavy across grid slots and seeds; samples of at least twelve
races require every class to win. No saved historical control substitutes for a
fresh measurement.

## Track and item ownership

Tracks under `track/tracks/` use TrackRoot and expose Geometry, Environment,
RacingLine, ordered Checkpoints with RespawnPoints, StartGrid and element containers.
All seven tracks are validated: test_loop, test_loop_hills, test_hairpin and
track_01_ridgeline_circuit, track_02_lumen_underpass, track_03_glacier_crown and
track_04_ochre_rift. RacingLine builds/bakes curve points once and provides
length/sample/tangent/right/curvature/offset APIs. Hinted offset queries search a
bounded neighborhood; unhinted queries can scan the baked line.

Ridgeline Circuit is the selectable ~1,499 m greybox: two long straights, chicane,
hairpin shortcut with dirt, moving obstacles, cliff edge, three boost pads, jump
pad, three item rows and eight checkpoint/grid slots. Track01 builds road/walls in
the track parent's ready callback after its sibling RacingLine exists. Checkpoint
shapes and rotations together span the road. The hairpin fixture gates likewise
use a 14 m crossing width, not a 2 m strip along the travel direction. Fall planes are thick enough to catch
fast falls in the scaled simulation. Fixed-roll test hills, primitive track art and
the continuous jump landing are explicitly Phase 13 art/geometry work.

ItemBox owns only hide/respawn and generic collection. Its respawn now uses elapsed
physics time. ItemManager owns one slot per kart, rank normalization/weighted picks,
roulette, cooldowns, scene-keyed ObjectPools, active projectiles and effect ticking.
ItemSlot deduplicates input by tick, then captures/consumes use edges; player and AI
share this path. The nine typed item scenes inherit projectile, homing, trap,
boost, shield, area or leader-strike bases. New items remain data/scene extensions,
not item-id branches in ItemManager.

Hunter follows the next racer ahead; traps arm before hitting; Nitro requests a
boost; shield absorbs one eligible hit. Pulse Blast telegraphs, slows, knocks back
and cancels drift only on accepted hits. Storm Beacon selects the leader, warns for
three seconds and respects shield/boost-pad/item-box immunity. Item lifecycle and
pool ownership remain race-local and are cleared on restart/exit.


## Grand Prix

`GrandPrix` is an autoload-free RefCounted owned by
`GameState.grand_prix_state`. Its seeded roster is selected once from the data
catalogue; `current_config()` carries the same kart/driver identities, difficulty
and seed into every scene. Grid slot is the identity used for scoring, independent
of a node's instance id after scene replacement. `RaceResults.Entry.grid_slot`
carries that stable identity into the results adapter.

`RaceModes` is the composition adapter. It submits each round exactly once, rejects
stale/duplicate/incomplete results, and advances only after scoring. Points are
15/12/10/8/6/4/2/1; DNFs earn zero. Ties use best finish, then finish-count countback,
then stable grid slot. Standings are defensive copies. Intermediate results show
both race rows and accumulated standings with Next Race. Final results show the
three-driver podium and final table. SaveManager keeps best cup rank/highest
points by `horizon_cup/<difficulty>` in the optional version-1
`grand_prix_bests` section; older saves acquire it through default merging.

## Time Trial and Ghost

Time trial uses the ordinary race lifecycle with one human, no AI and items off.
`TimeTrialGhost` wraps the chosen input source in `RecordingInputProvider`, storing
one raw InputFrame at its actual consumption boundary. Each valid best lap writes
`user://ghosts/<track_id>.json` through a temporary file/rename. Slower laps do not
replace the ghost; respawns invalidate only that lap. Unsupported/corrupt snapshots
are rejected before state restoration. The HUD shows elapsed/best time and delta
at equivalent forward progress. The final lap retains its completed elapsed time.

`GhostRecording` contains version/tick rate, initial state, input frames, external
track effects, lap ticks and scalar progress samples. Progress is used only for
timing comparison, never to move or correct the ghost. `KartReplayState` captures
exact basis vectors (not an Euler round trip), motion, drift, hit/wheelspin and
active boost state plus effective kart statistics. JSON number types are normalized
back to their explicit integer/boolean/float contract. BoostPad now enters through
`KartController.request_boost`, so pads, launches and accepted track hits can be
recorded at the same tick boundary; internal drift/trick boosts reproduce from input.

`GhostPlayback` feeds `GhostInputProvider` into a translucent real KartController.
Its root and BumpArea have collision layer/mask zero; it is never registered with
race ranks, pickups, collision resolution or AI. A layer-zero, world-mask-only
`KartWorldMotion` child reuses CharacterBody3D's slide solver against the road. It
cannot affect the player, pickups or hazards. Direct shape queries independently
measure ordered checkpoint crossings. Ground/terrain sensing remains active.
The kart scene is loaded on demand to avoid a PackedScene/script preload cycle.

Determinism is a **same-build, 60 Hz** contract, tested on test_loop for a standing
and flying lap with real pads and a scripted driver. Record/replay may differ by
one tick because Area3D and explicit query notifications have different boundaries;
the test also checks every sampled pose stays within 1 cm without pose correction.
Version 2 also records moving-obstacle transforms at each input boundary.
`GhostWorldReplay` creates collision-only copies on its private layer (bit 20),
excludes live movers from the ghost solver/rays, and applies recorded poses before
stepping input. Normal karts cannot collide with those copies. A regression checks
that moving the live gate leaves its replay copy at the recorded location. The
ghost remains input-driven; these are environment poses, not kart pose corrections.
Physics/content changes must bump/invalidate the ghost format before claiming
old ghosts compatible; cross-build deterministic replay is not claimed.

## Content authoring checklist

1. Add typed `.tres` resources with unique original ids, names and colors. Driver
   modifiers stay within ±5%; `voice_set` is an audio hook, not a voice asset.
2. A new track has all TrackRoot containers. `ContentTrack` creates the ordered
   checkpoints/grid/three item rows and full-depth kill plane before base validation.
   Theme scripts own dimensions, elevations, materials, hazards and shortcuts.
3. `RoadRibbon` joins shared banked edges into one mesh/trimesh, with real missing
   chords for chasms. Independent box end faces were unsuitable for banked/sloped
   road seams. Track01 keeps its original authoring path. Spawn/respawn transforms
   face horizontally; actual bank/slope normals cannot accumulate body roll while
   flat-road steering retains its established floating-point behavior.
4. Pads overlap the kart body above the surface. All fall footprints have a kill
   plane below geometry and at least 32 m deep (authored planes use 200 m). A
   shortcut cannot bypass ordered checkpoints; its next gate is after the rejoin.
   Elevated shortcuts include the launch approach in their AI route, without a
   drive-up ramp to the deck.
5. Lumen has emissive tunnel walls, two sliding gates and two fast alleys. Glacier
   has three full-width ice sheets, banked turns, a downhill/chasm launch and two
   path-following boulders. Ochre has broad sand shoulders, an enclosed basin,
   three chained boosts and a timed SQUASH storm that hits once per active phase.
6. Add simulator/sandbox entries and validator invocations. Validate all seven
   tracks, then run seeded full races at each difficulty and record actual timings.
7. New items use data plus an instance scene. TripleDart owns three RocketDart
   children, registers each live dart for AI/shields, reserves three budget slots,
   and removes registrations before pool return. PhantomDecoy inherits trap
   arming/owner immunity with a rotating pickup look. ItemManager remains unchanged.
8. Add audio-library ids (and generator aliases), previews and rank-table weights
   summing to 100. New item/track sounds currently reuse original placeholder WAVs.

New geometry APIs were checked against the official [SurfaceTool documentation](https://docs.godotengine.org/en/latest/classes/class_surfacetool.html),
[Mesh documentation](https://docs.godotengine.org/en/latest/classes/class_mesh.html), and
[Environment documentation](https://docs.godotengine.org/en/latest/classes/class_environment.html).

## Presentation and audio budgets

RaceCamera is a sibling Camera3D using velocity/drift blend, spring tracking,
ray-based clipping, 0.15-second look-back, speed-squared FOV and trauma-squared
shake. Settings scale shake/FOV to zero without disabling basic tracking. CameraFov
and CameraShake are independently testable value models.

KartVisuals owns body tilt, wheel spin/steer, suspension, hit flash and trick/hit
transforms. SkidStripBuffer is fixed-capacity; SkidMark emits an indexed world-space
strip while remaining parented for lifecycle. Five GPU emitters per kart yield 40
for eight karts, 60 for twelve. ParticleBudgetController caches effects, applies
quality and disables distant emitters beyond 80 m. FeedbackEffects pools 12 CPU
impact bursts. SpeedLines leaves the central 40% clear. HitStop restores prior time
scale after its tick budget and is disabled for headless/network event paths.

AudioManager's fixed budget is 16 3D + 8 2D players including engine/squeal and two
reserved BGM voices. Owner/voice-id checks prevent stolen leases being updated by
old owners. Priority and lifetime govern voice stealing; loops cannot steal equal-
priority loops. BGM uses a two-voice linear-gain crossfade; interrupted transitions
start from current gain. Menu -> countdown/race -> results requests are idempotent.
Music continues during pause with ducking; world/kart voices pause.

RaceAudio binds player/laps and EventBus; KartAudio reads its owner; UiAudio attaches
to menu/pause/results controls. SfxLibrary maps ids to streams/volume/pitch variance.
41 SFX and three BGM tracks are deterministic original CC0 PCM placeholders; final
asset replacement and listening/mix work are Phase 13. Engine low-pass uses the
local player's terrain and affects the shared Engine bus. Headless skips device
`.play()` only, preserving voice allocation, gain, pitch and lifetime logic.

## Verification and release evidence

- `tools/run_tests.sh`: recursive GUT unit/integration suite. The vertical-slice
  test keeps GUT separate from `current_scene`, drives real ui_* transitions,
  races three laps with a scripted player plus seven AI, restarts, and returns to
  menu three times. GUT captures push/engine errors; settled node/orphan/memory
  monitors compare warmed runs. Save paths are isolated and restored.
- `tools/run_sim.sh`: streams race progress, complete JSON payload and SIM_SUMMARY.
  Options include races/laps/karts/difficulty/track/items, seed, mixed-karts and
  strict-balance. There is no hand-parsed/truncated nested JSON summary.
- `tools/run_soak.sh`: fixed ten-race normal/8-kart/3-lap/items-on run. Captures both
  streams and fails on any error line, missing success JSON or nonzero simulator
  exit. `SOAK_LOG` selects the retained log path.
- `tools/validate_tracks.sh`: structure, ordered offsets, line closure, start and
  respawn proximity/ground, item-box proximity/count, and kill-zone footprint.
- `scenes/test/drive_snapshot.tscn`: seven sandbox track indices; scene_snapshot
  captures an arbitrary scene. Windowed commands must run in the background with
  redirected logs when called from the restricted agent environment.
- `tools/perf_check.sh 8 30` / `12 30`: real frame intervals after warmup, FPS,
  worst frame, particle count and renderer. The warmup-boundary frame is excluded;
  frames above 33 ms and process/physics/node/draw-call monitors at the worst
  frame are retained for spike diagnosis. Headless cannot establish GPU timing,
  native focus/fullscreen delivery, PNG appearance or subjective driving/audio feel.

Current exact gate outcomes and blocked native checks are recorded in DEVLOG's
Phase 12 report. No push, tag, Phase 13 implementation or independent delegated
review is part of this delivery.
