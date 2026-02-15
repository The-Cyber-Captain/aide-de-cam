class_name TestSecurityVectors
extends HarnessTest

# Authoritative allowlist for singleton exposure.
const _ALLOWED_SINGLETON_METHODS := [
	"getCameraCapabilities",
	"getCameraCapabilitiesToFile",
	"getCameraCapabilitiesWithMeta",
	"getCameraCapabilitiesToFileWithMeta",
	"getExposedMethods",
]

# Prefer short waits; plugin calls are synchronous. We only wait to catch deferred signal emission.
const _SOFT_SIGNAL_WAIT_SEC := 0.35

func id() -> String:
	return "security.vectors"

func group() -> String:
	return "security"

func run(runner: HarnessRunner) -> Dictionary:
	var assertions: Array = []
	var notes: Array[String] = []
	var artifacts := {
		"schema_path": SecurityPolicy.SCHEMA_PATH,
		"schema_sha256_expected": SecurityPolicy.SCHEMA_SHA256,
	}

	# --- Load capabilities schema (as before) ---
	var schema_text := _read_text_file(SecurityPolicy.SCHEMA_PATH)
	if schema_text == "":
		return _finish("fail", assertions, notes, artifacts, "schema: unable to read %s" % SecurityPolicy.SCHEMA_PATH)

	var schema_sha := _sha256_hex(schema_text)
	artifacts["schema_sha256_actual"] = schema_sha
	if schema_sha != SecurityPolicy.SCHEMA_SHA256:
		# Note only (do not fail solely on mismatch unless harness requires it).
		notes.append("schema: sha256 mismatch (expected %s, got %s)" % [SecurityPolicy.SCHEMA_SHA256, schema_sha])

	var resolver := JsonSchemaResolver.new()
	resolver.load_schema_from_text(schema_text)
	var validator := JsonSchemaValidator.new(resolver)
	var root_schema: Dictionary = resolver.schema_root

	# --- Acquire surfaces ---
	var wrapper: Node = null
	if runner and runner.get_tree() and runner.get_tree().root:
		wrapper = runner.get_tree().root.get_node_or_null(SecurityPolicy.WRAPPER_AUTOLOAD_NAME)

	var singleton: Object = null
	var has_singleton := Engine.has_singleton(SecurityPolicy.SINGLETON_NAME)
	if has_singleton:
		singleton = Engine.get_singleton(SecurityPolicy.SINGLETON_NAME)

	if wrapper == null and singleton == null:
		return _finish("skip", assertions, notes, artifacts, "not_android_or_plugin_missing")

	# --- Diagnostics (notes only) ---
	if wrapper != null:
		notes.append("wrapper: present name=%s class=%s" % [wrapper.name, wrapper.get_class()])
		notes.append("wrapper: has get_camera_capabilities=%s" % str(wrapper.has_method("get_camera_capabilities")))
		notes.append("wrapper: has get_camera_capabilities_to_file=%s" % str(wrapper.has_method("get_camera_capabilities_to_file")))
		notes.append("wrapper: has get_camera_capabilities_to_file_with_meta=%s" % str(wrapper.has_method("get_camera_capabilities_to_file_with_meta")))
	else:
		notes.append("wrapper: missing (%s)" % SecurityPolicy.WRAPPER_AUTOLOAD_NAME)

	notes.append("singleton: Engine.has_singleton(%s)=%s" % [SecurityPolicy.SINGLETON_NAME, str(has_singleton)])
	if singleton != null:
		notes.append("singleton: obj=%s" % str(singleton))
	else:
		notes.append("singleton: missing")

	# --- Secondary surface inventory (singleton only) ---
	var inventory: Dictionary = {}
	var exported_singleton_methods: Array[String] = []
	if singleton != null:
		var inv_ok := _try_get_inventory(singleton, inventory, notes)
		_add_assert(assertions, inv_ok, "singleton:getExposedMethods: inventory parses and contains methods[]")
		if inv_ok:
			exported_singleton_methods = _inventory_method_names(inventory)
			notes.append("inventory: exported methods=%s" % _stable_list(exported_singleton_methods))

			# Check A (authoritative, inventory-based)
			var unexpected := []
			for n in exported_singleton_methods:
				if not _ALLOWED_SINGLETON_METHODS.has(n):
					unexpected.append(n)
			_add_assert(assertions, unexpected.is_empty(),
				"inventory: exported methods only contain allowed names" + ("" if unexpected.is_empty() else " (unexpected=%s)" % _stable_list(unexpected)))

			# Missing allowed is a diagnostic note (non-fatal).
			var missing_allowed := []
			for a in _ALLOWED_SINGLETON_METHODS:
				if not exported_singleton_methods.has(a):
					missing_allowed.append(a)
			if missing_allowed.size() > 0:
				notes.append("inventory: missing allowed methods (non-fatal)=%s" % _stable_list(missing_allowed))

			# Check B (best-effort denylist call-probe, only if policy defines it)
			_run_suspicious_call_probes(singleton, assertions, notes)
	else:
		notes.append("inventory: skipped (singleton missing)")

	# --- Vector fuzzing: wrapper surface (snake_case) ---
	if wrapper != null:
		await _fuzz_wrapper(wrapper, runner, validator, root_schema, assertions, notes)

	# --- Vector fuzzing: singleton surface (camelCase, inventory-driven) ---
	if singleton != null and inventory.size() > 0 and inventory.has("methods"):
		_fuzz_singleton(singleton, inventory, runner, validator, root_schema, assertions, notes)

	# --- Final status ---
	var all_ok := true
	for a in assertions:
		if not a.get("ok", false):
			all_ok = false
			break

	return {
		"status": "pass" if all_ok else "fail",
		"assertions": assertions,
		"notes": notes,
		"artifacts": artifacts,
	}

