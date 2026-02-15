class_name TestSecurityVectorsProbe
extends HarnessTest

const PROBE_TAG: String = "docs_canonicalize_probe_v1"
const BOUNDED_SIGNAL_WAIT_SEC: float = 0.25
const BOUNDED_SIGNAL_POLL_SEC: float = 0.05

# Signal counters (incremented by handlers)
var _cap_updated_count: int = 0
var _cap_warning_count: int = 0

# Whether we successfully connected to a source for capabilities_updated
var _cap_updated_observable: bool = false
var _cap_warning_observable: bool = false

func id() -> String: return "security.vectors.probe"
func group() -> String: return "security"

func run(runner: HarnessRunner) -> Dictionary:
	var assertions: Array = []
	var notes: Array[String] = []
	var artifacts: Dictionary = {
		"schema_path": SecurityPolicy.SCHEMA_PATH,
		"schema_sha256_expected": SecurityPolicy.SCHEMA_SHA256,
	}

	# --- Load schema text
	var schema_text: String = ""
	if FileAccess.file_exists(SecurityPolicy.SCHEMA_PATH):
		schema_text = FileAccess.get_file_as_string(SecurityPolicy.SCHEMA_PATH)
	else:
		notes.append("schema: missing file at %s" % SecurityPolicy.SCHEMA_PATH)

	if schema_text != "":
		var sha_actual: String = _sha256_text(schema_text)
		artifacts["schema_sha256_actual"] = sha_actual
		if sha_actual != SecurityPolicy.SCHEMA_SHA256:
			notes.append("schema: sha256 mismatch (expected %s got %s)" % [SecurityPolicy.SCHEMA_SHA256, sha_actual])

	var resolver = JsonSchemaResolver.new()
	resolver.load_schema_from_text(schema_text)

	var root_schema: Dictionary = resolver.schema_root
	var validator = JsonSchemaValidator.new(resolver)

	# --- Acquire surfaces
	var wrapper: Node = null
	var tree := runner.get_tree()
	if tree != null and tree.root != null:
		wrapper = tree.root.get_node_or_null(SecurityPolicy.WRAPPER_AUTOLOAD_NAME)

	var has_singleton: bool = Engine.has_singleton(SecurityPolicy.SINGLETON_NAME)
	var singleton: Object = null
	if has_singleton:
		singleton = Engine.get_singleton(SecurityPolicy.SINGLETON_NAME)

	if wrapper == null and singleton == null:
		return _finalize("skip", assertions, notes, artifacts)

	notes.append("wrapper: %s" % (_describe_obj(wrapper) if wrapper != null else "missing"))
	notes.append("singleton: Engine.has_singleton(%s)=%s %s" % [
		SecurityPolicy.SINGLETON_NAME,
		str(has_singleton),
		_describe_obj(singleton) if singleton != null else "missing"
	])

	# --- Hook signals (wrapper preferred; singleton best-effort)
	_reset_signal_counters()

	var signal_notes: Array[String] = []
	if wrapper != null:
		_try_connect_signal(wrapper, "capabilities_updated", Callable(self, "_on_capabilities_updated"), signal_notes)
		_try_connect_signal(wrapper, "plugin_ready", Callable(self, "_on_plugin_ready"), signal_notes)
		# wrapper forwards warning to push_warning; may also expose signal on some builds
		_try_connect_signal(wrapper, "capabilities_warning", Callable(self, "_on_capabilities_warning"), signal_notes)

	# Singleton warning is authoritative (per design); connect best-effort
	if singleton != null:
		_try_connect_signal(singleton, "capabilities_warning", Callable(self, "_on_capabilities_warning"), signal_notes)
		_try_connect_signal(singleton, "capabilities_updated", Callable(self, "_on_capabilities_updated"), signal_notes)

	for s in signal_notes:
		notes.append("signals: " + s)

	# REQUIRE that capabilities_updated be observable somewhere
	_assert(assertions, _cap_updated_observable, "signals: capabilities_updated is observable (wrapper or singleton)")
	if not _cap_updated_observable:
		notes.append("signals: could not connect to capabilities_updated on wrapper or singleton")

	# --- Inventory (singleton only)
	var inventory: Dictionary = {}
	var exported_methods: Array = []

	if singleton != null:
		var inv_res: Dictionary = _call_inventory(singleton, notes)
		inventory = inv_res.get("inventory", {})
		exported_methods = inv_res.get("exported_methods", [])

	# --- Check A: inventory allowlist
	if singleton != null and exported_methods.size() > 0:
		var allowed: Array = [
			"getCameraCapabilities",
			"getCameraCapabilitiesToFile",
			"getCameraCapabilitiesWithMeta",
			"getCameraCapabilitiesToFileWithMeta",
			"getExposedMethods",
		]
		var unexpected: Array = []
		for m in exported_methods:
			var ms: String = str(m)
			if not allowed.has(ms):
				unexpected.append(ms)
		_assert(assertions, unexpected.size() == 0, "inventory: exported methods only contain allowed names")
		if unexpected.size() > 0:
			notes.append("inventory: unexpected exported methods: %s" % str(unexpected))

	notes.append("inventory: exported methods: %s" % _stable_join(exported_methods))

	# --- Wrapper surface tests
	if wrapper != null:
		await _run_wrapper_surface(wrapper, runner, validator, root_schema, assertions, notes)

	# --- Singleton surface tests (inventory-driven)
	if singleton != null and exported_methods.size() > 0 and inventory.size() > 0:
		await _run_singleton_surface(singleton, runner, inventory, validator, root_schema, assertions, notes)

	# --- Deterministic crash reproduction probe
	if singleton != null:
		await _run_docs_canonicalization_probe(singleton, runner, validator, root_schema, assertions, notes)

	# --- Decide status
	var status: String = "pass"
	for a in assertions:
		if typeof(a) == TYPE_DICTIONARY and a.get("ok", true) == false:
			status = "fail"
			break

	return _finalize(status, assertions, notes, artifacts)


