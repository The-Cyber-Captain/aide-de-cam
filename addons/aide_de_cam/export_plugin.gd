@tool
extends EditorPlugin

const PLUGIN_NAME := "AideDeCam"

var android_plugin: AndroidExportPlugin

func _enter_tree() -> void:
	android_plugin = AndroidExportPlugin.new()
	add_export_plugin(android_plugin)

func _exit_tree() -> void:
	remove_export_plugin(android_plugin)
	android_plugin = null

class AndroidExportPlugin extends EditorExportPlugin:
	func _get_name() -> String:
		return PLUGIN_NAME
		
	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid
		
	func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		return PackedStringArray([
			"res://addons/aide_de_cam/android/Aide-De-Cam-release.aar"
		])