# -----------------------------------------------------------------------------
# Inventory helpers (secondary surface)
# -----------------------------------------------------------------------------

func _try_get_inventory(singleton: Object, out_inventory: Dictionary, notes: Array[String]) -> bool:
	# Do not depend on has_method; JNISingleton introspection is unreliable.
	var raw : Variant = singleton.call("getExposedMethods")
	if raw == null:
		notes.append("inventory: getExposedMethods returned null")
		return false

	var inv := _coerce_json_to_dict(raw, "inventory", notes)
	if inv.is_empty():
		return false

	if not _validate_inventory_payload(inv, notes):
		return false

	out_inventory.clear()
	for k in inv.keys():
		out_inventory[k] = inv[k]
	return true

func _inventory_method_names(inventory: Dictionary) -> Array[String]:
	var names: Array[String] = []
	var methods: Array = inventory.get("methods", [])
	for m in methods:
		if typeof(m) == TYPE_DICTIONARY and m.has("name"):
			var n := String(m["name"])
			if n != "" and not names.has(n):
				names.append(n)
	names.sort()
	return names

func _validate_inventory_payload(inv: Dictionary, notes: Array[String]) -> bool:
	# Lightweight structural checks only (never validate against capabilities schema).
	if typeof(inv) != TYPE_DICTIONARY:
		notes.append("inventory: not an object")
		return false

	if not inv.has("inventory_schema_version") or typeof(inv["inventory_schema_version"]) != TYPE_INT:
		notes.append("inventory: missing/invalid inventory_schema_version (int required)")
		return false

	if not inv.has("methods") or typeof(inv["methods"]) != TYPE_ARRAY:
		notes.append("inventory: missing/invalid methods (Array required)")
		return false

	var methods: Array = inv["methods"]
	for i in range(methods.size()):
		var m : Variant = methods[i]
		if typeof(m) != TYPE_DICTIONARY:
			notes.append("inventory: methods[%d] not an object" % i)
			return false
		if not m.has("name") or typeof(m["name"]) != TYPE_STRING:
			notes.append("inventory: methods[%d].name missing/invalid" % i)
			return false
		if not m.has("argc") or typeof(m["argc"]) != TYPE_INT:
			notes.append("inventory: methods[%d].argc missing/invalid" % i)
			return false
	return true

# -----------------------------------------------------------------------------
# Capabilities helpers
# -----------------------------------------------------------------------------

func _validate_capabilities_payload(payload: Variant, validator: JsonSchemaValidator, root_schema: Dictionary, notes: Array[String], label: String) -> bool:
	if typeof(payload) != TYPE_STRING:
		notes.append("%s: expected String payload, got %s" % [label, _type_name(payload)])
		return false

	var s := String(payload)
	if s.strip_edges() == "":
		notes.append("%s: empty String payload" % label)
		return false

	var parsed = JSON.parse_string(s)
	if typeof(parsed) != TYPE_DICTIONARY:
		notes.append("%s: payload JSON did not parse to object" % label)
		return false

	var vr: Dictionary = validator.validate(parsed, root_schema)
	if not vr.get("valid", false):
		var errs: Array = vr.get("errors", [])
		notes.append("%s: schema invalid (%s errors)" % [label, str(errs.size())])
		for e in errs.slice(0, min(6, errs.size())):
			notes.append("%s: %s" % [label, str(e)])
		return false
	return true

