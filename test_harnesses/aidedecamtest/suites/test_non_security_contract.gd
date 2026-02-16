class_name TestNonSecurityContract
extends HarnessTest

func id() -> String: return "contract.non_security"
func group() -> String: return "contract"

func run(_runner: HarnessRunner) -> Dictionary:
	var assertions: Array = []
	var notes: Array[String] = []
	var artifacts: Dictionary = {
		"schema_path": SecurityPolicy.SCHEMA_PATH,
		"schema_sha256_expected": SecurityPolicy.SCHEMA_SHA256,
	}

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

	var schema_text: String = ""
	if FileAccess.file_exists(SecurityPolicy.SCHEMA_PATH):
		schema_text = FileAccess.get_file_as_string(SecurityPolicy.SCHEMA_PATH)
	else:
		notes.append("schema: missing file at %s" % SecurityPolicy.SCHEMA_PATH)

	if schema_text == "":
		_assert(assertions, false, "schema: load from SecurityPolicy.SCHEMA_PATH")
		return _finish("fail", assertions, notes, artifacts)

	var resolver := JsonSchemaResolver.new()
	resolver.load_schema_from_text(schema_text)
	var root_schema: Dictionary = resolver.schema_root
	var validator := JsonSchemaValidator.new(resolver)

	var base_raw: Variant = singleton.call("getCameraCapabilities")
	_assert(assertions, typeof(base_raw) == TYPE_STRING and String(base_raw).length() > 0, "api: getCameraCapabilities returns non-empty String")
	var payload: Dictionary = _parse_dict(String(base_raw), "getCameraCapabilities", assertions)
	if payload.is_empty():
		return _finish("fail", assertions, notes, artifacts)
	artifacts["base_payload_keys"] = payload.keys()
	_validate_schema_dict("json:getCameraCapabilities", payload, validator, root_schema, assertions, notes)

	var file_raw_empty: Variant = singleton.call("getCameraCapabilitiesToFile", "")
	_assert(assertions, typeof(file_raw_empty) == TYPE_STRING and String(file_raw_empty).length() > 0, "api: getCameraCapabilitiesToFile('') returns non-empty String")
	var payload_empty: Dictionary = _parse_dict(String(file_raw_empty), "getCameraCapabilitiesToFile('')", assertions)
	if not payload_empty.is_empty():
		_validate_schema_dict("json:getCameraCapabilitiesToFile('')", payload_empty, validator, root_schema, assertions, notes)

	var file_raw_custom: Variant = singleton.call("getCameraCapabilitiesToFile", "custom_subdir")
	_assert(assertions, typeof(file_raw_custom) == TYPE_STRING and String(file_raw_custom).length() > 0, "api: getCameraCapabilitiesToFile('custom_subdir') returns non-empty String")
	var payload_custom: Dictionary = _parse_dict(String(file_raw_custom), "getCameraCapabilitiesToFile('custom_subdir')", assertions)
	if not payload_custom.is_empty():
		_validate_schema_dict("json:getCameraCapabilitiesToFile('custom_subdir')", payload_custom, validator, root_schema, assertions, notes)

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
			_validate_schema_dict("json:user://camera_capabilities.json", user_d, validator, root_schema, assertions, notes)
			_assert(assertions, user_d.get("sdk_version", -1) == payload.get("sdk_version", -2), "fileio: sdk_version matches return payload")
			_assert(assertions, String(user_d.get("device_model", "")) == String(payload.get("device_model", "")), "fileio: device_model matches return payload")
			var uc: Variant = user_d.get("cameras", [])
			if typeof(uc) == TYPE_ARRAY and typeof(cameras_v) == TYPE_ARRAY:
				var uc_arr: Array = uc
				var cameras_arr: Array = cameras_v
				_assert(assertions, uc_arr.size() == cameras_arr.size(), "fileio: camera count matches return payload")

	return _finish(_status_from_assertions(assertions), assertions, notes, artifacts)

func _parse_dict(json_text: String, label: String, assertions: Array) -> Dictionary:
	var v: Variant = JSON.parse_string(json_text)
	var ok: bool = typeof(v) == TYPE_DICTIONARY
	_assert(assertions, ok, "json: %s parses to Dictionary" % label)
	if not ok:
		return {}
	return v

func _validate_schema_dict(label: String, payload: Dictionary, validator: JsonSchemaValidator, root_schema: Dictionary, assertions: Array, notes: Array[String]) -> void:
	var result: Dictionary = validator.validate(payload, root_schema)
	var valid: bool = bool(result.get("valid", false))
	_assert(assertions, valid, "%s: schema valid" % label)
	if not valid:
		var errs: Array = result.get("errors", [])
		notes.append("%s: schema invalid (%d errors)" % [label, errs.size()])
		var lim: int = int(min(5, errs.size()))
		for i in range(lim):
			notes.append("%s: %s" % [label, JSON.stringify(errs[i])])

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
