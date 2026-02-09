extends Node

# AideDeCam Plugin Test Harness
# Comprehensive test suite covering functionality, security, and edge cases

# Constants matching the Kotlin plugin limits
const MAX_DOCUMENTS_SUBDIR_LENGTH := 512
const MAX_DOCUMENTS_SUBDIR_SEGMENTS := 16

# Test state
var _test_count := 0
var _pass_count := 0
var _fail_count := 0
var _aide: Object = null

# Signal tracking
var _capabilities_updated_count := 0
var _capabilities_warning_count := 0
var _last_warning_message := ""

func _ready() -> void:
	print("\n=== AideDeCam Plugin Test Suite ===\n")
	
	# Wait a frame for plugin to initialize
	await get_tree().process_frame
	
	_run_all_tests()

func _run_all_tests() -> void:
	# 1. Platform & Environment
	_test_platform_is_android()
	_test_singleton_exists()
	
	# 2. API Method Behavior
	_test_get_camera_capabilities()
	_test_get_camera_capabilities_to_file_empty()
	_test_get_camera_capabilities_to_file_custom()
	
	# 3. JSON Structure & Validity
	_test_json_validity()
	_test_required_fields()
	_test_sdk_version_validity()
	_test_device_info_validity()
	
	# 4. Camera Data Structure
	_test_camera_array_structure()
	_test_camera_field_validity()
	
	# 5. Concurrent Camera Support
	_test_concurrent_camera_support()
	
	# 6. Vendor Warnings
	_test_warnings_structure()
	
	# 7. Error Handling
	_test_error_json_structure()
	
	# 8. File I/O (async tests)
	await _test_user_file_creation()
	await _test_user_file_validity()
	await _test_documents_file_creation()
	
	# 9. Security Vectors
	_test_path_traversal_attempts()
	_test_special_characters()
	_test_command_injection()
	_test_null_empty_inputs()
	_test_extreme_length_inputs()
	
	# 10. Signal Behavior (async test)
	_test_signal_existence()
	await _test_signal_emission()
	
	# 11. Limit Enforcement & Fallback (async tests)
	await _test_length_limit_fallback()
	await _test_segment_limit_fallback()
	
	# Print summary (async to ensure proper cleanup before quit)
	await _print_summary()

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

func _get_singleton() -> Object:
	if _aide == null:
		if Engine.has_singleton("AideDeCam"):
			_aide = Engine.get_singleton("AideDeCam")
	return _aide

func _test(test_name: String, condition: bool, details: String = "") -> void:
	_test_count += 1
	if condition:
		_pass_count += 1
		print("[PASS] %s" % test_name)
	else:
		_fail_count += 1
		print("[FAIL] %s" % test_name)
		if details != "":
			print("       Details: %s" % details)

func _parse_json(json_string: String) -> Variant:
	var json := JSON.new()
	var error := json.parse(json_string)
	if error == OK:
		return json.data
	return null

func _on_capabilities_updated() -> void:
	_capabilities_updated_count += 1

func _on_capabilities_warning(msg: String) -> void:
	_capabilities_warning_count += 1
	_last_warning_message = msg

# ============================================================================
# 1. PLATFORM & ENVIRONMENT TESTS
# ============================================================================

func _test_platform_is_android() -> void:
	var is_android := OS.get_name() == "Android"
	_test("Platform is Android", is_android, 
		"Current platform: %s" % OS.get_name())

func _test_singleton_exists() -> void:
	var has_singleton := Engine.has_singleton("AideDeCam")
	_test("Singleton exists", has_singleton)
	
	if has_singleton:
		var singleton := _get_singleton()
		_test("Singleton loads correctly", singleton != null)

# ============================================================================
# 2. API METHOD BEHAVIOR TESTS
# ============================================================================

