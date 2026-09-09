
## Merge gate
`tools/gate.sh` is the automatic merge gate (runs parse, tests, track validation, sim smoke, 400-line rule, project.godot hygiene, sensitive-path check). The global merge-gate hook runs it before any `gh pr merge`. SENSITIVE_PATHS: `net/`, `kart/kart_physics.gd`, `race/lap_tracker.gd`, `race/position_tracker.gd`, `core/autoload/save_manager.gd` — changes there need explicit approval (`GATE_ALLOW_SENSITIVE=1` only after the user approves).