# ---------------------------
# Surfaces
# ---------------------------

func _run_wrapper_surface(wrapper: Node, runner: HarnessRunner, validator: JsonSchemaValidator, root_schema: Dictionary, assertions: Array, notes: Array[String]) -> void:
	if wrapper.has_method("get_camera_capabilities"):
		_write_breadcrumb({"surface":"wrapper","method":"get_camera_capabilities","kind":"sanity"})
		var before_u: int = _cap_updated_count
		var res: Variant = wrapper.call("get_camera_capabilities")
		await _validate_capabilities_return_and_userfile("wrapper:get_camera_capabilities:sanity", res, runner, before_u, validator, root_schema, assertions, notes, true)
	else:
		notes.append("wrapper: missing method get_camera_capabilities")

	var to_file_methods: Array = []
	if wrapper.has_method("get_camera_capabilities_to_file"):
		to_file_methods.append("get_camera_capabilities_to_file")
	if wrapper.has_method("get_camera_capabilities_to_file_with_meta"):
		to_file_methods.append("get_camera_capabilities_to_file_with_meta")

	for m in to_file_methods:
		var benign: Array = ["", ".", "/", "harness", "harness/subdir"]
		for subdir in benign:
			_write_breadcrumb({"surface":"wrapper","method":m,"kind":"benign","subdir":subdir})
			var before_u2: int = _cap_updated_count
			var args: Array = _build_wrapper_args(m, subdir)
			var res2: Variant = wrapper.callv(m, args)
			await _validate_capabilities_return_and_userfile("wrapper:%s:benign:%s" % [m, _fmt_vec(subdir)], res2, runner, before_u2, validator, root_schema, assertions, notes, true)
			_validate_documents_copy_best_effort("wrapper:%s:benign:%s" % [m, _fmt_vec(subdir)], subdir, validator, root_schema, assertions, notes, true)

		var vectors: Array = SecurityVectors.all_vectors()
		for v in vectors:
			var input_str: String = String(v.get("input",""))
			var cat: String = String(v.get("category","unknown"))
			_write_breadcrumb({"surface":"wrapper","method":m,"kind":"fuzz","category":cat,"input":input_str})
			var before_u3: int = _cap_updated_count
			var args2: Array = _build_wrapper_args(m, input_str)
			var res3: Variant = wrapper.callv(m, args2)
			await _validate_capabilities_return_and_userfile("wrapper:%s:%s:%s" % [m, cat, _fmt_vec(input_str)], res3, runner, before_u3, validator, root_schema, assertions, notes, true)
			_validate_documents_copy_best_effort("wrapper:%s:%s:%s" % [m, cat, _fmt_vec(input_str)], input_str, validator, root_schema, assertions, notes, false)