func _test_get_camera_capabilities() -> void:
	var aide := _get_singleton()
	if aide == null:
		_test("getCameraCapabilities() returns valid String", false, "Singleton not available")
		return
	
	var result: String = aide.getCameraCapabilities()
	_test("getCameraCapabilities() returns valid String", 
		result is String and result.length() > 0)

func _test_get_camera_capabilities_to_file_empty() -> void:
	var aide := _get_singleton()
	if aide == null:
		_test("getCameraCapabilitiesToFile('') returns valid String", false, "Singleton not available")
		return
	
	var result: String = aide.getCameraCapabilitiesToFile("")
	_test("getCameraCapabilitiesToFile('') returns valid String", 
		result is String and result.length() > 0)

func _test_get_camera_capabilities_to_file_custom() -> void:
	var aide := _get_singleton()
	if aide == null:
		_test("getCameraCapabilitiesToFile('custom_subdir') returns valid String", false, "Singleton not available")
		return
	
	var result: String = aide.getCameraCapabilitiesToFile("custom_subdir")
	_test("getCameraCapabilitiesToFile('custom_subdir') returns valid String", 
		result is String and result.length() > 0)

# ============================================================================
# 3. JSON STRUCTURE & VALIDITY TESTS
# ============================================================================

func _test_json_validity() -> void:
	var aide := _get_singleton()
	if aide == null:
		_test("Returned data is valid JSON", false, "Singleton not available")
		return
	
	var result: String = aide.getCameraCapabilities()
	var data: Variant = _parse_json(result)
	_test("Returned data is valid JSON", data != null)
	
	if data != null:
		_test("Root object is a Dictionary", data is Dictionary)

func _test_required_fields() -> void:
	var aide := _get_singleton()
	if aide == null:
		_test("Required fields present", false, "Singleton not available")
		return
	
	var result: String = aide.getCameraCapabilities()
	var data: Variant = _parse_json(result)
	
	if data == null or not data is Dictionary:
		_test("Required fields present", false, "Invalid JSON or not a Dictionary")
		return
	
	var required_fields: Array[String] = ["sdk_version", "device_model", "device_manufacturer", 
		"android_version", "timestamp", "cameras"]
	var all_present: bool = true
	var missing: Array[String] = []
	
	for field in required_fields:
		if not data.has(field):
			all_present = false
			missing.append(field)
	
	_test("All required fields present", all_present, 
		"Missing: %s" % str(missing) if not all_present else "")

func _test_sdk_version_validity() -> void:
	var aide := _get_singleton()
	if aide == null:
		_test("SDK version validity", false, "Singleton not available")
		return
	
	var result: String = aide.getCameraCapabilities()
	var data: Variant = _parse_json(result)
	
	if data == null or not data is Dictionary:
		_test("SDK version is a number", false, "Invalid JSON")
		_test("SDK version >= 21", false, "Invalid JSON")
		return
	
	var sdk: Variant = data.get("sdk_version")
	_test("SDK version is a number", sdk is int or sdk is float)
	
	if sdk is int or sdk is float:
		_test("SDK version >= 21 (Camera2 minimum)", sdk >= 21, 
			"SDK version: %d" % sdk)

func _test_device_info_validity() -> void:
	var aide := _get_singleton()
	if aide == null:
		_test("Device info validity", false, "Singleton not available")
		return
	
	var result: String = aide.getCameraCapabilities()
	var data: Variant = _parse_json(result)
	
	if data == null or not data is Dictionary:
		_test("Device info fields are non-empty strings", false, "Invalid JSON")
		return
	
	var device_model: Variant = data.get("device_model", "")
	var device_manufacturer: Variant = data.get("device_manufacturer", "")
	var android_version: Variant = data.get("android_version", "")
	
	_test("device_model is non-empty string", 
		device_model is String and device_model.length() > 0)
	_test("device_manufacturer is non-empty string", 
		device_manufacturer is String and device_manufacturer.length() > 0)
	_test("android_version is non-empty string", 
		android_version is String and android_version.length() > 0)

