# Arcade Kart Racer Architecture

This document is the repository-specific architecture contract for Phase 0. It
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
7. Phase 0 establishes contracts and executable greyboxes only. Kart physics,
   drift, race flow, items, and AI behavior remain outside this phase.

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

The Phase 0 scene graph is intentionally small:

```text
scenes/main.tscn
└── Main (Node)
    └── KartSandbox (instanced scenes/test/kart_sandbox.tscn)
        ├── TestLoop (instanced track/tracks/test_loop/test_loop.tscn)
        ├── PlaceholderKart (CharacterBody3D)
        └── Camera3D
```

The sandbox provides a visual smoke test only. The placeholder kart has a mesh
and collision shape but no movement code.

## Domain ownership and dependency direction

### Core and data

All runtime domains may depend on `core/` and read `data/` resources.
`core/` must not depend on a gameplay domain. `data/schemas/` contains no
scene-tree queries or gameplay orchestration.

### Kart

Future kart code lives in `kart/`. It may read terrain information from
`track/` and request item use through an explicit `items/` API. It must not
reference `race/`, `ai/`, or `ui/` directly. Phase 0 provides only
`kart/kart_state.gd`, whose enum is the stable state vocabulary.

### Race

Future race orchestration lives in `race/`. `RaceManager` will own only the
race state machine and composition. Lap tracking, position tracking, respawn,
collision resolution, countdown, and results remain separate nodes/scripts.
Phase 0 provides only `race/race_state.gd`.

### Track

Track scenes live below `track/tracks/`; reusable elements live below
`track/elements/`. `track/track.gd` exposes and validates required child nodes
without referencing karts. `track/track_validator.gd` is a headless command
entrypoint used by `tools/validate_tracks.sh`.

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
│   ├── math/
│   ├── scene_loader.gd
│   └── object_pool.gd
├── kart/
├── race/
├── track/
│   ├── track.gd
│   ├── track_validator.gd
│   ├── track_template.tscn
│   ├── elements/
│   └── tracks/test_loop/test_loop.tscn
├── items/
│   ├── base/
│   └── instances/{rocket_dart,hunter_drone,spike_mine,nitro_can,
│                  aegis_bubble,pulse_blast,storm_beacon}/
├── ai/
├── camera/
├── ui/{theme,hud,menus,results,components}/
├── audio/placeholder/
├── effects/
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
presence, and racing-line closure. Checks requiring item boxes, kill-zone
coverage, raycast ground proof, or production racing-line offset metadata are
reported as Phase-later warnings rather than false failures.

## Testing and verification

- Unit tests: `tools/run_tests.sh` runs GUT over `tests/` recursively.
- Simulation: `tools/run_sim.sh` is a successful Phase 0 placeholder and states
  that simulation begins in Phase 6.
- Track contract: `tools/validate_tracks.sh` runs
  `track/track_validator.gd` headlessly against `test_loop.tscn`.
- Parse/import: `/opt/homebrew/bin/godot --headless --path . --import` runs
  before the final parse check; generated `*.uid` files are committed.

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
- The Phase 0 validator treats Phase 4-only requirements as explicit warnings,
  preventing scaffolding from pretending to provide item/kill-zone guarantees.
- Existing vendored GUT 9.6.1 is used unchanged and enabled through
  `project.godot`; no dependency download step is introduced.