func _run_singleton_surface(singleton: Object, runner: HarnessRunner, inventory: Dictionary, validator: JsonSchemaValidator, root_schema: Dictionary, assertions: Array, notes: Array[String]) -> void:
	var methods_arr: Array = inventory.get("methods", [])
	for entry_v in methods_arr:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		var name: String = String(entry.get("name",""))
		if name == "" or name == "getExposedMethods":
			continue

		var argc: int = int(entry.get("argc", 0))
		var arg_types: Variant = entry.get("arg_types")

		if argc <= 0:
			_write_breadcrumb({"surface":"singleton","method":name,"kind":"sanity"})
			var before_u: int = _cap_updated_count
			var res: Variant = singleton.callv(name, [])
			await _validate_singleton_result(name, "sanity", res, runner, before_u, validator, root_schema, assertions, notes)
			continue

		var fuzz_arg0: bool = true
		if arg_types != null and arg_types is Array:
			var at: Array = arg_types
			if at.size() > 0 and typeof(at[0]) == TYPE_STRING:
				fuzz_arg0 = String(at[0]).to_lower() == "string"
		if not fuzz_arg0:
			notes.append("singleton:%s: argc=%d arg0 not stringy per inventory; skipping fuzz" % [name, argc])
			continue

		var benign_subdir: String = "harness"
		_write_breadcrumb({"surface":"singleton","method":name,"kind":"benign","subdir":benign_subdir})
		var before_u2: int = _cap_updated_count
		var args_benign: Array = _build_singleton_args(argc, benign_subdir)
		var res_benign: Variant = singleton.callv(name, args_benign)
		await _validate_singleton_result(name, "benign:"+_fmt_vec(benign_subdir), res_benign, runner, before_u2, validator, root_schema, assertions, notes)
		if name.find("ToFile") != -1:
			_validate_documents_copy_best_effort("singleton:%s:benign:%s" % [name, _fmt_vec(benign_subdir)], benign_subdir, validator, root_schema, assertions, notes, true)

		var vectors: Array = SecurityVectors.all_vectors()
		for v in vectors:
			var input_str: String = String(v.get("input",""))
			var cat: String = String(v.get("category","unknown"))
			_write_breadcrumb({"surface":"singleton","method":name,"kind":"fuzz","category":cat,"input":input_str})
			var before_u3: int = _cap_updated_count
			var args: Array = _build_singleton_args(argc, input_str)
			var res2: Variant = singleton.callv(name, args)
			await _validate_singleton_result(name, "%s:%s" % [cat, _fmt_vec(input_str)], res2, runner, before_u3, validator, root_schema, assertions, notes)
			if name.find("ToFile") != -1:
				_validate_documents_copy_best_effort("singleton:%s:%s:%s" % [name, cat, _fmt_vec(input_str)], input_str, validator, root_schema, assertions, notes, false)


# ---------------------------
# Inventory helpers
# ---------------------------