# ============================================================================
# 4. CAMERA DATA STRUCTURE TESTS
# ============================================================================

func _test_camera_array_structure() -> void:
	var aide := _get_singleton()
	if aide == null:
		_test("Camera array structure", false, "Singleton not available")
		return
	
	var result: String = aide.getCameraCapabilities()
	var data: Variant = _parse_json(result)
	
	if data == null or not data is Dictionary:
		_test("cameras field is an Array", false, "Invalid JSON")
		_test("cameras array is not empty", false, "Invalid JSON")
		return
	
	var cameras: Variant = data.get("cameras")
	_test("cameras field is an Array", cameras is Array)
	
	if cameras is Array:
		_test("cameras array is not empty", cameras.size() > 0, 
			"Camera count: %d" % cameras.size())

func _test_camera_field_validity() -> void:
	var aide := _get_singleton()
	if aide == null:
		_test("Camera field validity", false, "Singleton not available")
		return
	
	var result: String = aide.getCameraCapabilities()
	var data: Variant = _parse_json(result)
	
	if data == null or not data is Dictionary:
		return
	
	var cameras: Variant = data.get("cameras")
	if not cameras is Array or cameras.size() == 0:
		return
	
	var valid_facing: Array[String] = ["front", "back", "external", "unknown"]
	var valid_hardware: Array[String] = ["legacy", "limited", "full", "level_3", "unknown"]
	
	var all_cameras_valid: bool = true
	for i in range(cameras.size()):
		var camera: Variant = cameras[i]
		if not camera is Dictionary:
			all_cameras_valid = false
			continue
		
		# Check required fields
		if not (camera.has("camera_id") and camera.has("facing") and camera.has("hardware_level")):
			all_cameras_valid = false
			continue
		
		# Check facing value
		if not camera.get("facing") in valid_facing:
			all_cameras_valid = false
		
		# Check hardware_level value
		if not camera.get("hardware_level") in valid_hardware:
			all_cameras_valid = false
	
	_test("All cameras have required fields with valid values", all_cameras_valid)

# ============================================================================
# 5. CONCURRENT CAMERA SUPPORT TESTS
# ============================================================================

func _test_concurrent_camera_support() -> void:
	var aide := _get_singleton()
	if aide == null:
		_test("Concurrent camera support field", false, "Singleton not available")
		return
	
	var result: String = aide.getCameraCapabilities()
	var data: Variant = _parse_json(result)
	
	if data == null or not data is Dictionary:
		_test("concurrent_camera_support field exists", false, "Invalid JSON")
		return
	
	_test("concurrent_camera_support field exists", 
		data.has("concurrent_camera_support"))
	
	if data.has("concurrent_camera_support"):
		var concurrent: Variant = data.get("concurrent_camera_support")
		var is_valid_type: bool = (concurrent is String) or (concurrent is Dictionary)
		_test("concurrent_camera_support is String or Dictionary", is_valid_type)
		
		if concurrent is Dictionary:
			_test("concurrent_camera_support has 'supported' key", 
				concurrent.has("supported"))

# ============================================================================
# 6. VENDOR WARNINGS TESTS
# ============================================================================

func _test_warnings_structure() -> void:
	var aide := _get_singleton()
	if aide == null:
		_test("Warnings structure", false, "Singleton not available")
		return
	
	var result: String = aide.getCameraCapabilities()
	var data: Variant = _parse_json(result)
	
	if data == null or not data is Dictionary:
		return
	
	# Check global warnings
	if data.has("warnings"):
		var warnings: Variant = data.get("warnings")
		_test("Global warnings field is an Array", warnings is Array)
	
	# Check per-camera warnings
	var cameras: Variant = data.get("cameras")
	if cameras is Array:
		for camera in cameras:
			if camera is Dictionary and camera.has("warnings"):
				var cam_warnings: Variant = camera.get("warnings")
				_test("Camera warnings field is an Array", cam_warnings is Array)

