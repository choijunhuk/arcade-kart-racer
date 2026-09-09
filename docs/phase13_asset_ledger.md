# Phase 13 placeholder disposition

Every historical Phase 13/PLACEHOLDER category in DEVLOG is covered here.
Historical reports remain chronological; this table is the current disposition.

| Category | Final disposition / reason |
|---|---|
| Box karts / unadorned drivers | Replaced: six cached bevelled chassis silhouettes, class accessories, rims, helmet/visor and suit color. Kart collision shapes unchanged. |
| Greybox road appearance / joint wedges | Replaced with connected UV road visual mesh, procedural asphalt and painted edges/curbs. Track01 physical box chords retained after trimesh conversion caused AI regression; visual welding does not claim physical seam redesign. |
| Track theme / props | Original noise terrain, themed procedural skies/fog, batched low-poly scenery and guardrail posts. Simplified trees/pylons/rocks intentionally retained as the original low-poly style. |
| Item boxes / boost and jump pads | Replaced: translucent question cube, emissive chevrons, visual ramp. Collection/launch collision contracts retained. |
| Particles / boost / shield | Radial alpha particles, additive sparks/exhaust/impact, fresnel shield. Existing hit-flash and threat marker retained because they already implement required feedback. |
| Skid | Bounded strips fade when inactive; a new drift starts a new strip to avoid reconnecting across the track. |
| Portraits / kart and nine item icons | Replaced with deterministic original Image-generated PNGs. |
| Track previews | Four generated schematic fallback PNGs are tracked in the Phase 13 implementation commit. Native SubViewport renderer tool implemented; native capture blocked by macOS XPC. Rendered replacement remains a native acceptance gap. |
| Default font | Explicitly keep Godot default; no verified offline redistributable font; never copy system fonts. |
| 41 SFX / three BGM / new track and item aliases | Explicitly keep original CC0 synthesized audio. Existing audio pool, mix and looping behavior preserved; no official downloaded replacements. Final listening/mix remains unverified. |
| Driver voice sets | Keep identifiers as extension hooks; no recorded speech. Original synthesized feedback avoids unlicensed recordings. |
| Controller vibration | Explicitly retain disabled implementation/stub: no verified physical controller on this surface. Setting remains stored; does not claim hardware feedback. |
| Localization / UI final art | Existing text retained; new icon assets replace color swatches. Full translation is not claimed without a locale specification. |
| Test hills fixed bank | Fixed-roll bank retained as regression fixture. Ramp/ledge/trigger lowered together 0.2m to bury the front top edge; fixes 4,387 head-ons to 8 in the seeded race. Ghost format bumped to 3 for the geometry change. |
| Track01 continuous jump landing | Keep continuous safe landing and unchanged launch trigger; replace visible ramp only. Genuine chasm already exists on Glacier. |
| Optional cinematic / spectator camera | Keep current race camera/countdown/results; optional cinematic omitted to preserve scope and runtime budget. |
| Native driving / audio / gamepad / GPU | Blocked on this surface; explicit manual acceptance gaps, not completed gates. |

Zero unexplained placeholder categories. Explicit retention is not a claim that
recorded audio, native previews or hardware acceptance were completed.