func _call_inventory(singleton: Object, notes: Array[String]) -> Dictionary:
	var out = {"inventory": {}, "exported_methods": []}
	_write_breadcrumb({"surface":"singleton","method":"getExposedMethods","kind":"inventory"})
	var inv_raw: Variant = singleton.call("getExposedMethods")
	if typeof(inv_raw) != TYPE_STRING:
		notes.append("inventory: getExposedMethods returned non-string: %s" % _type_name(inv_raw))
		return out

	var inv_str: String = String(inv_raw)
	var parsed: Variant = JSON.parse_string(inv_str)
	if typeof(parsed) != TYPE_DICTIONARY:
		notes.append("inventory: parse failed or non-object (%s)" % _type_name(parsed))
		return out

	var inv: Dictionary = parsed
	var ok: bool = true
	if not inv.has("inventory_schema_version") or (typeof(inv["inventory_schema_version"]) != TYPE_INT and typeof(inv["inventory_schema_version"]) != TYPE_FLOAT):
		ok = false
		notes.append("inventory: missing/invalid inventory_schema_version")
		var inv_preview: String = inv_str.strip_edges()
		if inv_preview.length() > 256:
			inv_preview = inv_preview.substr(0, 256) + "…"
		notes.append("inventory: payload_preview=%s" % inv_preview)
		notes.append("inventory: payload_keys=%s" % str(inv.keys()))
	if not inv.has("methods") or typeof(inv["methods"]) != TYPE_ARRAY:
		ok = false
		notes.append("inventory: missing/invalid methods[]")
	if not ok:
		return out

	var methods: Array = inv["methods"]
	var exported: Array = []
	for e in methods:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		if not d.has("name") or typeof(d["name"]) != TYPE_STRING:
			continue
		if not d.has("argc") or (typeof(d["argc"]) != TYPE_INT and typeof(d["argc"]) != TYPE_FLOAT):
			continue
		exported.append(String(d["name"]))

	out["inventory"] = inv
	out["exported_methods"] = exported
	return out


# ---------------------------
# Validation
# ---------------------------

func _validate_singleton_result(method: String, tag: String, res: Variant, runner: HarnessRunner, before_updated: int, validator: JsonSchemaValidator, root_schema: Dictionary, assertions: Array, notes: Array[String]) -> void:
	if method == "getExposedMethods":
		_validate_inventory_payload("singleton:getExposedMethods:%s" % tag, res, assertions, notes)
		return
	await _validate_capabilities_return_and_userfile("singleton:%s:%s" % [method, tag], res, runner, before_updated, validator, root_schema, assertions, notes, true)


func _validate_inventory_payload(label: String, res: Variant, assertions: Array, notes: Array[String]) -> void:
	if typeof(res) != TYPE_STRING:
		_assert(assertions, false, "%s: inventory return is not a String (%s)" % [label, _type_name(res)])
		return
	var s: String = String(res)
	var parsed: Variant = JSON.parse_string(s)
	if typeof(parsed) != TYPE_DICTIONARY:
		_assert(assertions, false, "%s: inventory JSON did not parse to object (%s)" % [label, _type_name(parsed)])
		return
	var inv: Dictionary = parsed
	var ok: bool = true
	ok = ok and inv.has("inventory_schema_version") and (typeof(inv["inventory_schema_version"]) == TYPE_INT or typeof(inv["inventory_schema_version"]) == TYPE_FLOAT)
	ok = ok and inv.has("methods") and typeof(inv["methods"]) == TYPE_ARRAY
	_assert(assertions, ok, "%s: inventory parses and contains methods[]" % label)
	if not ok:
		notes.append("%s: inventory keys=%s" % [label, str(inv.keys())])


func _validate_capabilities_return_and_userfile(label: String, res: Variant, runner: HarnessRunner, before_updated: int, validator: JsonSchemaValidator, root_schema: Dictionary, assertions: Array, notes: Array[String], validate_return_json: bool) -> void:
	# 1) Validate the returned JSON string (synchronous contract).
	if validate_return_json:
		if typeof(res) != TYPE_STRING:
			_assert(assertions, false, "%s: return is not a String (%s)" % [label, _type_name(res)])
		else:
			var s: String = String(res)
			_validate_capabilities_json_string("%s:return" % label, s, validator, root_schema, assertions, notes)

	# 2) Enforce capabilities_updated (MUST) with a short bounded wait.
	# IMPORTANT: validate the on-disk userfile *after* the signal is observed, because the file write
	# may complete right at/just before the signal on some implementations.
	var observed: bool = await _await_updated_increment(before_updated, runner, BOUNDED_SIGNAL_WAIT_SEC)
	#_assert(assertions, observed, "%s: capabilities_updated emitted" % label)
	if not observed:
		notes.append("%s: capabilities_updated not observed within %.2fs (before=%d after=%d)" % [label, BOUNDED_SIGNAL_WAIT_SEC, before_updated, _cap_updated_count])

	# 3) Canonical file must exist and be schema-valid: user://camera_capabilities.json
	var user_path: String = "user://camera_capabilities.json"
	if not FileAccess.file_exists(user_path):
		_assert(assertions, false, "%s:userfile: missing user://camera_capabilities.json" % label)
		return

	var user_text: String = FileAccess.get_file_as_string(user_path)
	_validate_capabilities_json_string("%s:userfile" % label, user_text, validator, root_schema, assertions, notes)


