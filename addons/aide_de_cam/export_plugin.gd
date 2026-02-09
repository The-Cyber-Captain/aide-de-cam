@tool
extends EditorPlugin

var export_plugin: AndroidExportPlugin

# Runtime bridge: automatically connects AideDeCam signals and forwards warnings
# into Godot output (including the Editor Output panel when running from the editor).
const RUNTIME_AUTOLOAD_NAME := "AideDeCamRuntime"
const RUNTIME_AUTOLOAD_PATH := "res://addons/aide_de_cam/aide_de_cam_runtime.gd"

func _enter_tree() -> void:
	# Ensure our runtime autoload exists so end-users don't need to write any GDScript.
	# (This is a project setting change while the plugin is enabled in the editor.)
	if not ProjectSettings.has_setting("autoload/" + RUNTIME_AUTOLOAD_NAME):
		add_autoload_singleton(RUNTIME_AUTOLOAD_NAME, RUNTIME_AUTOLOAD_PATH)
		ProjectSettings.save()

	export_plugin = AndroidExportPlugin.new()
	add_export_plugin(export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	export_plugin = null

	# Remove the autoload we added on enable.
	if ProjectSettings.has_setting("autoload/" + RUNTIME_AUTOLOAD_NAME):
		remove_autoload_singleton(RUNTIME_AUTOLOAD_NAME)
		ProjectSettings.save()

class AndroidExportPlugin extends EditorExportPlugin:
	const PLUGIN_NAME := "AideDeCam"

	func _get_name() -> String:
		return PLUGIN_NAME

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	# IMPORTANT: paths are relative to 'addons/' (per Godot docs)
	func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		return PackedStringArray([
			"res://addons/aide_de_cam/android/Aide-De-Cam-release.aar"
		])

