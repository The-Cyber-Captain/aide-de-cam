@tool
extends EditorPlugin

const AUTOLOAD_NAME = "AideDeCam"
const AUTOLOAD_PATH = "res://addons/aide_de_cam/aidedecam.gd"

var export_plugin

func _enter_tree() -> void:
	# Register the Android plugin
	export_plugin = preload("res://addons/aide_de_cam/export_plugin.gd").new()
	add_child(export_plugin)
	
	# Add autoload for autocomplete/docs
	if not has_autoload(AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)

func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
	
	if export_plugin:
		remove_child(export_plugin)
		export_plugin.queue_free()

func has_autoload(name: String) -> bool:
	return ProjectSettings.has_setting("autoload/" + name)