func _validate_user_file_capabilities(validator: JsonSchemaValidator, root_schema: Dictionary, notes: Array[String], label: String) -> bool:
	var p := "user://camera_capabilities.json"
	if not FileAccess.file_exists(p):
		notes.append("%s: expected file missing: %s" % [label, p])
		return false

	var txt := _read_text_file(p)
	if txt == "":
		notes.append("%s: file empty/unreadable: %s" % [label, p])
		return false

	return _validate_capabilities_payload(txt, validator, root_schema, notes, "%s:file" % label)

# -----------------------------------------------------------------------------
# Fuzzing: wrapper surface
# -----------------------------------------------------------------------------

func _fuzz_wrapper(wrapper: Node, runner: HarnessRunner, validator: JsonSchemaValidator, root_schema: Dictionary, assertions: Array, notes: Array[String]) -> void:
	var vectors: Array[Dictionary] = SecurityVectors.all_vectors()

	# Sanity (0-arg capabilities getter).
	if wrapper.has_method("get_camera_capabilities"):
		var obs := _arm_signal_observer(wrapper)
		_write_breadcrumb({"surface":"wrapper","method":"get_camera_capabilities","phase":"sanity"})
		var payload : Variant = wrapper.call("get_camera_capabilities")
		await _soft_signal_wait(wrapper)
		var ok := _validate_capabilities_payload(payload, validator, root_schema, notes, "wrapper:get_camera_capabilities")
		_add_assert(assertions, ok, "wrapper:get_camera_capabilities: returns schema-valid capabilities JSON")
		_note_signal_anomalies(obs, notes, "wrapper:get_camera_capabilities")

	# Fuzz any wrapper method that accepts a documentsSubdir-style String.
	if wrapper.has_method("get_camera_capabilities_to_file"):
		for v in vectors:
			var inp := String(v.get("input", ""))
			var cat := String(v.get("category", "unknown"))
			var obs2 := _arm_signal_observer(wrapper)
			_write_breadcrumb({"surface":"wrapper","method":"get_camera_capabilities_to_file","phase":"fuzz","category":cat,"documents_subdir":inp})
			var payload2 : Variant = wrapper.call("get_camera_capabilities_to_file", inp)
			await _soft_signal_wait(wrapper)
			var label := "wrapper:get_camera_capabilities_to_file:%s:%s" % [cat, inp]
			var ok2 := _validate_capabilities_payload(payload2, validator, root_schema, notes, label)
			var ok_file := _validate_user_file_capabilities(validator, root_schema, notes, label)
			_add_assert(assertions, ok2 and ok_file, "%s: returns schema-valid capabilities JSON" % label)
			_note_signal_anomalies(obs2, notes, label)

	if wrapper.has_method("get_camera_capabilities_to_file_with_meta"):
		var godot_version := _safe_fixed_string(ProjectSettings.get_setting("application/config/version", "GodotHarness"))
		var gen_version := _safe_fixed_string(HarnessRunner.REPORT_GENERATOR_VERSION if runner else "AideDeCamHarness")
		for v2 in vectors:
			var inp2 := String(v2.get("input", ""))
			var cat2 := String(v2.get("category", "unknown"))
			var obs3 := _arm_signal_observer(wrapper)
			_write_breadcrumb({"surface":"wrapper","method":"get_camera_capabilities_to_file_with_meta","phase":"fuzz","category":cat2,"documents_subdir":inp2})
			var payload3 : Variant = wrapper.call("get_camera_capabilities_to_file_with_meta", inp2, godot_version, gen_version)
			await _soft_signal_wait(wrapper)
			var label2 := "wrapper:get_camera_capabilities_to_file_with_meta:%s:%s" % [cat2, inp2]
			var ok3 := _validate_capabilities_payload(payload3, validator, root_schema, notes, label2)
			var ok_file3 := _validate_user_file_capabilities(validator, root_schema, notes, label2)
			_add_assert(assertions, ok3 and ok_file3, "%s: returns schema-valid capabilities JSON" % label2)
			_note_signal_anomalies(obs3, notes, label2)

# -----------------------------------------------------------------------------
# Fuzzing: singleton surface (inventory-driven)
# -----------------------------------------------------------------------------

