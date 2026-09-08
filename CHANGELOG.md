# Changelog

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
