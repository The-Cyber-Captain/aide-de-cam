# AideDeCam Test Harness (Production-Ready Skeleton)

This folder is meant to be copied into your Godot project (or merged into it).

## What it tests
- Runs a security/abuse vector suite against:
  1. The recommended GDScript autoload wrapper at `/root/AideDeCam` (methods per aidedecam.xml)
  2. The direct Android plugin singleton via `Engine.get_singleton("AideDeCam")` (Kotlin `@UsedByGodot` methods)

- Validates returned JSON + `user://camera_capabilities.json` against:
  `tests/schema/aidedecam-camera-capabilities-v1.schema.json`

- Emits a machine-readable report at:
  `user://aidedecam_harness_report.json`

## Install
0. Install the plugin (copy `aide_de_cam` into `addons` and enable)
#1. Copy the `tests/` folder into your project root (or wherever you prefer).
#2. Ensure your wrapper autoload node name is `AideDeCam` (as discussed).
#3. Ensure the Android plugin singleton is available as `AideDeCam`.

## Run
- Create a minimal scene with a Node and attach: `tests/run_harness.gd`
- Run on Android device (or Android Editor run).
- Check console and `user://aidedecam_harness_report.json`.

## Notes
- The schema validator supports exactly the keywords used by the v1 schema and **fails loudly** on new/unknown keywords
  to prevent false-positive "OK" results as the schema evolves.
- `SecurityPolicy.REQUIRE_WARNING_ON_FALLBACK` assumes fallback emits `capabilities_warning`. If your current build's fallback
  warning is emitted only by the wrapper/autoload (not by Kotlin), you can set this to `false` for singleton runs or adjust the suite.

## Schema hash
- Embedded schema SHA256: `cd97fb1293c847210a07d601714b51fe70c43b9b34687218359adc8b04fd18af`
