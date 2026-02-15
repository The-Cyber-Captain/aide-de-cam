class_name HarnessRunner
extends Node

const REPORT_GENERATOR := "aide-de-cam-test-harness"
const REPORT_GENERATOR_VERSION := "0.2.6"
const REPORT_SCHEMA_VERSION := 1

var tests: Array[HarnessTest] = []
var results: Array = []

func add_test(t: HarnessTest) -> void:
	tests.append(t)

# NOTE: async because tests may await signals/frames.
func run_all() -> Dictionary:
	var started := Time.get_ticks_msec()
	results.clear()

	for t in tests:
		var t0 := Time.get_ticks_msec()
		
		# IMPORTANT: test.run(...) may be async (contains await), so we must await it here.
		var r: Dictionary = await t.run(self)
		
		var dt := Time.get_ticks_msec() - t0
		r["id"] = t.id()
		r["group"] = t.group()
		r["duration_ms"] = dt
		results.append(r)

	var report := {
		"generator": REPORT_GENERATOR,
		"generator_version": REPORT_GENERATOR_VERSION,
		"report_schema_version": REPORT_SCHEMA_VERSION,
		"timestamp_utc": Time.get_datetime_string_from_system(true),
		"run_id": str(randi()) + "-" + str(Time.get_ticks_usec()),
		"summary": _summarize(results, Time.get_ticks_msec() - started),
		"tests": results,
	}
	_save_report(report)
	return report

func _summarize(rs: Array, duration_ms: int) -> Dictionary:
	var total := rs.size()
	var passed := 0
	var failed := 0
	var skipped := 0
	for r in rs:
		match r.get("status","skip"):
			"pass": passed += 1
			"fail": failed += 1
			_: skipped += 1
	return {
		"tests_total": total,
		"passed": passed,
		"failed": failed,
		"skipped": skipped,
		"duration_ms": duration_ms
	}

func _save_report(report: Dictionary) -> void:
	var p := "user://aidedecam_harness_report.json"
	var report_text := JSON.stringify(report, "\t")

	var f := FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_string(report_text)
		