func _fuzz_singleton(singleton: Object, inventory: Dictionary, runner: HarnessRunner, validator: JsonSchemaValidator, root_schema: Dictionary, assertions: Array, notes: Array[String]) -> void:
	var vectors: Array[Dictionary] = SecurityVectors.all_vectors()
	var methods: Array = inventory.get("methods", [])
	var fixed_godot := _safe_fixed_string(ProjectSettings.get_setting("application/config/version", "GodotHarness"))
	var fixed_gen := _safe_fixed_string(HarnessRunner.REPORT_GENERATOR_VERSION if runner else "AideDeCamHarness")

	for m in methods:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var name := String(m.get("name", ""))
		if name == "":
			continue

		var argc := int(m.get("argc", 0))
		var arg_types: Array = []
		if m.has("arg_types") and typeof(m["arg_types"]) == TYPE_ARRAY:
			arg_types = m["arg_types"]

		# Never fuzz getExposedMethods; sanity check it once.
		if name == "getExposedMethods":
			_write_breadcrumb({"surface":"singleton","method":name,"phase":"inventory_sanity"})
			var raw : Variant = singleton.callv(name, [])
			var inv2 := _coerce_json_to_dict(raw, "singleton:getExposedMethods", notes)
			var ok_inv := _validate_inventory_payload(inv2, notes)
			_add_assert(assertions, ok_inv, "singleton:getExposedMethods: inventory parses and contains methods[]")
			continue

		if argc <= 0:
			_write_breadcrumb({"surface":"singleton","method":name,"phase":"sanity"})
			var payload0 : Variant = singleton.callv(name, [])
			var label0 := "singleton:%s" % name
			var ok0 := _validate_call_result_by_kind(name, payload0, validator, root_schema, notes, label0)
			_add_assert(assertions, ok0, "%s: sanity call returns valid payload" % label0)
			continue

		# If arg_types is missing, assume arg0 is stringy and fuzz it.
		var fuzz_arg0 := true
		if arg_types.size() > 0:
			var t0 := String(arg_types[0])
			fuzz_arg0 = (t0 == "" or t0.to_lower() == "string")

		if fuzz_arg0:
			for v in vectors:
				var inp := String(v.get("input", ""))
				var cat := String(v.get("category", "unknown"))
				var args: Array = []
				args.resize(argc)
				args[0] = inp
				for i in range(1, argc):
					if i == 1:
						args[i] = fixed_godot
					elif i == 2:
						args[i] = fixed_gen
					else:
						args[i] = "AideDeCamHarness"

				_write_breadcrumb({"surface":"singleton","method":name,"phase":"fuzz","category":cat,"documents_subdir":inp})
				var payload : Variant = singleton.callv(name, args)
				var label := "singleton:%s:%s:%s" % [name, cat, inp]
				var ok := _validate_call_result_by_kind(name, payload, validator, root_schema, notes, label)
				if name.findn("ToFile") != -1:
					ok = ok and _validate_user_file_capabilities(validator, root_schema, notes, label)
				_add_assert(assertions, ok, "%s: did not crash; returned valid payload" % label)
		else:
			notes.append("singleton:%s: skipped fuzz (arg0 not stringy per inventory)" % name)

func _validate_call_result_by_kind(method_name: String, payload: Variant, validator: JsonSchemaValidator, root_schema: Dictionary, notes: Array[String], label: String) -> bool:
	if method_name == "getExposedMethods":
		var inv := _coerce_json_to_dict(payload, label, notes)
		return _validate_inventory_payload(inv, notes)

	# Capabilities getters must validate against capabilities schema.
	if _ALLOWED_SINGLETON_METHODS.has(method_name):
		return _validate_capabilities_payload(payload, validator, root_schema, notes, label)

	# Unknown/extra method: treat as failure if it appears to succeed.
	if payload != null:
		notes.append("%s: unexpected success from non-allowed method (returned %s)" % [label, _type_name(payload)])
	return false

# -----------------------------------------------------------------------------
# Suspicious exposure probing (best effort)
# -----------------------------------------------------------------------------

func _run_suspicious_call_probes(singleton: Object, assertions: Array, notes: Array[String]) -> void:
	var suspicious := _get_policy_suspicious_methods()
	if suspicious.is_empty():
		notes.append("probe: suspicious method call-probe skipped (policy has no suspicious list)")
		return

	for name in suspicious:
		var r : Variant = singleton.callv(String(name), [])
		var ok := (r == null)
		if not ok:
			notes.append("probe:%s: unexpectedly returned %s" % [String(name), _type_name(r)])
		_add_assert(assertions, ok, "probe:%s: callv() should not succeed" % String(name))

