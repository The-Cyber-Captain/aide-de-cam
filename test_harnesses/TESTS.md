Complete Test Coverage
1. Platform & Environment (2 tests)

Platform is Android
Singleton exists and loads correctly

2. API Method Behavior (3 tests)

getCameraCapabilities() returns valid String
getCameraCapabilitiesToFile("") returns valid String
getCameraCapabilitiesToFile("custom_subdir") returns valid String with custom path

3. JSON Structure & Validity (6 tests)

Returned data is valid JSON (parseable)
Root object is a Dictionary
All required fields present: sdk_version, device_model, device_manufacturer, android_version, timestamp, cameras
SDK version is a number
SDK version >= 21 (Camera2 API minimum)
Device info fields (device_model, device_manufacturer, android_version) are non-empty strings

4. Camera Data Structure (2 tests)

cameras field is an Array
cameras array is not empty (has at least one camera)
Each camera has required fields: camera_id, facing, hardware_level
Camera facing values are valid: "front", "back", "external", or "unknown"
Camera hardware_level values are valid: "legacy", "limited", "full", "level_3", or "unknown"

5. Concurrent Camera Support (1 test)

concurrent_camera_support field exists
Field is either String (SDK < 30) or Dictionary (SDK >= 30)
If Dictionary, contains supported key
If supported, contains max_concurrent_cameras value

6. Vendor Warnings (1 test)

Global warnings field (if present) is an Array
Per-camera warnings fields (if present) are Arrays
Warnings are properly structured and countable

7. Error Handling (2 tests)

Error responses have valid JSON structure
Error field is a String
Error responses still contain timestamp and sdk_version
Permission errors are properly identified and reported

8. File I/O (4 tests)

user://camera_capabilities.json is created
User directory file is readable
User directory file contains valid JSON
File content matches the returned JSON (comparing sdk_version, device info, camera count)
getCameraCapabilitiesToFile() completes without errors (Documents file verification)

9. Security Vectors (5 test categories, 42+ individual vectors)

Path traversal (11 vectors)
Special characters (18 vectors)
Command injection (10 vectors)
Null/empty inputs (3 vectors)
Extreme lengths (6 test cases with limit validation)

10. Signal Behavior (3 tests)

capabilities_updated signal exists
Signal is emitted after successful getCameraCapabilities() call
Signal is emitted after successful getCameraCapabilitiesToFile() call
Signal count matches number of successful calls
Signal is NOT emitted on error conditions

11. Limit Enforcement & Fallback (2 tests + coverage in extreme length tests)

Length > 512 chars triggers warning and fallback
Segment depth > 16 levels triggers warning and fallback
Fallback returns valid data (not error)
Fallback creates file in user:// location
Fallback still emits capabilities_updated signal
Paths at the limit (512 chars, 16 segments) work correctly
Paths beyond the limit work correctly via fallback