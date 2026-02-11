extends Node

## Camera capabilities scanner for Android devices.
##
## Provides detailed information about device cameras including supported
## formats, resolutions, hardware levels, and concurrent camera capabilities.

## Emitted when camera capabilities have been successfully gathered and saved.
signal capabilities_updated

## Emitted when the plugin singleton becomes available.
signal plugin_ready

var _plugin: Object = null
var _is_ready: bool = false

func _ready() -> void:
	_try_connect_plugin()
	
	# If plugin not available yet, retry
	if not _plugin:
		_retry_connection()

func _try_connect_plugin() -> void:
	if Engine.has_singleton("AideDeCam"):
		_plugin = Engine.get_singleton("AideDeCam")
		if _plugin:
			_plugin.capabilities_updated.connect(_on_capabilities_updated)
			_plugin.capabilities_warning.connect(_on_capabilities_warning)
			_is_ready = true
			plugin_ready.emit()

func _retry_connection() -> void:
	# Retry a few times with delays
	for i in range(10):
		await get_tree().create_timer(0.1).timeout
		_try_connect_plugin()
		if _plugin:
			return

## Returns true if the Android plugin is available.
func is_plugin_available() -> bool:
	return _plugin != null

## Returns camera capabilities as a JSON string, and writes a copy to:[br]
## - `user://camera_capabilities.json` [br]
##
## Notes: [br]
## - Does not write to the Documents folder.
func get_camera_capabilities() -> String:
	if _plugin:
		return _plugin.getCameraCapabilities()
	push_warning("[AideDeCam] Plugin not yet available")
	return '{"error": "Plugin not available"}'

## Returns camera capabilities as a JSON string, and writes copies to:[br]
## - `user://camera_capabilities.json` [br]
## - `Documents/<app-name>/<documents_subdir>/camera_capabilities_<timestamp>.json` [br]
##
## Parameters:[br]
## - `documents_subdir`: Subdirectory under Documents.[br]
##   Use ".", "/", or "" to write to the app root folder.
##
## Notes:[br]
## - Excessively long or malformed paths fall back to [method get_camera_capabilities].
func get_camera_capabilities_to_file(documents_subdir: String) -> String:
	if _plugin:
		return _plugin.getCameraCapabilitiesToFile(documents_subdir)
	push_warning("[AideDeCam] Plugin not yet available")
	return '{"error": "Plugin not available"}'

func _on_capabilities_updated() -> void:
	capabilities_updated.emit()

func _on_capabilities_warning(message: String) -> void:
	#capabilities_warning.emit(message)
	push_warning("[AideDeCam] " + message)
