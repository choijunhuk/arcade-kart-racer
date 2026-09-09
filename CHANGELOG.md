# Changelog

## v0.2 — Phase 13 (unreleased)

- Original six-kart chassis silhouettes, helmet/rim accessories, procedural track
  surfaces/skies/scenery, soft particles, fresnel shield and pickup/pad art.
- Driver/kart/item PNG icons, schematic track previews and a native preview renderer.
- Quality tiers now cap scale/MSAA/shadows/fog; cached distance LOD for kart details.
- Threaded scene loading with progress/failure state and post-load frame telemetry.
- Padded minimap projection with a minimum visible aspect ratio.
- Three export presets and an offline template preflight; explicit asset retention ledger.
- Native visual/GPU/audio/gamepad and cross-platform runtime acceptance remain pending.

## v0.1 — Vertical Slice (unreleased; no tag created)

- Complete Single Race flow: driver/kart/track/difficulty selection, eight racers,
  items, three laps, results, restart and return to menu.
- Recover malformed save/settings values and preserve keyboard bindings when
  stored remaps are corrupt. Pause local races on window focus loss.
- Correct scaled pickup/ranking timers, AI braking against its own earned boost,
  discarded drift countersteering and hairpin checkpoint crossing widths.
- Add real three-run scene-flow soak, lifecycle/resize/input recovery tests,
  same-seed item controls, strict 20-race balance and rotating mixed-class samples.
- Retain raw errors in the ten-race soak gate. Performance probe excludes the
  warmup-boundary frame and records monitors at the worst measured frame.
- Tune kart-class and item data; exact before/after measurements and remaining
  native-window verification limitations are recorded in DEVLOG.md.

Final art/audio assets, haptics, Time Trial, Grand Prix and multiplayer are outside
this release. Visual appearance, GPU performance and listening require native QA.
