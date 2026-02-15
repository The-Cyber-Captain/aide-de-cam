class_name TestSignalAndFallback
extends HarnessTest

const WAIT_STEP_SEC: float = 0.05

var _updated_count: int = 0
var _warning_count: int = 0

func id() -> String: return "signals.and.fallback"
func group() -> String: return "signals"

func run(runner: HarnessRunner) -> Dictionary:
	var assertions: Array = []
	var notes: Array[String] = []
	var artifacts: Dictionary = {}

	if OS.get_name() != "Android":
		_assert(assertions, false, "platform: Android")
		return _finish("skip", assertions, notes, artifacts)

	if not Engine.has_singleton(SecurityPolicy.SINGLETON_NAME):
		_assert(assertions, false, "environment: singleton exists")
		return _finish("skip", assertions, notes, artifacts)

	var singleton: Object = Engine.get_singleton(SecurityPolicy.SINGLETON_NAME)
	if singleton == null:
		_assert(assertions, false, "environment: singleton loads")
		return _finish("skip", assertions, notes, artifacts)

	_assert(assertions, bool(singleton.call("has_signal", "capabilities_updated")), "signal: capabilities_updated exists")
	if bool(singleton.call("has_signal", "capabilities_warning")):
		_assert(assertions, true, "signal: capabilities_warning exists")
	else:
		notes.append("signal: capabilities_warning missing on singleton")

	_reset_counters()
	_try_connect(singleton, "capabilities_updated", Callable(self, "_on_capabilities_updated"), notes)
	_try_connect(singleton, "capabilities_warning", Callable(self, "_on_capabilities_warning"), notes)

	var before_1: int = _updated_count
	var ok_1: bool = await _invoke_and_expect_update(singleton, runner, "getCameraCapabilities", [], before_1)
	_assert(assertions, ok_1, "signal: emitted after getCameraCapabilities")

	var before_2: int = _updated_count
	var ok_2: bool = await _invoke_and_expect_update(singleton, runner, "getCameraCapabilitiesToFile", ["signal_test"], before_2)
	_assert(assertions, ok_2, "signal: emitted after getCameraCapabilitiesToFile")

	var count_after_success: int = _updated_count
	_assert(assertions, count_after_success >= 2, "signal: update count reflects successful calls")

	# Fallback behavior: long path and deep segments should still return valid JSON and emit updated.
	var long_subdir: String = "A".repeat(SecurityPolicy.MAX_DOCUMENTS_SUBDIR_LENGTH + 64)
	var deep_segments: Array[String] = []
	for i in range(SecurityPolicy.MAX_DOCUMENTS_SUBDIR_SEGMENTS + 4):
		deep_segments.append("s%02d" % i)
	var deep_subdir: String = "/".join(deep_segments)

	var fb1_before: int = _updated_count
	var fb1_raw: Variant = singleton.call("getCameraCapabilitiesToFile", long_subdir)
	var fb1_json_ok: bool = _variant_json_is_capabilities(fb1_raw)
	var fb1_sig_ok: bool = await _await_count_increase(runner, fb1_before, SecurityPolicy.SIGNAL_TIMEOUT_SEC)
	_assert(assertions, fb1_json_ok, "fallback: length overflow returns valid capabilities JSON")
	_assert(assertions, fb1_sig_ok, "fallback: length overflow still emits capabilities_updated")

	var fb2_before: int = _updated_count
	var fb2_raw: Variant = singleton.call("getCameraCapabilitiesToFile", deep_subdir)
	var fb2_json_ok: bool = _variant_json_is_capabilities(fb2_raw)
	var fb2_sig_ok: bool = await _await_count_increase(runner, fb2_before, SecurityPolicy.SIGNAL_TIMEOUT_SEC)
	_assert(assertions, fb2_json_ok, "fallback: deep-segment overflow returns valid capabilities JSON")
	_assert(assertions, fb2_sig_ok, "fallback: deep-segment overflow still emits capabilities_updated")

	_assert(assertions, FileAccess.file_exists("user://camera_capabilities.json"), "fallback: canonical user file exists")

	if SecurityPolicy.REQUIRE_WARNING_ON_FALLBACK:
		_assert(assertions, _warning_count > 0, "fallback: capabilities_warning observed at least once")
		if _warning_count == 0:
			notes.append("fallback warning required by policy but not observed")

	artifacts["capabilities_updated_count"] = _updated_count
	artifacts["capabilities_warning_count"] = _warning_count

	return _finish(_status_from_assertions(assertions), assertions, notes, artifacts)

func _invoke_and_expect_update(singleton: Object, runner: HarnessRunner, method: String, args: Array, before: int) -> bool:
	var raw: Variant = singleton.callv(method, args)
	if not _variant_json_is_capabilities(raw):
		return false
	return await _await_count_increase(runner, before, SecurityPolicy.SIGNAL_TIMEOUT_SEC)

func _variant_json_is_capabilities(v: Variant) -> bool:
	if typeof(v) != TYPE_STRING:
		return false
	var parsed: Variant = JSON.parse_string(String(v))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	if d.has("error"):
		return false
	return d.has("cameras") and typeof(d.get("cameras", null)) == TYPE_ARRAY

func _await_count_increase(runner: HarnessRunner, before: int, timeout_sec: float) -> bool:
	if _updated_count > before:
		return true
	if runner == null or runner.get_tree() == null:
		return false
	var tree := runner.get_tree()
	var deadline: int = int(Time.get_ticks_msec() + int(timeout_sec * 1000.0))
	while Time.get_ticks_msec() < deadline:
		await tree.create_timer(WAIT_STEP_SEC).timeout
		if _updated_count > before:
			return true
	return false

func _try_connect(obj: Object, signal_name: String, cb: Callable, notes: Array[String]) -> void:
	if not bool(obj.call("has_signal", signal_name)):
		return
	if obj.has_method("is_connected") and bool(obj.call("is_connected", signal_name, cb)):
		return
	var err: int = int(obj.call("connect", signal_name, cb))
	if err != OK:
		notes.append("connect failed: %s err=%d" % [signal_name, err])

func _reset_counters() -> void:
	_updated_count = 0
	_warning_count = 0

func _on_capabilities_updated(_a: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null) -> void:
	_updated_count += 1

func _on_capabilities_warning(_message: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null) -> void:
	_warning_count += 1

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
