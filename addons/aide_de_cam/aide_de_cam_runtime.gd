extends Node

# Runtime helper shipped with the plugin.
# Connects AideDeCam's signals and forwards warnings into Godot's output.

const SINGLETON_NAME := "AideDeCam"
const RETRY_SECONDS := 6.0
const RETRY_INTERVAL := 0.25

var _aide: Object = null
var _connected := false
var _retries_left := int(RETRY_SECONDS / RETRY_INTERVAL)

func _ready() -> void:
	# On some devices/boot paths the Android singleton may appear a moment after startup.
	# We'll retry for a short period to make signal forwarding reliable.
	_schedule_retry()

func _schedule_retry() -> void:
	if _connected:
		return

	_try_connect()
	if _connected:
		return

	if _retries_left <= 0:
		# Give up quietly; nothing to connect to.
		return

	_retries_left -= 1
	var t := get_tree().create_timer(RETRY_INTERVAL)
	t.timeout.connect(_schedule_retry)

func _try_connect() -> void:
	if _connected:
		return
	if not Engine.has_singleton(SINGLETON_NAME):
		return

	_aide = Engine.get_singleton(SINGLETON_NAME)
	if _aide == null:
		return

	# Warnings (e.g. failed Documents write)
	if not _aide.is_connected("capabilities_warning", Callable(self, "_on_capabilities_warning")):
		_aide.connect("capabilities_warning", Callable(self, "_on_capabilities_warning"))

	# Success pulse when a fresh capabilities file has been written
	if not _aide.is_connected("capabilities_updated", Callable(self, "_on_capabilities_updated")):
		_aide.connect("capabilities_updated", Callable(self, "_on_capabilities_updated"))

	_connected = true

func _exit_tree() -> void:
	if _aide == null:
		return
	if _aide.is_connected("capabilities_warning", Callable(self, "_on_capabilities_warning")):
		_aide.disconnect("capabilities_warning", Callable(self, "_on_capabilities_warning"))
	if _aide.is_connected("capabilities_updated", Callable(self, "_on_capabilities_updated")):
		_aide.disconnect("capabilities_updated", Callable(self, "_on_capabilities_updated"))

func _on_capabilities_warning(msg: String) -> void:
	push_warning("[AideDeCam] " + msg)

func _on_capabilities_updated() -> void:
	# Keep this quiet by default; uncomment if useful for debugging.
	# print("[AideDeCam] capabilities_updated")
	pass
