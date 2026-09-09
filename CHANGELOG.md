# Changelog

## v0.3 — Phase 14 (unreleased; native acceptance pending)

- Add typed P1-P4 player slots, automatic AI remainder, and per-profile race bests.
- Add a device-owned local lobby with keyboard/P1 and joypad-index join/leave,
  independent driver/kart cursors, ready state, and automatic start.
- Render one shared World3D through independent one-to-four player cameras, HUDs,
  speed lines, configurable minimaps, scaled 3D viewports, and nearest-camera LOD.
- Let any joined player pause the shared race while the initiating device owns the
  pause menu; highlight every human in results and wait from the first human finish.
- Extend the performance probe with `--players N`, 60 fps two-player and 45 fps
  four-player targets. Headless composition measurements pass; native GPU and
  two-pad windowed acceptance remain pending in the main thread.

## v0.2 — Phase 13 (unreleased; native acceptance pending)

- Original six-kart chassis silhouettes, helmet/rim accessories, procedural track
  surfaces/skies/scenery, soft particles, fresnel shield and pickup/pad art.
- Driver/kart/item PNG icons, schematic track previews and a native preview renderer.
- Quality tiers now cap scale/MSAA/shadows/fog; cached distance LOD for kart details.
- Threaded scene loading with progress/failure state and post-load frame telemetry.
- Padded minimap projection with a minimum visible aspect ratio.
- Three export presets and an offline template preflight; explicit asset retention ledger.
- Match AI drift entry to the kart speed threshold so rejected low-speed hops
  preserve wall recovery steering; emergency braking releases drift for full
  steering recovery. Retain the existing collision budgets.
- Bury the hills ramp leading edge and invalidate older ghosts with format 3.
- Retain synthesized CC0 audio, Godot default font and disabled haptics explicitly
  in the asset ledger. Native visual/GPU/audio/gamepad and cross-platform runtime
  acceptance remain pending; missing export templates return exit 2 with an install hint.

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

Final external audio, haptics, online multiplayer, and native visual/GPU/listening
acceptance remain outside the automated headless evidence.
