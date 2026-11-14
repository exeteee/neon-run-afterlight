# NEON RUN: AFTERLIGHT

An original Android-first, offline 3D endless runner built with **Godot 4.7.2** and GDScript.

## Current feature set

- Three-lane runner controls: swipe left/right to change lanes, swipe up to jump, swipe down to slide.
- Procedurally recycled track segments and obstacle patterns.
- Obstacles with distinct responses: crates/spikes require jumping, overhead beams require sliding, trains require lane changes, and pulse gates require a charged energy dash.
- Coins, energy cells, temporary power-ups, score, distance and speed ramping.
- Three selectable difficulty presets.
- Three visual city districts that rotate as the run progresses.
- Permanent upgrades, milestones, high score and local JSON save.
- Russian-language menus, HUD, pause, results, settings and first-run tutorial.
- Original menu key art, app icon, ambient synth loop and generated sound effects.
- No network requests, accounts, ads or server dependency.

## Requirements

- Godot **4.7.2 stable** (standard/GDScript build, not .NET).
- For Android export: OpenJDK 17, Android SDK (platforms 35 and 36, build-tools 35.0.1 and 36.0.0, platform-tools, NDK r28b and CMake 3.10.2.4988404), and the matching Godot 4.7.2 export templates.
- The project uses Godot's Compatibility renderer for a broad Android GPU baseline.

## Open in Godot

1. Extract the project folder.
2. Open `project.godot` in Godot 4.7.2.
3. Press **F6/F5** to run. Desktop keyboard controls are included for development; the intended device controls are touch swipes.

## Playable browser preview

`preview/index.html` is a self-contained playable companion preview with swipe/keyboard controls. Open it in a modern browser; it does not replace the Android 3D project. It stores preview progress in browser local storage.

## Android APK export

1. Install the Android build dependencies in Editor Settings → Export → Android.
2. Install the matching 4.7.2 export templates.
3. Open Project → Export, select the `Android` preset, then Export Project to `build/NEON_RUN_AFTERLIGHT.apk`.
4. For local unattended export, see `scripts/build_android.sh`.

The APK is a debug/sideload build configuration. For Play Store publication, create a private release keystore and configure a signed release export; do not commit that keystore to source control.

## Save data

The game stores progress in `user://afterlight_profile.json` on the device. No internet access is needed.

## Project structure

- `scenes/main.tscn` — entry scene.
- `scripts/main.gd` — game controller, 3D world generation, gameplay, UI, audio and persistence.
- `assets/` — title art and launcher icon.
- `audio/` — original synthesized WAV loop and effects.
- `tests/` — local project integrity checks.
- `.github/workflows/` — Android build workflow template for a repository where GitHub Actions are enabled.

## License and assets

Game code and visual/audio assets in this project are original project materials. The title illustration and icon are generated for this game. No third-party game characters, music or proprietary assets are included.
