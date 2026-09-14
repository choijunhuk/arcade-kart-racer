# Release artifacts

`tools/build.sh` produces three unsigned desktop builds:

| Platform | Artifact | Notes |
|---|---|---|
| Windows | `build/windows/TurboCircuit.exe` (+ `TurboCircuit.pck` alongside it) | Never executed on real hardware. |
| macOS | `build/macos/TurboCircuit.zip` (unzips to `Turbo Circuit.app`) | Gatekeeper-blocked; unsigned. Smoke-tested via `--selftest` on this dev machine only (see below) — never run as a normal windowed app on another Mac. |
| Linux | `build/linux/TurboCircuit-linux.tar.gz` (also `TurboCircuit.x86_64` + `TurboCircuit.pck` loose in the same directory) | Never executed on real hardware. |

None of these have been run as an actual windowed game on the target OS. The macOS
build has only been smoke-tested headless (`--selftest`, see
`scenes/export_selftest.gd`) on the machine that built it — it verifies data
scanning and track instancing after export, not rendering, input, or audio.
**Windows and Linux builds have never been executed at all.** Treat all three as
needing a manual smoke run on real hardware before anyone relies on them.

## Opening the macOS build

The app is unsigned (`export_presets.cfg` has `codesign/codesign=0` — no Apple
Developer certificate is available in this environment), so macOS Gatekeeper
refuses to open it with a plain double-click ("app is damaged" / "cannot be
opened because the developer cannot be verified"). To run it anyway:

1. Unzip `TurboCircuit.zip` to get `Turbo Circuit.app`.
2. **Right-click (or Control-click) the app → Open → Open** in the dialog that
   appears. This one-time override is remembered per-app.
   - If that still refuses, clear the quarantine flag from Terminal instead:
     ```sh
     xattr -dr com.apple.quarantine "Turbo Circuit.app"
     ```
3. Launch normally after that.

## Using the Linux build

```sh
tar xzf TurboCircuit-linux.tar.gz
./TurboCircuit.x86_64
```

The tarball preserves the executable bit on `TurboCircuit.x86_64` (some
zip/upload transports don't); `tools/build.sh` also `chmod +x`s the loose
binary as a second safety net. `TurboCircuit.pck` must stay in the same
directory as the binary — it is the packed game data.

## Using the Windows build

Copy `TurboCircuit.exe` and `TurboCircuit.pck` from `build/windows/` to the
target machine (same directory) and run the `.exe`. It is unsigned, so
Windows SmartScreen may warn on first run ("Windows protected your PC") —
choose **More info → Run anyway**. This build has not been run on Windows in
this environment; treat the first real run there as the actual verification.

## macOS `--selftest` (what `tools/build.sh` automates)

`tools/build.sh` unzips the macOS export to `build/macos/extracted/`, then
runs the bundled binary headless with `--selftest`:

```sh
"Turbo Circuit.app/Contents/MacOS/Turbo Circuit" --headless -- --selftest
```

This exercises the paths that only break after export (`.tres.remap` data
scanning, track scene instancing — see `scenes/export_selftest.gd`) and
prints a single `EXPORT_SELFTEST {...}` JSON line ending in `"passed":true`.
The build script fails if that line is missing or reports failure. This is a
headless data/instancing check, not a graphics, input, or audio smoke test.
