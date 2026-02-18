# AideDeCam Test Harness (Production-Ready Skeleton)

This is a working tool you can modify as required; presented as a Godot project.

## What it tests
- Non-security contract
- Signals and fallback
- Runs a security/abuse vector suite against:
  1. The recommended GDScript autoload wrapper at `/root/AideDeCam` (methods per aidedecam.xml)
  2. The direct Android plugin singleton via `Engine.get_singleton("AideDeCam")` (Kotlin `@UsedByGodot` methods)

- Validates returned JSON + `user://camera_capabilities.json` against:
  `addons/aide_de_cam/doc_classes/aidedecam-camera-capabilities-v1.schema.json`

- Emits a machine-readable report at:
  `user://aidedecam_harness_report.json`

## Install
1. Install the plugin (copy `aide_de_cam` into `addons` and enable)
2. Create an Android export config;  
	* Set adaptive foreground icon (branding/android_adaptive_icon.png) for maximum pretty.  

## Run
- Open project.godot (AideDeCamTest)
- Export & Run / one-touch-deploy on a suitable Android device.
- Check console and `user://aidedecam_harness_report.json`.
(Useful: adb shell run-as com.sixdegreesofcrispybacon.aidedecamdemo <ls files/aidedecam_harness_report.json>)

## Notes
- The schema validator supports exactly the keywords used by the v1 schema and **fails loudly** on new/unknown keywords
  to prevent false-positive "OK" results as the schema evolves.
- `SecurityPolicy.REQUIRE_WARNING_ON_FALLBACK` assumes fallback emits `capabilities_warning`. If your current build's fallback
  warning is emitted only by the wrapper/autoload (not by Kotlin), you can set this to `false` for singleton runs or adjust the suite.

## Schema hash
- Embedded schema SHA256: `9168c92a9a4adcb5fc528d9d16600cb7571cdc1b8e270befae181f4a516bb6cb`
