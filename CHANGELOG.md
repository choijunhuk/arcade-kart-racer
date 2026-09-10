# Changelog

## v0.5 — Phase 16 (internet play, free infrastructure only)

- Add best-effort UPnP auto port-forward (threaded, 3s timeout) and a 10-character Crockford base32 host join code with checksum.
- Add a dedicated, kart-less headless server (`--server`) with tick-based auto-start (all-ready or 20s grace) and an automatic restart-to-lobby after RESULTS that keeps connected peers.
- Add an optional pure-UDP relay (`--relay`) plus a local loopback proxy for double-NAT hosts/clients, paired by room code; documented to run on any free VPS or always-on PC.
- Add HUD ping/loss and a "Reconnecting…" overlay on a >2s snapshot gap, and lobby UPnP status/host-code/copy/relay/password controls.
- Add a join handshake (protocol version + hashed session password) that rejects mismatched peers by message without logging the password, and a server-side input rate limiter.
- Add `tools/run_server.sh`, `tools/run_relay.sh`, `tools/run_server_test.sh` (dedicated server + 2 automated clients complete a race and the server loops back to lobby).

## v0.4 — Phase 15 (unreleased; ENet/LAN acceptance and independent reviews pending)

- Add an ENet LAN lobby, server-owned player selection/ready/start and load barrier.
- Add two-tick input buffering, 20Hz binary snapshots, local prediction/replay, 100ms remote interpolation, and bounded correction/extrapolation.
- Mirror authoritative race reads/results/events, pickup availability and active item visuals; keep client physics limited to its own kart.
- Reuse existing kart replay state, physics, player panels, HUD and audio bindings.
- Add headless loopback tooling with seeded one-way latency/loss and pre-correction same-input-tick error metrics.
- Actual ENet test execution is blocked by sandbox UDP bind permissions; no LAN or latency acceptance is claimed.

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