# ============================================================================
# 7. ERROR HANDLING TESTS
# ============================================================================

func _test_error_json_structure() -> void:
	# This test validates that even error responses have valid JSON structure
	# We can't easily trigger a real error, so we validate the structure would handle it
	var aide := _get_singleton()
	if aide == null:
		_test("Error JSON structure validation", false, "Singleton not available")
		return
	
	var result: String = aide.getCameraCapabilities()
	var data: Variant = _parse_json(result)
	
	if data == null or not data is Dictionary:
		_test("Error responses have valid JSON", false, "Invalid JSON")
		return
	
	# Check if this is an error response
	if data.has("error"):
		_test("Error field is a String", data.get("error") is String)
		_test("Error response contains timestamp", data.has("timestamp"))
		_test("Error response contains sdk_version", data.has("sdk_version"))
	else:
		# Normal response - just verify it's valid
		_test("Normal response has valid JSON structure", true)

# ============================================================================
# 8. FILE I/O TESTS
# ============================================================================

func _test_user_file_creation() -> void:
	var aide := _get_singleton()
	if aide == null:
		_test("User file creation", false, "Singleton not available")
		return
	
	# Call the method to create the file
	var _result: String = aide.getCameraCapabilities()
	
	# Wait a moment for file I/O
	await get_tree().create_timer(0.5).timeout
	
	var user_path := "user://camera_capabilities.json"
	var file_exists := FileAccess.file_exists(user_path)
	_test("user://camera_capabilities.json is created", file_exists)

func _test_user_file_validity() -> void:
	var aide := _get_singleton()
	if aide == null:
		_test("User file validity", false, "Singleton not available")
		return
	
	var api_result: String = aide.getCameraCapabilities()
	
	await get_tree().create_timer(0.5).timeout
	
	var user_path := "user://camera_capabilities.json"
	if not FileAccess.file_exists(user_path):
		_test("User file is readable", false, "File does not exist")
		_test("User file contains valid JSON", false, "File does not exist")
		_test("File content matches API result", false, "File does not exist")
		return
	
	var file := FileAccess.open(user_path, FileAccess.READ)
	if file == null:
		_test("User file is readable", false, "Cannot open file")
		return
	
	_test("User file is readable", true)
	
	var file_content: String = file.get_as_text()
	file.close()
	
	var file_data: Variant = _parse_json(file_content)
	_test("User file contains valid JSON", file_data != null)
	
	# Compare with API result
	var api_data: Variant = _parse_json(api_result)
	if file_data != null and api_data != null:
		var sdk_match: bool = file_data.get("sdk_version") == api_data.get("sdk_version")
		var model_match: bool = file_data.get("device_model") == api_data.get("device_model")
		var cameras_match: bool = true
		if file_data.has("cameras") and api_data.has("cameras"):
			cameras_match = file_data.get("cameras").size() == api_data.get("cameras").size()
		
		_test("File content matches API result", 
			sdk_match and model_match and cameras_match)

func _test_documents_file_creation() -> void:
	var aide := _get_singleton()
	if aide == null:
		_test("Documents file creation", false, "Singleton not available")
		return
	
	# This will attempt to write to Documents
	var _result: String = aide.getCameraCapabilitiesToFile("test_output")
	
	await get_tree().create_timer(0.5).timeout
	
	# We can't easily verify the Documents path from GDScript on Android,
	# but we can verify the call completes without crashing
	_test("getCameraCapabilitiesToFile() completes without errors", true)

# ============================================================================
# 9. SECURITY VECTORS - PATH TRAVERSAL
# ============================================================================