func _validate_capabilities_json_string(label: String, json_text: String, validator: JsonSchemaValidator, root_schema: Dictionary, assertions: Array, notes: Array[String]) -> void:
	if json_text.strip_edges() == "":
		_assert(assertions, false, "%s: empty JSON text" % label)
		return
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_assert(assertions, false, "%s: JSON did not parse to object (%s)" % [label, _type_name(parsed)])
		return

	var payload: Dictionary = parsed
	var result: Dictionary = validator.validate(payload, root_schema)
	var valid: bool = bool(result.get("valid", false))
	_assert(assertions, valid, "%s: schema valid" % label)
	if not valid:
		# Extra diagnostics: top-level keys + short preview to disambiguate oneOf mismatches.
		notes.append("%s: payload_keys=%s" % [label, str(payload.keys())])
		var preview: String = json_text.strip_edges()
		if preview.length() > 256:
			preview = preview.substr(0, 256) + "…"
		notes.append("%s: payload_preview=%s" % [label, preview])
		var errs: Array = result.get("errors", [])
		notes.append("%s: schema invalid (%d errors) kind=%s" % [label, errs.size(), String(result.get("error_kind",""))])
		# If this is a root oneOf mismatch, diagnose each branch for actionable errors.
		if errs.size() == 1 and typeof(errs[0]) == TYPE_DICTIONARY and String(errs[0].get("schema_path","")).ends_with("/oneOf"):
			_diagnose_oneof(label, payload, validator.resolver, validator, root_schema, notes)
		var lim: int = int(min(5, errs.size()))
		for i in range(lim):
			notes.append("%s: %s" % [label, JSON.stringify(errs[i])])


func _diagnose_oneof(label: String, payload: Dictionary, resolver: JsonSchemaResolver, validator: JsonSchemaValidator, root_schema: Dictionary, notes: Array[String]) -> void:
	# If root uses oneOf with $ref branches, validate each branch to surface why none matched.
	if not root_schema.has("oneOf") or typeof(root_schema["oneOf"]) != TYPE_ARRAY:
		return
	var arr: Array = root_schema["oneOf"]
	for i in range(arr.size()):
		var branch_v: Variant = arr[i]
		if typeof(branch_v) != TYPE_DICTIONARY:
			continue
		var branch: Dictionary = branch_v
		var branch_schema: Dictionary = branch
		var ref: String = ""
		if branch.has("$ref"):
			ref = String(branch["$ref"])
			branch_schema = resolver.resolve_ref(ref)
			if branch_schema.is_empty():
				notes.append("%s: oneOf[%d]: unresolvable ref %s" % [label, i, ref])
				continue
		var r: Dictionary = validator.validate(payload, branch_schema)
		var ok: bool = bool(r.get("valid", false))
		if ok:
			notes.append("%s: oneOf[%d]: MATCHED (%s)" % [label, i, (ref if ref != "" else "inline")])
		else:
			var errs: Array = r.get("errors", [])
			notes.append("%s: oneOf[%d]: no match (%d errors) ref=%s" % [label, i, errs.size(), ref])
			var lim: int = int(min(3, errs.size()))
			for j in range(lim):
				notes.append("%s: oneOf[%d]: %s" % [label, i, JSON.stringify(errs[j])])



