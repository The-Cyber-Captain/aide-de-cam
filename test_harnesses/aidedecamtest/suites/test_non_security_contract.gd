class_name TestNonSecurityContract
extends HarnessTest

func id() -> String: return "contract.non_security"
func group() -> String: return "contract"

func run(_runner: HarnessRunner) -> Dictionary:
	var assertions: Array = []
	var notes: Array[String] = []
	var artifacts: Dictionary = {}

	var is_android: bool = OS.get_name() == "Android"
	_assert(assertions, is_android, "platform: Android")
	if not is_android:
		return _finish("skip", assertions, notes, artifacts)

	var has_singleton: bool = Engine.has_singleton(SecurityPolicy.SINGLETON_NAME)
	_assert(assertions, has_singleton, "environment: singleton exists")
	if not has_singleton:
		return _finish("skip", assertions, notes, artifacts)

	var singleton: Object = Engine.get_singleton(SecurityPolicy.SINGLETON_NAME)
	_assert(assertions, singleton != null, "environment: singleton loads")
	if singleton == null:
		return _finish("skip", assertions, notes, artifacts)

	var base_raw: Variant = singleton.call("getCameraCapabilities")
	_assert(assertions, typeof(base_raw) == TYPE_STRING and String(base_raw).length() > 0, "api: getCameraCapabilities returns non-empty String")

	var file_raw_empty: Variant = singleton.call("getCameraCapabilitiesToFile", "")
	_assert(assertions, typeof(file_raw_empty) == TYPE_STRING and String(file_raw_empty).length() > 0, "api: getCameraCapabilitiesToFile('') returns non-empty String")

	var file_raw_custom: Variant = singleton.call("getCameraCapabilitiesToFile", "custom_subdir")
	_assert(assertions, typeof(file_raw_custom) == TYPE_STRING and String(file_raw_custom).length() > 0, "api: getCameraCapabilitiesToFile('custom_subdir') returns non-empty String")

	var payload_v: Variant = JSON.parse_string(String(base_raw))
	_assert(assertions, typeof(payload_v) == TYPE_DICTIONARY, "json: getCameraCapabilities payload parses to Dictionary")
	if typeof(payload_v) != TYPE_DICTIONARY:
		return _finish("fail", assertions, notes, artifacts)

	var payload: Dictionary = payload_v
	artifacts["base_payload_keys"] = payload.keys()

	var required: Array[String] = ["sdk_version", "device_model", "device_manufacturer", "cameras"]
	var has_required: bool = true
	var missing: Array[String] = []
	for f in required:
		if not payload.has(f):
			has_required = false
			missing.append(f)
	_assert(assertions, has_required, "json: required fields present")
	if missing.size() > 0:
		notes.append("missing required fields: %s" % str(missing))

	_assert(assertions, payload.has("timestamp") or payload.has("timestamp_ms"), "json: timestamp field present (timestamp or timestamp_ms)")

	var sdk : int = payload.get("sdk_version", -1)
	_assert(assertions, typeof(sdk) == TYPE_INT or typeof(sdk) == TYPE_FLOAT, "json: sdk_version is numeric")
	if typeof(sdk) == TYPE_INT or typeof(sdk) == TYPE_FLOAT:
		_assert(assertions, int(sdk) >= 21, "json: sdk_version >= 21")

	_assert(assertions, _non_empty_string(payload.get("device_model", "")), "json: device_model non-empty")
	_assert(assertions, _non_empty_string(payload.get("device_manufacturer", "")), "json: device_manufacturer non-empty")
	if payload.has("android_version"):
		_assert(assertions, _non_empty_string(payload.get("android_version", "")), "json: android_version non-empty when present")

	var cameras_v: Variant = payload.get("cameras", [])
	_assert(assertions, typeof(cameras_v) == TYPE_ARRAY, "camera: cameras is Array")
	if typeof(cameras_v) == TYPE_ARRAY:
		var cameras: Array = cameras_v
		_assert(assertions, cameras.size() > 0, "camera: cameras array non-empty")
		for c in cameras:
			if typeof(c) != TYPE_DICTIONARY:
				_assert(assertions, false, "camera: each camera entry is Dictionary")
				continue
			var cd: Dictionary = c
			_assert(assertions, cd.has("camera_id"), "camera: camera_id present")
			_assert(assertions, cd.has("facing"), "camera: facing present")
			_assert(assertions, cd.has("hardware_level"), "camera: hardware_level present")
			if cd.has("facing"):
				_assert(assertions, ["front", "back", "external", "unknown"].has(String(cd["facing"])), "camera: facing value valid")
			if cd.has("hardware_level"):
				_assert(assertions, ["legacy", "limited", "full", "level_3", "unknown"].has(String(cd["hardware_level"])), "camera: hardware_level value valid")

	_assert(assertions, payload.has("concurrent_camera_support"), "concurrency: concurrent_camera_support present")
	if payload.has("concurrent_camera_support"):
		var ccs: Variant = payload["concurrent_camera_support"]
		var type_ok: bool = typeof(ccs) == TYPE_STRING or typeof(ccs) == TYPE_DICTIONARY
		_assert(assertions, type_ok, "concurrency: concurrent_camera_support type is String or Dictionary")
		if typeof(ccs) == TYPE_DICTIONARY:
			var ccsd: Dictionary = ccs
			_assert(assertions, ccsd.has("supported"), "concurrency: dictionary has supported")
			if bool(ccsd.get("supported", false)):
				_assert(assertions, ccsd.has("max_concurrent_cameras"), "concurrency: supported => max_concurrent_cameras present")

	if payload.has("warnings"):
		_assert(assertions, typeof(payload["warnings"]) == TYPE_ARRAY, "warnings: root warnings is Array when present")
	if typeof(cameras_v) == TYPE_ARRAY:
		for c2 in cameras_v:
			if typeof(c2) != TYPE_DICTIONARY:
				continue
			var cd2: Dictionary = c2
			if cd2.has("warnings"):
				_assert(assertions, typeof(cd2["warnings"]) == TYPE_ARRAY, "warnings: per-camera warnings is Array when present")

	if payload.has("error"):
		_assert(assertions, typeof(payload["error"]) == TYPE_STRING, "error: error field is String when present")
		_assert(assertions, payload.has("sdk_version"), "error: sdk_version present when error present")
		_assert(assertions, payload.has("timestamp") or payload.has("timestamp_ms"), "error: timestamp present when error present")
	else:
		notes.append("error handling: no error payload observed in normal run")

	var user_path: String = "user://camera_capabilities.json"
	_assert(assertions, FileAccess.file_exists(user_path), "fileio: user://camera_capabilities.json exists")
	if FileAccess.file_exists(user_path):
		var user_text: String = FileAccess.get_file_as_string(user_path)
		var user_v: Variant = JSON.parse_string(user_text)
		_assert(assertions, typeof(user_v) == TYPE_DICTIONARY, "fileio: user://camera_capabilities.json parses")
		if typeof(user_v) == TYPE_DICTIONARY:
			var user_d: Dictionary = user_v
			_assert(assertions, user_d.get("sdk_version", -1) == payload.get("sdk_version", -2), "fileio: sdk_version matches return payload")
			_assert(assertions, String(user_d.get("device_model", "")) == String(payload.get("device_model", "")), "fileio: device_model matches return payload")
			var uc: Variant = user_d.get("cameras", [])
			if typeof(uc) == TYPE_ARRAY and typeof(cameras_v) == TYPE_ARRAY:
				_assert(assertions, uc.size() == cameras_v.size(), "fileio: camera count matches return payload")

	return _finish(_status_from_assertions(assertions), assertions, notes, artifacts)

func _non_empty_string(v: Variant) -> bool:
	return typeof(v) == TYPE_STRING and String(v).strip_edges() != ""

func _assert(assertions: Array, ok: bool, message: String) -> void:
	assertions.append({"ok": ok, "message": message})

func _status_from_assertions(assertions: Array) -> String:
	for a in assertions:
		if typeof(a) == TYPE_DICTIONARY and not bool(a.get("ok", false)):
			return "fail"
	return "pass"

func _finish(status: String, assertions: Array, notes: Array[String], artifacts: Dictionary) -> Dictionary:
	return {
		"status": status,
		"assertions": assertions,
		"notes": notes,
		"artifacts": artifacts,
	}