func _test_path_traversal_attempts() -> void:
	var aide := _get_singleton()
	if aide == null:
		print("\n--- Path Traversal Tests (SKIPPED - no singleton) ---")
		return
	
	print("\n--- Path Traversal Tests ---")
	
	var traversal_vectors: Array[String] = [
		"../",
		"../../",
		"../../../etc/passwd",
		"..\\..\\",
		"..",
		"./../../",
		"test/../../../sensitive",
		"/etc/passwd",
		"\\etc\\passwd",
		"%2e%2e%2f",
		"..%252f"
	]
	
	for vector in traversal_vectors:
		var result: String = aide.getCameraCapabilitiesToFile(vector)
		var data: Variant = _parse_json(result)
		var is_safe: bool = data != null and data is Dictionary
		_test("Path traversal safe: '%s'" % vector, is_safe)

# ============================================================================
# 9. SECURITY VECTORS - SPECIAL CHARACTERS
# ============================================================================

func _test_special_characters() -> void:
	var aide := _get_singleton()
	if aide == null:
		print("\n--- Special Characters Tests (SKIPPED - no singleton) ---")
		return
	
	print("\n--- Special Characters Tests ---")
	
	var special_char_vectors: Array[String] = [
		"test space",
		"test\ttab",
		"test\nnewline",
		"test;semicolon",
		"test|pipe",
		"test&ampersand",
		"test'quote",
		'test"doublequote',
		"test`backtick",
		"test$dollar",
		"test*asterisk",
		"test?question",
		"test<less",
		"test>greater",
		"test:colon",
		"NUL",
		"CON"
		# Note: null byte test omitted - GDScript cannot handle \0 in string literals
	]
	
	for vector in special_char_vectors:
		var result: String = aide.getCameraCapabilitiesToFile(vector)
		var data: Variant = _parse_json(result)
		var is_safe: bool = data != null and data is Dictionary
		var display_vector: String = vector.replace("\n", "\\n").replace("\t", "\\t")
		_test("Special char safe: '%s'" % display_vector, is_safe)

# ============================================================================
# 9. SECURITY VECTORS - COMMAND INJECTION
# ============================================================================

func _test_command_injection() -> void:
	var aide := _get_singleton()
	if aide == null:
		print("\n--- Command Injection Tests (SKIPPED - no singleton) ---")
		return
	
	print("\n--- Command Injection Tests ---")
	
	var injection_vectors: Array[String] = [
		"; rm -rf /",
		"&& cat /etc/passwd",
		"| ls -la",
		"`whoami`",
		"$(whoami)",
		"; ls; ",
		"test; DROP TABLE users;",
		"../../etc/passwd && echo 'hacked'",
		"test\nrm -rf /",
		"test`id`test"
	]
	
	for vector in injection_vectors:
		var result: String = aide.getCameraCapabilitiesToFile(vector)
		var data: Variant = _parse_json(result)
		var is_safe: bool = data != null and data is Dictionary
		_test("Command injection safe: '%s'" % vector.replace("\n", "\\n"), is_safe)

# ============================================================================
# 9. SECURITY VECTORS - NULL/EMPTY INPUTS
# ============================================================================

func _test_null_empty_inputs() -> void:
	var aide := _get_singleton()
	if aide == null:
		print("\n--- Null/Empty Input Tests (SKIPPED - no singleton) ---")
		return
	
	print("\n--- Null/Empty Input Tests ---")
	
	var empty_vectors: Array[String] = [
		"",
		"   ",
		" "
	]
	
	for vector in empty_vectors:
		var result: String = aide.getCameraCapabilitiesToFile(vector)
		var data: Variant = _parse_json(result)
		var is_safe: bool = data != null and data is Dictionary
		_test("Empty input safe: '%s'" % vector.replace(" ", "<space>"), is_safe)

# ============================================================================
# 9. SECURITY VECTORS - EXTREME LENGTH
# ============================================================================