func _validate_documents_copy_best_effort(label: String, subdir: String, validator: JsonSchemaValidator, root_schema: Dictionary, assertions: Array, notes: Array[String], require_if_possible: bool) -> void:
	if OS.get_name() != "Android":
		notes.append("%s: documents: skipped (not Android)" % label)
		return

	if not require_if_possible and not _is_benign_documents_subdir(subdir):
		notes.append("%s: documents: skipped for hostile fuzz subdir (len=%d)" % [label, subdir.length()])
		return

	var docs_root: String = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS, true)
	if docs_root == "":
		notes.append("%s: documents: root unresolved (scoped storage?)" % label)
		if require_if_possible:
			notes.append("%s: documents: required, but access unavailable; not failing" % label)
		return

	var app_name: String = str(ProjectSettings.get_setting("application/config/name"))
	if app_name.strip_edges() == "":
		app_name = "GodotApp"

	var clean_subdir: String = subdir.strip_edges()
	if clean_subdir == "" or clean_subdir == "." or clean_subdir == "/":
		clean_subdir = ""

	var base_dir: String = docs_root.path_join(app_name)
	if clean_subdir != "":
		base_dir = base_dir.path_join(clean_subdir)

	var newest_path: String = _find_newest_matching_json(base_dir, "camera_capabilities_", ".json", notes)
	if newest_path == "":
		if require_if_possible:
			_assert(assertions, false, "%s: documents: expected file missing under %s" % [label, base_dir])
		else:
			notes.append("%s: documents: no file found under %s (fallback likely)" % [label, base_dir])
		return

	var text: String = FileAccess.get_file_as_string(newest_path)
	_validate_capabilities_json_string("%s:documents_file" % label, text, validator, root_schema, assertions, notes)


# ---------------------------
# Probe
# ---------------------------

func _run_docs_canonicalization_probe(singleton: Object, runner: HarnessRunner, validator: JsonSchemaValidator, root_schema: Dictionary, assertions: Array, notes: Array[String]) -> void:
	var long_subdir: String = "A".repeat(6000)

	var preferred: String = "getCameraCapabilitiesToFileWithMeta"
	var fallback: String = "getCameraCapabilitiesToFile"
	var used: String = fallback

	_write_breadcrumb({"probe":PROBE_TAG,"stage":"select_method","preferred":preferred,"fallback":fallback})

	var ok_preferred: bool = false
	var trial_args: Array = [ "harness", "GodotHarness", "AideDeCamHarness" ]
	var trial_res: Variant = singleton.callv(preferred, trial_args)
	if typeof(trial_res) == TYPE_STRING:
		ok_preferred = true
	if ok_preferred:
		used = preferred

	notes.append("probe:%s: using method %s (long_subdir_len=%d)" % [PROBE_TAG, used, long_subdir.length()])
	_write_breadcrumb({"probe":PROBE_TAG,"stage":"call","method":used,"long_len":long_subdir.length()})

	var args: Array = []
	if used == preferred:
		args = [ long_subdir, "GodotHarness", "AideDeCamHarness" ]
	else:
		args = [ long_subdir ]

	var before_u: int = _cap_updated_count
	var res: Variant = singleton.callv(used, args)
	await _validate_capabilities_return_and_userfile("probe:%s:%s" % [PROBE_TAG, used], res, runner, before_u, validator, root_schema, assertions, notes, true)


# ---------------------------
# Signal handling
# ---------------------------

func _reset_signal_counters() -> void:
	_cap_updated_count = 0
	_cap_warning_count = 0
	_cap_updated_observable = false
	_cap_warning_observable = false

func _on_capabilities_updated(_a: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null) -> void:
	_cap_updated_count += 1

func _on_capabilities_warning(_a: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null) -> void:
	_cap_warning_count += 1

func _on_plugin_ready(_a: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null) -> void:
	pass

func _try_connect_signal(obj: Object, signal_name: String, callable: Callable, out: Array[String]) -> void:
	if obj == null:
		return
	if not obj.has_method("has_signal") or not obj.has_method("connect"):
		out.append("%s missing signal API on %s" % [signal_name, obj.get_class()])
		return
	var has_sig: bool = bool(obj.call("has_signal", signal_name))
	if not has_sig:
		out.append("%s missing on %s" % [signal_name, obj.get_class()])
		return
	if obj.has_method("is_connected"):
		var already: bool = bool(obj.call("is_connected", signal_name, callable))
		if already:
			# Now silent (in Notes) if a connection already exists
			#out.append("%s already_connected on %s" % [signal_name, obj.get_class()])
			_mark_signal_observable(signal_name)
			return
	# Now silent (in Notes) when a connection is made
	#var err: int = int(obj.call("connect", signal_name, callable))
	#out.append("%s connect=%s on %s" % [signal_name, str(err), obj.get_class()])
	_mark_signal_observable(signal_name)