func _get_policy_suspicious_methods() -> Array[String]:
	# Only use if already defined in SecurityPolicy constants; otherwise skip.
	var out: Array[String] = []
	var inst := SecurityPolicy.new()
	var script : Variant = inst.get_script()
	if script == null:
		return out

	var cmap := {}
	if script.has_method("get_script_constant_map"):
		cmap = script.call("get_script_constant_map")
	if typeof(cmap) != TYPE_DICTIONARY:
		return out

	var key_candidates := [
		"SUSPICIOUS_SINGLETON_METHODS",
		"SUSPICIOUS_METHOD_NAMES",
		"SUSPICIOUS_METHODS",
	]
	for k in key_candidates:
		if cmap.has(k) and typeof(cmap[k]) == TYPE_ARRAY:
			for n in cmap[k]:
				if typeof(n) == TYPE_STRING:
					out.append(String(n))
			break
	return out

# -----------------------------------------------------------------------------
# Signals (best-effort, non-flaky)
# -----------------------------------------------------------------------------

func _arm_signal_observer(target: Object) -> Dictionary:
	# Returns a dict with flags; used for notes only.
	var obs := {
		"target": target,
		"has_updated": false,
		"has_warning": false,
		"had_updated": false,
		"had_warning": false,
		"updated_count": 0,
		"warning_count": 0,
	}
	if target == null:
		return obs

	obs["has_updated"] = target.has_signal("capabilities_updated")
	obs["has_warning"] = target.has_signal("capabilities_warning")

	if obs["has_updated"]:
		target.connect("capabilities_updated", func():
			obs["had_updated"] = true
			obs["updated_count"] = int(obs["updated_count"]) + 1
		, CONNECT_ONE_SHOT | CONNECT_DEFERRED)

	if obs["has_warning"]:
		target.connect("capabilities_warning", func(_msg := ""):
			obs["had_warning"] = true
			obs["warning_count"] = int(obs["warning_count"]) + 1
		, CONNECT_DEFERRED)

	return obs

func _note_signal_anomalies(obs: Dictionary, notes: Array[String], label: String) -> void:
	if obs.is_empty():
		return
	if obs.get("has_updated", false) and not obs.get("had_updated", false):
		notes.append("%s: signal capabilities_updated not observed (best-effort)" % label)

func _soft_signal_wait(obj: Object) -> void:
	if obj is Node and (obj as Node).get_tree() != null:
		var timer := (obj as Node).get_tree().create_timer(_SOFT_SIGNAL_WAIT_SEC)
		await timer.timeout

# -----------------------------------------------------------------------------
# Generic helpers
# -----------------------------------------------------------------------------

func _finish(status: String, assertions: Array, notes: Array[String], artifacts: Dictionary, note: String) -> Dictionary:
	if note != "":
		notes.append(note)
	return {
		"status": status,
		"assertions": assertions,
		"notes": notes,
		"artifacts": artifacts,
	}

func _add_assert(assertions: Array, ok: bool, message: String) -> void:
	assertions.append({"ok": ok, "message": message})
	_write_partial_report(assertions)

func _read_text_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t

func _sha256_hex(s: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(s.to_utf8_buffer())
	return ctx.finish().hex_encode()

func _coerce_json_to_dict(v: Variant, label: String, notes: Array[String]) -> Dictionary:
	if typeof(v) == TYPE_DICTIONARY:
		return v
	if typeof(v) == TYPE_STRING:
		var parsed = JSON.parse_string(String(v))
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
		notes.append("%s: JSON did not parse to object" % label)
		return {}
	notes.append("%s: expected JSON String or Dictionary, got %s" % [label, _type_name(v)])
	return {}

func _type_name(v: Variant) -> String:
	match typeof(v):
		TYPE_NIL: return "nil"
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "String"
		TYPE_OBJECT: return "Object"
		TYPE_DICTIONARY: return "Dictionary"
		TYPE_ARRAY: return "Array"
		_: return "type_%d" % typeof(v)

func _write_breadcrumb(step: Dictionary) -> void:
	# Best-effort crash breadcrumb. Overwrites each time.
	var path := "user://last_security_vectors_step.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(step))
	f.close()

func _write_partial_report(assertions: Array) -> void:
	# Best-effort partial report that survives process aborts.
	# This is NOT the harness report; it is for crash forensics.
	var path := "user://security_vectors_partial_report.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	var obj := {"id": id(), "group": group(), "status": "running", "assertions": assertions}
	f.store_string(JSON.stringify(obj))
	f.close()

func _stable_list(arr: Array) -> String:
	var xs := []
	for v in arr:
		xs.append(String(v))
	xs.sort()
	return "[" + ", ".join(xs) + "]"

func _safe_fixed_string(v: Variant) -> String:
	var s := String(v)
	if s.strip_edges() == "":
		return "GodotHarness"
	if s.length() > 64:
		s = s.substr(0, 64)
	return s