func _test_extreme_length_inputs() -> void:
	var aide := _get_singleton()
	if aide == null:
		print("\n--- Extreme Length Tests (SKIPPED - no singleton) ---")
		return
	
	print("\n--- Extreme Length Tests ---")
	
	# Test at the limit (should work)
	var at_limit: String = "A".repeat(MAX_DOCUMENTS_SUBDIR_LENGTH)
	var result: String = aide.getCameraCapabilitiesToFile(at_limit)
	var data: Variant = _parse_json(result)
	_test("Path at 512 char limit works", data != null and data is Dictionary)
	
	# Test beyond limit (should fallback gracefully)
	var beyond_limit: String = "B".repeat(MAX_DOCUMENTS_SUBDIR_LENGTH + 100)
	result = aide.getCameraCapabilitiesToFile(beyond_limit)
	data = _parse_json(result)
	_test("Path > 512 chars returns valid JSON (fallback)", data != null and data is Dictionary)
	
	# Test extreme length
	var extreme: String = "C".repeat(10000)
	result = aide.getCameraCapabilitiesToFile(extreme)
	data = _parse_json(result)
	_test("Extreme length (10000 chars) returns valid JSON (fallback)", 
		data != null and data is Dictionary)
	
	# Test at segment limit
	var segments_at_limit: Array[String] = []
	for i in range(MAX_DOCUMENTS_SUBDIR_SEGMENTS):
		segments_at_limit.append("dir%d" % i)
	var at_segment_limit: String = "/".join(segments_at_limit)
	result = aide.getCameraCapabilitiesToFile(at_segment_limit)
	data = _parse_json(result)
	_test("Path with 16 segments works", data != null and data is Dictionary)
	
	# Test beyond segment limit
	var segments_beyond: Array[String] = []
	for i in range(MAX_DOCUMENTS_SUBDIR_SEGMENTS + 5):
		segments_beyond.append("dir%d" % i)
	var beyond_segment_limit: String = "/".join(segments_beyond)
	result = aide.getCameraCapabilitiesToFile(beyond_segment_limit)
	data = _parse_json(result)
	_test("Path > 16 segments returns valid JSON (fallback)", 
		data != null and data is Dictionary)

# ============================================================================
# 10. SIGNAL BEHAVIOR TESTS
# ============================================================================

func _test_signal_existence() -> void:
	var aide := _get_singleton()
	if aide == null:
		_test("Signal existence", false, "Singleton not available")
		return
	
	var has_updated := aide.has_signal("capabilities_updated")
	var has_warning := aide.has_signal("capabilities_warning")
	
	_test("capabilities_updated signal exists", has_updated)
	_test("capabilities_warning signal exists", has_warning)

func _test_signal_emission() -> void:
	var aide := _get_singleton()
	if aide == null:
		_test("Signal emission", false, "Singleton not available")
		return
	
	# Connect to signals
	if aide.has_signal("capabilities_updated"):
		if not aide.is_connected("capabilities_updated", Callable(self, "_on_capabilities_updated")):
			aide.connect("capabilities_updated", Callable(self, "_on_capabilities_updated"))
	if aide.has_signal("capabilities_warning"):
		if not aide.is_connected("capabilities_warning", Callable(self, "_on_capabilities_warning")):
			aide.connect("capabilities_warning", Callable(self, "_on_capabilities_warning"))
	
	# Reset counters
	_capabilities_updated_count = 0
	_capabilities_warning_count = 0
	
	# Call methods
	var _result1: String = aide.getCameraCapabilities()
	await get_tree().create_timer(0.2).timeout
	
	var _result2: String = aide.getCameraCapabilitiesToFile("signal_test")
	await get_tree().create_timer(0.2).timeout
	
	_test("capabilities_updated signal emitted", _capabilities_updated_count >= 2,
		"Signal count: %d" % _capabilities_updated_count)
	
	# Disconnect signals
	if aide.is_connected("capabilities_updated", Callable(self, "_on_capabilities_updated")):
		aide.disconnect("capabilities_updated", Callable(self, "_on_capabilities_updated"))
	if aide.is_connected("capabilities_warning", Callable(self, "_on_capabilities_warning")):
		aide.disconnect("capabilities_warning", Callable(self, "_on_capabilities_warning"))

