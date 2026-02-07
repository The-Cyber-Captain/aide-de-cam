@tool
extends EditorPlugin

var export_plugin: AndroidExportPlugin

func _enter_tree() -> void:
	export_plugin = AndroidExportPlugin.new()
	add_export_plugin(export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	export_plugin = null

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