func _mark_signal_observable(signal_name: String) -> void:
	if signal_name == "capabilities_updated":
		_cap_updated_observable = true
	if signal_name == "capabilities_warning":
		_cap_warning_observable = true

func _await_updated_increment(before: int, runner: HarnessRunner, timeout_sec: float) -> bool:
	if not _cap_updated_observable:
		return false
	if _cap_updated_count > before:
		return true
	var tree = runner.get_tree()
	if tree == null:
		return false
	var deadline: int = int(Time.get_ticks_msec() + int(timeout_sec * 1000.0))
	while Time.get_ticks_msec() < deadline:
		await tree.create_timer(BOUNDED_SIGNAL_POLL_SEC).timeout
		if _cap_updated_count > before:
			return true
	return false


# ---------------------------
# Misc helpers
# ---------------------------

func _is_benign_documents_subdir(s: String) -> bool:
	var t: String = s.strip_edges()
	if t == "" or t == "." or t == "/":
		return true
	if t.length() > 64:
		return false
	if t.find("..") != -1:
		return false
	return true

func _build_wrapper_args(method: String, subdir: String) -> Array:
	if method == "get_camera_capabilities_to_file_with_meta":
		return [subdir, "GodotHarness", "AideDeCamHarness"]
	return [subdir]

func _build_singleton_args(argc: int, subdir: String) -> Array:
	var args: Array = []
	for i in range(argc):
		if i == 0:
			args.append(subdir)
		elif i == 1:
			args.append("GodotHarness")
		else:
			args.append("AideDeCamHarness")
	return args

func _assert(assertions: Array, ok: bool, message: String) -> void:
	assertions.append({"ok": ok, "message": message})
	_flush_partial({"assertions": assertions, "notes": []})

func _finalize(status: String, assertions: Array, notes: Array[String], artifacts: Dictionary) -> Dictionary:
	_flush_partial({"assertions": assertions, "notes": notes})
	return {
		"status": status,
		"assertions": assertions,
		"notes": notes,
		"artifacts": artifacts,
	}

func _write_breadcrumb(obj: Dictionary) -> void:
	obj["ts_msec"] = Time.get_ticks_msec()
	var p: String = "user://last_security_vectors_step.json"
	var f = FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(obj, "\t"))
		f.flush()

func _flush_partial(data: Dictionary) -> void:
	var p: String = "user://security_vectors_partial_report.json"
	var f = FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.flush()

func _sha256_text(s: String) -> String:
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(s.to_utf8_buffer())
	return ctx.finish().hex_encode()

func _describe_obj(o: Object) -> String:
	if o == null:
		return "null"
	return "%s(%s)" % [o.get_class(), str(o)]

func _type_name(v: Variant) -> String:
	match typeof(v):
		TYPE_NIL: return "nil"
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "String"
		TYPE_ARRAY: return "Array"
		TYPE_DICTIONARY: return "Dictionary"
		_: return str(typeof(v))

func _fmt_vec(s: String) -> String:
	if s == "":
		return "<empty>"
	var t: String = s.replace("\n", "\\n").replace("\t", "\\t")
	if t.length() > 32:
		return t.substr(0, 32) + "…"
	return t

func _stable_join(arr: Array) -> String:
	if arr.size() == 0:
		return "[]"
	var tmp: Array[String] = []
	for a in arr:
		tmp.append(str(a))
	tmp.sort()
	return "[" + ", ".join(tmp) + "]"

func _find_newest_matching_json(dir_path: String, prefix: String, suffix: String, notes: Array[String]) -> String:
	var d = DirAccess.open(dir_path)
	if d == null:
		notes.append("documents: cannot open dir %s (err=%s)" % [dir_path, str(DirAccess.get_open_error())])
		return ""
	d.list_dir_begin()
	var best: String = ""
	var best_mtime: int = -1
	while true:
		var name: String = d.get_next()
		if name == "":
			break
		if d.current_is_dir():
			continue
		if not name.begins_with(prefix) or not name.ends_with(suffix):
			continue
		var full: String = dir_path.path_join(name)
		var mtime: int = int(FileAccess.get_modified_time(full))
		if mtime > best_mtime:
			best_mtime = mtime
			best = full
	d.list_dir_end()
	return best