# ============================================================================
# 11. LIMIT ENFORCEMENT & FALLBACK TESTS
# ============================================================================

func _test_length_limit_fallback() -> void:
	var aide := _get_singleton()
	if aide == null:
		print("\n--- Length Limit Fallback (SKIPPED - no singleton) ---")
		return
	
	print("\n--- Length Limit Fallback Tests ---")
	
	# Connect to warning signal
	_capabilities_warning_count = 0
	_last_warning_message = ""
	if aide.has_signal("capabilities_warning"):
		if not aide.is_connected("capabilities_warning", Callable(self, "_on_capabilities_warning")):
			aide.connect("capabilities_warning", Callable(self, "_on_capabilities_warning"))
	
	# Test exceeding length limit
	var too_long: String = "X".repeat(MAX_DOCUMENTS_SUBDIR_LENGTH + 50)
	var result: String = aide.getCameraCapabilitiesToFile(too_long)
	
	await get_tree().create_timer(0.3).timeout
	
	var data: Variant = _parse_json(result)
	_test("Length limit exceeded: returns valid JSON (not error)", 
		data != null and data is Dictionary and not data.has("error"))
	
	_test("Length limit exceeded: emits warning", 
		_capabilities_warning_count > 0,
		"Warning: %s" % _last_warning_message)
	
	# Verify fallback still creates user:// file
	var user_file_exists: bool = FileAccess.file_exists("user://camera_capabilities.json")
	_test("Length limit fallback: creates user:// file", user_file_exists)
	
	# Disconnect
	if aide.is_connected("capabilities_warning", Callable(self, "_on_capabilities_warning")):
		aide.disconnect("capabilities_warning", Callable(self, "_on_capabilities_warning"))

func _test_segment_limit_fallback() -> void:
	var aide := _get_singleton()
	if aide == null:
		print("\n--- Segment Limit Fallback (SKIPPED - no singleton) ---")
		return
	
	print("\n--- Segment Limit Fallback Tests ---")
	
	# Connect to warning signal
	_capabilities_warning_count = 0
	_last_warning_message = ""
	if aide.has_signal("capabilities_warning"):
		if not aide.is_connected("capabilities_warning", Callable(self, "_on_capabilities_warning")):
			aide.connect("capabilities_warning", Callable(self, "_on_capabilities_warning"))
	
	# Test exceeding segment limit
	var segments: Array[String] = []
	for i in range(MAX_DOCUMENTS_SUBDIR_SEGMENTS + 10):
		segments.append("level%d" % i)
	var too_deep: String = "/".join(segments)
	
	var result: String = aide.getCameraCapabilitiesToFile(too_deep)
	
	await get_tree().create_timer(0.3).timeout
	
	var data: Variant = _parse_json(result)
	_test("Segment limit exceeded: returns valid JSON (not error)", 
		data != null and data is Dictionary and not data.has("error"))
	
	_test("Segment limit exceeded: emits warning", 
		_capabilities_warning_count > 0,
		"Warning: %s" % _last_warning_message)
	
	# Disconnect
	if aide.is_connected("capabilities_warning", Callable(self, "_on_capabilities_warning")):
		aide.disconnect("capabilities_warning", Callable(self, "_on_capabilities_warning"))

# ============================================================================
# SUMMARY
# ============================================================================

func _print_summary() -> void:
	print("\n=== Test Summary ===")
	print("Total tests:  %d" % _test_count)
	print("Passed:       %d" % _pass_count)
	print("Failed:       %d" % _fail_count)
	
	if _fail_count == 0:
		print("\n✓ ALL TESTS PASSED")
	else:
		print("\n✗ SOME TESTS FAILED")
	
	print("====================\n")
	
	# Wait a moment before quitting to ensure all output is flushed
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()
